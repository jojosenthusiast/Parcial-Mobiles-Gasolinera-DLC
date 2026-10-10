import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'branches_page.dart';
import 'format.dart';
import 'settings.dart';
import 'tokens.dart';
import 'widgets.dart';

const _heroInk = DlcBrand.ink;
const _heroInkSoft = Color(0xFF3B2A1F);

/// Reward the customer is closest to reaching, and whether it is already
/// reachable. Rewards without a numeric cost are ignored.
({Map<String, dynamic> reward, bool reachable})? nextReward(
  List<Map<String, dynamic>> rewards,
  num balance,
) {
  final priced =
      rewards.where((r) => (parseNum(r['pointsCost']) ?? 0) > 0).toList()..sort(
        (a, b) =>
            parseNum(a['pointsCost'])!.compareTo(parseNum(b['pointsCost'])!),
      );
  if (priced.isEmpty) return null;
  for (final reward in priced) {
    if (parseNum(reward['pointsCost'])! > balance) {
      return (reward: reward, reachable: false);
    }
  }
  return (reward: priced.last, reachable: true);
}

/// Inicio: one dominant card (balance) and a few secondary cards.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.profile,
    required this.loyalty,
    required this.rewards,
    required this.points,
    required this.branches,
    required this.quotes,
    required this.busy,
    required this.animateBalance,
    required this.onBalanceCounted,
    required this.onDecideQuote,
    required this.onSeeBranches,
    required this.onSeeRewards,
    required this.onSeeHistory,
  });
  final Map<String, dynamic>? profile, loyalty;
  final List<Map<String, dynamic>> rewards, points, branches, quotes;
  final bool busy, animateBalance;
  final VoidCallback onBalanceCounted,
      onSeeBranches,
      onSeeRewards,
      onSeeHistory;
  final void Function(Map<String, dynamic> quote, bool confirm) onDecideQuote;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final balance = parseNum(loyalty?['pointsBalance']) ?? 0;
    final name = asStr(profile?['fullName']).trim();
    final first = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    var index = 0;
    Widget reveal(Widget child) =>
        Reveal(group: 'home', index: index++, child: child);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        reveal(
          Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 4),
            child: Semantics(
              header: true,
              child: Text(
                first.isEmpty ? 'Hola' : 'Hola, $first',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        for (final quote in quotes)
          reveal(
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: PaymentRequestCard(
                quote: quote,
                busy: busy,
                onDecide: onDecideQuote,
              ),
            ),
          ),
        reveal(
          _HeroBalance(
            balance: balance,
            loyalty: loyalty,
            settings: settings,
            animate: animateBalance,
            onCounted: onBalanceCounted,
          ),
        ),
        const SizedBox(height: 14),
        reveal(
          _NextRewardCard(
            reward: nextReward(rewards, balance),
            balance: balance,
            onSeeRewards: onSeeRewards,
          ),
        ),
        const SizedBox(height: 14),
        reveal(_ActivityCard(points: points, onSeeAll: onSeeHistory)),
        const SizedBox(height: 14),
        reveal(_BranchesPreview(branches: branches, onSeeAll: onSeeBranches)),
      ],
    );
  }
}

class _HeroBalance extends StatelessWidget {
  const _HeroBalance({
    required this.balance,
    required this.loyalty,
    required this.settings,
    required this.animate,
    required this.onCounted,
  });
  final num balance;
  final Map<String, dynamic>? loyalty;
  final DlcSettings settings;
  final bool animate;
  final VoidCallback onCounted;

  @override
  Widget build(BuildContext context) {
    final canRedeem = loyalty?['canRedeem'] == true;
    final message = asStr(loyalty?['message']);
    final rate = parseNum(loyalty?['redemptionUsdPerPoint']);
    final ringColor = Colors.white.withValues(alpha: 0.2);
    return DlcCard(
      weight: CardWeight.hero,
      padding: EdgeInsets.zero,
      semanticLabel:
          'Puntos disponibles: ${formatPoints(balance)}'
          '${canRedeem ? '. Equivalen a ${settings.money(loyalty?['availableValueUsd'])}' : ''}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              right: -36,
              top: -36,
              child: _Circle(size: 150, color: ringColor),
            ),
            Positioned(
              right: 48,
              bottom: -56,
              child: _Circle(
                size: 120,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.star_fill,
                          size: 16,
                          color: _heroInk,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Puntos disponibles',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _heroInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: CountUp(
                          value: balance,
                          animate: animate,
                          onDone: onCounted,
                          style: const TextStyle(
                            fontSize: 40,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: _heroInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'pts',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _heroInkSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: _heroInk.withValues(alpha: 0.18)),
                  const SizedBox(height: 14),
                  if (canRedeem) ...[
                    const Text(
                      'Equivalen a',
                      style: TextStyle(fontSize: 14, color: _heroInkSoft),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      settings.money(loyalty?['availableValueUsd']),
                      style: numeric(
                        const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _heroInk,
                        ),
                      ),
                    ),
                    if (rate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tasa vigente: 1 punto = ${formatMoney(rate, decimals: math.max(settings.decimals, 3))}',
                        style: numeric(
                          const TextStyle(fontSize: 12, color: _heroInkSoft),
                        ),
                      ),
                    ],
                  ] else
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          CupertinoIcons.info_circle,
                          size: 18,
                          color: _heroInkSoft,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'El canje de puntos no está habilitado por ahora. Tus puntos se siguen acumulando.',
                            style: TextStyle(fontSize: 14, color: _heroInkSoft),
                          ),
                        ),
                      ],
                    ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style: const TextStyle(fontSize: 12, color: _heroInkSoft),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

class _NextRewardCard extends StatelessWidget {
  const _NextRewardCard({
    required this.reward,
    required this.balance,
    required this.onSeeRewards,
  });
  final ({Map<String, dynamic> reward, bool reachable})? reward;
  final num balance;
  final VoidCallback onSeeRewards;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.dlc;
    final next = reward;
    if (next == null) {
      return DlcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SectionHeader(
              icon: CupertinoIcons.gift,
              title: 'Próxima recompensa',
            ),
            EmptyState(
              icon: CupertinoIcons.gift,
              message:
                  'Cuando haya recompensas publicadas, verás aquí cuánto te falta para la siguiente.',
            ),
          ],
        ),
      );
    }
    final item = next.reward;
    final cost = parseNum(item['pointsCost'])!;
    final accent = colors.accents[0];
    final missing = math.max(0, cost - balance);
    return DlcCard(
      onTap: onSeeRewards,
      semanticLabel:
          'Próxima recompensa: ${asStr(item['title'])}. '
          '${next.reachable ? 'Disponible para canje' : 'Te faltan ${formatPoints(missing)} puntos'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: CupertinoIcons.gift, tone: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Próxima recompensa',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      asStr(item['title']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ProgressBar(
            fraction: balance / cost,
            color: accent.bar!,
            track: accent.bg,
            semanticLabel: 'Progreso hacia ${asStr(item['title'])}',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                next.reachable
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.arrow_up_right,
                size: 16,
                color: next.reachable ? colors.ok.fg : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  next.reachable
                      ? 'Ya puedes canjearla'
                      : 'Te faltan ${formatPoints(missing)} pts',
                  style: numeric(
                    TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: next.reachable ? colors.ok.fg : scheme.onSurface,
                    ),
                  ),
                ),
              ),
              Text(
                '${formatPoints(math.min(balance, cost))} / ${formatPoints(cost)}',
                style: numeric(
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.points, required this.onSeeAll});
  final List<Map<String, dynamic>> points;
  final VoidCallback onSeeAll;
  @override
  Widget build(BuildContext context) => DlcCard(
    weight: CardWeight.compact,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          icon: CupertinoIcons.time,
          title: 'Actividad reciente',
          trailing: points.length > 3
              ? TextButton(onPressed: onSeeAll, child: const Text('Ver todo'))
              : null,
        ),
        if (points.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.doc_text_search,
            message:
                'Tu historial aparecerá aquí cuando acumules puntos con tus compras.',
          )
        else
          for (final row in points.take(3)) PointEventRow(row: row),
      ],
    ),
  );
}

class _BranchesPreview extends StatelessWidget {
  const _BranchesPreview({required this.branches, required this.onSeeAll});
  final List<Map<String, dynamic>> branches;
  final VoidCallback onSeeAll;
  @override
  Widget build(BuildContext context) => DlcCard(
    weight: CardWeight.compact,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          icon: CupertinoIcons.placemark,
          title: 'Sucursales',
          trailing: branches.length > 3
              ? TextButton(onPressed: onSeeAll, child: const Text('Ver todas'))
              : null,
        ),
        if (branches.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.building_2_fill,
            message: 'Aún no hay sucursales activas para mostrar.',
          )
        else
          for (final b in branches.take(3)) BranchTile(branch: b),
      ],
    ),
  );
}

/// One ledger event: icon per type, Spanish label, date and signed points.
class PointEventRow extends StatelessWidget {
  const PointEventRow({super.key, required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final look = pointEventLook(row['type']);
    final tone = toneFor(context.dlc, look.kind, scheme);
    final delta = parseNum(row['pointsDelta']) ?? 0;
    final deltaColor = delta > 0
        ? context.dlc.ok.fg
        : delta < 0
        ? context.dlc.crit.fg
        : scheme.onSurface;
    final reason = asStr(row['reason']).trim();
    final date = formatDateTime(row['createdAt']);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              IconBadge(icon: look.icon, tone: tone, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      look.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (reason.isNotEmpty && reason != look.label)
                      Text(
                        reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (date != '—')
                      Text(
                        date,
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
                '${formatSignedPoints(delta)} pts',
                style: numeric(
                  TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: deltaColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Complete points history.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.points});
  final List<Map<String, dynamic>> points;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Historial de puntos')),
    body: points.isEmpty
        ? const Center(
            child: EmptyState(
              icon: CupertinoIcons.doc_text_search,
              message:
                  'Tu historial aparecerá aquí cuando acumules puntos con tus compras.',
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: points.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, i) => PointEventRow(row: points[i]),
          ),
  );
}

/// Points-payment request waiting for the customer's decision.
class PaymentRequestCard extends StatelessWidget {
  const PaymentRequestCard({
    super.key,
    required this.quote,
    required this.busy,
    required this.onDecide,
  });
  final Map<String, dynamic> quote;
  final bool busy;
  final void Function(Map<String, dynamic> quote, bool confirm) onDecide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = SettingsScope.of(context);
    final warn = context.dlc.warn;
    final look = quoteStatusLook(quote['status'] ?? 'pending');
    final expires = parseDate(quote['expiresAt']);
    return DlcCard(
      color: warn.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.creditcard, color: warn.fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pago con puntos en ${asStr(quote['branchName'])}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: warn.fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${formatPoints(quote['points'])} puntos · ${settings.money(quote['amountUsd'])}',
            style: numeric(
              TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          Text(
            'Venta total: ${settings.money(quote['saleTotalUsd'])}',
            style: TextStyle(color: scheme.onSurface),
          ),
          if (expires != null)
            Text(
              'Vence a las ${formatTime(expires)}',
              style: TextStyle(fontSize: 12, color: warn.fg),
            ),
          const SizedBox(height: 6),
          Text(
            'Al confirmar, los puntos se descuentan y el importe se aplica a esta venta. No se puede deshacer desde la app.',
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
          if (asStr(quote['status']).isNotEmpty &&
              asStr(quote['status']) != 'pending') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(look: look),
            ),
          ],
          const SizedBox(height: 12),
          DlcButton(
            label: 'Confirmar pago',
            icon: CupertinoIcons.check_mark,
            onPressed: busy ? null : () => onDecide(quote, true),
          ),
          const SizedBox(height: 8),
          DlcButton(
            label: 'Rechazar',
            icon: CupertinoIcons.xmark,
            kind: DlcButtonKind.danger,
            onPressed: busy ? null : () => onDecide(quote, false),
          ),
        ],
      ),
    );
  }
}
