import 'package:dlc_api/dlc_api.dart';
import 'haptics.dart';
import 'live_form.dart';
import 'validators.dart';
import 'app_theme.dart';
import 'package:flutter/material.dart';

class StaffShiftsScreen extends StatefulWidget {
  const StaffShiftsScreen({required this.api, required this.branchId, required this.permissions, super.key});
  final EmployeeSession api;
  final String branchId;
  final Set<String> permissions;

  @override
  State<StaffShiftsScreen> createState() => _StaffShiftsScreenState();
}

class _StaffShiftsScreenState extends State<StaffShiftsScreen> {
  List<Map<String, dynamic>> employees = const [], shifts = const [];
  bool loading = true;
  String? error;

  bool get canPlan => widget.permissions.contains('staff.shifts.plan');

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final now = DateTime.now();
      final rows = await Future.wait<dynamic>([
        widget.api.staffEmployees(widget.branchId),
        widget.api.staffShifts(widget.branchId, DateTime(now.year, now.month, now.day).toUtc(), DateTime(now.year, now.month, now.day + 7).toUtc()),
      ]);
      employees = rows[0] as List<Map<String, dynamic>>;
      shifts = rows[1] as List<Map<String, dynamic>>;
    } on DlcApiException catch (e) { error = e.message; }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _schedule() async {
    if (employees.isEmpty) { _message('Registra primero al menos un empleado activo.'); return; }
    final selection = await _scheduleDialog(context, employees);
    if (selection == null || !mounted) return;
    setState(() { loading = true; error = null; });
    try {
      await widget.api.scheduleStaffShift(widget.branchId, employeeId: selection.employeeId,
        position: selection.position, startsAt: selection.startsAt, endsAt: selection.endsAt);
      await load();
    } on DlcApiException catch (e) { Haptics.error(); if (mounted) setState(() { error = e.message; loading = false; }); }
  }

  Future<void> _cancel(Map<String, dynamic> shift) async {
    final controller = TextEditingController();
    String? reasonError(String? v) => minLengthText(v, 10, field: 'El motivo');
    final reason = await showDialog<String>(context: context, builder: (context) => ValidatedFormDialog(
      title: 'Cancelar turno', submitLabel: 'Cancelar turno', cancelLabel: 'Volver',
      onCancel: () => Navigator.pop(context), onSubmit: () => Navigator.pop(context, controller.text.trim()),
      isValid: () => reasonError(controller.text) == null,
      contentBuilder: (context, changed) => LiveTextField(controller: controller, minLines: 2, maxLines: 4, maxLength: 500, label: 'Motivo (mínimo 10 caracteres)', validator: reasonError, onChanged: changed),
    ));
    controller.dispose();
    if (reason == null || !mounted) return;
    setState(() { loading = true; error = null; });
    try { await widget.api.cancelStaffShift(widget.branchId, _str(shift['id']), reason); await load(); }
    on DlcApiException catch (e) { Haptics.error(); if (mounted) setState(() { error = e.message; loading = false; }); }
  }

  Future<void> _recordAttendance(Map<String, dynamic> shift, String kind) async {
    setState(() { loading = true; error = null; });
    try { await widget.api.recordStaffAttendance(widget.branchId, _str(shift['id']), kind); await load(); }
    on DlcApiException catch (e) { Haptics.error(); if (mounted) setState(() { error = e.message; loading = false; }); }
  }

  Future<void> _createEmployee() async {
    final code = TextEditingController(), name = TextEditingController(), position = TextEditingController(), email = TextEditingController();
    String? codeError(String? v) => requiredText(v, field: 'El código') ?? maxLengthText(v, 24, field: 'El código');
    String? nameError(String? v) => personName(v, field: 'El nombre');
    String? positionError(String? v) => minLengthText(v, 3, field: 'El puesto');
    String? emailError(String? v) => (v == null || v.trim().isEmpty) ? null : emailAddress(v);
    final ok = await showDialog<bool>(context: context, builder: (context) => ValidatedFormDialog(
      title: 'Registrar empleado', submitLabel: 'Guardar', cancelLabel: 'Volver',
      onCancel: () => Navigator.pop(context, false), onSubmit: () => Navigator.pop(context, true),
      isValid: () => allValid([codeError(code.text), nameError(name.text), positionError(position.text), emailError(email.text)]),
      contentBuilder: (context, changed) => Column(mainAxisSize: MainAxisSize.min, children: [
        LiveTextField(controller: code, label: 'Código de empleado', maxLength: 24, validator: codeError, onChanged: changed),
        LiveTextField(controller: name, label: 'Nombre legal', validator: nameError, onChanged: changed),
        LiveTextField(controller: position, label: 'Puesto', validator: positionError, onChanged: changed),
        LiveTextField(controller: email, keyboardType: TextInputType.emailAddress, label: 'Correo (opcional)', validator: emailError, onChanged: changed),
      ]),
    ));
    if (ok != true || !mounted) { code.dispose(); name.dispose(); position.dispose(); email.dispose(); return; }
    setState(() { loading = true; error = null; });
    try {
      await widget.api.createStaffEmployee(widget.branchId, employeeCode: code.text, legalName: name.text,
        positionTitle: position.text, contactEmail: email.text);
      Haptics.success();
      await load();
    } on DlcApiException catch (e) { Haptics.error(); if (mounted) setState(() { error = e.message; loading = false; }); }
    finally { code.dispose(); name.dispose(); position.dispose(); email.dispose(); }
  }

  void _message(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Personal y turnos'), actions: [
      if (widget.permissions.contains('staff.manage')) IconButton(onPressed: loading ? null : _createEmployee, tooltip: 'Registrar empleado', icon: const Icon(Icons.person_add_alt_1)),
      IconButton(onPressed: load, tooltip: 'Actualizar', icon: const Icon(Icons.refresh))]),
    floatingActionButton: canPlan ? FloatingActionButton.extended(onPressed: loading ? null : _schedule, icon: const Icon(Icons.add), label: const Text('Programar turno')) : null,
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: [
      if (error != null) Card(color: context.dlc.criticalContainer, child: ListTile(leading: const Icon(Icons.error_outline), title: Text(error!))),
      Card(child: ListTile(leading: const Icon(Icons.groups_outlined), title: Text('${employees.length} empleados activos'), subtitle: const Text('La lista y la programación se consultan al servidor.'))),
      const SizedBox(height: 14),
      Text('Turnos · próximos 7 días', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      if (shifts.isEmpty) const Card(child: ListTile(leading: Icon(Icons.event_busy), title: Text('No hay turnos en este período.'))),
      ...shifts.map((shift) {
        final start = DateTime.tryParse(_str(shift['startsAt']))?.toLocal();
        final end = DateTime.tryParse(_str(shift['endsAt']))?.toLocal();
        final dateText = start == null || end == null ? 'Horario no disponible' : '${_date(start)} · ${_time(start)}–${_time(end)}';
        final status = _str(shift['status']);
        final attendanceAction = widget.permissions.contains('staff.attendance.record') && status == 'scheduled'
          ? shift['clockedInAt'] == null
            ? IconButton(tooltip: 'Marcar entrada', onPressed: () => _recordAttendance(shift, 'clock_in'), icon: const Icon(Icons.login))
            : shift['clockedOutAt'] == null
              ? IconButton(tooltip: 'Marcar salida', onPressed: () => _recordAttendance(shift, 'clock_out'), icon: const Icon(Icons.logout))
              : null
          : null;
        final actions = [if (attendanceAction != null) attendanceAction, if (canPlan && status == 'scheduled') IconButton(tooltip: 'Cancelar turno', onPressed: () => _cancel(shift), icon: const Icon(Icons.event_busy_outlined))];
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(_str(shift['employeeName']), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$dateText\n${_position(_str(shift['position']))} · $status'), isThreeLine: true,
          trailing: actions.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: actions),
        )));
      }),
      const SizedBox(height: 76),
    ])),
  );
}

class _ShiftSelection {
  const _ShiftSelection(this.employeeId, this.position, this.startsAt, this.endsAt);
  final String employeeId, position;
  final DateTime startsAt, endsAt;
}

Future<_ShiftSelection?> _scheduleDialog(BuildContext context, List<Map<String, dynamic>> employees) async {
  String employeeId = _str(employees.first['id']);
  String position = 'manager';
  final now = DateTime.now();
  DateTime date = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  TimeOfDay start = const TimeOfDay(hour: 8, minute: 0), end = const TimeOfDay(hour: 16, minute: 0);
  return showDialog<_ShiftSelection>(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(
    title: const Text('Programar turno'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(initialValue: employeeId, decoration: const InputDecoration(labelText: 'Empleado'), items: employees.map((e) => DropdownMenuItem(value: _str(e['id']), child: Text(_str(e['legalName']), overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() => employeeId = v ?? employeeId)),
      const SizedBox(height: 8), DropdownButtonFormField<String>(initialValue: position, decoration: const InputDecoration(labelText: 'Puesto'), items: const [DropdownMenuItem(value: 'manager', child: Text('Gerencia')), DropdownMenuItem(value: 'store', child: Text('Tienda')), DropdownMenuItem(value: 'maintenance', child: Text('Mantenimiento'))], onChanged: (v) => setState(() => position = v ?? position)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Fecha'), subtitle: Text(_date(date)), trailing: const Icon(Icons.calendar_today), onTap: () async { final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 2)); if (picked != null) setState(() => date = picked); }),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Inicio'), subtitle: Text(start.format(context)), trailing: const Icon(Icons.schedule), onTap: () async { final picked = await showTimePicker(context: context, initialTime: start); if (picked != null) setState(() => start = picked); }),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Fin'), subtitle: Text(end.format(context)), trailing: const Icon(Icons.schedule), onTap: () async { final picked = await showTimePicker(context: context, initialTime: end); if (picked != null) setState(() => end = picked); }),
      const Text('La API valida el horario, el ámbito de la sucursal y los conflictos de turnos.'),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')), FilledButton(onPressed: () {
      final startsAt = DateTime(date.year, date.month, date.day, start.hour, start.minute);
      final endsAt = DateTime(date.year, date.month, date.day, end.hour, end.minute);
      if (!endsAt.isAfter(startsAt)) return;
      Navigator.pop(context, _ShiftSelection(employeeId, position, startsAt, endsAt));
    }, child: const Text('Programar'))],
  )));
}

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _position(String value) => switch (value) {'cashier' => 'Caja', 'forecourt' => 'Pista', 'store' => 'Tienda', 'manager' => 'Gerencia', 'maintenance' => 'Mantenimiento', _ => value};
String _str(dynamic value) => value?.toString() ?? '';
