import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'haptics.dart';
import 'ui/account_page.dart';
import 'ui/benefits_page.dart';
import 'ui/branches_page.dart';
import 'ui/format.dart';
import 'ui/home_page.dart';
import 'ui/settings.dart';
import 'ui/tokens.dart';
import 'ui/widgets.dart';

export 'ui/tokens.dart' show buildDlcTheme;

const _apiUrl = String.fromEnvironment(
  'DLC_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:4000/api/v1',
);
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _termsVersion = String.fromEnvironment(
  'CUSTOMER_TERMS_VERSION',
  defaultValue: 'qa-draft-v1',
);
const _authRedirect = String.fromEnvironment(
  'SUPABASE_AUTH_REDIRECT_URL',
  defaultValue: 'sv.com.dlc.dlc_customers://login-callback/',
);

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Shared rules: the same functions drive inline feedback and submission.
String? validateEmail(String? value) =>
    _emailPattern.hasMatch((value ?? '').trim())
    ? null
    : 'Escribe un correo válido.';

String? validatePassword(String? value) => (value ?? '').length < 8
    ? 'La contraseña debe tener al menos 8 caracteres.'
    : null;

String? validateFullName(String? value) =>
    (value ?? '').trim().length < 2 ? 'Escribe tu nombre completo.' : null;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'Uncaught Flutter framework error',
      name: 'dlc.customer.crash',
      error: details.exception.runtimeType,
      stackTrace: details.stack,
      level: 1000,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Uncaught asynchronous application error',
      name: 'dlc.customer.crash',
      error: error.runtimeType,
      stackTrace: stack,
      level: 1200,
    );
    return false;
  };
  if (_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
  }
  runApp(const CustomerApp());
}

class CustomerApp extends StatefulWidget {
  const CustomerApp({super.key});
  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  // Preferences live in memory: the app has no local preference store yet.
  final DlcSettings _settings = DlcSettings();

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, _) => SettingsScope(
      settings: _settings,
      child: MaterialApp(
        title: 'DLC Clientes',
        debugShowCheckedModeBanner: false,
        theme: buildDlcTheme(Brightness.light),
        darkTheme: buildDlcTheme(Brightness.dark),
        themeMode: _settings.themeMode,
        themeAnimationDuration: const Duration(milliseconds: 200),
        themeAnimationCurve: dlcEaseOut,
        home: (_supabaseUrl.isEmpty || _supabaseKey.isEmpty)
            ? const ConfigurationScreen()
            : const CustomerRoot(),
      ),
    ),
  );
}

class ConfigurationScreen extends StatelessWidget {
  const ConfigurationScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandWordmark(height: 48),
              const SizedBox(height: 20),
              Icon(
                CupertinoIcons.wrench,
                size: 32,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              const Text(
                'Falta configuración de QA. Inicia la app con SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY y DLC_API_BASE_URL usando --dart-define.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class CustomerApi {
  CustomerApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  Future<dynamic> get(String path, {String? token}) =>
      _send('GET', path, token: token);
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    required String token,
  }) => _send('POST', path, body: body, token: token);
  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final base = Uri.parse(_apiUrl);
    final normalized = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final route = Uri.parse(path);
    final uri = base.replace(
      path: '$normalized${route.path}',
      query: route.hasQuery ? route.query : null,
    );
    final correlationId = _newId();
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Accept': 'application/json',
          'X-Request-ID': correlationId,
        });
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      dynamic decoded;
      try {
        decoded = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body);
      } on FormatException {
        throw CustomerApiError(
          'El servidor devolvió una respuesta inesperada.',
          status: response.statusCode,
          correlationId: correlationId,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final root = decoded is Map ? decoded : const {};
        final error = root['error'] is Map ? root['error'] as Map : root;
        final message = error['message'] is String
            ? error['message'] as String
            : 'La solicitud no se completó (HTTP ${response.statusCode}).';
        developer.log(
          'Customer API HTTP ${response.statusCode} $method ${_safePath(path)} correlationId=$correlationId',
          name: 'dlc.customer',
          level: 900,
        );
        throw CustomerApiError(
          message,
          status: response.statusCode,
          correlationId: error['correlationId'] as String? ?? correlationId,
        );
      }
      if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
      return decoded;
    } on CustomerApiError {
      rethrow;
    } on Exception catch (error, stack) {
      developer.log(
        'Customer API network failure $method ${_safePath(path)} correlationId=$correlationId',
        name: 'dlc.customer',
        error: error.runtimeType,
        stackTrace: stack,
        level: 1000,
      );
      throw CustomerApiError(
        'No se pudo conectar con DLC. Comprueba tu conexión.',
        correlationId: correlationId,
      );
    }
  }
}

class CustomerApiError implements Exception {
  const CustomerApiError(this.message, {this.status, this.correlationId});
  final String message;
  final int? status;
  final String? correlationId;
  @override
  String toString() => message;
}

String _safePath(String value) => value
    .split('?')
    .first
    .replaceAll(
      RegExp(r'[0-9a-f]{8}-[0-9a-f-]{27,}', caseSensitive: false),
      ':id',
    );
String _newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Customer-facing Spanish text for the most common Supabase auth failures.
String _authMessage(AuthException e) {
  final text = e.message.toLowerCase();
  if (text.contains('invalid login credentials')) {
    return 'Correo o contraseña incorrectos. Revisa tus datos e inténtalo de nuevo.';
  }
  if (text.contains('email not confirmed')) {
    return 'Aún no confirmas tu correo. Abre el enlace que te enviamos.';
  }
  if (text.contains('already registered') || text.contains('already exists')) {
    return 'Ese correo ya tiene una cuenta. Inicia sesión.';
  }
  if (text.contains('rate limit') || text.contains('too many')) {
    return 'Demasiados intentos. Espera un momento antes de volver a intentar.';
  }
  return e.message;
}

class CustomerRoot extends StatefulWidget {
  const CustomerRoot({super.key});
  @override
  State<CustomerRoot> createState() => _CustomerRootState();
}

class _CustomerRootState extends State<CustomerRoot> {
  final api = CustomerApi();
  final TextEditingController branchSearch = TextEditingController();
  Session? get session => Supabase.instance.client.auth.currentSession;
  User? get user => Supabase.instance.client.auth.currentUser;
  Map<String, dynamic>? profile;
  Map<String, dynamic>? loyalty;
  Map<String, dynamic>? qr;
  List<Map<String, dynamic>> rewards = [],
      campaigns = [],
      promotions = [],
      branches = [],
      services = [],
      points = [],
      notifications = [],
      pointPaymentQuotes = [];
  String unreadCount = '0';
  String? selectedPromotionBranchId;
  bool busy = false;
  bool loading = true, loaded = false;
  bool promotionsLoading = false;
  bool balanceCounted = false;
  bool recoveringPassword = false;
  UiError? loadError, actionError;
  DateTime? lastLoaded;
  int tab = 0;
  int _inflight = 0;
  late final StreamSubscription<AuthState> authSubscription;

  @override
  void initState() {
    super.initState();
    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (!mounted) return;
      setState(() {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          recoveringPassword = true;
        }
        // A fresh identity must not flash the previous one's screens.
        if (state.event == AuthChangeEvent.signedOut ||
            (state.event == AuthChangeEvent.signedIn && profile == null)) {
          loaded = false;
          balanceCounted = false;
          tab = 0;
        }
      });
      unawaited(_reload());
    });
    _reload();
  }

  @override
  void dispose() {
    authSubscription.cancel();
    branchSearch.dispose();
    api._client.close();
    super.dispose();
  }

  void _clearPrivateData() {
    profile = null;
    loyalty = null;
    qr = null;
    points = [];
    notifications = [];
    pointPaymentQuotes = [];
    unreadCount = '0';
  }

  /// Reloads everything but keeps the previous data on screen: the skeleton
  /// only shows before the first successful load.
  Future<void> _reload() async {
    if (!mounted) return;
    _inflight++;
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final publicResults = await Future.wait([
        api.get('/customer/rewards'),
        api.get('/customer/campaigns'),
        api.get(_promotionFeedPath),
        api.get('/customer/branches'),
        api.get('/customer/services'),
      ]);
      rewards = _maps(publicResults[0]);
      campaigns = _maps(publicResults[1]);
      promotions = _maps(publicResults[2]);
      branches = _maps(publicResults[3]);
      services = _maps(publicResults[4]);
      final token = session?.accessToken;
      if (token != null) {
        try {
          final results = await Future.wait([
            api.get('/customer/me', token: token),
            api.get('/customer/me/loyalty', token: token),
            api.get('/customer/me/qr', token: token),
            api.get('/customer/me/points', token: token),
            api.get('/customer/me/notifications', token: token),
            api.get('/customer/me/points-payment-quotes', token: token),
          ]);
          profile = _map(results[0]);
          loyalty = _map(results[1]);
          qr = _map(results[2]);
          points = _maps(_map(results[3])['items']);
          notifications = _maps(_map(results[4])['items']);
          unreadCount = _str(_map(results[4])['unreadCount']);
          pointPaymentQuotes = _maps(results[5]);
        } on CustomerApiError catch (e) {
          if (e.status == 404) {
            _clearPrivateData();
          } else {
            rethrow;
          }
        }
      } else {
        _clearPrivateData();
      }
      loaded = true;
      lastLoaded = DateTime.now();
    } on CustomerApiError catch (e) {
      loadError = UiError(e.message, reference: e.correlationId);
    } catch (e, stack) {
      developer.log(
        'Customer reload failure',
        name: 'dlc.customer',
        error: e.runtimeType,
        stackTrace: stack,
        level: 1000,
      );
      loadError = const UiError(
        'No pudimos actualizar tus datos. Inténtalo de nuevo.',
      );
    } finally {
      _inflight--;
      if (mounted) setState(() => loading = _inflight > 0);
    }
  }

  /// Runs [action] behind the busy flag. Returns true on success; on failure
  /// it shows the error banner and plays the error haptic.
  Future<bool> _run(Future<void> Function() action) async {
    if (busy) return false;
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      if (mounted) setState(() => actionError = UiError(_authMessage(e)));
    } on CustomerApiError catch (e) {
      if (mounted) {
        setState(
          () => actionError = UiError(e.message, reference: e.correlationId),
        );
      }
    } catch (e, stack) {
      developer.log(
        'Customer flow failure',
        name: 'dlc.customer',
        error: e.runtimeType,
        stackTrace: stack,
        level: 1000,
      );
      if (mounted) {
        setState(
          () => actionError = const UiError(
            'No se pudo completar esta acción. Intenta de nuevo.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    Haptics.error();
    return false;
  }

  Future<bool> _signOut() => _run(() async {
    await Supabase.instance.client.auth.signOut();
    await _reload();
    Haptics.selection();
  });

  @override
  Widget build(BuildContext context) {
    final signedIn = session != null;
    final ready = signedIn && profile != null && !recoveringPassword;
    final banner = actionError != null
        ? ErrorBanner(
            error: actionError!,
            onDismiss: () => setState(() => actionError = null),
          )
        : (loadError != null && (loaded || !signedIn))
        ? ErrorBanner(
            error: loadError!,
            onRetry: loading ? null : _reload,
            staleSince: loaded ? lastLoaded : null,
          )
        : null;
    return Scaffold(
      appBar: ready
          ? AppBar(
              centerTitle: false,
              title: const BrandWordmark(height: 30),
              actions: [
                IconButton(
                  tooltip: unreadCount == '0'
                      ? 'Avisos'
                      : '$unreadCount avisos sin leer',
                  onPressed: () => _openNotifications(),
                  icon: Badge(
                    isLabelVisible: unreadCount != '0',
                    label: Text(unreadCount),
                    child: const Icon(CupertinoIcons.bell),
                  ),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            ?banner,
            Expanded(child: _body(signedIn)),
          ],
        ),
      ),
      bottomNavigationBar: ready
          ? NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (v) {
                Haptics.selection();
                setState(() => tab = v);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(CupertinoIcons.house),
                  selectedIcon: Icon(CupertinoIcons.house_fill),
                  label: 'Inicio',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.gift),
                  selectedIcon: Icon(CupertinoIcons.gift_fill),
                  label: 'Beneficios',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.qrcode),
                  label: 'Mi código',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.placemark),
                  selectedIcon: Icon(CupertinoIcons.placemark_fill),
                  label: 'Sucursales',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.person),
                  selectedIcon: Icon(CupertinoIcons.person_fill),
                  label: 'Perfil',
                ),
              ],
            )
          : null,
    );
  }

  Widget _body(bool signedIn) {
    if (recoveringPassword) {
      return RecoveryPasswordScreen(
        busy: busy,
        onSubmit: (password) => _run(() async {
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(password: password),
          );
          if (mounted) setState(() => recoveringPassword = false);
          await _reload();
        }),
      );
    }
    if (!signedIn) {
      return AuthScreen(busy: busy, onAction: _run, onChanged: _reload);
    }
    if (!loaded) {
      if (loadError != null && !loading) {
        return ErrorState(
          error: loadError!,
          onRetry: _reload,
          extra: TextButton.icon(
            onPressed: busy ? null : _signOut,
            icon: const Icon(CupertinoIcons.arrow_right_square, size: 18),
            label: const Text('Cerrar sesión'),
          ),
        );
      }
      return const HomeSkeleton();
    }
    if (profile == null) {
      return ProfileScreen(busy: busy, onSubmit: _saveProfile);
    }
    return _signedBody();
  }

  Widget _signedBody() {
    final balance = parseNum(loyalty?['pointsBalance']) ?? 0;
    final page = switch (tab) {
      0 => HomePage(
        profile: profile,
        loyalty: loyalty,
        rewards: rewards,
        points: points,
        branches: branches,
        quotes: pointPaymentQuotes,
        busy: busy,
        animateBalance: !balanceCounted,
        onBalanceCounted: () => balanceCounted = true,
        onDecideQuote: (quote, confirm) => _decidePointPayment(quote, confirm),
        onSeeBranches: () => setState(() => tab = 3),
        onSeeRewards: () => setState(() => tab = 1),
        onSeeHistory: _openHistory,
      ),
      1 => BenefitsPage(
        balance: balance,
        rewards: rewards,
        promotions: promotions,
        campaigns: campaigns,
        services: services,
        branches: branches,
        selectedBranchId: selectedPromotionBranchId,
        promotionsLoading: promotionsLoading,
        onSelectBranch: _selectPromotionBranch,
        onOpenPromotion: (item) => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PromotionDetailPage(promotion: item),
          ),
        ),
      ),
      2 => QrPage(qr: qr),
      3 => BranchesPage(
        branches: branches,
        search: branchSearch,
        onSearchChanged: () => setState(() {}),
      ),
      _ => AccountPage(
        profile: profile,
        email: user?.email,
        busy: busy,
        onSignOut: () => _signOut(),
      ),
    };
    return RefreshIndicator(onRefresh: _reload, child: page);
  }

  void _openHistory() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => HistoryPage(points: points)),
  );

  Future<bool> _decidePointPayment(
    Map<String, dynamic> quote,
    bool confirm,
  ) => _run(() async {
    final token = session?.accessToken;
    if (token == null) {
      throw const CustomerApiError(
        'Inicia sesión para resolver esta solicitud.',
      );
    }
    final id = Uri.encodeComponent(_str(quote['id']));
    final action = confirm ? 'confirm' : 'decline';
    // The quote is single-use, so its UUID is also a durable decision command ID.
    // Retrying after a timeout replays the same confirmation instead of spending twice.
    final result = _map(
      await api.post('/customer/me/points-payment-quotes/$id/$action', {
        'commandId': _str(quote['id']),
      }, token: token),
    );
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _str(result['status']) == 'expired'
                ? 'La solicitud venció. Pide a caja que genere una nueva.'
                : confirm
                ? 'Pago confirmado. Los puntos se aplicaron a la venta.'
                : 'Solicitud rechazada. No se descontaron puntos.',
          ),
        ),
      );
    }
    if (confirm) {
      Haptics.success();
    } else {
      Haptics.selection();
    }
  });

  String get _promotionFeedPath => selectedPromotionBranchId == null
      ? '/customer/promotions'
      : '/customer/promotions?branchId=${Uri.encodeQueryComponent(selectedPromotionBranchId!)}';

  /// Changes the branch filter and refreshes only the promotions list; the
  /// previous promotions stay visible while the new ones load.
  Future<void> _selectPromotionBranch(String? branchId) async {
    setState(() {
      selectedPromotionBranchId = branchId;
      promotionsLoading = true;
      actionError = null;
    });
    try {
      promotions = _maps(await api.get(_promotionFeedPath));
    } on CustomerApiError catch (e) {
      if (mounted) {
        setState(
          () => actionError = UiError(e.message, reference: e.correlationId),
        );
      }
    } finally {
      if (mounted) setState(() => promotionsLoading = false);
    }
  }

  Future<void> _openNotifications() async {
    final token = session?.accessToken;
    if (token == null) return;
    try {
      final result = _map(
        await api.get('/customer/me/notifications', token: token),
      );
      final items = _maps(result['items']);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              CustomerNotificationsPage(api: api, token: token, items: items),
        ),
      );
      await _reload();
    } on CustomerApiError catch (e) {
      if (mounted) setState(() => actionError = UiError(e.message));
    }
  }

  Future<void> _saveProfile(
    String name,
    String phone,
    bool communicationsConsent,
  ) async {
    await _run(() async {
      final token = session?.accessToken;
      if (token == null) {
        throw const CustomerApiError('Inicia sesión nuevamente.');
      }
      await api.post('/customer/me/profile', {
        'fullName': name.trim(),
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
        'termsVersion': _termsVersion,
        'termsAccepted': true,
        'communicationsConsent': communicationsConsent,
      }, token: token);
      await _reload();
    });
  }
}

/// Shared frame for the signed-out screens: centred column, brand on top.
class _AuthFrame extends StatelessWidget {
  const _AuthFrame({required this.formKey, required this.children});
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.busy,
    required this.onAction,
    required this.onChanged,
  });
  final bool busy;
  final Future<bool> Function(Future<void> Function()) onAction;
  final VoidCallback onChanged;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false;
  bool showPassword = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      Haptics.error();
      return;
    }
    await widget.onAction(() async {
      if (register) {
        final result = await Supabase.instance.client.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: _authRedirect,
          data: {'display_name': name.text.trim()},
        );
        if (result.session == null && mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              icon: const Icon(CupertinoIcons.mail, size: 32),
              title: const Text('Revisa tu correo'),
              content: const Text(
                'Enviamos un enlace de confirmación. Ábrelo en este dispositivo; luego inicia sesión.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
          if (mounted) setState(() => register = false);
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
      widget.onChanged();
      Haptics.success();
    });
  }

  Future<void> _resetPassword() => widget.onAction(() async {
    final problem = validateEmail(email.text);
    if (problem != null) throw CustomerApiError(problem);
    await Supabase.instance.client.auth.resetPasswordForEmail(
      email.text.trim(),
      redirectTo: _authRedirect,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Si el correo está registrado, recibirás instrucciones para restablecer tu contraseña.',
          ),
        ),
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _AuthFrame(
      formKey: _formKey,
      children: [
        const SizedBox(height: 8),
        const Center(child: BrandWordmark(height: 64)),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            register ? 'Crea tu cuenta' : 'Bienvenido',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Accede a tus puntos, novedades y beneficios DLC.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        if (register) ...[
          TextFormField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            validator: validateFullName,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              prefixIcon: Icon(CupertinoIcons.person),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          validator: validateEmail,
          decoration: const InputDecoration(
            labelText: 'Correo electrónico',
            prefixIcon: Icon(CupertinoIcons.mail),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: password,
          obscureText: !showPassword,
          autofillHints: [
            register ? AutofillHints.newPassword : AutofillHints.password,
          ],
          validator: validatePassword,
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(CupertinoIcons.lock),
            suffixIcon: IconButton(
              tooltip: showPassword
                  ? 'Ocultar contraseña'
                  : 'Mostrar contraseña',
              icon: Icon(
                showPassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
              ),
              onPressed: () => setState(() => showPassword = !showPassword),
            ),
          ),
        ),
        const SizedBox(height: 20),
        DlcButton(
          label: register ? 'Crear cuenta' : 'Iniciar sesión',
          icon: register
              ? CupertinoIcons.person_add
              : CupertinoIcons.arrow_right_circle,
          busy: widget.busy,
          onPressed: widget.busy ? null : _submit,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: widget.busy
              ? null
              : () => setState(() => register = !register),
          child: Text(register ? 'Ya tengo cuenta' : 'Crear una cuenta'),
        ),
        if (!register)
          TextButton(
            onPressed: widget.busy ? null : _resetPassword,
            child: const Text('Olvidé mi contraseña'),
          ),
        const SizedBox(height: 10),
        Text(
          'Cuenta de prueba: las condiciones legales deben aprobarse antes de activar producción.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class RecoveryPasswordScreen extends StatefulWidget {
  const RecoveryPasswordScreen({
    super.key,
    required this.busy,
    required this.onSubmit,
  });
  final bool busy;
  final Future<bool> Function(String password) onSubmit;
  @override
  State<RecoveryPasswordScreen> createState() => _RecoveryPasswordScreenState();
}

class _RecoveryPasswordScreenState extends State<RecoveryPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final password = TextEditingController();
  bool showPassword = false;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      Haptics.error();
      return;
    }
    widget.onSubmit(password.text);
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(
    formKey: _formKey,
    children: [
      const SizedBox(height: 8),
      const Center(child: BrandWordmark(height: 48)),
      const SizedBox(height: 20),
      Semantics(
        header: true,
        child: const Text(
          'Crea una contraseña nueva',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: password,
        obscureText: !showPassword,
        autofillHints: const [AutofillHints.newPassword],
        validator: validatePassword,
        decoration: InputDecoration(
          labelText: 'Nueva contraseña',
          prefixIcon: const Icon(CupertinoIcons.lock),
          suffixIcon: IconButton(
            tooltip: showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
            icon: Icon(
              showPassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
            ),
            onPressed: () => setState(() => showPassword = !showPassword),
          ),
        ),
      ),
      const SizedBox(height: 16),
      DlcButton(
        label: 'Guardar contraseña',
        icon: CupertinoIcons.check_mark,
        busy: widget.busy,
        onPressed: widget.busy ? null : _submit,
      ),
    ],
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.busy, required this.onSubmit});
  final bool busy;
  final Future<void> Function(String name, String phone, bool consent) onSubmit;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final name = TextEditingController(), phone = TextEditingController();
  bool termsAccepted = false, communicationsConsent = false;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      Haptics.error();
      return;
    }
    if (!termsAccepted) {
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes aceptar las condiciones para crear el perfil.'),
        ),
      );
      return;
    }
    widget.onSubmit(name.text, phone.text, communicationsConsent);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _AuthFrame(
      formKey: _formKey,
      children: [
        const SizedBox(height: 8),
        const Center(child: BrandWordmark(height: 48)),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: const Text(
            'Completa tu perfil',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              CupertinoIcons.checkmark_seal,
              size: 18,
              color: context.dlc.ok.fg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Correo verificado: ${Supabase.instance.client.auth.currentUser?.email ?? ''}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          validator: validateFullName,
          decoration: const InputDecoration(
            labelText: 'Nombre completo',
            prefixIcon: Icon(CupertinoIcons.person),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Teléfono (opcional)',
            prefixIcon: Icon(CupertinoIcons.phone),
          ),
        ),
        CheckboxListTile(
          value: termsAccepted,
          onChanged: (v) => setState(() => termsAccepted = v ?? false),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Acepto las condiciones vigentes de la cuenta. Las recompensas solo estarán disponibles cuando se publique el programa.',
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          value: communicationsConsent,
          onChanged: (v) => setState(() => communicationsConsent = v ?? false),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Quiero recibir novedades y comunicaciones promocionales (opcional).',
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 8),
        DlcButton(
          label: 'Guardar y continuar',
          icon: CupertinoIcons.check_mark,
          busy: widget.busy,
          onPressed: widget.busy ? null : _submit,
        ),
      ],
    );
  }
}

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
    : const [];
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
String _str(dynamic value) => value?.toString() ?? '';

class PromotionDetailPage extends StatelessWidget {
  const PromotionDetailPage({super.key, required this.promotion});
  final Map<String, dynamic> promotion;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.dlc;
    final settings = SettingsScope.of(context);
    final terms = _map(promotion['terms']);
    final excludes = asStrings(terms['excludes']);
    final branchName = _str(promotion['branchName']);
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de promoción')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_str(promotion['imageUrl']).isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                _str(promotion['imageUrl']),
                height: 220,
                fit: BoxFit.cover,
                semanticLabel: _str(promotion['imageAlt']),
                errorBuilder: (_, _, _) => SizedBox(
                  height: 120,
                  child: Center(
                    child: Icon(
                      CupertinoIcons.photo,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _str(promotion['title']),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                promotionKindIcon(promotion['kind']),
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  promotionHeadline(
                    promotion,
                    unit: settings.volumeUnit,
                    decimals: settings.decimals,
                  ),
                  style: numeric(
                    TextStyle(
                      fontSize: 18,
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (branchName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Sucursal: $branchName'),
          ],
          const SizedBox(height: 10),
          Text(_str(promotion['motive'])),
          const SizedBox(height: 18),
          DlcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: CupertinoIcons.calendar,
                  title: 'Vigencia',
                ),
                Text(
                  '${formatDate(promotion['startsAt'])} — ${formatDate(promotion['endsAt'])}',
                ),
                Text('Zona horaria: ${_str(promotion['timeZone'])}'),
                Text(
                  'Repetición: ${recurrenceLabel(_map(promotion['recurrence']))}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DlcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: CupertinoIcons.check_mark_circled,
                  title: 'Aplica cuando',
                ),
                for (final item in asStrings(terms['applies']))
                  _TermRow(
                    icon: CupertinoIcons.check_mark_circled,
                    color: colors.ok.fg,
                    text: item,
                  ),
                if (excludes.isNotEmpty) ...[
                  const Divider(),
                  const SectionHeader(
                    icon: CupertinoIcons.nosign,
                    title: 'No aplica en',
                  ),
                  for (final item in excludes)
                    _TermRow(
                      icon: CupertinoIcons.xmark_circle,
                      color: colors.crit.fg,
                      text: item,
                    ),
                ],
              ],
            ),
          ),
          if (_str(promotion['kind']) == 'cashback')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'El cashback queda sujeto a los términos publicados y a la validación de la entidad financiera participante.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _TermRow extends StatelessWidget {
  const _TermRow({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class CustomerNotificationsPage extends StatefulWidget {
  const CustomerNotificationsPage({
    super.key,
    required this.api,
    required this.token,
    required this.items,
  });
  final CustomerApi api;
  final String token;
  final List<Map<String, dynamic>> items;
  @override
  State<CustomerNotificationsPage> createState() =>
      _CustomerNotificationsPageState();
}

class _CustomerNotificationsPageState extends State<CustomerNotificationsPage> {
  late List<Map<String, dynamic>> items = widget.items;
  UiError? error;
  final Set<String> busy = {};

  Future<void> _read(Map<String, dynamic> item) async {
    final id = _str(item['id']);
    if (id.isEmpty || item['readAt'] != null || busy.contains(id)) return;
    setState(() {
      busy.add(id);
      error = null;
    });
    try {
      await widget.api.post('/customer/me/notifications/read', {
        'notificationId': id,
      }, token: widget.token);
      if (mounted) {
        setState(() {
          item['readAt'] = DateTime.now().toUtc().toIso8601String();
        });
      }
    } on CustomerApiError catch (e) {
      if (mounted) setState(() => error = UiError(e.message));
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Avisos')),
      body: Column(
        children: [
          if (error != null)
            ErrorBanner(
              error: error!,
              onDismiss: () => setState(() => error = null),
            ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: EmptyState(
                      icon: CupertinoIcons.bell_slash,
                      message:
                          'No tienes avisos por el momento. Aquí verás novedades de tus puntos y promociones.',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _NotificationTile(
                            item: item,
                            busy: busy.contains(_str(item['id'])),
                            onTap: () => _read(item),
                            scheme: scheme,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.scheme,
  });
  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final unread = item['readAt'] == null;
    final colors = context.dlc;
    return DlcCard(
      weight: CardWeight.compact,
      onTap: onTap,
      semanticLabel: unread ? 'Aviso sin leer' : 'Aviso leído',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: notificationIcon(item['type']),
            tone: unread ? colors.accents[0] : colors.info,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _str(item['title']),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (_str(item['body']).isNotEmpty) Text(_str(item['body'])),
                const SizedBox(height: 4),
                Text(
                  formatDateTime(item['createdAt']),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (unread) ...[
                  const SizedBox(height: 6),
                  const StatusChip(
                    look: StatusLook(
                      'Nuevo',
                      CupertinoIcons.circle_fill,
                      ToneKind.brand,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}
