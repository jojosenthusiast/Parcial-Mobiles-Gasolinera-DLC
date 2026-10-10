import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'format.dart';
import 'settings.dart';
import 'tokens.dart';
import 'widgets.dart';

/// Colourful reward card with progress toward its cost.
class RewardCard extends StatelessWidget {
  const RewardCard({
    super.key,
    required this.reward,
    required this.index,
    required this.balance,
  });
  final Map<String, dynamic> reward;
  final int index;
  final num balance;

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final tone = colors.accents[index % colors.accents.length];
    final cost = parseNum(reward['pointsCost']);
    final reachable = cost != null && cost > 0 && balance >= cost;
    final missing = cost == null ? null : math.max(0, cost - balance);
    final description = asStr(reward['description']).trim();
    return DlcCard(
      color: tone.bg,
      semanticLabel:
          'Recompensa ${asStr(reward['title'])}'
          '${cost == null ? '' : ', ${formatPoints(cost)} puntos'}'
          '${reachable
              ? ', disponible para canje'
              : missing == null
              ? ''
              : ', te faltan ${formatPoints(missing)} puntos'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.bar,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  CupertinoIcons.gift_fill,
                  size: 22,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? DlcBrand.ink
                      : Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asStr(reward['title']),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tone.fg,
                      ),
                    ),
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: TextStyle(fontSize: 14, color: tone.fg),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                cost == null ? '—' : '${formatPoints(cost)} pts',
                style: numeric(
                  TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tone.fg,
                  ),
                ),
              ),
            ],
          ),
          if (cost != null && cost > 0) ...[
            const SizedBox(height: 14),
            ProgressBar(
              fraction: balance / cost,
              color: tone.bar!,
              track: tone.fg.withValues(alpha: 0.16),
              semanticLabel: 'Progreso hacia ${asStr(reward['title'])}',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  reachable
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.arrow_up_right,
                  size: 16,
                  color: tone.fg,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reachable
                        ? 'Disponible para canje'
                        : 'Te faltan ${formatPoints(missing)} pts',
                    style: numeric(
                      TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tone.fg,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Beneficios: rewards, promotions, news and services.
class BenefitsPage extends StatelessWidget {
  const BenefitsPage({
    super.key,
    required this.balance,
    required this.rewards,
    required this.promotions,
    required this.campaigns,
    required this.services,
    required this.branches,
    required this.selectedBranchId,
    required this.promotionsLoading,
    required this.onSelectBranch,
    required this.onOpenPromotion,
  });
  final num balance;
  final List<Map<String, dynamic>> rewards,
      promotions,
      campaigns,
      services,
      branches;
  final String? selectedBranchId;
  final bool promotionsLoading;
  final ValueChanged<String?> onSelectBranch;
  final ValueChanged<Map<String, dynamic>> onOpenPromotion;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    var index = 0;
    Widget reveal(Widget child) =>
        Reveal(group: 'benefits', index: index++, child: child);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Beneficios',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        const SectionHeader(icon: CupertinoIcons.gift, title: 'Recompensas'),
        if (rewards.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.gift,
            message:
                'Todavía no hay recompensas publicadas. Sigue acumulando puntos: te avisaremos cuando haya novedades.',
          ),
        for (var i = 0; i < rewards.length; i++)
          reveal(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RewardCard(reward: rewards[i], index: i, balance: balance),
            ),
          ),
        const SizedBox(height: 8),
        const SectionHeader(
          icon: CupertinoIcons.tag,
          title: 'Promociones con beneficio',
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: selectedBranchId ?? '',
          icon: const Icon(CupertinoIcons.chevron_down, size: 18),
          decoration: const InputDecoration(
            labelText: 'Filtrar por sucursal',
            prefixIcon: Icon(CupertinoIcons.line_horizontal_3_decrease),
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Todas las sucursales'),
            ),
            for (final branch in branches)
              DropdownMenuItem(
                value: asStr(branch['id']),
                child: Text(
                  asStr(branch['name']),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: promotionsLoading
              ? null
              : (value) => onSelectBranch(
                  value == null || value.isEmpty ? null : value,
                ),
        ),
        SizedBox(
          height: 4,
          child: promotionsLoading
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        if (promotions.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.tag,
            message:
                'No hay promociones vigentes para esta selección. Prueba con otra sucursal.',
          ),
        for (final item in promotions)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: PromotionCard(
              promotion: item,
              settings: settings,
              onTap: () => onOpenPromotion(item),
            ),
          ),
        const SizedBox(height: 12),
        const SectionHeader(icon: CupertinoIcons.sparkles, title: 'Novedades'),
        if (campaigns.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.sparkles,
            message: 'No hay novedades publicadas por ahora.',
          ),
        for (final item in campaigns)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DlcCard(
              weight: CardWeight.compact,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(
                    icon: CupertinoIcons.sparkles,
                    tone: context.dlc.accents[3],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asStr(item['title']),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          asStr(item['body']),
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        const SectionHeader(icon: CupertinoIcons.wrench, title: 'Servicios'),
        if (services.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.wrench,
            message: 'No hay servicios publicados en este momento.',
          ),
        for (final item in services)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DlcCard(
              weight: CardWeight.compact,
              child: Row(
                children: [
                  IconBadge(
                    icon: CupertinoIcons.wrench,
                    tone: context.dlc.info,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asStr(item['description']),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          asStr(item['branchName']),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    settings.money(item['priceUsd']),
                    style: numeric(
                      const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class PromotionCard extends StatelessWidget {
  const PromotionCard({
    super.key,
    required this.promotion,
    required this.settings,
    required this.onTap,
  });
  final Map<String, dynamic> promotion;
  final DlcSettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = asStr(promotion['imageUrl']);
    return DlcCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image.isNotEmpty)
              Image.network(
                image,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                semanticLabel: asStr(promotion['imageAlt']),
                errorBuilder: (_, _, _) => SizedBox(
                  height: 80,
                  child: Center(
                    child: Icon(
                      CupertinoIcons.photo,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBadge(
                        icon: promotionKindIcon(promotion['kind']),
                        tone: context.dlc.accents[0],
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          asStr(promotion['title']),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    promotionHeadline(
                      promotion,
                      unit: settings.volumeUnit,
                      decimals: settings.decimals,
                    ),
                    style: numeric(
                      TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  if (asStr(promotion['motive']).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      asStr(promotion['motive']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ver condiciones',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                          color: scheme.primary,
                        ),
                      ],
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
}
