/// Country support shared by branch models and network metrics.
///
/// The backend stores `countryCode` as ISO 3166-1 alpha-2 in uppercase and
/// defaults to `SV` (El Salvador) when a branch has none.
const String kDefaultCountryCode = 'SV';

/// Returns an uppercase two-letter code, or [kDefaultCountryCode] when [raw]
/// is missing or malformed. Tolerates responses from older servers.
String normalizeCountryCode(Object? raw) {
  final code = raw?.toString().trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : kDefaultCountryCode;
}

/// One entry of `countries: [{countryCode, branchCount}]` in network responses.
class NetworkCountry {
  const NetworkCountry({required this.countryCode, required this.branchCount});

  final String countryCode;
  final int branchCount;

  factory NetworkCountry.fromJson(Map<String, dynamic> json) => NetworkCountry(
    countryCode: normalizeCountryCode(json['countryCode']),
    branchCount: int.tryParse('${json['branchCount'] ?? 0}') ?? 0,
  );

  /// Parses the optional `countries` list; missing or malformed => empty.
  static List<NetworkCountry> listFrom(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((m) => NetworkCountry.fromJson(Map<String, dynamic>.from(m)))
            .toList(growable: false)
      : const <NetworkCountry>[];
}
