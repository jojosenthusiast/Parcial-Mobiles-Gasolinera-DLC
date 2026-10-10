import 'package:dlc_api/dlc_api.dart';
import 'app_theme.dart';
import 'package:flutter/material.dart';

class LoyaltyProgramsScreen extends StatefulWidget {
  const LoyaltyProgramsScreen({
    required this.api,
    required this.permissions,
    super.key,
  });
  final EmployeeSession api;
  final Set<String> permissions;
  @override
  State<LoyaltyProgramsScreen> createState() => _LoyaltyProgramsScreenState();
}

class _LoyaltyProgramsScreenState extends State<LoyaltyProgramsScreen> {
  final rate = TextEditingController(text: '1');
  final minimum = TextEditingController(text: '0');
  final redemptionRate = TextEditingController(text: '0');
  List<Map<String, dynamic>> rows = const [];
  bool loading = true, busy = false;
  String? error;
  bool get canManage => widget.permissions.contains('loyalty.program.manage');
  bool get canApprove => widget.permissions.contains('loyalty.program.approve');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    rate.dispose();
    minimum.dispose();
    redemptionRate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      rows = await widget.api.loyaltyPrograms();
    } on DlcApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await _load();
    } on DlcApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _create() async {
    final points = double.tryParse(rate.text.trim());
    final min = double.tryParse(minimum.text.trim());
    final redemption = double.tryParse(redemptionRate.text.trim());
    if (points == null ||
        points <= 0 ||
        min == null ||
        min < 0 ||
        redemption == null ||
        redemption < 0 ||
        redemption > 1000) {
      setState(
        () => error =
            'Revisa las tasas. La tasa de acumulación debe ser positiva; el mínimo y el valor de canje no pueden ser negativos.',
      );
      return;
    }
    await _run(
      () => widget.api.createLoyaltyProgram(
        pointsPerEligibleUsd: points,
        minimumEligibleUsd: min,
        redemptionUsdPerPoint: redemption,
      ),
    );
  }

  Future<void> _decide(Map<String, dynamic> item, String decision) async {
    final reason = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          decision == 'approve'
              ? 'Aprobar política de puntos'
              : 'Rechazar política',
        ),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Motivo (obligatorio al rechazar)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reason.text.trim()),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    final explanation = reason.text.trim();
    reason.dispose();
    if (result == null) return;
    if (decision == 'reject' && explanation.isEmpty) {
      setState(() => error = 'Indica el motivo del rechazo.');
      return;
    }
    await _run(
      () => widget.api.decideLoyaltyProgram(
        '${item['id']}',
        decision,
        reason: explanation.isEmpty ? null : explanation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Programa de puntos')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Política general de lealtad',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 14),
                  child: Text(
                    'Las tasas se administran a nivel central. Cada cambio queda como una versión y requiere aprobación de otra persona antes de activarse.',
                  ),
                ),
                if (error != null)
                  Card(
                    color: context.dlc.criticalContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(error!),
                    ),
                  ),
                if (canManage) _editor(),
                const SizedBox(height: 10),
                ...rows.map(_programCard),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
          ),
  );

  Widget _editor() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Proponer nueva versión',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Puntos por cada USD elegible',
              helperText: 'Se redondea hacia abajo al registrar puntos.',
            ),
          ),
          TextField(
            controller: minimum,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Compra mínima elegible en USD',
            ),
          ),
          TextField(
            controller: redemptionRate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor de canje por punto en USD',
              helperText:
                  'Usa 0 para mantener el pago con puntos desactivado. Máximo USD 1,000 por punto.',
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'La conversión aprobada habilita cotizaciones con confirmación del Cliente. Mantén la tasa en 0 en producción hasta implementar y probar los reversos de puntos por devolución.',
              style: TextStyle(color: context.dlc.warning),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: busy ? null : _create,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Crear borrador'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _programCard(Map<String, dynamic> item) {
    final status = '${item['status'] ?? ''}';
    final actions = <Widget>[];
    if (status == 'draft' && canManage)
      actions.add(
        TextButton(
          onPressed: busy
              ? null
              : () => _run(
                  () => widget.api.submitLoyaltyProgram('${item['id']}'),
                ),
          child: const Text('Enviar a aprobación'),
        ),
      );
    if (status == 'pending_approval' && canApprove) {
      actions.add(
        TextButton(
          onPressed: busy ? null : () => _decide(item, 'reject'),
          child: const Text('Rechazar'),
        ),
      );
      actions.add(
        FilledButton(
          onPressed: busy ? null : () => _decide(item, 'approve'),
          child: const Text('Aprobar y activar'),
        ),
      );
    }
    if (status == 'active' && canApprove)
      actions.add(
        TextButton(
          onPressed: busy
              ? null
              : () => _run(
                  () => widget.api.retireLoyaltyProgram('${item['id']}'),
                ),
          child: const Text('Retirar'),
        ),
      );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Versión ${item['version'] ?? '—'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                Chip(label: Text(status.replaceAll('_', ' '))),
              ],
            ),
            Text(
              '${item['pointsPerEligibleUsd']} puntos / USD · mínimo \$${item['minimumEligibleUsd']}',
            ),
            Text(
              item['redemptionUsdPerPoint'] == null ||
                      item['redemptionUsdPerPoint'] == 0
                  ? 'Pago con puntos desactivado'
                  : 'Valor configurado: USD ${item['redemptionUsdPerPoint']} por punto',
            ),
            if (item['decisionReason'] != null)
              Text('Motivo: ${item['decisionReason']}'),
            if (actions.isNotEmpty)
              Wrap(alignment: WrapAlignment.end, children: actions),
          ],
        ),
      ),
    );
  }
}
