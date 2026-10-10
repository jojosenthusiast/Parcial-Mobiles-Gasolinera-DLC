import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/foundation.dart';

import 'branch_status.dart';
import 'country_catalog.dart';
import 'preferences.dart';

/// What the user is looking at: the whole network, one country or a set of
/// branches. Pure value type (maps 1:1 to a Swift struct).
@immutable
class ScopeState {
  const ScopeState({this.countryCode, this.branchIds = const {}});

  /// Null means every country.
  final String? countryCode;

  /// Empty means every branch (inside [countryCode] when set).
  final Set<String> branchIds;

  static const network = ScopeState();

  bool get isNetwork => countryCode == null && branchIds.isEmpty;

  /// Branches inside the scope (any status).
  List<BranchSummary> resolve(List<BranchSummary> all) {
    final inCountry = filterBranchesByCountry(all, countryCode);
    if (branchIds.isEmpty) return inCountry;
    return [
      for (final b in inCountry)
        if (branchIds.contains(b.id)) b,
    ];
  }

  /// Only operating branches inside the scope.
  List<BranchSummary> resolveActive(List<BranchSummary> all) =>
      activeBranches(resolve(all));

  /// Changes the country and drops branches that no longer belong to it.
  ScopeState withCountry(String? code, List<BranchSummary> all) {
    final normalized = code == null || code.isEmpty
        ? null
        : normalizeCountryCode(code);
    final inCountry = filterBranchesByCountry(all, normalized);
    return ScopeState(
      countryCode: normalized,
      branchIds: {
        for (final b in inCountry)
          if (branchIds.contains(b.id)) b.id,
      },
    );
  }

  ScopeState withBranches(Iterable<String> ids) =>
      ScopeState(countryCode: countryCode, branchIds: ids.toSet());

  /// Forgets branches that disappeared and a country without branches.
  ScopeState sanitize(List<BranchSummary> all) {
    final known = {for (final b in all) b.id};
    final country = countryCode != null &&
            all.any((b) => b.countryCode == countryCode)
        ? countryCode
        : null;
    final ids = branchIds.where(known.contains).toSet();
    final next = ScopeState(countryCode: country, branchIds: ids);
    return next.withCountry(country, all);
  }

  Map<String, dynamic> toJson() => {
    'country': countryCode,
    'branches': branchIds.toList()..sort(),
  };

  factory ScopeState.fromJson(Object? raw) {
    if (raw is! Map) return ScopeState.network;
    final country = raw['country']?.toString();
    final ids = raw['branches'];
    return ScopeState(
      countryCode: country == null || country.isEmpty
          ? null
          : normalizeCountryCode(country),
      branchIds: ids is List ? ids.map((e) => e.toString()).toSet() : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScopeState &&
      other.countryCode == countryCode &&
      setEquals(other.branchIds, branchIds);

  @override
  int get hashCode => Object.hash(countryCode, Object.hashAllUnordered(branchIds));
}

/// Branches the screens should show for [scope]: the explicit selection, or
/// the operating branches inside the country (all of them when none operates
/// yet, so the user sees why).
List<BranchSummary> effectiveBranches(
  ScopeState scope,
  List<BranchSummary> all,
) {
  final inScope = scope.resolve(all);
  if (scope.branchIds.isNotEmpty) return inScope;
  final active = activeBranches(inScope);
  return active.isEmpty ? inScope : active;
}

/// "Toda la red", "El Salvador", "Centro", "Centro y 2 más".
String describeScope(ScopeState scope, List<BranchSummary> all) {
  final inScope = scope.resolve(all);
  if (scope.branchIds.isNotEmpty) {
    if (inScope.isEmpty) return 'Sin sucursales';
    if (inScope.length == 1) return inScope.first.name;
    return '${inScope.first.name} y ${inScope.length - 1} más';
  }
  if (scope.countryCode != null) return countryName(scope.countryCode);
  return 'Toda la red';
}

/// Short text of the country chip.
String countryChipLabel(ScopeState scope) =>
    scope.countryCode == null ? 'Todos' : countryName(scope.countryCode);

/// Short text of the branch chip.
String branchChipLabel(ScopeState scope, List<BranchSummary> all) {
  if (scope.branchIds.isEmpty) return 'Todas';
  final inScope = scope.resolve(all);
  if (inScope.length == 1) return inScope.first.name;
  return '${inScope.length} sucursales';
}

/// "Viendo: El Salvador - 3 sucursales" (the visible chip text).
String viewingLabel(ScopeState scope, List<BranchSummary> all) {
  final inScope = scope.resolve(all);
  final count = inScope.length == 1 ? '1 sucursal' : '${inScope.length} sucursales';
  if (scope.branchIds.isNotEmpty && inScope.length == 1) {
    final b = inScope.first;
    return '${b.name} · ${countryName(b.countryCode)}';
  }
  return '${describeScope(scope, all)} · $count';
}

/// Remembers the scope per user and applies the lock rules.
class ScopeController extends ChangeNotifier {
  ScopeController({KeyValueStore? store})
    : _store = store ?? InMemoryKeyValueStore();

  final KeyValueStore _store;
  ScopeState _state = ScopeState.network;
  String? _userId;
  bool _locked = false;

  ScopeState get state => _state;

  /// True for branch managers: their branch is fixed (lock icon).
  bool get locked => _locked;

  String _key(String userId) => 'scope.$userId';

  /// Restores the saved scope of [userId] and applies it (sanitised) to
  /// [branches]. Locked users always see their own branch.
  Future<void> restore(
    String userId,
    List<BranchSummary> branches, {
    required bool locked,
  }) async {
    _userId = userId;
    _locked = locked;
    var next = ScopeState.network;
    if (locked) {
      next = ScopeState(
        countryCode: branches.length == 1 ? branches.first.countryCode : null,
        branchIds: {for (final b in branches) b.id},
      );
    } else {
      try {
        next = ScopeState.fromJson(decodeJson(await _store.read(_key(userId))));
      } catch (_) {
        next = ScopeState.network;
      }
      next = next.sanitize(branches);
    }
    _state = next;
    notifyListeners();
  }

  /// Updates the scope (ignored when locked) and persists it.
  Future<void> update(ScopeState next) async {
    if (_locked || next == _state) return;
    _state = next;
    notifyListeners();
    await _persist();
  }

  /// Keeps the controller in sync without persisting (internal selections).
  void syncSilently(ScopeState next) {
    if (_locked || next == _state) return;
    _state = next;
    notifyListeners();
  }

  void clear() {
    _userId = null;
    _locked = false;
    _state = ScopeState.network;
    notifyListeners();
  }

  Future<void> _persist() async {
    final id = _userId;
    if (id == null) return;
    final json = encodeJson(_state.toJson());
    if (json == null) return;
    try {
      await _store.write(_key(id), json);
    } catch (_) {
      // Best effort.
    }
  }
}
