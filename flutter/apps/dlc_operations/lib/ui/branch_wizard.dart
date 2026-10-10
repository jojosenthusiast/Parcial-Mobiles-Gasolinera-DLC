import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../branch_prices_screen.dart';
import '../code_suggest.dart';
import '../country_catalog.dart';
import '../format.dart';
import '../haptics.dart';
import '../infrastructure_setup_screen.dart';
import '../labels.dart';
import '../live_form.dart';
import '../preferences.dart';
import '../staff_shifts_screen.dart';
import '../validators.dart';
import 'form_sheet.dart';
import 'kit.dart';
import 'util.dart';
import 'wizard_logic.dart';

/// "Alta de sucursal" as a guided stepper with checkpoints (5 steps).
///
/// Server mapping (PATCH /branches/:id/onboarding): the branch is created
/// when infrastructure is confirmed (the operating profile and pump count are
/// fixed at creation); every step then writes its own checkpoint
/// (identity, products, tanks, dispensers, staff, review). Until the branch
/// exists, steps are saved as a local draft. The store step has no server
/// equivalent: it is stored inside the `review` checkpoint only.
class BranchWizardPage extends StatefulWidget {
  const BranchWizardPage({
    required this.api,
    required this.existingCodes,
    this.branchId,
    this.onChanged,
    super.key,
  });
  final EmployeeSession api;
  final List<String> existingCodes;

  /// Resume this draft branch instead of starting a new one.
  final String? branchId;

  /// Called after the branch changed on the server (created, saved, activated).
  final VoidCallback? onChanged;

  @override
  State<BranchWizardPage> createState() => _BranchWizardPageState();
}

class _BranchWizardPageState extends State<BranchWizardPage> {
  final _name = TextEditingController(),
      _code = TextEditingController(),
      _timezone = TextEditingController(text: 'America/El_Salvador'),
      _pumps = TextEditingController(text: '6'),
      _tanks = TextEditingController(text: '3'),
      _staffName = TextEditingController(),
      _staffEmail = TextEditingController(),
      _staffCode = TextEditingController(text: 'EMP-01'),
      _registers = TextEditingController(text: '1');

  late final DraftBinder _draft;
  String _country = kDefaultCountryCode;
  String _zone = 'central';
  final Set<String> _fuels = {'super', 'regular', 'diesel'};
  bool _hasStore = false;
  bool _staffLater = false;
  int _step = 0;
  String? _branchId;
  int _version = 1;
  String _status = 'draft';
  bool _loading = true, _busy = false, _restored = false, _codeTouched = false;
  bool _done = false, _staffRegistered = false;
  String? _error;
  final Map<int, DateTime> _savedAt = {};
  final Map<int, bool> _savedOnServer = {};
  Map<String, dynamic> _readiness = const {};
  Set<String> _permissions = const {};

  @override
  void initState() {
    super.initState();
    _draft = DraftBinder(
      store: SessionKeyValueStore(widget.api),
      key: 'branchWizard',
      fields: {
        'name': _name,
        'code': _code,
        'timezone': _timezone,
        'pumps': _pumps,
        'tanks': _tanks,
        'staffName': _staffName,
        'staffEmail': _staffEmail,
        'staffCode': _staffCode,
        'registers': _registers,
      },
      extra: () => {
        'country': _country,
        'zone': _zone,
        'fuels': _fuels.join(','),
        'store': '$_hasStore',
        'later': '$_staffLater',
        'step': '$_step',
        'branchId': _branchId ?? '',
        'registered': '$_staffRegistered',
      },
    );
    _init();
  }

  @override
  void dispose() {
    _draft.dispose();
    for (final c in [
      _name, _code, _timezone, _pumps, _tanks, _staffName, _staffEmail,
      _staffCode, _registers,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Loading / resuming
  // -------------------------------------------------------------------------

  Future<void> _init() async {
    String? resumeId = widget.branchId;
    int localStep = 0;
    if (resumeId == null) {
      final saved = await _draft.restore();
      if (saved != null) {
        _restored = true;
        _country = saved['country'] ?? _country;
        _zone = saved['zone'] ?? _zone;
        final fuels = (saved['fuels'] ?? '').split(',').where(wizardFuels.containsKey);
        if (fuels.isNotEmpty) {
          _fuels
            ..clear()
            ..addAll(fuels);
        }
        _hasStore = saved['store'] == 'true';
        _staffLater = saved['later'] == 'true';
        _staffRegistered = saved['registered'] == 'true';
        localStep = (int.tryParse(saved['step'] ?? '') ?? 0).clamp(0, kWizardSteps - 1);
        final id = saved['branchId'];
        if (id != null && id.isNotEmpty) resumeId = id;
      }
    }
    if (resumeId != null) {
      await _loadServer(resumeId, localStep: localStep);
    } else {
      _step = localStep;
      if (_code.text.trim().isEmpty) _suggestCode();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _suggestCode() {
    _code.text = suggestBranchCode(widget.existingCodes, _country);
  }

  Future<void> _loadServer(String id, {int localStep = 0}) async {
    try {
      final values = await Future.wait<dynamic>([
        widget.api.branchDetail(id),
        widget.api.capabilities(branchId: id),
      ]);
      final detail = values[0] as Map<String, dynamic>;
      _permissions = (values[1] as List<String>).toSet();
      _branchId = id;
      _version = int.tryParse('${detail['onboardingVersion']}') ?? 1;
      _status = asText(detail['status'], 'draft');
      _name.text = asText(detail['name']);
      _code.text = asText(detail['code']);
      _timezone.text = asText(detail['timezone'], _timezone.text);
      _country = normalizeCountryCode(detail['countryCode']);
      _zone = asText(detail['zone'], _zone);
      final od = asMap(detail['onboardingData']);
      final fuels = asList(asMap(od['products'])['fuels']).map((e) => '$e');
      final usable = fuels.where(wizardFuels.containsKey).toList();
      if (usable.isNotEmpty) {
        _fuels
          ..clear()
          ..addAll(usable);
      }
      final tanks = asMap(od['tanks'])['planned'];
      if (tanks != null) _tanks.text = '$tanks';
      final pumps = asMap(od['dispensers'])['planned'] ?? od['expectedDispenserCount'];
      if (pumps != null) _pumps.text = '$pumps';
      final store = asMap(asMap(od['review'])['store']);
      if (store.isNotEmpty) {
        _hasStore = store['enabled'] == true;
        _registers.text = '${store['registers'] ?? 1}';
      }
      final staff = asMap(od['staff']);
      _staffLater = staff['status'] == 'deferred';
      for (final k in const ['identity', 'products', 'dispensers', 'staff', 'review']) {
        if (od.containsKey(k)) {
          final idx = switch (k) {
            'identity' => 0,
            'products' || 'dispensers' => 1,
            'staff' => 2,
            _ => 3,
          };
          _savedOnServer[idx] = true;
        }
      }
      final resume = resumeStepFor(od);
      _step = widget.branchId != null
          ? resume
          : (localStep > resume ? localStep : resume);
      if (_step == kWizardSteps - 1) await _loadReadiness();
    } on DlcApiException catch (e) {
      _error = e.message;
    }
  }

  Future<void> _loadReadiness() async {
    final id = _branchId;
    if (id == null) return;
    try {
      final r = await widget.api.branchReadiness(id);
      final d = await widget.api.branchDetail(id);
      if (!mounted) return;
      setState(() {
        _readiness = r;
        _version = int.tryParse('${d['onboardingVersion']}') ?? _version;
        _status = asText(d['status'], _status);
      });
    } on DlcApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  // -------------------------------------------------------------------------
  // Validation
  // -------------------------------------------------------------------------

  String? get _codeError {
    final base = branchCode(_code.text);
    if (base != null) return base;
    if (_branchId == null && codeExists(widget.existingCodes, _code.text)) {
      return 'Ese código ya existe. Prueba con ${suggestBranchCode([...widget.existingCodes, _code.text], _country)}.';
    }
    return null;
  }

  String? _nameError(String? v) =>
      requiredText(v, field: 'El nombre') ?? maxLengthText(v, 120, field: 'El nombre');

  String? _pumpsError(String? v) =>
      integerInRange(v, min: 1, max: 200, field: 'Las bombas');

  String? _tanksError(String? v) => tanksForFuels(v, _fuels.length);

  String? _staffNameError(String? v) => personName(v, field: 'El nombre');
  String? _staffCodeError(String? v) => branchCode(v);
  String? _staffEmailError(String? v) =>
      (v == null || v.trim().isEmpty) ? null : emailAddress(v);
  String? _registersError(String? v) =>
      integerInRange(v, min: 1, max: 10, field: 'Las cajas');

  bool _stepValid(int step) => switch (step) {
    0 =>
      _codeError == null &&
          _nameError(_name.text) == null &&
          ianaTimezone(_timezone.text) == null,
    1 =>
      _pumpsError(_pumps.text) == null &&
          _fuels.isNotEmpty &&
          _tanksError(_tanks.text) == null,
    2 =>
      _staffLater ||
          _staffRegistered ||
          (_staffNameError(_staffName.text) == null &&
              _staffCodeError(_staffCode.text) == null &&
              _staffEmailError(_staffEmail.text) == null),
    3 => !_hasStore || _registersError(_registers.text) == null,
    _ => true,
  };

  // -------------------------------------------------------------------------
  // Saving checkpoints
  // -------------------------------------------------------------------------

  Future<void> _saveStep(String step, Map<String, dynamic> data) async {
    final id = _branchId!;
    final result = await widget.api.saveBranchStep(
      id,
      expectedVersion: _version,
      step: step,
      data: data,
    );
    _version = int.tryParse('${result['onboardingVersion']}') ?? _version + 1;
  }

  Future<void> _continue() async {
    if (_busy || !_stepValid(_step)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final stepIndex = _step;
    try {
      switch (stepIndex) {
        case 0:
          await _draft.save();
          if (_branchId != null) {
            await _saveStep('identity', {
              'code': _code.text.trim().toUpperCase(),
              'name': _name.text.trim(),
              'zone': _zone,
              'timezone': _timezone.text.trim(),
              'countryCode': _country,
            });
            _savedOnServer[0] = true;
            widget.onChanged?.call();
          }
        case 1:
          await _saveInfrastructure();
        case 2:
          await _saveStaff();
        case 3:
          await _saveStore();
      }
      Haptics.success();
      if (!mounted) return;
      setState(() {
        _savedAt[stepIndex] = DateTime.now();
        _step = stepIndex + 1;
      });
      await _draft.save();
      if (_step == kWizardSteps - 1) await _loadReadiness();
    } on DlcApiException catch (e) {
      Haptics.error();
      if (!mounted) return;
      setState(() {
        _error = e.message;
        // A duplicate code is a step-1 problem.
        if (e.statusCode == 409 && _branchId == null) _step = 0;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveInfrastructure() async {
    final pumps = int.parse(_pumps.text.trim());
    if (_branchId == null) {
      final created = await widget.api.createBranchDraft(
        code: _code.text,
        name: _name.text,
        zone: _zone,
        timezone: _timezone.text,
        profile: profileForPumps(pumps),
        expectedDispenserCount: pumps,
        countryCode: _country,
      );
      final id = asText(created['id']);
      if (id.isEmpty) {
        throw const DlcApiException('No se pudo crear el borrador. Intenta de nuevo.');
      }
      _branchId = id;
      final detail = await widget.api.branchDetail(id);
      _version = int.tryParse('${detail['onboardingVersion']}') ?? 1;
      try {
        _permissions = (await widget.api.capabilities(branchId: id)).toSet();
      } on DlcApiException {
        _permissions = const {};
      }
      _savedOnServer[0] = true;
      widget.onChanged?.call();
    }
    await _saveStep('products', {'fuels': _fuels.toList()});
    await _saveStep('tanks', {'planned': int.parse(_tanks.text.trim())});
    await _saveStep('dispensers', {'planned': pumps});
    _savedOnServer[1] = true;
    widget.onChanged?.call();
  }

  Future<void> _saveStaff() async {
    final id = _branchId!;
    if (_staffLater) {
      await _saveStep('staff', {'status': 'deferred', 'employeeCount': 0});
    } else {
      if (!_staffRegistered) {
        await widget.api.createStaffEmployee(
          id,
          employeeCode: _staffCode.text,
          legalName: _staffName.text,
          positionTitle: 'Administrador de sucursal',
          contactEmail: _staffEmail.text,
        );
        _staffRegistered = true;
      }
      final employees = await widget.api.staffEmployees(id);
      await _saveStep('staff', {
        'status': employees.isEmpty ? 'deferred' : 'confirmed',
        'employeeCount': employees.length,
      });
    }
    _savedOnServer[2] = true;
    widget.onChanged?.call();
  }

  Future<void> _saveStore() async {
    // No server step exists for the store yet: it travels in `review`.
    await _saveStep('review', {
      'store': {
        'enabled': _hasStore,
        if (_hasStore) 'registers': int.parse(_registers.text.trim()),
      },
    });
    _savedOnServer[3] = true;
    widget.onChanged?.call();
  }

  Future<void> _activate() async {
    final id = _branchId;
    if (id == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.activateBranch(id, _version);
      await _draft.clear();
      Haptics.success();
      widget.onChanged?.call();
      if (mounted) setState(() => _done = true);
    } on DlcApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
      await _loadReadiness();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAndExit() async {
    await _draft.save();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _resolve(String step) async {
    final id = _branchId;
    if (id == null) return;
    final perms = _permissions;
    Widget? page = switch (step) {
      'products' || 'tanks' || 'dispensers' || 'openingBalances' =>
        InfrastructureSetupScreen(api: widget.api, branchId: id, permissions: perms),
      'staff' => StaffShiftsScreen(
        api: widget.api,
        branchId: id,
        permissions: perms.difference({'staff.shifts.plan'}),
      ),
      'prices' => BranchPricesScreen(api: widget.api, branchId: id, permissions: perms),
      _ => null,
    };
    if (page == null) return;
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _loadReadiness();
  }

  /// Time of the most recent checkpoint (any step).
  DateTime? get _lastSaved => _savedAt.values.isEmpty
      ? null
      : _savedAt.values.reduce((a, b) => a.isAfter(b) ? a : b);

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    if (_done) return _SuccessView(name: _name.text, onClose: () => Navigator.pop(context, true));
    final last = _step == kWizardSteps - 1;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _draft.save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _branchId == null ? 'Nueva sucursal' : (_name.text.isEmpty ? 'Alta de sucursal' : _name.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : _saveAndExit,
              child: const Text('Guardar y salir'),
            ),
          ],
        ),
        body: _loading
            ? const SingleChildScrollView(child: PageSkeleton(rows: 2))
            : Column(
                children: [
                  _ProgressHeader(step: _step, savedAt: _lastSaved),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        if (_restored && _step == 0 && _branchId == null) ...[
                          DraftBanner(
                            onDiscard: () async {
                              await _draft.clear();
                              _name.clear();
                              _suggestCode();
                              setState(() => _restored = false);
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        _HintCard(text: wizardStepHints[_step]),
                        const SizedBox(height: 14),
                        if (_error != null) ...[
                          ErrorState(message: _error!),
                          const SizedBox(height: 12),
                        ],
                        ..._stepBody(context),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(top: BorderSide(color: c.border)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: Row(
                          children: [
                            if (_step > 0)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _step--;
                                          _error = null;
                                        }),
                                  icon: const Icon(CupertinoIcons.chevron_left, size: 16),
                                  label: const Text('Atrás'),
                                ),
                              ),
                            if (_step > 0) const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: last
                                  ? FilledButton.icon(
                                      onPressed:
                                          _busy ||
                                              _readiness['canActivate'] != true ||
                                              !_permissions.contains('branch.activate')
                                          ? null
                                          : _activate,
                                      icon: const Icon(CupertinoIcons.checkmark_seal, size: 18),
                                      label: Text(_busy ? 'Activando...' : 'Activar sucursal'),
                                    )
                                  : FilledButton.icon(
                                      onPressed: _busy || !_stepValid(_step)
                                          ? null
                                          : _continue,
                                      icon: _busy
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(CupertinoIcons.chevron_right, size: 16),
                                      label: Text(_busy ? 'Guardando...' : 'Continuar'),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _stepBody(BuildContext context) => switch (_step) {
    0 => _stepBasics(context),
    1 => _stepInfrastructure(context),
    2 => _stepStaff(context),
    3 => _stepStore(context),
    _ => _stepReview(context),
  };

  List<Widget> _stepBasics(BuildContext context) => [
    LiveTextField(
      controller: _name,
      label: 'Nombre de la sucursal',
      maxLength: 120,
      validator: _nameError,
      onChanged: () {
        setState(() {});
      },
    ),
    const SizedBox(height: 6),
    LiveTextField(
      controller: _code,
      label: 'Código',
      helper: 'Sugerido: ${suggestBranchCode(widget.existingCodes, _country)}. Letras, números y guion.',
      maxLength: 24,
      textCapitalization: TextCapitalization.characters,
      validator: (_) => _codeError,
      onChanged: () => setState(() => _codeTouched = true),
    ),
    const SizedBox(height: 6),
    SelectField<String>(
      label: 'País',
      valueLabel: countryName(_country),
      icon: CupertinoIcons.globe,
      enabled: _branchId == null,
      onTap: () async {
        final picked = await showSelectSheet<String>(
          context,
          title: 'País',
          selected: _country,
          options: [
            for (final code in selectableCountryCodes([_country]))
              SelectOption(
                code,
                countryName(code),
                detail: 'Moneda ${currencyForCountry(code)}',
              ),
          ],
        );
        if (picked == null) return;
        setState(() {
          _country = picked;
          if (!_codeTouched && _branchId == null) _suggestCode();
        });
        _draft.touch();
      },
    ),
    const SizedBox(height: 14),
    SelectField<String>(
      label: 'Zona',
      valueLabel: zoneLabel(_zone),
      icon: CupertinoIcons.map,
      onTap: () async {
        final picked = await showSelectSheet<String>(
          context,
          title: 'Zona',
          selected: _zone,
          options: [
            for (final z in const ['occidental', 'central', 'oriental', 'other'])
              SelectOption(z, zoneLabel(z)),
          ],
        );
        if (picked == null) return;
        setState(() => _zone = picked);
        _draft.touch();
      },
    ),
    const SizedBox(height: 14),
    LiveTextField(
      controller: _timezone,
      label: 'Zona horaria (IANA)',
      helper: 'Ejemplo: America/El_Salvador. Define la hora de los cortes.',
      validator: ianaTimezone,
      onChanged: () => setState(() {}),
    ),
  ];

  List<Widget> _stepInfrastructure(BuildContext context) {
    final c = context.dlc;
    return [
      LiveTextField(
        controller: _pumps,
        label: 'Número de bombas (surtidores)',
        helper: 'Entre 1 y 200. Seis es el formato estándar.',
        keyboardType: TextInputType.number,
        validator: _pumpsError,
        onChanged: () => setState(() {}),
      ),
      const SizedBox(height: 10),
      const Text(
        'Tipos de combustible',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        'Elige 1, 2 o 3 tipos.',
        style: TextStyle(color: c.muted, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in wizardFuels.entries)
            FilterChip(
              label: Text(e.value),
              selected: _fuels.contains(e.key),
              avatar: CircleAvatar(
                radius: 6,
                backgroundColor: DlcColors.fuelFill(e.key),
              ),
              showCheckmark: true,
              onSelected: (on) {
                setState(() {
                  if (on) {
                    _fuels.add(e.key);
                  } else if (_fuels.length > 1) {
                    _fuels.remove(e.key);
                  }
                });
                _draft.touch();
              },
            ),
        ],
      ),
      const SizedBox(height: 14),
      LiveTextField(
        controller: _tanks,
        label: 'Número de tanques',
        helper: 'Al menos uno por tipo de combustible (${_fuels.length}).',
        keyboardType: TextInputType.number,
        validator: _tanksError,
        onChanged: () => setState(() {}),
      ),
      if (_branchId != null &&
          _permissions.contains('infrastructure.read')) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _resolve('tanks'),
          icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 18),
          label: const Text('Configurar equipos ahora'),
        ),
      ],
    ];
  }

  List<Widget> _stepStaff(BuildContext context) {
    final c = context.dlc;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _staffLater,
        title: const Text('Completar después'),
        subtitle: const Text(
          'Podrás registrar al personal más tarde, pero la sucursal no se activa sin al menos una persona.',
        ),
        onChanged: (v) {
          setState(() => _staffLater = v);
          _draft.touch();
        },
      ),
      const SizedBox(height: 8),
      if (_staffRegistered)
        DlcCard(
          weight: CardWeight.quiet,
          child: Row(
            children: [
              Icon(CupertinoIcons.checkmark_circle, color: c.optimal),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('El administrador ya está registrado.'),
              ),
            ],
          ),
        )
      else if (!_staffLater) ...[
        const Text(
          'Persona que administra la sucursal',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        LiveTextField(
          controller: _staffName,
          label: 'Nombre completo',
          validator: _staffNameError,
          prefixIcon: CupertinoIcons.person,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 6),
        LiveTextField(
          controller: _staffCode,
          label: 'Código de empleado',
          helper: 'Sugerido: EMP-01.',
          textCapitalization: TextCapitalization.characters,
          validator: _staffCodeError,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 6),
        LiveTextField(
          controller: _staffEmail,
          label: 'Correo (opcional)',
          keyboardType: TextInputType.emailAddress,
          validator: _staffEmailError,
          prefixIcon: CupertinoIcons.envelope,
          onChanged: () => setState(() {}),
        ),
      ],
    ];
  }

  List<Widget> _stepStore(BuildContext context) {
    final c = context.dlc;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _hasStore,
        title: const Text('Tendrá tienda'),
        subtitle: const Text('Venta de productos además del combustible.'),
        onChanged: (v) {
          setState(() => _hasStore = v);
          _draft.touch();
        },
      ),
      if (_hasStore) ...[
        const SizedBox(height: 8),
        LiveTextField(
          controller: _registers,
          label: 'Cajas registradoras',
          helper: 'Entre 1 y 10.',
          keyboardType: TextInputType.number,
          validator: _registersError,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 8),
        DlcCard(
          weight: CardWeight.quiet,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.info_circle, size: 18, color: c.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El catálogo de productos y las cajas se crean en Caja una vez activa la sucursal. Aquí queda registrada la intención.',
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _stepReview(BuildContext context) {
    final c = context.dlc;
    final blockers = asMaps(_readiness['blockers']);
    final ready = _readiness['canActivate'] == true;
    return [
      if (_readiness.isEmpty)
        const PageSkeleton(rows: 2)
      else ...[
        DlcCard(
          weight: ready ? CardWeight.standard : CardWeight.quiet,
          color: ready ? c.optimalContainer : null,
          child: Row(
            children: [
              Icon(
                ready ? CupertinoIcons.checkmark_seal : CupertinoIcons.clock,
                color: ready ? c.optimal : c.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ready
                      ? 'Lista para activar'
                      : '${blockers.length} ${blockers.length == 1 ? 'pendiente' : 'pendientes'} antes de activar',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ready ? c.optimal : c.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final b in blockers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DlcCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(CupertinoIcons.exclamationmark_circle, size: 18, color: c.warning),
                      const SizedBox(width: 8),
                      Expanded(child: Text(asText(b['message']))),
                    ],
                  ),
                  if (_canResolve(asText(b['step'])))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _resolve(asText(b['step'])),
                        icon: const Icon(CupertinoIcons.chevron_right, size: 14),
                        label: Text(_resolveLabel(asText(b['step']))),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (!_permissions.contains('branch.activate') && ready)
          Text(
            'Tu perfil no puede activar sucursales. Pide a un Gerente General que lo haga.',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _loadReadiness,
          icon: const Icon(CupertinoIcons.refresh, size: 16),
          label: const Text('Revisar de nuevo'),
        ),
      ],
    ];
  }

  bool _canResolve(String step) => const {
    'products', 'tanks', 'dispensers', 'openingBalances', 'staff', 'prices',
  }.contains(step);

  String _resolveLabel(String step) => switch (step) {
    'staff' => 'Registrar personal',
    'prices' => 'Configurar precios',
    'openingBalances' => 'Registrar saldos iniciales',
    _ => 'Configurar equipos',
  };
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step, this.savedAt});
  final int step;
  final DateTime? savedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < kWizardSteps; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i <= step ? c.brand : c.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const SizedBox(height: 6),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Paso ${step + 1} de $kWizardSteps',
                    style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (savedAt != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.checkmark_circle, size: 14, color: c.optimal),
                    const SizedBox(width: 4),
                    Text(
                      'Guardado ${formatClock(savedAt!)}',
                      style: TextStyle(color: c.optimal, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            wizardStepTitles[step],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return DlcCard(
      weight: CardWeight.quiet,
      color: c.infoContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.lightbulb, size: 18, color: c.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Por qué importa: $text',
              style: TextStyle(color: c.ink, fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.name, required this.onClose});
  final String name;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.optimalContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Icon(CupertinoIcons.checkmark_seal, size: 48, color: c.optimal),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Sucursal activada',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '${name.isEmpty ? 'La sucursal' : name} ya puede operar. Verás su resumen en el tablero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onClose,
                  icon: const Icon(CupertinoIcons.checkmark_alt, size: 18),
                  label: const Text('Listo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
