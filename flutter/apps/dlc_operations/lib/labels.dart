import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// One central dictionary for every server status shown in the UI: Spanish
/// label + icon + semantic tone (colour comes from [DlcColors]).
@immutable
class StatusSpec {
  const StatusSpec(this.label, this.icon, this.tone);
  final String label;
  final IconData icon;
  final DlcStatus tone;
}

const _ok = DlcStatus.optimal;
const _warn = DlcStatus.warning;
const _crit = DlcStatus.critical;
const _info = DlcStatus.info;
const _mid = DlcStatus.medium;

final Map<String, StatusSpec> kStatusSpecs = {
  // Lifecycle
  'active': StatusSpec('Activa', CupertinoIcons.checkmark_circle, _ok),
  'activa': StatusSpec('Activa', CupertinoIcons.checkmark_circle, _ok),
  'configured': StatusSpec('En configuración', CupertinoIcons.slider_horizontal_3, _warn),
  'draft': StatusSpec('Borrador', CupertinoIcons.pencil, _warn),
  'suspended': StatusSpec('Suspendida', CupertinoIcons.pause_circle, _crit),
  'archived': StatusSpec('Archivada', CupertinoIcons.archivebox, _info),
  'inactive': StatusSpec('Inactiva', CupertinoIcons.minus_circle, _info),
  'retired': StatusSpec('Retirada', CupertinoIcons.archivebox, _info),
  'disabled': StatusSpec('Fuera de servicio', CupertinoIcons.nosign, _crit),
  // Equipment
  'operational': StatusSpec('Disponible', CupertinoIcons.checkmark_circle, _ok),
  'available': StatusSpec('Disponible', CupertinoIcons.checkmark_circle, _ok),
  'maintenance': StatusSpec('En mantenimiento', CupertinoIcons.wrench, _warn),
  'offline': StatusSpec('Fuera de servicio', CupertinoIcons.nosign, _crit),
  'out_of_service': StatusSpec('Fuera de servicio', CupertinoIcons.nosign, _crit),
  'faulty': StatusSpec('Dañado', CupertinoIcons.exclamationmark_triangle, _crit),
  'damaged': StatusSpec('Dañado', CupertinoIcons.exclamationmark_triangle, _crit),
  'unknown': StatusSpec('Sin estado', CupertinoIcons.question_circle, _info),
  // Workflow
  'open': StatusSpec('Abierta', CupertinoIcons.circle, _info),
  'in_progress': StatusSpec('En proceso', CupertinoIcons.timer, _mid),
  'prepared': StatusSpec('En revisión', CupertinoIcons.eye, _mid),
  'inReview': StatusSpec('Requiere revisión', CupertinoIcons.eye, _warn),
  'in_review': StatusSpec('Requiere revisión', CupertinoIcons.eye, _warn),
  'reviewed': StatusSpec('Revisado', CupertinoIcons.checkmark_seal, _ok),
  'closed': StatusSpec('Cerrado', CupertinoIcons.lock, _ok),
  'reported': StatusSpec('Reportada', CupertinoIcons.exclamationmark_bubble, _warn),
  'assessed': StatusSpec('Evaluada', CupertinoIcons.doc_text_search, _mid),
  'resolved': StatusSpec('Resuelta', CupertinoIcons.checkmark_circle, _ok),
  'cancelled': StatusSpec('Cancelado', CupertinoIcons.xmark_circle, _info),
  'canceled': StatusSpec('Cancelado', CupertinoIcons.xmark_circle, _info),
  'completed': StatusSpec('Completado', CupertinoIcons.checkmark_circle, _ok),
  'done': StatusSpec('Completado', CupertinoIcons.checkmark_circle, _ok),
  'failed': StatusSpec('Fallido', CupertinoIcons.xmark_octagon, _crit),
  'expired': StatusSpec('Vencido', CupertinoIcons.clock, _crit),
  // Approvals and prices
  'pending': StatusSpec('Pendiente', CupertinoIcons.clock, _warn),
  'pending_approval': StatusSpec('Pendiente de aprobación', CupertinoIcons.clock, _warn),
  'submitted': StatusSpec('Enviado', CupertinoIcons.paperplane, _mid),
  'approved': StatusSpec('Aprobado', CupertinoIcons.checkmark_seal, _ok),
  'rejected': StatusSpec('Rechazado', CupertinoIcons.xmark_octagon, _crit),
  'scheduled': StatusSpec('Programado', CupertinoIcons.calendar, _info),
  'applied': StatusSpec('Vigente', CupertinoIcons.checkmark_circle, _ok),
  'paused': StatusSpec('Pausada', CupertinoIcons.pause_circle, _warn),
  'received': StatusSpec('Recibido', CupertinoIcons.cube_box, _ok),
  'partially_received': StatusSpec('Recibido parcial', CupertinoIcons.cube_box, _mid),
  'ordered': StatusSpec('Ordenado', CupertinoIcons.doc_text, _info),
  'paid': StatusSpec('Pagado', CupertinoIcons.checkmark_circle, _ok),
  // Severity
  'critical': StatusSpec('Crítica', CupertinoIcons.exclamationmark_octagon, _crit),
  'high': StatusSpec('Alta', CupertinoIcons.exclamationmark_triangle, _crit),
  'medium': StatusSpec('Media', CupertinoIcons.exclamationmark_circle, _mid),
  'low': StatusSpec('Baja', CupertinoIcons.info_circle, _info),
  'warning': StatusSpec('En aviso', CupertinoIcons.exclamationmark_triangle, _mid),
  'normal': StatusSpec('Normal', CupertinoIcons.checkmark_circle, _ok),
};

/// "partially_received" -> "Partially received" when the status is unknown.
String humanizeKey(String raw) {
  final spaced = raw
      .trim()
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .toLowerCase();
  if (spaced.isEmpty) return '';
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Resolves any server status; unknown values degrade gracefully to a
/// humanised label with an info icon (never a raw `snake_case` string).
StatusSpec statusSpec(Object? raw) {
  final key = raw?.toString().trim() ?? '';
  if (key.isEmpty) return kStatusSpecs['unknown']!;
  final hit = kStatusSpecs[key] ?? kStatusSpecs[key.toLowerCase()];
  if (hit != null) return hit;
  return StatusSpec(humanizeKey(key), CupertinoIcons.info_circle, DlcStatus.info);
}

String statusLabel(Object? raw) => statusSpec(raw).label;

/// Severity ordering used by alert centres: 0 is the most severe.
int severityRank(Object? raw) => switch (raw?.toString().toLowerCase()) {
  'critical' => 0,
  'high' => 1,
  'warning' || 'medium' => 2,
  'low' => 3,
  _ => 4,
};

/// Service modes, units and other enums shown as text.
String serviceModeLabel(Object? raw) => switch (raw?.toString()) {
  'full_service' => 'Servicio completo',
  'self_service' => 'Autoservicio',
  final other => other == null || other.isEmpty ? '' : humanizeKey(other),
};

String unitLabel(Object? raw) => switch (raw?.toString()) {
  'liter' || 'liters' || 'l' || 'L' => 'litro',
  'gallon' || 'gallons' => 'galón',
  final other => other == null || other.isEmpty ? '' : other,
};

String zoneLabel(Object? raw) => switch (raw?.toString()) {
  'occidental' => 'Occidental',
  'central' => 'Central',
  'oriental' => 'Oriental',
  'other' => 'Otra',
  final other => other == null || other.isEmpty ? '' : humanizeKey(other),
};

/// Compact badge: icon + label in the tone colours (never colour alone).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.raw, {this.compact = false, super.key});
  final Object? raw;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spec = statusSpec(raw);
    final c = context.dlc;
    final fg = c.foreground(spec.tone);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: c.container(spec.tone),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: compact ? 12 : 14, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
