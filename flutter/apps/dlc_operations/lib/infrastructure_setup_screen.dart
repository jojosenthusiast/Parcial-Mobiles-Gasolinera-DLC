import 'package:dlc_api/dlc_api.dart';
import 'live_form.dart';
import 'validators.dart';
import 'app_theme.dart';
import 'package:flutter/material.dart';

/// Configuración conectada a la API para combustibles e infraestructura física.
/// El servidor mantiene autoridad sobre permisos, relaciones y saldos.
class InfrastructureSetupScreen extends StatefulWidget {
  const InfrastructureSetupScreen({
    required this.api,
    required this.branchId,
    required this.permissions,
    super.key,
  });
  final EmployeeSession api;
  final String branchId;
  final Set<String> permissions;

  @override
  State<InfrastructureSetupScreen> createState() =>
      _InfrastructureSetupScreenState();
}

class _InfrastructureSetupScreenState extends State<InfrastructureSetupScreen> {
  Map<String, dynamic> configuration = const {};
  List<Map<String, dynamic>> products = const [];
  final Map<String, Map<String, dynamic>> balances = {};
  bool loading = true;
  String? error;

  bool get canManage => widget.permissions.contains('branch.manage');
  bool get canPropose => widget.permissions.contains('infrastructure.propose');
  bool get canOpenInventory =>
      widget.permissions.contains('branch.manage') &&
      widget.permissions.contains('inventory.read');
  List<Map<String, dynamic>> get tanks => _rows(configuration['tanks']);
  List<Map<String, dynamic>> get dispensers =>
      _rows(configuration['dispensers']);
  List<Map<String, dynamic>> get offers => _rows(configuration['fuelOffers']);

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
      final results = await Future.wait<dynamic>([
        widget.api.branchConfiguration(widget.branchId),
        widget.api.fuelProducts(branchId: widget.branchId),
      ]);
      configuration = results[0] as Map<String, dynamic>;
      products = results[1] as List<Map<String, dynamic>>;
      balances.clear();
      if (widget.permissions.contains('inventory.read')) {
        await Future.wait(
          tanks.map((tank) async {
            final id = _str(tank['id']);
            if (id.isNotEmpty)
              balances[id] = await widget.api.tankInventory(
                widget.branchId,
                id,
              );
          }),
        );
      }
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _write(Future<dynamic> Function() action) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await action();
      await load();
    } on DlcApiException catch (e) {
      if (mounted) await load();
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _offer(Map<String, dynamic> product) async {
    await _write(
      () async =>
          widget.api.activateFuelOffer(widget.branchId, _str(product['id'])),
    );
  }

  Future<void> _newTank() async {
    final offeredProducts = offers
        .where((row) => row['status'] == 'active')
        .toList();
    if (offeredProducts.isEmpty) {
      _show('Asigna primero un combustible activo a la sucursal.');
      return;
    }
    final values = await _form(
      context,
      title: 'Registrar tanque',
      fields: const [
        _Field('code', 'Código', required: true),
        _Field('name', 'Nombre', required: true),
        _Field('nominal', 'Capacidad nominal (L)', required: true),
        _Field('safe', 'Límite seguro (L)', required: true),
        _Field('reserve', 'Reserva no utilizable (L)', required: true),
      ],
      productOptions: offeredProducts,
    );
    if (values == null || !mounted) return;
    await _write(
      () async => widget.api.createTank(
        widget.branchId,
        code: values['code']!,
        name: values['name']!,
        fuelProductId: values['fuelProductId']!,
        nominalCapacityL: values['nominal']!,
        safeFillLimitL: values['safe']!,
        unusableReserveL: values['reserve']!,
      ),
    );
  }

  Future<void> _newDispenser() async {
    final values = await _form(
      context,
      title: 'Registrar dispensador',
      fields: const [
        _Field('code', 'Código', required: true),
        _Field('name', 'Nombre'),
      ],
    );
    if (values == null || !mounted) return;
    await _write(
      () async => widget.api.createDispenser(
        widget.branchId,
        code: values['code']!,
        name: values['name'],
      ),
    );
  }

  Future<void> _newNozzle(Map<String, dynamic> dispenser) async {
    final enabledProducts = offers
        .where((row) => row['status'] == 'active')
        .toList();
    if (enabledProducts.isEmpty) {
      _show('Asigna primero un combustible activo a la sucursal.');
      return;
    }
    final values = await _form(
      context,
      title: 'Agregar boquilla a ${_str(dispenser['code'])}',
      fields: const [
        _Field('code', 'Código de boquilla', required: true),
        _Field('productCode', 'Código de producto', required: true),
      ],
      productOptions: enabledProducts,
      includeMeterOptions: true,
      tankOptions: tanks,
    );
    if (values == null || !mounted) return;
    await _write(() async {
      final nozzle = await widget.api.createNozzle(
        widget.branchId,
        _str(dispenser['id']),
        code: values['code']!,
        productCode: values['productCode']!,
        fuelProductId: values['fuelProductId']!,
        serviceMode: values['serviceMode']!,
        meterUnit: values['meterUnit']!,
        meterPrecision: int.parse(values['precision']!),
      );
      final tankId = values['tankId'];
      if (tankId != null && tankId.isNotEmpty) {
        await widget.api.connectNozzle(
          widget.branchId,
          _str(nozzle['id']),
          tankId,
          'Conexión inicial desde configuración de sucursal',
        );
      }
    });
  }

  Future<void> _connect(Map<String, dynamic> nozzle) async {
    final compatible = tanks
        .where(
          (t) =>
              _str(t['fuelProductId']) == _str(nozzle['fuelProductId']) &&
              t['status'] != 'decommissioned',
        )
        .toList();
    if (compatible.isEmpty) {
      _show(
        'No hay tanque de esta sucursal para el combustible de la boquilla.',
      );
      return;
    }
    final tank = await _choose<Map<String, dynamic>>(
      context,
      'Conectar boquilla',
      compatible,
      (t) => '${_str(t['code'])} · ${_str(t['name'])}',
    );
    if (tank == null || !mounted) return;
    final reason = await _text(
      context,
      'Motivo de conexión',
      initial: 'Configuración inicial de infraestructura',
    );
    if (reason == null || !mounted) return;
    await _write(
      () async => widget.api.connectNozzle(
        widget.branchId,
        _str(nozzle['id']),
        _str(tank['id']),
        reason,
      ),
    );
  }

  Future<void> _opening(Map<String, dynamic> tank) async {
    final balance = balances[_str(tank['id'])]?['balance'];
    if (balance != null) {
      _show(
        'El tanque ya tiene saldo registrado (${_str(balance['onHandL'])} L).',
      );
      return;
    }
    final values = await _form(
      context,
      title: 'Saldo inicial · ${_str(tank['code'])}',
      fields: const [
        _Field('quantity', 'Cantidad observada (L)', required: true),
        _Field('reason', 'Referencia o motivo', required: true),
      ],
    );
    if (values == null || !mounted) return;
    if (!RegExp(_decimal).hasMatch(values['quantity']!)) {
      _show('La cantidad debe ser decimal, sin separadores de miles.');
      return;
    }
    await _write(
      () async => widget.api.openTankInventory(
        widget.branchId,
        _str(tank['id']),
        quantity: values['quantity']!,
        valuationQuality: 'unknown',
        reason: values['reason'],
      ),
    );
  }

  void _show(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final readiness = Map<String, dynamic>.from(
      configuration['readiness'] as Map? ?? const {},
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Infraestructura y combustibles'),
        actions: [
          IconButton(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null)
                    Card(
                      color: context.dlc.criticalContainer,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(error!),
                      ),
                    ),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        readiness['ready'] == true
                            ? Icons.check_circle
                            : Icons.pending_actions,
                        color: readiness['ready'] == true
                            ? context.dlc.optimal
                            : context.dlc.warning,
                      ),
                      title: Text(
                        readiness['ready'] == true
                            ? 'Configuración lista'
                            : 'Configuración pendiente',
                      ),
                      subtitle: Text(
                        '${(readiness['issues'] as List<dynamic>? ?? const []).length} bloqueos reportados por el servidor · ${_str(configuration['profile'])}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _section(
                    'Combustibles de la sucursal',
                    Icons.local_gas_station,
                    canManage ? () => _pickOffer() : null,
                    offers.isEmpty
                        ? [
                            const ListTile(
                              title: Text(
                                'No hay combustibles activos asignados.',
                              ),
                            ),
                          ]
                        : offers
                              .map(
                                (p) => ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.oil_barrel_outlined,
                                  ),
                                  title: Text(_str(p['displayName'])),
                                  subtitle: Text(
                                    '${_str(p['sku'])} · ${_str(p['family'])}',
                                  ),
                                  trailing: Text(_str(p['status'])),
                                ),
                              )
                              .toList(),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    'Tanques',
                    Icons.opacity,
                    canPropose ? _newTank : null,
                    tanks.isEmpty
                        ? [
                            const ListTile(
                              title: Text('No hay tanques configurados.'),
                            ),
                          ]
                        : tanks.map((tank) {
                            final balance =
                                balances[_str(tank['id'])]?['balance'] as Map?;
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.water_drop_outlined),
                              title: Text(
                                '${_str(tank['code'])} · ${_str(tank['name'])}',
                              ),
                              subtitle: Text(
                                '${_str(tank['fuelName'])} · ${_str(tank['nominalCapacityL'])} L · ${balance == null ? 'Saldo sin abrir' : '${_str(balance['onHandL'])} L (${_str(balance['valuationQuality'])})'}',
                              ),
                              trailing: canOpenInventory && balance == null
                                  ? IconButton(
                                      tooltip: 'Registrar saldo inicial',
                                      onPressed: () => _opening(tank),
                                      icon: const Icon(Icons.add_card),
                                    )
                                  : null,
                            );
                          }).toList(),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    'Dispensadores y boquillas',
                    Icons.ev_station,
                    canPropose ? _newDispenser : null,
                    dispensers.isEmpty
                        ? [
                            const ListTile(
                              title: Text('No hay dispensadores configurados.'),
                            ),
                          ]
                        : dispensers.map((d) {
                            final nozzles = _rows(d['nozzles']);
                            return Card(
                              child: ExpansionTile(
                                leading: const Icon(Icons.ev_station),
                                title: Text(
                                  '${_str(d['code'])} · ${_str(d['name']).isEmpty ? 'Sin nombre' : _str(d['name'])}',
                                ),
                                subtitle: Text(
                                  '${_str(d['physicalStatus'])} · ${nozzles.length} boquillas',
                                ),
                                children: [
                                  ...nozzles.map(
                                    (n) => ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.water),
                                      title: Text(
                                        '${_str(n['code'])} · ${_str(n['productCode'])}',
                                      ),
                                      subtitle: Text(
                                        '${_str(n['serviceMode'])} · ${n['tankId'] == null ? 'Sin tanque conectado' : 'Tanque conectado'}',
                                      ),
                                      trailing: canPropose
                                          ? PopupMenuButton<String>(
                                              onSelected: (_) => _connect(n),
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(
                                                  value: 'connect',
                                                  child: Text(
                                                    'Cambiar conexión de tanque',
                                                  ),
                                                ),
                                              ],
                                            )
                                          : null,
                                    ),
                                  ),
                                  if (canPropose)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () => _newNozzle(d),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Agregar boquilla'),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Los cambios se guardan en el servidor con auditoría. Revisa la configuración y los permisos del usuario antes de activar una sucursal.',
                    style: TextStyle(color: context.dlc.muted),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _section(
    String title,
    IconData icon,
    VoidCallback? add,
    List<Widget> children,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (add != null)
                IconButton(
                  onPressed: add,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Agregar',
                ),
            ],
          ),
          ...children,
        ],
      ),
    ),
  );

  Future<void> _pickOffer() async {
    final current = offers.map((p) => _str(p['id'])).toSet();
    final available = products
        .where((p) => !current.contains(_str(p['id'])))
        .toList();
    if (available.isEmpty) {
      _show('No hay otros combustibles activos en el catálogo.');
      return;
    }
    final selected = await _choose<Map<String, dynamic>>(
      context,
      'Asignar combustible',
      available,
      (p) => '${_str(p['displayName'])} · ${_str(p['sku'])}',
    );
    if (selected != null) await _offer(selected);
  }
}

const _decimal = r'^(?:0|[1-9]\d{0,11})(?:\.\d{1,12})?$';

class _Field {
  const _Field(this.key, this.label, {this.required = false});
  final String key, label;
  final bool required;
}

Future<Map<String, String>?> _form(
  BuildContext context, {
  required String title,
  required List<_Field> fields,
  List<Map<String, dynamic>> productOptions = const [],
  List<Map<String, dynamic>> tankOptions = const [],
  bool includeMeterOptions = false,
}) async {
  final controllers = {
    for (final field in fields) field.key: TextEditingController(),
  };
  String? productId = productOptions.isEmpty
      ? null
      : _str(productOptions.first['id']);
  String serviceMode = 'full_service', meterUnit = 'liter', precision = '3';
  String? tankId;
  String? fieldError(_Field field, String? value) => field.required
      ? requiredText(value, field: field.label)
      : maxLengthText(value, 200, field: field.label);
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...fields.map(
                (field) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LiveTextField(
                    controller: controllers[field.key]!,
                    label: field.required ? '${field.label} *' : field.label,
                    validator: (v) => fieldError(field, v),
                    onChanged: () => setState(() {}),
                  ),
                ),
              ),
              if (productOptions.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: productId,
                  decoration: const InputDecoration(
                    labelText: 'Combustible',
                    border: OutlineInputBorder(),
                  ),
                  items: productOptions
                      .map(
                        (p) => DropdownMenuItem(
                          value: _str(p['id']),
                          child: Text(
                            _str(p['displayName']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    productId = v;
                    tankId = '';
                  }),
                ),
              if (includeMeterOptions) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: serviceMode,
                  decoration: const InputDecoration(
                    labelText: 'Modo de servicio',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'full_service',
                      child: Text('Atendido'),
                    ),
                    DropdownMenuItem(
                      value: 'self_service',
                      child: Text('Autoservicio'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => serviceMode = v ?? serviceMode),
                ),
                DropdownButtonFormField<String>(
                  initialValue: meterUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unidad del totalizador',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'liter', child: Text('Litros')),
                    DropdownMenuItem(
                      value: 'gallon_us',
                      child: Text('Galón US'),
                    ),
                  ],
                  onChanged: (v) => setState(() => meterUnit = v ?? meterUnit),
                ),
                DropdownButtonFormField<String>(
                  initialValue: precision,
                  decoration: const InputDecoration(
                    labelText: 'Decimales del totalizador',
                  ),
                  items: List.generate(
                    10,
                    (i) => DropdownMenuItem(value: '$i', child: Text('$i')),
                  ),
                  onChanged: (v) => setState(() => precision = v ?? precision),
                ),
                if (tankOptions
                    .where((t) => _str(t['fuelProductId']) == productId)
                    .isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: tankId ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Tanque inicial (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Sin conexión inicial'),
                      ),
                      ...tankOptions
                          .where((t) => _str(t['fuelProductId']) == productId)
                          .map(
                            (t) => DropdownMenuItem(
                              value: _str(t['id']),
                              child: Text(
                                '${_str(t['code'])} · ${_str(t['fuelName'])}',
                              ),
                            ),
                          ),
                    ],
                    onChanged: (v) => setState(() => tankId = v),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: !fields.every(
              (f) => fieldError(f, controllers[f.key]?.text) == null,
            )
                ? null
                : () {
              Navigator.pop(context, {
                for (final entry in controllers.entries)
                  entry.key: entry.value.text.trim(),
                if (productId != null) 'fuelProductId': productId!,
                'serviceMode': serviceMode,
                'meterUnit': meterUnit,
                'precision': precision,
                if (tankId != null && tankId!.isNotEmpty) 'tankId': tankId!,
              });
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  for (final controller in controllers.values) {
    controller.dispose();
  }
  return result;
}

Future<String?> _text(
  BuildContext context,
  String title, {
  required String initial,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => ValidatedFormDialog(
      title: title,
      submitLabel: 'Guardar',
      cancelLabel: 'Cancelar',
      onCancel: () => Navigator.pop(context),
      onSubmit: () => Navigator.pop(context, controller.text.trim()),
      isValid: () => minLengthText(controller.text, 3, field: 'El texto') == null,
      contentBuilder: (context, changed) => LiveTextField(
        controller: controller,
        label: 'Detalle',
        minLines: 2,
        maxLines: 4,
        validator: (v) => minLengthText(v, 3, field: 'El texto'),
        onChanged: changed,
      ),
    ),
  );
  controller.dispose();
  if (value != null && value.trim().length < 3) return null;
  return value;
}

Future<T?> _choose<T>(
  BuildContext context,
  String title,
  List<T> values,
  String Function(T) label,
) => showDialog<T>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 420,
      child: ListView(
        shrinkWrap: true,
        children: values
            .map(
              (v) => ListTile(
                title: Text(label(v)),
                onTap: () => Navigator.pop(context, v),
              ),
            )
            .toList(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
    ],
  ),
);

List<Map<String, dynamic>> _rows(dynamic value) =>
    (value as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
String _str(dynamic value) => value?.toString() ?? '';
