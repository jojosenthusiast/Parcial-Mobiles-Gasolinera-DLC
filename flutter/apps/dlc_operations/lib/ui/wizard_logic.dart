import '../code_suggest.dart';

/// Pure rules of the "Alta de sucursal" wizard (maps 1:1 to Swift).
const int kWizardSteps = 5;

const wizardStepTitles = <String>[
  'Datos básicos',
  'Infraestructura',
  'Personal',
  'Tienda',
  'Revisión y activación',
];

const wizardStepHints = <String>[
  'El nombre, el código y el país identifican a la sucursal en todos los reportes y definen su moneda.',
  'Cuántas bombas y tipos de combustible tendrá fija lo que el servidor exige antes de activar la sucursal.',
  'Se necesita al menos una persona que administre. Si aún no la tienes, puedes completar esto después.',
  'La tienda es opcional. Si la sucursal vende productos, se prepara su caja desde el inicio.',
  'Aquí ves qué falta. Resuelve cada pendiente y activa la sucursal cuando el servidor la dé por lista.',
];

/// Where to resume a branch that already exists on the server, from its
/// `onboardingData` (a step is done when its checkpoint key exists).
int resumeStepFor(Map<String, dynamic> onboardingData) {
  if (!onboardingData.containsKey('dispensers')) return 1;
  if (!onboardingData.containsKey('staff')) return 2;
  if (!onboardingData.containsKey('review')) return 3;
  return 4;
}

/// Operating profile the server needs at creation time. Six pumps matches
/// the lab template; any other count is an operational branch.
String profileForPumps(int pumps) => pumps == 6 ? 'academicLab22' : 'operational';

/// Fuel families the branch can sell, in display order.
const wizardFuels = <String, String>{
  'super': 'Súper',
  'regular': 'Regular',
  'diesel': 'Diésel',
};

/// Next branch code for [countryCode] from the codes already in use:
/// `['SV-001']` -> `SV-002`; none -> `SV-01`.
String suggestBranchCode(Iterable<String> existing, String countryCode) {
  final prefix = '${countryCode.toUpperCase()}-';
  final inCountry = existing.where(
    (c) => c.toUpperCase().startsWith(prefix),
  );
  return suggestNextCode(inCountry.toList().reversed, fallbackPrefix: prefix) ??
      '${prefix}01';
}

/// Minimum tanks: one per fuel type. Maximum is a sane upper bound.
String? tanksForFuels(String? value, int fuelCount) {
  final n = int.tryParse(value?.trim() ?? '');
  if (n == null) return 'Los tanques deben ser un número entero.';
  if (n < (fuelCount < 1 ? 1 : fuelCount)) {
    return 'Necesitas al menos un tanque por tipo de combustible ($fuelCount).';
  }
  if (n > 20) return 'Los tanques deben estar entre 1 y 20.';
  return null;
}
