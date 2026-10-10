import 'dart:ui' show PlatformDispatcher;
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'infrastructure_setup_screen.dart';
import 'staff_shifts_screen.dart';
import 'branch_onboarding_screen.dart';
import 'branch_status.dart';
import 'maintenance_screen.dart';
import 'operational_assets_screen.dart';
import 'procurement_screen.dart';
import 'cash_screen.dart';
import 'promotions_screen.dart';
import 'loyalty_programs_screen.dart';
import 'dispense_screen.dart';
import 'app_theme.dart';
import 'theme_mode_controller.dart';
import 'country_catalog.dart';
import 'cut_window.dart';
import 'haptics.dart';
import 'network_dashboard_page.dart';
import 'charts.dart';
import 'live_form.dart';
import 'validators.dart';
import 'tank_levels.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'Uncaught Flutter framework error',
      name: 'dlc.operations.crash',
      error: details.exception.runtimeType,
      stackTrace: details.stack,
      level: 1000,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Uncaught asynchronous application error',
      name: 'dlc.operations.crash',
      error: error.runtimeType,
      stackTrace: stack,
      level: 1200,
    );
    return false;
  };
  final session = EmployeeSession();
  runApp(
    OperationsApp(
      controller: OperationsController(
        session,
        themeController: ThemeModeController(
          store: CallbackThemePreferenceStore(
            reader: () => session.readPreference('themeMode'),
            writer: (value) => session.writePreference('themeMode', value),
          ),
        ),
      ),
    ),
  );
}

class OperationsController extends ChangeNotifier {
  OperationsController(this.api, {ThemeModeController? themeController})
    : themeController = themeController ?? ThemeModeController() {
    api.onSessionExpired = _handleSessionExpired;
  }
  final EmployeeSession api;
  final ThemeModeController themeController;
  EmployeeIdentity? identity;
  List<BranchSummary> branches = const [];
  BranchSummary? branch;
  Map<String, dynamic> dashboard = const {};
  List<Map<String, dynamic>> pumps = const [];
  Set<String> permissions = const {};
  Set<String> globalPermissions = const {};
  bool busy = true, loadingBranch = false;

  /// True when the server rejected the selected branch with the 404
  /// "Sucursal fuera de tu ámbito." (not active yet, or out of scope).
  bool branchUnavailable = false;
  String? error;

  /// Code / HTTP / Ref of the last genuine error, shown collapsed.
  String? errorDetails;

  List<BranchSummary> get activeBranchList => activeBranches(branches);

  bool get canManageBranches => globalPermissions.contains('branch.manage');

  /// The selected branch cannot show its operation (not active, or the server
  /// refused it as out of scope).
  bool get branchNotReady =>
      branch != null && (!branch!.isActive || branchUnavailable);

  void _setError(DlcApiException e) {
    error = e.message;
    errorDetails = technicalDetails(e);
  }

  Future<void> start() async {
    try {
      identity = await api.restore();
      if (identity != null) {
        await _loadBranches();
        await _selectAssignedBranch();
      }
    } on DlcApiException catch (e) {
      _setError(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      identity = await api.login(email, password);
      await _loadBranches();
      await _selectAssignedBranch();
    } on DlcApiException catch (e) {
      _setError(e);
      identity = null;
      await api.clear();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _loadBranches() async {
    // GET /branches is only authorized for org-wide role assignments. Branch
    // scoped users load just the branches they are assigned to.
    globalPermissions = (await api.capabilities()).toSet();
    if (globalPermissions.contains('branch.read')) {
      // Every status is requested so draft/configured branches are known and
      // can be explained instead of failing on branch-scoped endpoints.
      branches = await api.branches(status: '');
    } else {
      final assigned = (identity?.roles ?? const <EmployeeRole>[])
          .map((r) => r.branchId)
          .whereType<String>()
          .toSet();
      final loaded = <BranchSummary>[];
      for (final id in assigned) {
        try {
          loaded.add(BranchSummary.fromJson(await api.branchDetail(id)));
        } on DlcApiException catch (e) {
          if (e.statusCode != 403 && e.statusCode != 404) rethrow;
        }
      }
      branches = loaded;
    }
    if (branch != null && !branches.any((b) => b.id == branch!.id))
      branch = null;
  }

  Future<void> _selectAssignedBranch() async {
    final assigned = identity!.roles
        .map((r) => r.branchId)
        .whereType<String>()
        .toSet();
    // Prefer an ACTIVE branch. With none active, org-wide users stay on the
    // branch list (onboarding entry points); branch-scoped users get the
    // explanation for their only branch.
    var preferred = pickDefaultBranch(branches, assignedIds: assigned);
    if (preferred == null &&
        activeBranchList.isEmpty &&
        branches.length == 1 &&
        !globalPermissions.contains('branch.read')) {
      preferred = branches.first;
    }
    if (preferred != null) await selectBranch(preferred);
  }

  bool can(String permission) => permissions.contains(permission);

  Future<void> selectBranch(BranchSummary selected) async {
    if (loadingBranch) return;
    if (!branches.any((b) => b.id == selected.id)) {
      error = 'La sucursal no pertenece a tu acceso.';
      notifyListeners();
      return;
    }
    branch = selected;
    branchUnavailable = false;
    error = null;
    errorDetails = null;
    dashboard = const {};
    pumps = const [];
    if (!selected.isActive) {
      // Draft / configured / suspended: never call branch-scoped endpoints.
      permissions = globalPermissions;
      notifyListeners();
      return;
    }
    loadingBranch = true;
    notifyListeners();
    try {
      final responses = await Future.wait<dynamic>([
        api.branchDashboard(selected.id),
        api.dispensers(selected.id),
        api.capabilities(branchId: selected.id),
      ]);
      dashboard = responses[0] as Map<String, dynamic>;
      pumps = responses[1] as List<Map<String, dynamic>>;
      permissions = (responses[2] as List<String>).toSet();
    } on DlcApiException catch (e) {
      if (isBranchScopeError(e)) {
        await _markBranchUnavailable(selected);
      } else {
        _setError(e);
      }
    } finally {
      loadingBranch = false;
      notifyListeners();
    }
  }

  /// Race: the branch was listed as selectable but the server refused it.
  /// Re-read the list so the friendly state shows the real status.
  Future<void> _markBranchUnavailable(BranchSummary selected) async {
    branchUnavailable = true;
    error = null;
    errorDetails = null;
    dashboard = const {};
    pumps = const [];
    permissions = globalPermissions;
    try {
      await _loadBranches();
    } on DlcApiException {
      // Keep the last known list; the state below still explains the situation.
    }
    branch = branches.where((b) => b.id == selected.id).firstOrNull ?? selected;
  }

  /// Leaves the selected branch (back to the branch list).
  void clearBranch() {
    branch = null;
    branchUnavailable = false;
    dashboard = const {};
    pumps = const [];
    permissions = const {};
    error = null;
    errorDetails = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (branch != null && !branchNotReady) {
      await selectBranch(branch!);
      return;
    }
    final current = branch?.id;
    try {
      await _loadBranches();
      error = null;
      errorDetails = null;
    } on DlcApiException catch (e) {
      _setError(e);
    }
    if (current != null) {
      // The branch may have been activated meanwhile.
      final updated = branches.where((b) => b.id == current).firstOrNull;
      if (updated != null && updated.isActive) {
        await selectBranch(updated);
        return;
      }
      branch = updated;
      branchUnavailable = false;
    }
    notifyListeners();
  }

  Future<void> reportIssue(
    String pumpId,
    String description,
    String severity,
  ) async {
    if (branch == null) throw const DlcApiException('Selecciona una sucursal.');
    if (!can('incident.create'))
      throw const DlcApiException(
        'Tu perfil no tiene permiso para registrar incidencias.',
      );
    await api.createIncident(
      branchId: branch!.id,
      assetId: pumpId,
      description: description,
      severity: severity,
    );
    await refresh();
  }

  void _handleSessionExpired() {
    identity = null;
    branches = const [];
    branch = null;
    pumps = const [];
    dashboard = const {};
    permissions = const {};
    globalPermissions = const {};
    loadingBranch = false;
    branchUnavailable = false;
    errorDetails = null;
    busy = false;
    error = 'Tu sesión expiró. Inicia sesión de nuevo.';
    notifyListeners();
  }

  Future<void> logout() async {
    busy = true;
    notifyListeners();
    try {
      await api.logout();
    } on DlcApiException {
      await api.clear();
    } finally {
      identity = null;
      branches = const [];
      branch = null;
      pumps = const [];
      dashboard = const {};
      permissions = const {};
      globalPermissions = const {};
      error = null;
      errorDetails = null;
      branchUnavailable = false;
      busy = false;
      notifyListeners();
    }
  }
}

class OperationsApp extends StatefulWidget {
  const OperationsApp({required this.controller, super.key});
  final OperationsController controller;
  @override
  State<OperationsApp> createState() => _OperationsAppState();
}

class _OperationsAppState extends State<OperationsApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.themeController.load();
    widget.controller.start();
  }

  @override
  void dispose() {
    widget.controller.themeController.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.controller,
      widget.controller.themeController,
    ]),
    builder: (context, _) => MaterialApp(
      title: 'DLC Operaciones',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: widget.controller.themeController.mode,
      home: RootPage(controller: widget.controller),
    ),
  );
}

class RootPage extends StatelessWidget {
  const RootPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  Widget build(BuildContext context) {
    if (controller.busy && controller.identity == null)
      return const LoadingPage();
    if (controller.identity == null) return LoginPage(controller: controller);
    if (controller.branch == null)
      return BranchPickerPage(controller: controller);
    if (controller.branchNotReady)
      return BranchNotReadyPage(controller: controller);
    return HomePage(controller: controller);
  }
}

Future<void> openBranchOnboarding(
  BuildContext context,
  OperationsController controller, {
  String? branchId,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => BranchOnboardingScreen(
      api: controller.api,
      initialBranchId: branchId,
      onActivated: () => controller.refresh(),
    ),
  ),
);

/// Shown instead of the dashboard when the selected branch is a draft /
/// not active (or the server refused it as out of scope).
class BranchNotReadyPage extends StatelessWidget {
  const BranchNotReadyPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  Widget build(BuildContext context) {
    final branch = controller.branch!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sucursal'),
        actions: [
          IconButton(
            onPressed: controller.refresh,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: controller.clearBranch,
            tooltip: 'Ver sucursales',
            icon: const Icon(Icons.store_outlined),
          ),
          IconButton(
            onPressed: controller.logout,
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              BrandHeader(
                title: branch.name,
                subtitle: '${branch.code} · ${branch.zone}',
              ),
              const SizedBox(height: 14),
              if (controller.error != null)
                ErrorBox(controller.error!, details: controller.errorDetails),
              BranchNotReadyPanel(
                branch: branch,
                canManage: controller.canManageBranches,
                onOpenOnboarding: () => openBranchOnboarding(
                  context,
                  controller,
                  branchId: branch.id,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  bool showPassword = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Image.asset(
                    'assets/branding/dlc_logo.png',
                    width: 190,
                    height: 110,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'OPERACIÓN DLC',
                  style: TextStyle(
                    color: context.dlc.brand,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Iniciar sesión',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: context.dlc.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ingresa con la cuenta asignada por tu organización. Tu perfil determina las sucursales y acciones disponibles.',
                  style: TextStyle(color: context.dlc.muted, height: 1.45),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Form(
                      key: form,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                            validator: emailAddress,
                          ),
                          const SizedBox(height: 13),
                          TextFormField(
                            controller: password,
                            obscureText: !showPassword,
                            textInputAction: TextInputAction.go,
                            onFieldSubmitted: (_) => submit(),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: showPassword
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',
                                onPressed: () => setState(
                                  () => showPassword = !showPassword,
                                ),
                                icon: Icon(
                                  showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Escribe tu contraseña.'
                                : null,
                          ),
                          if (widget.controller.error != null) ...[
                            const SizedBox(height: 13),
                            ErrorBox(widget.controller.error!),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: widget.controller.busy ? null : submit,
                              icon: widget.controller.busy
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.login),
                              label: Text(
                                widget.controller.busy
                                    ? 'Verificando acceso…'
                                    : 'Entrar',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: context.dlc.brand,
                                minimumSize: const Size.fromHeight(52),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    'Acceso protegido · DLC',
                    style: TextStyle(color: context.dlc.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> submit() async {
    if (form.currentState?.validate() ?? false) {
      await widget.controller.signIn(email.text, password.text);
      if (widget.controller.error != null) Haptics.error();
    } else {
      Haptics.error();
    }
  }
}

class BranchPickerPage extends StatefulWidget {
  const BranchPickerPage({
    required this.controller,
    this.onSelected,
    super.key,
  });
  final OperationsController controller;
  final ValueChanged<BranchSummary>? onSelected;
  @override
  State<BranchPickerPage> createState() => _BranchPickerPageState();
}

class _BranchPickerPageState extends State<BranchPickerPage> {
  String? country;

  OperationsController get controller => widget.controller;

  Future<void> openNetwork(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => NetworkDashboardPage(
        api: controller.api,
        branches: controller.branches,
        onOpenOnboarding: controller.canManageBranches
            ? () => openBranchOnboarding(context, controller)
            : null,
        onOpenBranch: (b) async {
          Navigator.pop(context);
          await controller.selectBranch(b);
          if (context.mounted && widget.onSelected != null) {
            widget.onSelected!(b);
          }
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final countries = countryOptions(controller.branches);
    final visible = filterBranchesByCountry(controller.branches, country);
    final canSeeNetwork =
        controller.globalPermissions.contains('branch.read') &&
        controller.branches.length > 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sucursales'),
        actions: [
          if (canSeeNetwork)
            IconButton(
              onPressed: () => openNetwork(context),
              tooltip: 'Tablero consolidado',
              icon: const Icon(Icons.public),
            ),
          if (controller.globalPermissions.contains('branch.manage'))
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BranchOnboardingScreen(
                    api: controller.api,
                    onActivated: () => controller.refresh(),
                  ),
                ),
              ),
              tooltip: 'Alta de sucursal',
              icon: const Icon(Icons.add_business_outlined),
            ),
          ListenableBuilder(
            listenable: controller.themeController,
            builder: (context, _) => IconButton(
              onPressed: () => controller.themeController.select(
                nextThemeMode(controller.themeController.mode),
              ),
              tooltip:
                  'Apariencia: ${themeModeLabel(controller.themeController.mode)}',
              icon: Icon(themeModeIcon(controller.themeController.mode)),
            ),
          ),
          IconButton(
            onPressed: controller.logout,
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            BrandHeader(
              title: controller.identity!.isGeneralManager
                  ? 'Vista de la red'
                  : 'Tus sucursales',
              subtitle:
                  '${controller.identity!.displayName} · ${controller.identity!.roles.map((r) => r.name).toSet().join(', ')}',
            ),
            const SizedBox(height: 15),
            if (controller.error != null)
              ErrorBox(controller.error!, details: controller.errorDetails),
            if (controller.branches.isNotEmpty &&
                controller.activeBranchList.isEmpty) ...[
              NoActiveBranchesPanel(
                canManage: controller.canManageBranches,
                onOpenOnboarding: () =>
                    openBranchOnboarding(context, controller),
              ),
              const SizedBox(height: 10),
            ],
            if (canSeeNetwork) ...[
              Card(
                child: ListTile(
                  leading: Icon(Icons.public, color: context.dlc.brand),
                  title: const Text('Tablero consolidado'),
                  subtitle: const Text(
                    'Ventas, cortes y niveles por país o sucursal.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openNetwork(context),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (controller.globalPermissions.contains('branch.manage')) ...[
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.add_business_outlined,
                    color: context.dlc.brand,
                  ),
                  title: const Text('Configurar una sucursal'),
                  subtitle: const Text(
                    'Crear o continuar un borrador de alta.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => BranchOnboardingScreen(
                        api: controller.api,
                        onActivated: () => controller.refresh(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (countries.length > 1) ...[
              CountryDropdown(
                value: country,
                includeAll: true,
                codes: [for (final c in countries) c.countryCode],
                counts: {
                  for (final c in countries) c.countryCode: c.branchCount,
                },
                onChanged: (v) {
                  Haptics.selection();
                  setState(() => country = v);
                },
              ),
              const SizedBox(height: 10),
            ],
            if (controller.branches.isEmpty && controller.error == null)
              const EmptyPanel(
                icon: Icons.store_mall_directory_outlined,
                title: 'Sin sucursales visibles',
                message:
                    'La cuenta no tiene asignación activa o no hay sucursales disponibles.',
              ),
            ...visible.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BranchCard(
                  branch: b,
                  onTap: () async {
                    await controller.selectBranch(b);
                    if (context.mounted && widget.onSelected != null) {
                      widget.onSelected!(b);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({required this.controller, super.key});
  final OperationsController controller;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      DashboardPage(controller: c),
      PumpsPage(controller: c),
      ReportsPage(controller: c),
      CutsPage(controller: c),
      AccountPage(controller: c),
    ];
    final labels = ['Inicio', 'Bombas', 'Reportes', 'Cortes', 'Cuenta'];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          labels[tab],
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: c.refresh,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
          if (c.can('operational_asset.read'))
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => OperationalAssetsScreen(
                    api: c.api,
                    branchId: c.branch!.id,
                    permissions: c.permissions,
                    branches: c.branches,
                  ),
                ),
              ),
              tooltip: 'Activos operativos',
              icon: const Icon(Icons.handyman_outlined),
            ),
          if (c.can('incident.read'))
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => IncidentsPage(controller: c),
                ),
              ),
              tooltip: 'Incidencias',
              icon: const Icon(Icons.warning_amber_outlined),
            ),
          if (c.branches.length > 1)
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BranchPickerPage(
                    controller: c,
                    onSelected: (_) => Navigator.pop(context),
                  ),
                ),
              ),
              tooltip: 'Cambiar sucursal',
              icon: const Icon(Icons.store_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_gas_station_outlined),
            selectedIcon: Icon(Icons.local_gas_station),
            label: 'Bombas',
          ),
          NavigationDestination(
            icon: Icon(Icons.query_stats_outlined),
            selectedIcon: Icon(Icons.query_stats),
            label: 'Reportes',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Cortes',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Cuenta',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  Widget build(BuildContext context) {
    final data = controller.dashboard, inv = mapOf(data['inventory']);
    final tanks = listOf(inv['tanks']), cuts = listOf(data['cuts']);
    final alerts = listOf(data['alerts']),
        incidents = listOf(data['openIncidents']);
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey('dashboard'),
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          BrandHeader(
            title: controller.branch!.name,
            subtitle:
                '${controller.identity!.isGeneralManager ? 'Gerente General' : 'Gerente de Sucursal'} · ${controller.branch!.zone}',
          ),
          const SizedBox(height: 14),
          if (controller.error != null)
            ErrorBox(controller.error!, details: controller.errorDetails),
          if (controller.loadingBranch && data.isEmpty)
            const LinearProgressIndicator(minHeight: 3),
          if (data.isEmpty && !controller.loadingBranch)
            const EmptyPanel(
              icon: Icons.cloud_off_outlined,
              title: 'No se cargó el tablero',
              message:
                  'Actualiza para consultar los datos vigentes de esta sucursal.',
            ),
          if (data.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Tanques',
                    value: '${tanks.length}',
                    detail: 'configurados',
                    icon: Icons.opacity_outlined,
                    color: context.dlc.brand,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    label: 'Incidencias',
                    value: '${incidents.length}',
                    detail: 'abiertas',
                    icon: Icons.report_problem_outlined,
                    color: incidents.isEmpty
                        ? context.dlc.optimal
                        : context.dlc.critical,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            SectionTitle(title: 'Cortes de hoy', trailing: '${cuts.length}/2'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: cuts.isEmpty
                      ? [const Text('No hay cortes para la fecha operativa.')]
                      : cuts.map((raw) {
                          final cut = mapOf(raw);
                          final slot = cut['slot']?.toString();
                          final closed = cut['status'] == 'closed';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              closed ? Icons.check_circle : Icons.timelapse,
                              color: closed
                                  ? context.dlc.optimal
                                  : context.dlc.brand,
                            ),
                            title: Text(
                              [
                                cutName(slot),
                                cutWindowLabel(cut),
                              ].where((part) => part.isNotEmpty).join(' · '),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${cut['registeredDispensers'] ?? 0} de ${cut['expectedDispensers'] ?? '—'} bombas · ${cut['status'] ?? 'sin estado'}',
                            ),
                          );
                        }).toList(),
                ),
              ),
            ),
            if (cuts.any((c) => num(mapOf(c)['closedSalesUsd']) != null)) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: TrendBarChart(
                    title: 'Ventas por corte de hoy (USD)',
                    points: [
                      for (final raw in cuts)
                        if (num(mapOf(raw)['closedSalesUsd']) != null)
                          TrendPoint(
                            cutName(mapOf(raw)['slot']),
                            num(mapOf(raw)['closedSalesUsd'])!,
                          ),
                    ],
                    format: formatUsd,
                    color: context.dlc.brand,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            SectionTitle(
              title: 'Inventario de combustible',
              trailing: inv['totalLiters'] == null
                  ? 'Dato incompleto'
                  : '${fmt(inv['totalLiters'])} L',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: TankLevelBars(
                  levels: fuelLevelsFromTanks(tanks.map(mapOf)),
                ),
              ),
            ),
            ...tanks.map((raw) {
              final t = mapOf(raw);
              final pct = tankPercent(t);
              final status = pct == null ? null : tankStatusForPercent(pct);
              final color = status == null
                  ? context.dlc.muted
                  : context.dlc.foreground(status);
              final fuel =
                  '${t['fuelName'] ?? 'Combustible'} · ${t['code'] ?? ''}';
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Card(
                  child: Semantics(
                    container: true,
                    label:
                        '$fuel: ${pct == null ? 'sin medición' : '${pct.toStringAsFixed(1)} %, ${tankStatusText(status!).toLowerCase()}'}',
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  status?.icon ?? Icons.help_outline,
                                  size: 18,
                                  color: color,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    fuel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Text(
                                  pct == null
                                      ? 'Sin medición'
                                      : '${pct.toStringAsFixed(1)}% · ${status!.label}',
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${t['onHandLiters'] == null ? 'Sin saldo' : fmt(t['onHandLiters']) + ' L'} · capacidad ${fmt(t['capacityLiters'])} L',
                                style: TextStyle(
                                  color: context.dlc.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (alerts.isNotEmpty) ...[
              const SizedBox(height: 14),
              SectionTitle(
                title: 'Alertas que requieren acción',
                trailing: '${alerts.length}',
              ),
              ...alerts.take(4).map((raw) {
                final a = mapOf(raw);
                return Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: AlertCard(
                    title: '${a['title'] ?? 'Alerta'}',
                    detail: '${a['detail'] ?? ''}',
                    critical:
                        a['severity'] == 'critical' || a['severity'] == 'high',
                  ),
                );
              }),
            ],
            const SizedBox(height: 14),
            SectionTitle(
              title: 'Bombas',
              trailing: '${controller.pumps.length} registradas',
            ),
            PumpList(controller: controller, compact: true),
            const SizedBox(height: 8),
            Text(
              'Última actualización: ${dateLabel(data['lastSourceAt'])} · Día operativo ${data['operationalDate'] ?? '—'}',
              style: TextStyle(color: context.dlc.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class PumpsPage extends StatelessWidget {
  const PumpsPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: controller.refresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 5, 18, 24),
      children: [
        Text(
          'Equipo de pista',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            color: context.dlc.ink,
          ),
        ),
        Text(
          'Abre una bomba para ver sus datos y registrar una incidencia.',
          style: TextStyle(color: context.dlc.muted),
        ),
        const SizedBox(height: 14),
        if (controller.error != null) ErrorBox(controller.error!),
        if (controller.pumps.isEmpty && !controller.loadingBranch)
          const EmptyPanel(
            icon: Icons.local_gas_station_outlined,
            title: 'Sin bombas visibles',
            message: 'No hay dispensadores en esta sucursal.',
          ),
        PumpList(controller: controller),
      ],
    ),
  );
}

class PumpList extends StatelessWidget {
  const PumpList({required this.controller, this.compact = false, super.key});
  final OperationsController controller;
  final bool compact;
  @override
  Widget build(BuildContext context) => Column(
    children: controller.pumps.map((pump) {
      final id = textOf(pump, ['id']),
          code = textOf(pump, ['code', 'name'], fallback: 'Dispensador');
      final status = textOf(pump, [
        'physicalStatus',
        'status',
      ], fallback: 'unknown');
      final ready = status == 'active' || status == 'operational';
      final nozzles = listOf(pump['nozzles']);
      final fuels = nozzles
          .map((v) => textOf(mapOf(v), ['fuelName', 'productName']))
          .where((v) => v.isNotEmpty)
          .toSet()
          .join(' · ');
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: id.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PumpDetailPage(
                        controller: controller,
                        pumpId: id,
                        snapshot: pump,
                      ),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ready
                          ? context.dlc.optimalContainer
                          : context.dlc.brandContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.local_gas_station,
                      color: ready ? context.dlc.optimal : context.dlc.critical,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          code,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (fuels.isNotEmpty)
                          Text(
                            fuels,
                            style: TextStyle(
                              color: context.dlc.muted,
                              fontSize: 12,
                            ),
                          ),
                        Text(
                          stateLabel(status),
                          style: TextStyle(
                            color: ready
                                ? context.dlc.optimal
                                : context.dlc.critical,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    compact ? Icons.chevron_right : Icons.arrow_forward_ios,
                    size: 16,
                    color: context.dlc.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );
}

class PumpDetailPage extends StatefulWidget {
  const PumpDetailPage({
    required this.controller,
    required this.pumpId,
    required this.snapshot,
    super.key,
  });
  final OperationsController controller;
  final String pumpId;
  final Map<String, dynamic> snapshot;
  @override
  State<PumpDetailPage> createState() => _PumpDetailPageState();
}

class _PumpDetailPageState extends State<PumpDetailPage> {
  Map<String, dynamic>? detail;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      detail = await widget.controller.api.dispenser(
        widget.controller.branch!.id,
        widget.pumpId,
      );
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pump = detail ?? widget.snapshot, nozzles = listOf(pump['nozzles']);
    return Scaffold(
      appBar: AppBar(
        title: Text(textOf(pump, ['code', 'name'], fallback: 'Bomba')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 3),
          if (error != null) ErrorBox(error!),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    textOf(pump, ['name', 'code'], fallback: 'Dispensador'),
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: context.dlc.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${widget.controller.branch!.name} · ${textOf(pump, ['serviceMode'], fallback: 'Modo no configurado')}',
                    style: TextStyle(color: context.dlc.muted),
                  ),
                  const SizedBox(height: 9),
                  StatusPill(
                    stateLabel(
                      textOf(pump, [
                        'physicalStatus',
                        'status',
                      ], fallback: 'unknown'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 13),
          SectionTitle(
            title: 'Mangueras y producto',
            trailing: '${nozzles.length}',
          ),
          if (nozzles.isEmpty)
            const EmptyPanel(
              icon: Icons.info_outline,
              title: 'Sin mangueras registradas',
              message: 'Revisa la configuración de esta bomba.',
            ),
          ...nozzles.map((v) {
            final n = mapOf(v);
            return Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Card(
                child: ListTile(
                  leading: Icon(
                    Icons.water_drop_outlined,
                    color: context.dlc.brand,
                  ),
                  title: Text(
                    textOf(n, [
                      'fuelName',
                      'productName',
                    ], fallback: 'Combustible sin asignar'),
                  ),
                  subtitle: Text(
                    'Manguera ${textOf(n, ['code'], fallback: '—')} · ${textOf(n, ['meterUnit'], fallback: 'unidad no definida')}',
                  ),
                  onTap: widget.controller.can('dispense.read')
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => DispenseScreen(
                              api: widget.controller.api,
                              branchId: widget.controller.branch!.id,
                              nozzle: n,
                              permissions: widget.controller.permissions,
                            ),
                          ),
                        )
                      : null,
                  trailing: textOf(n, ['meterValue']).isEmpty
                      ? IconButton(
                          tooltip: 'Registrar línea base',
                          onPressed: !widget.controller.can('inventory.measure')
                              ? null
                              : () => baselineDialog(n),
                          icon: Icon(
                            Icons.add_circle_outline,
                            color: context.dlc.brand,
                          ),
                        )
                      : StatusPill(
                          '${fmt(n['meterValue'])} ${textOf(n, ['meterUnit'], fallback: '')}',
                        ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          if (widget.controller.can('incident.create'))
            FilledButton.icon(
              onPressed: () => incidentDialog(context),
              icon: const Icon(Icons.add_alert_outlined),
              label: const Text('Registrar incidencia'),
              style: FilledButton.styleFrom(
                backgroundColor: context.dlc.brand,
                minimumSize: const Size.fromHeight(50),
              ),
            )
          else
            const ErrorBox(
              'Tu perfil no puede registrar incidencias en esta sucursal.',
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar detalle'),
          ),
        ],
      ),
    );
  }

  Future<void> baselineDialog(Map<String, dynamic> nozzle) async {
    final value = TextEditingController(), serial = TextEditingController();
    final id = textOf(nozzle, ['id']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => ValidatedFormDialog(
        title: 'Línea base del totalizador',
        submitLabel: 'Guardar línea base',
        isValid: () => allValid([
          positiveNumber(
            value.text,
            field: 'La lectura',
            allowZero: true,
            maxDecimals: 9,
          ),
          maxLengthText(serial.text, 80, field: 'La serie'),
        ]),
        onCancel: () => Navigator.pop(d, false),
        onSubmit: () => Navigator.pop(d, true),
        contentBuilder: (context, changed) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Este valor inicia la continuidad de lecturas y debe capturarse antes del primer corte.',
            ),
            const SizedBox(height: 10),
            LiveTextField(
              controller: value,
              label: 'Lectura acumulada',
              keyboardType: LiveTextField.decimal(),
              validator: (v) => positiveNumber(
                v,
                field: 'La lectura',
                allowZero: true,
                maxDecimals: 9,
              ),
              onChanged: changed,
            ),
            const SizedBox(height: 8),
            LiveTextField(
              controller: serial,
              label: 'Serie del medidor (opcional)',
              maxLength: 80,
              validator: (v) => maxLengthText(v, 80, field: 'La serie'),
              onChanged: changed,
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      try {
        await widget.controller.api.captureBaseline(
          widget.controller.branch!.id,
          id,
          value.text,
          serial: serial.text,
          note: 'Línea base inicial',
        );
        Haptics.success();
        await load();
      } on DlcApiException catch (e) {
        Haptics.error();
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    value.dispose();
    serial.dispose();
  }

  Future<void> incidentDialog(BuildContext context) async {
    final description = TextEditingController();
    String severity = 'medium';
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialog) => ValidatedFormDialog(
        title: 'Reportar daño o incidencia',
        submitLabel: 'Guardar',
        isValid: () => allValid([
          minLengthText(description.text, 10, field: 'La descripción'),
        ]),
        onCancel: () => Navigator.pop(dialog, false),
        onSubmit: () => Navigator.pop(dialog, true),
        contentBuilder: (context, changed) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Se vinculará con esta bomba y sucursal.',
              style: TextStyle(color: context.dlc.muted),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: severity,
              decoration: const InputDecoration(labelText: 'Severidad'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Baja')),
                DropdownMenuItem(value: 'medium', child: Text('Media')),
                DropdownMenuItem(value: 'high', child: Text('Alta')),
                DropdownMenuItem(value: 'critical', child: Text('Crítica')),
              ],
              onChanged: (v) {
                if (v == null) return;
                severity = v;
                if (v == 'critical') {
                  Haptics.critical();
                } else {
                  Haptics.selection();
                }
                changed();
              },
            ),
            const SizedBox(height: 9),
            LiveTextField(
              controller: description,
              label: 'Qué ocurrió',
              hint: 'Ej.: la manguera presenta una fuga visible.',
              minLines: 3,
              maxLines: 5,
              maxLength: 2000,
              validator: (v) => minLengthText(v, 10, field: 'La descripción'),
              onChanged: changed,
            ),
          ],
        ),
      ),
    );
    if (submit != true || !mounted) {
      description.dispose();
      return;
    }
    try {
      await widget.controller.reportIssue(
        widget.pumpId,
        description.text,
        severity,
      );
      Haptics.success();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Incidencia registrada.')));
    } on DlcApiException catch (e) {
      Haptics.error();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      description.dispose();
    }
  }
}

class IncidentsPage extends StatefulWidget {
  const IncidentsPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  State<IncidentsPage> createState() => _IncidentsPageState();
}

class _IncidentsPageState extends State<IncidentsPage> {
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = const [];
  String status = '';
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      rows = await widget.controller.api.incidents(
        widget.controller.branch!.id,
        status: status,
        query: search.text,
      );
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Incidencias'),
      actions: [
        IconButton(
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          BrandHeader(
            title: 'Registro de incidentes',
            subtitle: 'Daños, seguridad, combustible y terceros',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: search,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              labelText: 'Buscar código o descripción',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: load,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Estado'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Todos')),
              DropdownMenuItem(value: 'reported', child: Text('Reportadas')),
              DropdownMenuItem(value: 'assessed', child: Text('Evaluadas')),
              DropdownMenuItem(value: 'in_progress', child: Text('En proceso')),
              DropdownMenuItem(value: 'resolved', child: Text('Resueltas')),
              DropdownMenuItem(value: 'closed', child: Text('Cerradas')),
            ],
            onChanged: (v) {
              if (v != null) {
                status = v;
                load();
              }
            },
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ErrorBox(error!),
            ),
          if (loading) const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 12),
          SectionTitle(title: 'Resultados', trailing: '${rows.length}'),
          if (!loading && rows.isEmpty)
            const EmptyPanel(
              icon: Icons.verified_outlined,
              title: 'No se encontraron incidencias',
              message:
                  'Prueba otro filtro o registra una incidencia desde el detalle del equipo.',
            ),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Card(
                child: ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => IncidentDetailPage(
                        controller: widget.controller,
                        summary: row,
                      ),
                    ),
                  ).then((_) => load()),
                  leading: Icon(
                    row['severity'] == 'critical' || row['severity'] == 'high'
                        ? Icons.error_outline
                        : Icons.report_outlined,
                    color:
                        row['severity'] == 'critical' ||
                            row['severity'] == 'high'
                        ? context.dlc.critical
                        : context.dlc.brand,
                  ),
                  title: Text(
                    textOf(row, ['code', 'category'], fallback: 'Incidencia'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${textOf(row, ['status'], fallback: 'reported')} · ${dateLabel(row['occurredAt'])}\n${textOf(row, ['description'], fallback: 'Sin descripción')}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class IncidentDetailPage extends StatefulWidget {
  const IncidentDetailPage({
    required this.controller,
    required this.summary,
    super.key,
  });
  final OperationsController controller;
  final Map<String, dynamic> summary;
  @override
  State<IncidentDetailPage> createState() => _IncidentDetailPageState();
}

class _IncidentDetailPageState extends State<IncidentDetailPage> {
  Map<String, dynamic> record = const {};
  bool loading = true, working = false;
  String? error;
  String get id => textOf(widget.summary, ['id']);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      record = await widget.controller.api.incident(
        widget.controller.branch!.id,
        id,
      );
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incident = mapOf(record['incident']).isEmpty
        ? record
        : mapOf(record['incident']);
    final events = listOf(record['events']);
    final status = textOf(incident, ['status'], fallback: 'reported');
    final next = status == 'reported'
        ? 'assessed'
        : status == 'assessed'
        ? 'in_progress'
        : status == 'in_progress'
        ? 'resolved'
        : status == 'resolved'
        ? 'closed'
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          textOf(incident, ['code'], fallback: 'Detalle de incidencia'),
        ),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 3),
          if (error != null) ErrorBox(error!),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    textOf(incident, ['category'], fallback: 'Incidencia'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: context.dlc.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    textOf(incident, [
                      'description',
                    ], fallback: 'Sin descripción'),
                  ),
                  const Divider(height: 22),
                  Text(
                    'Severidad: ${textOf(incident, ['severity'], fallback: '—')}',
                  ),
                  Text('Estado: $status'),
                  Text('Reportada: ${dateLabel(incident['occurredAt'])}'),
                  Text(
                    'Activo: ${textOf(incident, ['assetType'], fallback: 'Sucursal')} ${textOf(incident, ['assetCode', 'assetId'])}',
                  ),
                ],
              ),
            ),
          ),
          if (next != null &&
              widget.controller.can(
                (next == 'assessed' || next == 'in_progress')
                    ? 'incident.assign'
                    : 'incident.resolve',
              ))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: FilledButton.icon(
                onPressed: working ? null : () => transition(next),
                icon: const Icon(Icons.arrow_forward),
                label: Text('Avanzar a ${stateLabel(next)}'),
              ),
            ),
          const SizedBox(height: 13),
          SectionTitle(title: 'Bitácora', trailing: '${events.length} eventos'),
          if (events.isEmpty)
            const EmptyPanel(
              icon: Icons.history,
              title: 'Sin eventos adicionales',
              message:
                  'Las transiciones futuras aparecerán aquí con usuario y fecha.',
            ),
          ...events.map((e) {
            final event = mapOf(e);
            return Card(
              child: ListTile(
                leading: Icon(Icons.history, color: context.dlc.brand),
                title: Text(
                  textOf(event, [
                    'action',
                    'status',
                    'nextStatus',
                  ], fallback: 'Actualización'),
                ),
                subtitle: Text(
                  '${textOf(event, ['note', 'description'])}\n${dateLabel(event['createdAt'] ?? event['occurredAt'])} · ${textOf(event, ['actorName', 'userName'], fallback: 'usuario registrado')}',
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  int incidentVersion() {
    final entity = mapOf(record['incident']);
    return int.tryParse(
          '${entity['version'] ?? record['version'] ?? widget.summary['version'] ?? 1}',
        ) ??
        1;
  }

  Future<void> transition(String target) async {
    final note = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => ValidatedFormDialog(
        title: 'Avanzar a ${stateLabel(target)}',
        submitLabel: 'Guardar',
        isValid: () =>
            allValid([maxLengthText(note.text, 1000, field: 'La nota')]),
        onCancel: () => Navigator.pop(d, false),
        onSubmit: () => Navigator.pop(d, true),
        contentBuilder: (context, changed) => LiveTextField(
          controller: note,
          label: 'Nota de seguimiento',
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          validator: (v) => maxLengthText(v, 1000, field: 'La nota'),
          onChanged: changed,
        ),
      ),
    );
    if (yes != true || !mounted) {
      note.dispose();
      return;
    }
    setState(() => working = true);
    try {
      await widget.controller.api.transitionIncident(
        widget.controller.branch!.id,
        id,
        int.tryParse('${incidentVersion()}') ?? 1,
        target,
        note.text,
      );
      await load();
    } on DlcApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      note.dispose();
      if (mounted) setState(() => working = false);
    }
  }
}

String stateLabel(String state) => switch (state) {
  'active' || 'operational' => 'Disponible',
  'open' => 'En captura',
  'in_progress' => 'En proceso',
  'prepared' => 'En revisión',
  'reviewed' => 'Revisado',
  'inReview' => 'Requiere revisión',
  'closed' => 'Cerrado',
  'scheduled' || 'pending' => 'Pendiente',
  'reported' => 'Reportada',
  'assessed' => 'Evaluada',
  'resolved' => 'Resuelta',
  'maintenance' => 'En mantenimiento',
  'offline' || 'disabled' => 'Fuera de servicio',
  'faulty' || 'damaged' => 'Dañado',
  _ => 'Estado por confirmar',
};

const reportPermissions = <String, String>{
  'closed_cuts': 'cut.read',
  'fuel_sales': 'sale.read',
  'tank_movements': 'inventory.read',
  'incidents': 'incident.read',
  'purchase_orders': 'purchase.read',
  'fuel_prices': 'price.read',
  'expenses': 'finance.cost.read',
  'cash_closures': 'cash.read',
  'store_stock': 'pos.catalog.read',
  'maintenance_orders': 'maintenance.plan',
  'operational_assets': 'operational_asset.read',
  'staff_shifts': 'staff.read',
};
const reportTypes = <String, String>{
  'closed_cuts': 'Cortes cerrados',
  'fuel_sales': 'Ventas de combustible',
  'tank_movements': 'Movimientos de tanques',
  'incidents': 'Incidencias',
  'purchase_orders': 'Órdenes de compra',
  'fuel_prices': 'Precios de combustible',
  'maintenance_orders': 'Órdenes de mantenimiento',
  'staff_shifts': 'Turnos de personal',
  'expenses': 'Gastos operativos',
  'cash_closures': 'Cierres de caja',
  'store_stock': 'Inventario de tienda',
  'operational_assets': 'Activos operativos',
};

class ReportsPage extends StatefulWidget {
  const ReportsPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  List<Map<String, dynamic>> runs = const [];
  String selected = 'fuel_sales';
  bool loading = true, creating = false;
  String? error;
  DateTime to = DateTime.now(),
      from = DateTime.now().subtract(const Duration(days: 6));
  String? pendingCommandId;
  List<String> get visibleTypes => reportTypes.keys
      .where(
        (type) =>
            widget.controller.can(reportPermissions[type] ?? 'report.read') &&
            (type == 'closed_cuts' ? widget.controller.can('sale.read') : true),
      )
      .toList(growable: false);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      runs = await widget.controller.api.reportRuns(
        widget.controller.branch!.id,
      );
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> create() async {
    setState(() {
      creating = true;
      error = null;
    });
    try {
      final types = visibleTypes;
      if (types.isEmpty)
        throw const DlcApiException(
          'Tu perfil no tiene permisos para ejecutar reportes.',
        );
      final type = types.contains(selected) ? selected : types.first;
      pendingCommandId ??= widget.controller.api.newCommandId();
      final run = await widget.controller.api.createReport(
        widget.controller.branch!.id,
        type,
        from,
        to,
        commandId: pendingCommandId,
      );
      pendingCommandId = null;
      await load();
      if (mounted && textOf(run, ['id']).isNotEmpty)
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ReportDetailPage(
              controller: widget.controller,
              run: run,
              title: reportTypes[type] ?? type,
            ),
          ),
        );
    } on DlcApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 5, 18, 24),
      children: [
        BrandHeader(
          title: 'Reportes',
          subtitle: 'Instantáneas filtradas por período y sucursal',
        ),
        const SizedBox(height: 13),
        if (!widget.controller.can('report.read'))
          const ErrorBox('Tu perfil no tiene acceso al módulo de reportes.'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crear reporte',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: context.dlc.ink,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: visibleTypes.isEmpty
                      ? null
                      : (visibleTypes.contains(selected)
                            ? selected
                            : visibleTypes.first),
                  decoration: const InputDecoration(labelText: 'Información'),
                  items: visibleTypes
                      .map(
                        (key) => DropdownMenuItem(
                          value: key,
                          child: Text(reportTypes[key]!),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => selected = v);
                  },
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => chooseDate(true),
                        icon: const Icon(Icons.date_range),
                        label: Text('Desde ${shortDate(from)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => chooseDate(false),
                        icon: const Icon(Icons.event),
                        label: Text('Hasta ${shortDate(to)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        creating ||
                            visibleTypes.isEmpty ||
                            !widget.controller.can('report.read')
                        ? null
                        : create,
                    icon: creating
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(
                      creating ? 'Generando…' : 'Generar instantánea',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ErrorBox(error!),
          ),
        const SizedBox(height: 14),
        SectionTitle(
          title: 'Historial de reportes',
          trailing: '${runs.length}',
        ),
        if (loading) const LinearProgressIndicator(minHeight: 3),
        if (!loading && runs.isEmpty)
          const EmptyPanel(
            icon: Icons.analytics_outlined,
            title: 'Aún no hay reportes',
            message:
                'Genera una instantánea para consultar y exportar el resultado.',
          ),
        ...runs
            .take(30)
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Card(
                  child: ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ReportDetailPage(
                          controller: widget.controller,
                          run: r,
                          title:
                              reportTypes[textOf(r, ['reportType', 'type'])] ??
                              textOf(r, [
                                'reportType',
                                'type',
                              ], fallback: 'Reporte'),
                        ),
                      ),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: context.dlc.brandContainer,
                      child: Icon(
                        Icons.insert_chart_outlined,
                        color: context.dlc.brand,
                      ),
                    ),
                    title: Text(
                      reportTypes[textOf(r, ['reportType', 'type'])] ??
                          textOf(r, [
                            'reportType',
                            'type',
                          ], fallback: 'Reporte'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${dateLabel(r['createdAt'])} · ${r['rowCount'] ?? '—'} filas · ${textOf(mapOf(r['filters']), ['from'], fallback: '')} – ${textOf(mapOf(r['filters']), ['to'], fallback: '')}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            ),
      ],
    ),
  );
  Future<void> chooseDate(bool isFrom) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: isFrom ? from : to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (selectedDate != null)
      setState(() => isFrom ? from = selectedDate : to = selectedDate);
  }
}

class ReportDetailPage extends StatefulWidget {
  const ReportDetailPage({
    required this.controller,
    required this.run,
    required this.title,
    super.key,
  });
  final OperationsController controller;
  final Map<String, dynamic> run;
  final String title;
  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  Map<String, dynamic> data = const {};
  bool loading = true, exporting = false;
  String? error;
  int offset = 0;
  String get id => textOf(widget.run, ['id']);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      data = await widget.controller.api.reportPage(
        widget.controller.branch!.id,
        id,
        offset: offset,
      );
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = listOf(data['rows']).map(mapOf).toList();
    final meta = data;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null) ErrorBox(error!),
          if (loading) const LinearProgressIndicator(minHeight: 3),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${meta['rowCount'] ?? widget.run['rowCount'] ?? '—'} filas · ${meta['timezone'] ?? 'zona horaria de sucursal'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: context.dlc.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Corte de datos: ${dateLabel(meta['asOf'] ?? widget.run['createdAt'])}',
                    style: TextStyle(color: context.dlc.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              exporting ||
                                  !widget.controller.can('report.export')
                              ? null
                              : () => export(true),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('PDF'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              exporting ||
                                  !widget.controller.can('report.export')
                              ? null
                              : () => export(false),
                          icon: const Icon(Icons.table_view_outlined),
                          label: const Text('Excel'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SectionTitle(title: 'Detalle', trailing: '${rows.length} visibles'),
          if (rows.isEmpty && !loading)
            const EmptyPanel(
              icon: Icons.inbox_outlined,
              title: 'Sin filas para estos filtros',
              message:
                  'La instantánea se conservó; el período no devolvió registros.',
            ),
          ...rows.map(
            (r) => Card(
              child: ExpansionTile(
                title: Text(
                  textOf(r, [
                    'fuelName',
                    'productName',
                    'dispenserCode',
                    'operationalDate',
                    'occurredAt',
                    'id',
                  ], fallback: 'Registro'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  r.entries
                      .take(3)
                      .map((e) => '${e.key}: ${e.value}')
                      .join(' · '),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(r),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (meta['nextOffset'] != null)
            OutlinedButton(
              onPressed: loading
                  ? null
                  : () => setState(() {
                      offset =
                          int.tryParse('${meta['nextOffset']}') ?? offset + 100;
                      load();
                    }),
              child: const Text('Cargar siguientes 100'),
            ),
        ],
      ),
    );
  }

  Future<void> export(bool pdf) async {
    setState(() => exporting = true);
    try {
      final bytes = await widget.controller.api.exportReport(
        widget.controller.branch!.id,
        id,
        pdf: pdf,
      );
      final filename =
          'dlc_${textOf(mapOf(data['filters']), ['type'], fallback: 'reporte')}_${id.substring(0, 8)}.${pdf ? 'pdf' : 'xlsx'}';
      final mime = pdf
          ? 'application/pdf'
          : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: filename, mimeType: mime)],
          subject: widget.title,
        ),
      );
    } on DlcApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }
}

String shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

class CutsPage extends StatefulWidget {
  const CutsPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  State<CutsPage> createState() => _CutsPageState();
}

class _CutsPageState extends State<CutsPage> {
  List<Map<String, dynamic>> cuts = const [];
  bool loading = true, generating = false;
  String? error;
  DateTime date = DateTime.now();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      cuts = await widget.controller.api.dailyCuts(
        widget.controller.branch!.id,
        date,
      );
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> generate() async {
    setState(() {
      generating = true;
      error = null;
    });
    try {
      cuts = await widget.controller.api.generateDailyCuts(
        widget.controller.branch!.id,
        date,
      );
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 5, 18, 24),
      children: [
        BrandHeader(
          title: 'Cortes operativos',
          subtitle: '${widget.controller.branch!.name} · dos ventanas al día',
        ),
        const SizedBox(height: 14),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.calendar_today_outlined,
              color: context.dlc.brand,
            ),
            title: const Text('Fecha operativa'),
            subtitle: Text(dateLabel(date)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 2)),
              );
              if (selected != null) {
                date = selected;
                await load();
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        if (error != null) ErrorBox(error!),
        if (loading) const LinearProgressIndicator(minHeight: 3),
        if (!loading && cuts.isEmpty) ...[
          const EmptyPanel(
            icon: Icons.receipt_long_outlined,
            title: 'No hay cortes generados',
            message:
                'Genera las dos ventanas para esta fecha. El servidor valida horario y continuidad.',
          ),
          if (widget.controller.can('cut.capture'))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: FilledButton.icon(
                onPressed: generating ? null : generate,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  generating ? 'Generando…' : 'Generar los dos cortes',
                ),
              ),
            ),
        ],
        if (cuts.isNotEmpty) ...[
          SectionTitle(title: 'Ventanas del día', trailing: '${cuts.length}/2'),
          ...cuts.map(
            (cut) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CutCard(
                cut: cut,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CutDetailPage(
                      controller: widget.controller,
                      initial: cut,
                    ),
                  ),
                ).then((_) => load()),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'El cierre conserva lecturas y conciliación como historial. Solo cortes cerrados alimentan métricas históricas.',
          style: TextStyle(color: context.dlc.muted, fontSize: 12, height: 1.4),
        ),
      ],
    ),
  );
}

class _CutCard extends StatelessWidget {
  const _CutCard({required this.cut, required this.onTap});
  final Map<String, dynamic> cut;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final slot = cut['slot']?.toString();
    final status = (cut['status'] ?? 'pending').toString();
    final closed = status == 'closed';
    final window = cutWindowLabel(cut);
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        leading: CircleAvatar(
          backgroundColor: closed
              ? context.dlc.optimalContainer
              : context.dlc.brandContainer,
          child: Icon(
            closed ? Icons.check : Icons.timelapse,
            color: closed ? context.dlc.optimal : context.dlc.brand,
          ),
        ),
        title: Text(
          cutName(slot),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${window.isEmpty ? '—' : window} · ${stateLabel(status)}\nVersión ${cut['version'] ?? '—'} · abre el detalle para revisar lecturas',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class CutDetailPage extends StatefulWidget {
  const CutDetailPage({
    required this.controller,
    required this.initial,
    super.key,
  });
  final OperationsController controller;
  final Map<String, dynamic> initial;
  @override
  State<CutDetailPage> createState() => _CutDetailPageState();
}

class _CutDetailPageState extends State<CutDetailPage> {
  late Map<String, dynamic> cut = Map.of(widget.initial);
  Map<String, dynamic> assets = const {},
      progress = const {},
      reconciliation = const {};
  bool loading = true, working = false;
  String? error;
  String get branchId => widget.controller.branch!.id;
  String get cutId => textOf(cut, ['id']);
  int get version => int.tryParse('${cut['version'] ?? 1}') ?? 1;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait<Map<String, dynamic>>([
        widget.controller.api.cutAssets(branchId, cutId),
        widget.controller.api.cutProgress(branchId, cutId),
      ]);
      assets = results[0];
      progress = results[1];
      final updated = mapOf(assets['cut']);
      if (updated.isNotEmpty) cut = updated;
      if (cut['status'] == 'prepared' ||
          cut['status'] == 'inReview' ||
          cut['status'] == 'closed') {
        try {
          reconciliation = await widget.controller.api.cutReconciliation(
            branchId,
            cutId,
          );
        } on DlcApiException {
          reconciliation = const {};
        }
      }
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> run(Future<void> Function() action, String success) async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await action();
      Haptics.success();
      await load();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
    } on DlcApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slot = cut['slot']?.toString();
    final nozzles = listOf(
      assets['nozzles'],
    ).map(mapOf).where((n) => n['participation'] != 'excused').toList();
    final products = listOf(progress['products']).map(mapOf).toList();
    final closed = cut['status'] == 'closed';
    final canClose =
        cut['status'] == 'prepared' ||
        (cut['status'] == 'inReview' &&
            mapOf(reconciliation['review']).isNotEmpty);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Corte ${cutName(slot).toLowerCase()} ${cutWindowLabel(cut)}'.trim(),
        ),
        actions: [
          IconButton(
            onPressed: working ? null : load,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 3),
          if (error != null) ErrorBox(error!),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado: ${stateLabel('${cut['status'] ?? 'pending'}')}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: context.dlc.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Versión ${cut['version'] ?? '—'} · ${dateLabel(cut['startsAt'])}',
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${nozzles.where((n) => n['cutReadingId'] != null).length} de ${nozzles.length} mangueras visibles',
                    style: TextStyle(color: context.dlc.muted),
                  ),
                ],
              ),
            ),
          ),
          if (cut['status'] == 'scheduled' || cut['status'] == 'pending') ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: working || !widget.controller.can('cut.capture')
                  ? null
                  : () => run(() async {
                      await widget.controller.api.openCut(
                        branchId,
                        cutId,
                        version,
                      );
                    }, 'Corte abierto; se congeló el equipo esperado.'),
              icon: const Icon(Icons.lock_open),
              label: const Text('Abrir corte'),
            ),
          ],
          if (cut['status'] == 'open' || cut['status'] == 'in_progress') ...[
            const SizedBox(height: 13),
            SectionTitle(
              title: 'Lecturas de totalizador',
              trailing: '${nozzles.length} mangueras',
            ),
            Text(
              'Captura el valor acumulado del medidor. El servidor valida continuidad, duplicados y versión.',
              style: TextStyle(color: context.dlc.muted, fontSize: 12),
            ),
            ...nozzles.map(
              (n) => Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Card(
                  child: ListTile(
                    title: Text(
                      'Bomba ${textOf(n, ['dispenserCode', 'dispenserId'], fallback: '—')} · Manguera ${textOf(n, ['code'], fallback: '—')}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${textOf(n, ['fuelName', 'productName'], fallback: 'Combustible')} · ${textOf(n, ['meterUnit'], fallback: 'unidad no indicada')}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Capturar lectura',
                      onPressed:
                          working || !widget.controller.can('cut.capture')
                          ? null
                          : () => capture(n),
                      icon: Icon(Icons.edit_note, color: context.dlc.brand),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 13),
            SectionTitle(
              title: 'Medición de tanques',
              trailing: '${listOf(assets['tanks']).length}',
            ),
            Text(
              'Registra volumen, agua y temperatura observados. Los valores se validan contra capacidad en el servidor.',
              style: TextStyle(color: context.dlc.muted, fontSize: 12),
            ),
            ...listOf(assets['tanks']).map((raw) {
              final tank = mapOf(raw);
              return Card(
                child: ListTile(
                  leading: Icon(
                    Icons.opacity_outlined,
                    color: context.dlc.brand,
                  ),
                  title: Text(
                    '${textOf(tank, ['code'], fallback: 'Tanque')} · ${textOf(tank, ['fuelName'], fallback: 'Combustible')}',
                  ),
                  subtitle: Text(
                    'Medido ${tank['measuredLiters'] ?? 'pendiente'} L / ${tank['capacityLiters'] ?? '—'} L · agua ${tank['waterLiters'] ?? '—'} L · temp. ${tank['temperatureC'] ?? '—'} °C',
                  ),
                  trailing: IconButton(
                    tooltip: 'Registrar medición',
                    onPressed: working || !widget.controller.can('cut.capture')
                        ? null
                        : () => measureTank(tank),
                    icon: Icon(Icons.edit_outlined, color: context.dlc.brand),
                  ),
                ),
              );
            }),
            const SizedBox(height: 9),
            FilledButton.icon(
              onPressed: working || !widget.controller.can('cut.submit')
                  ? null
                  : () => run(() async {
                      await widget.controller.api.prepareCut(
                        branchId,
                        cutId,
                        version,
                      );
                    }, 'Conciliación preparada.'),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Preparar conciliación'),
            ),
          ],
          if (products.isNotEmpty) ...[
            const SizedBox(height: 13),
            SectionTitle(title: 'Consolidado por combustible'),
            ...products.map(
              (p) => Card(
                child: ListTile(
                  leading: Icon(
                    Icons.water_drop_outlined,
                    color: context.dlc.brand,
                  ),
                  title: Text(
                    textOf(p, ['productName'], fallback: 'Combustible'),
                  ),
                  subtitle: Text(
                    'Esperadas ${p['expected'] ?? 0} · capturadas ${p['captured'] ?? 0} · ${p['meterLiters'] ?? '—'} L',
                  ),
                ),
              ),
            ),
          ],
          if (reconciliation.isNotEmpty) ...[
            const SizedBox(height: 13),
            SectionTitle(title: 'Conciliación'),
            ...listOf(reconciliation['products']).map((raw) {
              final row = mapOf(raw);
              return Card(
                child: ListTile(
                  title: Text(
                    textOf(row, ['productName'], fallback: 'Combustible'),
                  ),
                  subtitle: Text(
                    'Medidor ${row['meterLiters'] ?? '—'} L · venta ${row['soldLiters'] ?? '—'} L · variación ${row['varianceLiters'] ?? '—'} L',
                  ),
                  trailing: Icon(
                    (num(row['varianceLiters']) == 0)
                        ? Icons.check_circle
                        : Icons.warning_amber,
                    color: (num(row['varianceLiters']) == 0)
                        ? context.dlc.optimal
                        : context.dlc.brand,
                  ),
                ),
              );
            }),
            ...listOf(reconciliation['tanks']).map((raw) {
              final row = mapOf(raw);
              return Card(
                child: ListTile(
                  leading: Icon(Icons.opacity_outlined, color: context.dlc.ink),
                  title: Text(
                    '${textOf(row, ['tankCode'], fallback: 'Tanque')} · ${textOf(row, ['fuelName'], fallback: 'Combustible')}',
                  ),
                  subtitle: Text(
                    'Medido ${row['measuredLiters'] ?? '—'} L · libro ${row['ledgerLiters'] ?? '—'} L · diferencia ${row['varianceLiters'] ?? '—'} L · agua ${row['waterLiters'] ?? '—'} L',
                  ),
                ),
              );
            }),
            if (mapOf(reconciliation['finance']).isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conciliación de cobros',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: context.dlc.ink,
                        ),
                      ),
                      Text(
                        'Ventas USD ${reconciliation['finance']?['salesUsd'] ?? '—'} · cobro confirmado USD ${reconciliation['finance']?['confirmedCollectionUsd'] ?? '—'}',
                      ),
                      Text(
                        'Efectivo ${reconciliation['finance']?['cashConfirmedUsd'] ?? '—'} · tarjeta ${reconciliation['finance']?['cardConfirmedUsd'] ?? '—'} · reembolsos ${reconciliation['finance']?['refundedUsd'] ?? '—'}',
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if ((cut['status'] == 'prepared' || cut['status'] == 'inReview') &&
              !closed) ...[
            const SizedBox(height: 12),
            if (cut['status'] == 'inReview' &&
                mapOf(reconciliation['review']).isEmpty)
              OutlinedButton.icon(
                onPressed: working || !widget.controller.can('cut.close')
                    ? null
                    : review,
                icon: const Icon(Icons.rule_folder_outlined),
                label: const Text('Aprobar discrepancia / revisión'),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  working || !canClose || !widget.controller.can('cut.close')
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('Cerrar corte'),
                          content: const Text(
                            'El cierre es definitivo y quedará auditado. Confirma que la conciliación fue revisada.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: const Text('Volver'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text('Cerrar corte'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true)
                        await run(() async {
                          await widget.controller.api.closeCut(
                            branchId,
                            cutId,
                            version,
                          );
                        }, 'Corte cerrado y auditado.');
                    },
              icon: const Icon(Icons.lock_outline),
              label: const Text('Cerrar corte'),
            ),
          ],
          if (closed)
            const AlertCard(
              title: 'Corte cerrado',
              detail:
                  'El servidor bloquea cambios y conserva el snapshot de cierre.',
              critical: false,
            ),
        ],
      ),
    );
  }

  Future<void> measureTank(Map<String, dynamic> tank) async {
    final capacity = num(tank['capacityLiters'] ?? tank['capacityL']);
    final liters = TextEditingController(
          text: '${tank['measuredLiters'] ?? ''}',
        ),
        water = TextEditingController(text: '${tank['waterLiters'] ?? ''}'),
        temperature = TextEditingController(
          text: '${tank['temperatureC'] ?? ''}',
        );
    final save = await showDialog<bool>(
      context: context,
      builder: (d) => ValidatedFormDialog(
        title: 'Medir tanque ${textOf(tank, ['code'], fallback: '')}',
        submitLabel: 'Guardar medición',
        onCancel: () => Navigator.pop(d, false),
        onSubmit: () => Navigator.pop(d, true),
        isValid: () => allValid([
          tankMeasureLiters(liters.text, capacity),
          optionalNumber(water.text, field: 'El agua', maxDecimals: 3),
          optionalNumber(
            temperature.text,
            field: 'La temperatura',
            signed: true,
            maxDecimals: 3,
          ),
        ]),
        contentBuilder: (context, changed) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveTextField(
              controller: liters,
              label: 'Combustible observado (L)',
              keyboardType: LiveTextField.decimal(),
              validator: (v) => tankMeasureLiters(v, capacity),
              onChanged: changed,
            ),
            const SizedBox(height: 4),
            LiveTextField(
              controller: water,
              label: 'Agua (L, opcional)',
              keyboardType: LiveTextField.decimal(),
              validator: (v) =>
                  optionalNumber(v, field: 'El agua', maxDecimals: 3),
              onChanged: changed,
            ),
            const SizedBox(height: 4),
            LiveTextField(
              controller: temperature,
              label: 'Temperatura °C (opcional)',
              keyboardType: LiveTextField.decimal(signed: true),
              validator: (v) => optionalNumber(
                v,
                field: 'La temperatura',
                signed: true,
                maxDecimals: 3,
              ),
              onChanged: changed,
            ),
          ],
        ),
      ),
    );
    if (save == true && mounted) {
      await run(() async {
        await widget.controller.api.captureTankMeasure(
          branchId,
          cutId,
          textOf(tank, ['id']),
          version,
          liters.text.trim(),
          water.text.trim(),
          temperature.text.trim(),
        );
      }, 'Medición de tanque registrada.');
    }
    liters.dispose();
    water.dispose();
    temperature.dispose();
  }

  Future<void> capture(Map<String, dynamic> nozzle) async {
    final id = textOf(nozzle, ['id']);
    if (id.isEmpty) return;
    final input = TextEditingController();
    final previous = num(
      nozzle['lastMeterValue'] ?? nozzle['meterValue'] ?? nozzle['lastReading'],
    );
    final value = await showDialog<String>(
      context: context,
      builder: (d) => ValidatedFormDialog(
        title: 'Lectura acumulada',
        submitLabel: 'Guardar lectura',
        onCancel: () => Navigator.pop(d),
        onSubmit: () => Navigator.pop(d, input.text.trim()),
        isValid: () => finalNotBelowInitial(input.text, previous) == null,
        contentBuilder: (context, changed) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (previous != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Lectura anterior: ${fmt(previous)}',
                  style: TextStyle(color: context.dlc.muted),
                ),
              ),
            LiveTextField(
              controller: input,
              autofocus: true,
              label: 'Totalizador',
              hint: 'Ej. 125430.250',
              keyboardType: LiveTextField.decimal(),
              validator: (v) =>
                  finalNotBelowInitial(v, previous, field: 'La lectura'),
              onChanged: changed,
            ),
          ],
        ),
      ),
    );
    input.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    await run(() async {
      final reading = await widget.controller.api.captureReading(
        branchId,
        id,
        value,
        int.tryParse('${nozzle['meterVersion'] ?? 0}') ?? 0,
      );
      final readingId = textOf(reading, ['id']);
      if (readingId.isEmpty)
        throw const DlcApiException(
          'La lectura se guardó, pero falta su identificador para asociarla al corte. Actualiza el corte antes de continuar.',
        );
      await widget.controller.api.attachCutMeter(
        branchId,
        cutId,
        id,
        readingId,
        version,
      );
    }, 'Lectura vinculada al corte.');
  }

  Future<void> review() async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (d) => ValidatedFormDialog(
        title: 'Revisión de corte',
        submitLabel: 'Enviar revisión',
        onCancel: () => Navigator.pop(d),
        onSubmit: () => Navigator.pop(d, reason.text),
        isValid: () =>
            minLengthText(reason.text, 8, field: 'La explicación') == null,
        contentBuilder: (context, changed) => LiveTextField(
          controller: reason,
          label: 'Motivo de aprobación',
          hint: 'Explica la discrepancia revisada',
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          validator: (v) => minLengthText(v, 8, field: 'La explicación'),
          onChanged: changed,
        ),
      ),
    );
    reason.dispose();
    if (value == null || !mounted) return;
    await run(() async {
      await widget.controller.api.reviewCut(branchId, cutId, version, value);
    }, 'Revisión registrada.');
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  Widget build(BuildContext context) {
    final u = controller.identity!;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        BrandHeader(
          title: 'Mi cuenta',
          subtitle: 'Perfil verificado por el servidor',
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                Text(u.email, style: TextStyle(color: context.dlc.muted)),
                const Divider(height: 24),
                ...u.roles.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '${r.name}${r.branchId == null ? ' · Red' : ''}',
                      style: TextStyle(color: context.dlc.ink),
                    ),
                  ),
                ),
                if (controller.branch != null)
                  Text(
                    'Sucursal: ${controller.branch!.name}',
                    style: TextStyle(color: context.dlc.muted),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: ThemeModeSelector(controller: controller.themeController),
          ),
        ),
        if (controller.globalPermissions.contains('branch.manage')) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.add_business_outlined,
                color: context.dlc.brand,
              ),
              title: const Text(
                'Alta de sucursal',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Crear o continuar borradores de sucursal'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BranchOnboardingScreen(
                    api: controller.api,
                    onActivated: () => controller.refresh(),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (controller.globalPermissions.any(
          (p) => p.startsWith('loyalty.program.'),
        )) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.loyalty_outlined, color: context.dlc.brand),
              title: const Text(
                'Programa de puntos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Tasa central, versiones y aprobación'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => LoyaltyProgramsScreen(
                    api: controller.api,
                    permissions: controller.globalPermissions,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (({...controller.permissions, ...controller.globalPermissions}).any(
          (p) =>
              p == 'promotion.read' ||
              p == 'promotion.manage' ||
              p == 'promotion.network.manage',
        )) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.local_offer_outlined,
                color: context.dlc.brand,
              ),
              title: const Text(
                'Promociones y ofertas',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Reglas, calendario, condiciones y revisión',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PromotionsScreen(
                    api: controller.api,
                    branchId: controller.branch?.id,
                    branchTimeZone:
                        controller.branch?.timezone ?? 'America/El_Salvador',
                    permissions: {
                      ...controller.permissions,
                      ...controller.globalPermissions,
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
        if (controller.branch != null &&
            controller.can('infrastructure.read')) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.settings_input_component_outlined,
                color: context.dlc.brand,
              ),
              title: const Text(
                'Infraestructura de sucursal',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Combustibles, tanques, dispensadores, boquillas y saldos iniciales',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => InfrastructureSetupScreen(
                    api: controller.api,
                    branchId: controller.branch!.id,
                    permissions: controller.permissions,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (controller.branch != null && controller.can('staff.read')) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.groups_2_outlined, color: context.dlc.brand),
              title: const Text(
                'Personal y turnos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Personal activo, agenda semanal y programación de turnos',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => StaffShiftsScreen(
                    api: controller.api,
                    branchId: controller.branch!.id,
                    permissions: controller.permissions,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (controller.branch != null &&
            controller.can('maintenance.plan')) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.build_outlined, color: context.dlc.brand),
              title: const Text(
                'Mantenimiento',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Órdenes, tareas, finalización y verificación',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MaintenanceScreen(
                    api: controller.api,
                    branchId: controller.branch!.id,
                    permissions: controller.permissions,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (controller.branch != null && controller.can('purchase.read')) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.local_shipping_outlined,
                color: context.dlc.brand,
              ),
              title: const Text(
                'Compras de combustible',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Proveedores, aprobación, órdenes y recepción a tanque',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ProcurementScreen(
                    api: controller.api,
                    branchId: controller.branch!.id,
                    permissions: controller.permissions,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (controller.branch != null &&
            (controller.can('cash.read') || controller.can('cash.open'))) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.point_of_sale_outlined,
                color: context.dlc.brand,
              ),
              title: const Text(
                'Cajas y turnos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Abrir turno, movimientos y arqueo de cierre',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CashScreen(
                    api: controller.api,
                    branchId: controller.branch!.id,
                    permissions: controller.permissions,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: controller.logout,
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.dlc.critical,
            minimumSize: const Size.fromHeight(49),
          ),
        ),
      ],
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({required this.title, required this.subtitle, super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Image.asset(
        'assets/branding/dlc_logo.png',
        width: 74,
        height: 53,
        fit: BoxFit.contain,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.dlc.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(color: context.dlc.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
}

class BranchCard extends StatelessWidget {
  const BranchCard({required this.branch, required this.onTap, super.key});
  final BranchSummary branch;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: context.dlc.brandContainer,
        child: Icon(Icons.storefront_outlined, color: context.dlc.brand),
      ),
      title: Text(
        branch.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${branch.code} · ${branch.zone} · ${countryName(branch.countryCode)}',
      ),
      trailing: branch.isActive
          ? const Icon(Icons.chevron_right)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BranchStatusChip(status: branch.status),
                const Icon(Icons.chevron_right),
              ],
            ),
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    super.key,
  });
  final String label, value, detail;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: context.dlc.muted, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: context.dlc.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            detail,
            style: TextStyle(color: context.dlc.muted, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, this.trailing, super.key});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.dlc.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: context.dlc.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    ),
  );
}

class AlertCard extends StatelessWidget {
  const AlertCard({
    required this.title,
    required this.detail,
    required this.critical,
    super.key,
  });
  final String title, detail;
  final bool critical;
  @override
  Widget build(BuildContext context) => Card(
    color: critical ? context.dlc.criticalContainer : context.dlc.surface,
    child: ListTile(
      leading: Icon(
        critical ? Icons.warning_amber_rounded : Icons.info_outline,
        color: critical ? context.dlc.critical : context.dlc.brand,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(detail),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final ok = label == 'Disponible';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: ok
            ? context.dlc.optimalContainer
            : context.dlc.criticalContainer,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ok ? context.dlc.optimal : context.dlc.critical,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {this.details, super.key});
  final String message;

  /// Code / HTTP / Ref line, kept collapsed under "Detalles técnicos".
  final String? details;
  @override
  Widget build(BuildContext context) => Card(
    color: context.dlc.criticalContainer,
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: context.dlc.critical),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: context.dlc.critical),
                ),
              ),
            ],
          ),
          if (details != null && details!.isNotEmpty)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('technical-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Detalles técnicos',
                  style: TextStyle(color: context.dlc.critical, fontSize: 12),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      details!,
                      style: TextStyle(
                        color: context.dlc.critical,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        children: [
          Icon(icon, size: 30, color: context.dlc.muted),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: context.dlc.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.dlc.muted),
          ),
        ],
      ),
    ),
  );
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: CircularProgressIndicator(color: context.dlc.brand)),
  );
}

Map<String, dynamic> mapOf(dynamic x) =>
    x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{};
List<dynamic> listOf(dynamic x) => x is List ? x : const [];
double? num(dynamic x) => x == null ? null : double.tryParse(x.toString());
String fmt(dynamic x) {
  final v = num(x);
  return v == null ? '—' : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
}

String textOf(
  Map<String, dynamic> x,
  List<String> keys, {
  String fallback = '',
}) {
  for (final k in keys) {
    final v = x[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  return fallback;
}

String dateLabel(dynamic raw) {
  final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (d == null) return 'sin fecha';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
