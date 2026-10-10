import 'package:dlc_api/dlc_api.dart';
import 'app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'infrastructure_setup_screen.dart';
import 'staff_shifts_screen.dart';
import 'branch_prices_screen.dart';
import 'country_catalog.dart';
import 'haptics.dart';
import 'branch_status.dart';
import 'live_form.dart';
import 'validators.dart';

class BranchOnboardingScreen extends StatefulWidget {
  const BranchOnboardingScreen({
    required this.api,
    required this.onActivated,
    this.initialBranchId,
    super.key,
  });
  final EmployeeSession api;
  final VoidCallback onActivated;

  /// Opens the readiness wizard directly on this branch (e.g. from the
  /// "branch is in preparation" state).
  final String? initialBranchId;
  @override
  State<BranchOnboardingScreen> createState() => _BranchOnboardingScreenState();
}

const kAcademicLabProfile = 'academicLab22';
const kAcademicLabDispenserCount = 6;

/// The server rejects `academicLab22` with any dispenser count other than 6,
/// so that profile always sends exactly six.
int dispenserCountForProfile(String profile, int requested) =>
    profile == kAcademicLabProfile ? kAcademicLabDispenserCount : requested;

class _BranchOnboardingScreenState extends State<BranchOnboardingScreen> {
  final _code = TextEditingController(),
      _name = TextEditingController(),
      _timezone = TextEditingController(text: 'America/El_Salvador');
  List<BranchSummary> _drafts = const [];
  BranchSummary? _selected;
  Map<String, dynamic> _detail = const {}, _readiness = const {};
  Set<String> _permissions = const {};
  String _zone = 'central',
      _profile = 'academicLab22',
      _country = kDefaultCountryCode;
  int _expectedDispensers = 6;
  final _dispensers = TextEditingController(text: '6');
  bool _loading = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(branchId: widget.initialBranchId);
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _timezone.dispose();
    _dispensers.dispose();
    super.dispose();
  }

  Future<void> _load({String? branchId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drafts = [...await widget.api.branches(status: 'draft')];
      if (branchId != null && !drafts.any((b) => b.id == branchId)) {
        // A configured (not yet active) branch is not part of the draft list.
        try {
          final extra = BranchSummary.fromJson(
            await widget.api.branchDetail(branchId),
          );
          if (extra.isInPreparation) drafts.add(extra);
        } on DlcApiException {
          // Fall back to the plain draft list.
        }
      }
      _drafts = drafts;
      if (branchId != null)
        _selected = drafts.where((b) => b.id == branchId).firstOrNull;
      if (_selected != null && !_drafts.any((b) => b.id == _selected!.id))
        _selected = null;
      if (_selected != null) {
        final data = await Future.wait<dynamic>([
          widget.api.branchDetail(_selected!.id),
          widget.api.branchReadiness(_selected!.id),
          widget.api.capabilities(branchId: _selected!.id),
        ]);
        _detail = data[0] as Map<String, dynamic>;
        _readiness = data[1] as Map<String, dynamic>;
        _permissions = (data[2] as List<String>).toSet();
      }
    } on DlcApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Live validation of the draft form; the primary button needs all null.
  List<String?> get _draftErrors => [
    branchCode(_code.text),
    requiredText(_name.text, field: 'El nombre') ??
        maxLengthText(_name.text, 120, field: 'El nombre'),
    ianaTimezone(_timezone.text),
    if (_profile == 'operational')
      integerInRange(
        _dispensers.text,
        min: 1,
        max: 200,
        field: 'Los dispensadores',
      ),
  ];

  bool get _draftValid => allValid(_draftErrors);

  Future<void> _create() async {
    if (!_draftValid) {
      Haptics.error();
      setState(() => _error = 'Corrige los campos marcados antes de crear.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.api.createBranchDraft(
        code: _code.text,
        name: _name.text,
        zone: _zone,
        timezone: _timezone.text,
        profile: _profile,
        expectedDispenserCount: dispenserCountForProfile(
          _profile,
          _expectedDispensers,
        ),
        countryCode: _country,
      );
      Haptics.success();
      final id = result['id']?.toString();
      _code.clear();
      _name.clear();
      await _load(branchId: id);
    } on DlcApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeCountry(String code) async {
    final id = _selected?.id;
    if (id == null || code == normalizeCountryCode(_detail['countryCode'])) return;
    Haptics.selection();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveBranchStep(
        id,
        expectedVersion: _int(_readiness['onboardingVersion']),
        step: 'identity',
        data: {'countryCode': code},
      );
      Haptics.success();
      await _load(branchId: id);
    } on DlcApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openInfrastructure() async {
    final id = _selected?.id;
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => InfrastructureSetupScreen(
          api: widget.api,
          branchId: id,
          permissions: _permissions,
        ),
      ),
    );
    if (mounted) await _load(branchId: id);
  }

  Future<void> _openStaff() async {
    final id = _selected?.id;
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StaffShiftsScreen(
          api: widget.api,
          branchId: id,
          permissions: _permissions.difference({'staff.shifts.plan'}),
        ),
      ),
    );
    if (mounted) await _load(branchId: id);
  }

  Future<void> _openPrices() async {
    final id = _selected?.id;
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BranchPricesScreen(
          api: widget.api,
          branchId: id,
          permissions: _permissions,
        ),
      ),
    );
    if (mounted) await _load(branchId: id);
  }

  Future<void> _confirmStaff() async {
    final id = _selected?.id;
    if (id == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rows = await widget.api.staffEmployees(id);
      if (rows.isEmpty) {
        if (mounted)
          setState(() {
            _error =
                'Registra al menos una persona activa antes de confirmar la revisión.';
            _saving = false;
          });
        return;
      }
      await widget.api.saveBranchStep(
        id,
        expectedVersion: _int(_readiness['onboardingVersion']),
        step: 'staff',
        data: {'status': 'confirmed', 'employeeCount': rows.length},
      );
      await _load(branchId: id);
    } on DlcApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _activate() async {
    final branch = _selected;
    if (branch == null) return;
    final version = _int(_readiness['onboardingVersion']);
    if (_readiness['canActivate'] != true ||
        !_permissions.contains('branch.activate'))
      return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.activateBranch(branch.id, version);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sucursal activada.')));
        widget.onActivated();
        Navigator.pop(context);
      }
    } on DlcApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Alta de sucursal'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Actualizar',
          icon: const Icon(CupertinoIcons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: context.dlc.criticalContainer,
                    child: ListTile(
                      leading: const Icon(CupertinoIcons.exclamationmark_circle),
                      title: Text(_error!),
                    ),
                  ),
                if (_selected == null) ...[
                  Text(
                    'Crear borrador',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  LiveTextField(
                    controller: _code,
                    label: 'Código',
                    helper: 'Ej. SV-001 (letras, números, guion).',
                    maxLength: 24,
                    textCapitalization: TextCapitalization.characters,
                    validator: branchCode,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  LiveTextField(
                    controller: _name,
                    label: 'Nombre de sucursal',
                    maxLength: 120,
                    validator: (v) =>
                        requiredText(v, field: 'El nombre') ??
                        maxLengthText(v, 120, field: 'El nombre'),
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  CountryDropdown(
                    value: _country,
                    onChanged: (v) {
                      Haptics.selection();
                      setState(() => _country = v ?? _country);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _zone,
                    decoration: const InputDecoration(labelText: 'Zona'),
                    items: const [
                      DropdownMenuItem(
                        value: 'occidental',
                        child: Text('Occidental'),
                      ),
                      DropdownMenuItem(
                        value: 'central',
                        child: Text('Central'),
                      ),
                      DropdownMenuItem(
                        value: 'oriental',
                        child: Text('Oriental'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Otra')),
                    ],
                    onChanged: (v) => setState(() => _zone = v ?? _zone),
                  ),
                  const SizedBox(height: 8),
                  LiveTextField(
                    controller: _timezone,
                    label: 'Zona horaria (IANA)',
                    validator: ianaTimezone,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _profile,
                    decoration: const InputDecoration(labelText: 'Perfil'),
                    items: const [
                      DropdownMenuItem(
                        value: 'academicLab22',
                        child: Text('Laboratorio 22 · 6 dispensadores'),
                      ),
                      DropdownMenuItem(
                        value: 'operational',
                        child: Text('Operativo'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      _profile = v ?? _profile;
                      if (_profile == kAcademicLabProfile) {
                        _expectedDispensers = kAcademicLabDispenserCount;
                      } else {
                        _expectedDispensers =
                            int.tryParse(_dispensers.text.trim()) ??
                            _expectedDispensers;
                      }
                    }),
                  ),
                  if (_profile == 'operational') ...[
                    const SizedBox(height: 8),
                    LiveTextField(
                      controller: _dispensers,
                      label: 'Dispensadores esperados',
                      helper: 'Entre 1 y 200.',
                      keyboardType: TextInputType.number,
                      validator: (v) => integerInRange(
                        v,
                        min: 1,
                        max: 200,
                        field: 'Los dispensadores',
                      ),
                      onChanged: () => setState(
                        () => _expectedDispensers =
                            int.tryParse(_dispensers.text.trim()) ?? 1,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving || !_draftValid ? null : _create,
                    icon: const Icon(CupertinoIcons.plus_app),
                    label: Text(_saving ? 'Creando…' : 'Crear y configurar'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Borradores existentes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_drafts.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('No hay borradores pendientes.'),
                      ),
                    ),
                  ..._drafts.map(
                    (b) => Card(
                      child: ListTile(
                        leading: const Icon(CupertinoIcons.bag),
                        title: Text(b.name),
                        subtitle: Text(
                          '${b.code} · ${countryName(b.countryCode)} · versión ${b.onboardingVersion}',
                        ),
                        trailing: const Icon(CupertinoIcons.chevron_right),
                        onTap: () => _load(branchId: b.id),
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_selected!.name} · configuración',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _selected = null),
                        tooltip: 'Volver a borradores',
                        icon: const Icon(CupertinoIcons.list_bullet),
                      ),
                    ],
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(CupertinoIcons.bag),
                      title: Text(
                        'Código ${_str(_detail['code'])} · ${_str(_detail['status']).isEmpty ? 'draft' : _str(_detail['status'])}',
                      ),
                      subtitle: Text(
                        'País: ${countryName(_detail['countryCode']?.toString())} · Zona: ${_str(_detail['zone'])} · Horario: ${_str(_detail['timezone'] ?? _detail['timeZone'])}',
                      ),
                    ),
                  ),
                  if (_permissions.contains('branch.manage'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: CountryDropdown(
                        value: normalizeCountryCode(_detail['countryCode']),
                        enabled: !_saving,
                        onChanged: (v) {
                          if (v != null) _changeCountry(v);
                        },
                      ),
                    ),
                  Card(
                    child: ListTile(
                      leading: const Icon(CupertinoIcons.checkmark_rectangle),
                      title: Text(
                        _readiness['canActivate'] == true
                            ? 'Lista para activar'
                            : 'Preparación pendiente',
                      ),
                      subtitle: Text(
                        '${listOf(_readiness['blockers']).length} requisito(s) pendiente(s) · versión ${_readiness['onboardingVersion'] ?? _selected!.onboardingVersion}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _action(
                    'Combustibles, tanques y dispensadores',
                    'Configura oferta, tanques, mangueras y saldo inicial.',
                    CupertinoIcons.gauge,
                    _permissions.contains('infrastructure.read')
                        ? _openInfrastructure
                        : null,
                  ),
                  _action(
                    'Personal',
                    'Registra empleados activos antes de activar.',
                    CupertinoIcons.person_3,
                    _permissions.contains('staff.read') ? _openStaff : null,
                  ),
                  _action(
                    'Precios vigentes',
                    'Propón, aprueba con otra persona y programa cada precio.',
                    CupertinoIcons.tag,
                    _permissions.contains('price.read') ? _openPrices : null,
                  ),
                  if (_permissions.contains('staff.manage'))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _confirmStaff,
                        icon: const Icon(CupertinoIcons.checkmark_seal),
                        label: const Text('Confirmar revisión del personal'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Requisitos del servidor',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ...listOf(_readiness['blockers']).map((raw) {
                    final row = mapOf(raw);
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          CupertinoIcons.clock,
                          color: context.dlc.warning,
                        ),
                        title: Text(_str(row['message'])),
                        subtitle: Text(
                          '${_str(row['step'])} · ${_str(row['code'])}',
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  if (_permissions.contains('branch.activate'))
                    FilledButton.icon(
                      onPressed: _saving || _readiness['canActivate'] != true
                          ? null
                          : _activate,
                      icon: const Icon(CupertinoIcons.checkmark_circle),
                      label: Text(_saving ? 'Guardando…' : 'Activar sucursal'),
                    ),
                  if (_readiness['canActivate'] != true)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'La activación se habilita cuando el servidor valide todos los requisitos, incluidos precios efectivos y datos operativos.',
                        style: TextStyle(color: context.dlc.muted),
                      ),
                    ),
                ],
              ],
            ),
          ),
  );

  Widget _action(
    String title,
    String detail,
    IconData icon,
    VoidCallback? action,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(detail),
      trailing: const Icon(CupertinoIcons.chevron_right),
      onTap: action,
    ),
  );
}

Map<String, dynamic> mapOf(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<dynamic> listOf(dynamic value) => value is List ? value : const [];
String _str(dynamic value) => value?.toString() ?? '';
int _int(dynamic value) => int.tryParse('$value') ?? 1;
