import 'package:dlc_api/dlc_api.dart';
import 'package:dlc_operations/country_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

BranchSummary branch(String id, String? country) => BranchSummary.fromJson({
  'id': id,
  'code': id.toUpperCase(),
  'name': 'Sucursal $id',
  'zone': 'central',
  'timezone': 'America/El_Salvador',
  if (country != null) 'countryCode': country,
});

void main() {
  final branches = [
    branch('a', 'SV'),
    branch('b', 'gt'),
    branch('c', null),
    branch('d', 'GT'),
    branch('e', 'XX'),
  ];

  group('normalizeCountryCode', () {
    test('uppercases, trims and defaults to SV', () {
      expect(normalizeCountryCode('gt'), 'GT');
      expect(normalizeCountryCode(' hn '), 'HN');
      expect(normalizeCountryCode(null), 'SV');
      expect(normalizeCountryCode(''), 'SV');
      expect(normalizeCountryCode('SLV'), 'SV');
      expect(normalizeCountryCode('1'), 'SV');
      expect(normalizeCountryCode(42), 'SV');
    });
  });

  group('BranchSummary.countryCode', () {
    test('missing field falls back to SV', () {
      expect(branches[2].countryCode, 'SV');
    });
    test('lowercase input is normalized', () {
      expect(branches[1].countryCode, 'GT');
    });
    test('const constructor default is SV', () {
      const b = BranchSummary(
        id: '1',
        code: 'C',
        name: 'N',
        zone: 'z',
        timezone: 'tz',
      );
      expect(b.countryCode, 'SV');
    });
  });

  group('countryName', () {
    test('Spanish names for common codes', () {
      expect(countryName('SV'), 'El Salvador');
      expect(countryName('GT'), 'Guatemala');
      expect(countryName('HN'), 'Honduras');
      expect(countryName('NI'), 'Nicaragua');
      expect(countryName('CR'), 'Costa Rica');
      expect(countryName('PA'), 'Panamá');
      expect(countryName('MX'), 'México');
      expect(countryName('US'), 'Estados Unidos');
      expect(countryName('CO'), 'Colombia');
    });
    test('falls back to the code or SV', () {
      expect(countryName('XX'), 'XX');
      expect(countryName(null), 'El Salvador');
    });
  });

  group('filtering', () {
    test('no country returns every branch', () {
      expect(filterBranchesByCountry(branches, null), branches);
      expect(filterBranchesByCountry(branches, ''), branches);
    });
    test('filters by country, missing countries count as SV', () {
      expect(filterBranchesByCountry(branches, 'SV').map((b) => b.id), [
        'a',
        'c',
      ]);
      expect(filterBranchesByCountry(branches, 'gt').map((b) => b.id), [
        'b',
        'd',
      ]);
      expect(filterBranchesByCountry(branches, 'MX'), isEmpty);
    });
    test('country and branch filters combine', () {
      expect(
        filterBranches(branches, countryCode: 'GT', branchId: 'd').single.id,
        'd',
      );
      expect(
        filterBranches(branches, countryCode: 'SV', branchId: 'd'),
        isEmpty,
      );
      expect(filterBranches(branches, branchId: 'e').single.id, 'e');
    });
  });

  group('reconcileBranchForCountry', () {
    test('keeps a compatible branch', () {
      expect(reconcileBranchForCountry('b', 'GT', branches), 'b');
      expect(reconcileBranchForCountry('a', null, branches), 'a');
    });
    test('resets an incompatible or unknown branch', () {
      expect(reconcileBranchForCountry('a', 'GT', branches), isNull);
      expect(reconcileBranchForCountry('zzz', null, branches), isNull);
      expect(reconcileBranchForCountry(null, 'GT', branches), isNull);
    });
  });

  group('countryOptions', () {
    test('counts branches per country sorted by Spanish name', () {
      final options = countryOptions(branches);
      expect(options.map((c) => c.countryCode), ['SV', 'GT', 'XX']);
      // Sorted by name: "El Salvador" < "Guatemala" < "XX".
      expect({for (final c in options) c.countryCode: c.branchCount}, {
        'SV': 2,
        'GT': 2,
        'XX': 1,
      });
    });
    test('prefers the server list when present', () {
      final options = countryOptions(
        branches,
        fromServer: const [
          NetworkCountry(countryCode: 'HN', branchCount: 7),
          NetworkCountry(countryCode: 'CR', branchCount: 1),
        ],
      );
      expect(options.map((c) => c.countryCode), ['CR', 'HN']);
      expect(options.last.branchCount, 7);
    });
  });

  group('selectableCountryCodes', () {
    test('includes known codes plus extras without duplicates', () {
      final codes = selectableCountryCodes(['gt', 'XX']);
      expect(codes, containsAll(kCountryNamesEs.keys));
      expect(codes, contains('XX'));
      expect(codes.where((c) => c == 'GT').length, 1);
    });
  });

  group('NetworkCountry', () {
    test('parses the countries list tolerantly', () {
      final list = NetworkCountry.listFrom([
        {'countryCode': 'gt', 'branchCount': 3},
        {'branchCount': '2'},
        'garbage',
      ]);
      expect(list.length, 2);
      expect(list[0].countryCode, 'GT');
      expect(list[0].branchCount, 3);
      expect(list[1].countryCode, 'SV');
      expect(list[1].branchCount, 2);
      expect(NetworkCountry.listFrom(null), isEmpty);
      expect(NetworkCountry.listFrom('x'), isEmpty);
    });
  });
}
