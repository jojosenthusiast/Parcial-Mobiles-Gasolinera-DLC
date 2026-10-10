import 'app_theme.dart';

/// Recovery actions for a dispense authorization, driven by the server state
/// machine: cancel only from `authorized`, `unknown` only from `dispensing`,
/// no-flow reconciliation only from `unknown`.
enum DispenseRecovery { cancel, markUnknown, reconcileNoFlow }

List<DispenseRecovery> recoveriesFor(String status) => switch (status) {
  'authorized' => const [DispenseRecovery.cancel],
  'dispensing' => const [DispenseRecovery.markUnknown],
  'unknown' => const [DispenseRecovery.reconcileNoFlow],
  _ => const [],
};

/// Plain-language state of an authorization (no raw codes on screen).
class DispenseStateInfo {
  const DispenseStateInfo(this.label, this.tone, this.hint);
  final String label;
  final DlcStatus tone;
  final String hint;
}

DispenseStateInfo dispenseStateInfo(String status) => switch (status) {
  'authorized' => const DispenseStateInfo(
    'Autorizado, sin iniciar',
    DlcStatus.info,
    'Si el cliente ya no va a despachar, cancela la autorización para liberar la manguera.',
  ),
  'active' => const DispenseStateInfo(
    'Activo',
    DlcStatus.info,
    'La autorización está vigente.',
  ),
  'dispensing' => const DispenseStateInfo(
    'Despachando',
    DlcStatus.medium,
    'Captura la lectura final al terminar. Si quedó colgado, márcalo como desconocido.',
  ),
  'unknown' => const DispenseStateInfo(
    'Por conciliar',
    DlcStatus.critical,
    'No se sabe cuánto combustible salió. Concilia con evidencia si no hubo flujo.',
  ),
  'posting' => const DispenseStateInfo(
    'Registrando venta',
    DlcStatus.info,
    'El servidor está cerrando el despacho.',
  ),
  'completed' => const DispenseStateInfo(
    'Completado',
    DlcStatus.optimal,
    'Despacho cerrado.',
  ),
  'cancelled' => const DispenseStateInfo(
    'Cancelado',
    DlcStatus.info,
    'La autorización fue cancelada; la manguera está libre.',
  ),
  'expired' => const DispenseStateInfo(
    'Vencido',
    DlcStatus.warning,
    'La autorización venció sin usarse.',
  ),
  _ => DispenseStateInfo(
    status.isEmpty ? 'Sin autorización' : 'Estado desconocido',
    DlcStatus.info,
    '',
  ),
};

/// Title / message / confirm label / whether a reason must be typed.
({String title, String message, String confirm, bool destructive})
recoveryCopy(DispenseRecovery action) => switch (action) {
  DispenseRecovery.cancel => (
    title: 'Cancelar autorización',
    message:
        'Se libera la manguera y no se cobra nada. Úsalo solo si el combustible no salió.',
    confirm: 'Cancelar autorización',
    destructive: true,
  ),
  DispenseRecovery.markUnknown => (
    title: 'Marcar como desconocido',
    message:
        'Indica que no se puede confirmar el volumen despachado. Quedará pendiente de conciliación.',
    confirm: 'Marcar desconocido',
    destructive: true,
  ),
  DispenseRecovery.reconcileNoFlow => (
    title: 'Conciliar sin flujo',
    message:
        'Confirma que no salió combustible. Se requiere una referencia de evidencia y el motivo.',
    confirm: 'Conciliar',
    destructive: false,
  ),
};
