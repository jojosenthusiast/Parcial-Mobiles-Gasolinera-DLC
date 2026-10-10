import 'package:dlc_api/dlc_api.dart';
import 'package:dlc_operations/app_theme.dart';
import 'package:dlc_operations/format.dart';
import 'package:dlc_operations/preferences.dart';
import 'package:dlc_operations/scope.dart';
import 'package:dlc_operations/ui/data_widgets.dart';
import 'package:dlc_operations/ui/inventory_page.dart';
import 'package:dlc_operations/ui/kit.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

BranchSummary b(String id, String country, {String status = 'active'}) =>
    BranchSummary(
      id: id,
      code: id.toUpperCase(),
      name: 'Sucursal $id',
      zone: 'central',
      timezone: 'America/El_Salvador',
      countryCode: country,
      status: status,
    );

void main() {
  final all = [
    b('a', 'SV'),
    b('b', 'SV'),
    b('c', 'GT'),
    b('d', 'GT', status: 'draft'),
  ];

  group('ScopeState filtering', () {
    test('network shows everything, country narrows, branches pick', () {
      expect(ScopeState.network.resolve(all).length, 4);
      const gt = ScopeState(countryCode: 'GT');
      expect(gt.resolve(all).map((x) => x.id), ['c', 'd']);
      expect(gt.resolveActive(all).map((x) => x.id), ['c']);
      final picked = const ScopeState().withBranches({'a', 'c'});
      expect(picked.resolve(all).map((x) => x.id), ['a', 'c']);
    });

    test('changing country drops branches of other countries', () {
      final s = const ScopeState().withBranches({'a', 'c'}).withCountry('GT', all);
      expect(s.branchIds, {'c'});
      expect(s.countryCode, 'GT');
      expect(s.withCountry(null, all).branchIds, {'c'});
    });

    test('sanitize forgets branches and countries that vanished', () {
      final s = const ScopeState(countryCode: 'HN', branchIds: {'zzz', 'a'})
          .sanitize(all);
      expect(s.countryCode, isNull);
      expect(s.branchIds, {'a'});
    });

    test('effective branches prefer the operating ones', () {
      expect(effectiveBranches(ScopeState.network, all).map((x) => x.id), ['a', 'b', 'c']);
      expect(
        effectiveBranches(const ScopeState(countryCode: 'GT'), all).map((x) => x.id),
        ['c'],
      );
      // explicit selection of a draft is respected
      expect(
        effectiveBranches(const ScopeState(branchIds: {'d'}), all).map((x) => x.id),
        ['d'],
      );
      // nothing active: show what exists
      expect(effectiveBranches(ScopeState.network, [b('d', 'GT', status: 'draft')]).length, 1);
    });

    test('labels', () {
      expect(describeScope(ScopeState.network, all), 'Toda la red');
      expect(describeScope(const ScopeState(countryCode: 'GT'), all), 'Guatemala');
      expect(describeScope(const ScopeState(branchIds: {'a'}), all), 'Sucursal a');
      expect(describeScope(const ScopeState(branchIds: {'a', 'b'}), all), 'Sucursal a y 1 más');
      expect(viewingLabel(ScopeState.network, all), 'Toda la red · 4 sucursales');
      expect(branchChipLabel(const ScopeState(branchIds: {'a', 'b'}), all), '2 sucursales');
    });

    test('json round trip', () {
      const s = ScopeState(countryCode: 'GT', branchIds: {'c', 'd'});
      expect(ScopeState.fromJson(s.toJson()), s);
      expect(ScopeState.fromJson('nonsense'), ScopeState.network);
    });
  });

  group('ScopeController', () {
    test('remembers the scope per user', () async {
      final store = InMemoryKeyValueStore();
      final c1 = ScopeController(store: store);
      await c1.restore('u1', all, locked: false);
      await c1.update(const ScopeState(countryCode: 'GT'));

      final c2 = ScopeController(store: store);
      await c2.restore('u1', all, locked: false);
      expect(c2.state.countryCode, 'GT');

      final other = ScopeController(store: store);
      await other.restore('u2', all, locked: false);
      expect(other.state.isNetwork, isTrue);
    });

    test('branch manager is locked to the branch and cannot change it', () async {
      final c = ScopeController();
      await c.restore('u1', [b('a', 'SV')], locked: true);
      expect(c.locked, isTrue);
      expect(c.state.branchIds, {'a'});
      await c.update(ScopeState.network);
      expect(c.state.branchIds, {'a'});
      c.clear();
      expect(c.locked, isFalse);
    });
  });

  group('display preferences', () {
    test('unit and decimals persist and are clamped', () async {
      final store = InMemoryKeyValueStore();
      final p = DisplayPrefsController(store: store);
      await p.setUnit(VolumeUnit.gallons);
      await p.setDecimals(7);
      expect(p.prefs.decimals, 4);

      final again = DisplayPrefsController(store: store);
      await again.load();
      expect(again.prefs.unit, VolumeUnit.gallons);
      expect(again.prefs.decimals, 4);
    });

    test('defaults: litres and 2 decimals', () async {
      final p = DisplayPrefsController();
      await p.load();
      expect(p.prefs.unit, VolumeUnit.liters);
      expect(p.prefs.decimals, 2);
    });
  });

  group('alerts and inventory ordering', () {
    test('alerts are sorted by severity, stable inside a level', () {
      final sorted = sortAlerts(const [
        AlertItem(title: 'b', detail: '', severity: 'low'),
        AlertItem(title: 'c1', detail: '', severity: 'critical'),
        AlertItem(title: 'w', detail: '', severity: 'warning'),
        AlertItem(title: 'c2', detail: '', severity: 'critical'),
      ]);
      expect(sorted.map((a) => a.title), ['c1', 'c2', 'w', 'b']);
    });

    test('tanks come most critical first (30/60 thresholds)', () {
      InventoryTank t(String n, num? pct) => InventoryTank(
        branchName: n,
        tank: {'percentage': pct, 'capacityLiters': 100},
      );
      final sorted = sortBySeverity([t('ok', 80), t('mid', 45), t('low', 12), t('none', null), t('edge', 30)]);
      expect(sorted.map((e) => e.branchName), ['low', 'edge', 'mid', 'ok', 'none']);
      expect(tankSeverity(30), 0);
      expect(tankSeverity(60), 1);
      expect(tankSeverity(61), 2);
    });

    test('select options are searched without accents', () {
      const options = [
        SelectOption('1', 'Panamá'),
        SelectOption('2', 'Perú', detail: 'Lima'),
      ];
      expect(filterOptions(options, 'PANAMA').single.value, '1');
      expect(filterOptions(options, 'lima').single.value, '2');
      expect(filterOptions(options, '').length, 2);
    });
  });

  group('brand tokens', () {
    test('action colour passes AA in both modes (button text and links)', () {
      for (final c in [DlcColors.light, DlcColors.dark]) {
        expect(contrastRatio(c.action, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.onBrand, c.action), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.fuelSuper, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.fuelRegular, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.fuelDiesel, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.borderStrong, c.surface), greaterThanOrEqualTo(3));
        expect(contrastRatio(c.muted, c.canvas), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.ink, c.brandContainer), greaterThanOrEqualTo(4.5));
      }
      expect(contrastRatio(const Color(0xffffffff), DlcColors.light.heroEnd), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(const Color(0xffffffff), DlcColors.light.heroStart), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(const Color(0xffffffff), DlcColors.dark.heroEnd), greaterThanOrEqualTo(4.5));
    });
  });
}
