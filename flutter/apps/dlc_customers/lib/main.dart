import 'dart:ui' show PlatformDispatcher;
import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'haptics.dart';

const _apiUrl = String.fromEnvironment(
  'DLC_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:4000/api/v1',
);
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _termsVersion = String.fromEnvironment(
  'CUSTOMER_TERMS_VERSION',
  defaultValue: 'qa-draft-v1',
);
const _authRedirect = String.fromEnvironment(
  'SUPABASE_AUTH_REDIRECT_URL',
  defaultValue: 'sv.com.dlc.dlc_customers://login-callback/',
);
const _ink = Color(0xff213b32),
    _orange = Color(0xffd94d24),
    _paper = Color(0xfff5f0e5);
// Dark-mode counterparts: lighter tones so brand colours keep contrast on dark surfaces.
const _inkDark = Color(0xffa9d1bd),
    _orangeDark = Color(0xffff8a5c),
    _paperDark = Color(0xff111a16),
    _cardDark = Color(0xff1d2a25);

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Shared rules: the same functions drive inline feedback and submission.
String? validateEmail(String? value) =>
    _emailPattern.hasMatch((value ?? '').trim())
    ? null
    : 'Escribe un correo válido.';

String? validatePassword(String? value) => (value ?? '').length < 8
    ? 'La contraseña debe tener al menos 8 caracteres.'
    : null;

String? validateFullName(String? value) =>
    (value ?? '').trim().length < 2 ? 'Escribe tu nombre completo.' : null;

/// Brand theme for one brightness. Light and dark share seed and component
/// theming; only the palette differs.
ThemeData buildDlcTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final paper = dark ? _paperDark : _paper;
  final scheme = ColorScheme.fromSeed(
    seedColor: _ink,
    brightness: brightness,
    primary: dark ? _inkDark : _ink,
    secondary: dark ? _orangeDark : _orange,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: scheme.primary,
    ),
    cardTheme: CardThemeData(
      color: dark ? _cardDark : Colors.white,
      elevation: 0,
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'Uncaught Flutter framework error',
      name: 'dlc.customer.crash',
      error: details.exception.runtimeType,
      stackTrace: details.stack,
      level: 1000,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Uncaught asynchronous application error',
      name: 'dlc.customer.crash',
      error: error.runtimeType,
      stackTrace: stack,
      level: 1200,
    );
    return false;
  };
  if (_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
  }
  runApp(const CustomerApp());
}

class CustomerApp extends StatefulWidget {
  const CustomerApp({super.key});
  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  // In-memory only: the choice resets when the app restarts.
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DLC Clientes',
    debugShowCheckedModeBanner: false,
    theme: buildDlcTheme(Brightness.light),
    darkTheme: buildDlcTheme(Brightness.dark),
    themeMode: _themeMode,
    home: (_supabaseUrl.isEmpty || _supabaseKey.isEmpty)
        ? const ConfigurationScreen()
        : CustomerRoot(
            themeMode: _themeMode,
            onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
          ),
  );
}

class ConfigurationScreen extends StatelessWidget {
  const ConfigurationScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Falta configuración de QA. Inicia la app con SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY y DLC_API_BASE_URL usando --dart-define.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class CustomerApi {
  CustomerApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  Future<dynamic> get(String path, {String? token}) =>
      _send('GET', path, token: token);
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    required String token,
  }) => _send('POST', path, body: body, token: token);
  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final base = Uri.parse(_apiUrl);
    final normalized = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final route = Uri.parse(path);
    final uri = base.replace(
      path: '$normalized${route.path}',
      query: route.hasQuery ? route.query : null,
    );
    final correlationId = _newId();
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Accept': 'application/json',
          'X-Request-ID': correlationId,
        });
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      dynamic decoded;
      try {
        decoded = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body);
      } on FormatException {
        throw CustomerApiError(
          'El servidor devolvió una respuesta inesperada.',
          status: response.statusCode,
          correlationId: correlationId,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final root = decoded is Map ? decoded : const {};
        final error = root['error'] is Map ? root['error'] as Map : root;
        final message = error['message'] is String
            ? error['message'] as String
            : 'La solicitud no se completó (HTTP ${response.statusCode}).';
        developer.log(
          'Customer API HTTP ${response.statusCode} $method ${_safePath(path)} correlationId=$correlationId',
          name: 'dlc.customer',
          level: 900,
        );
        throw CustomerApiError(
          message,
          status: response.statusCode,
          correlationId: error['correlationId'] as String? ?? correlationId,
        );
      }
      if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
      return decoded;
    } on CustomerApiError {
      rethrow;
    } on Exception catch (error, stack) {
      developer.log(
        'Customer API network failure $method ${_safePath(path)} correlationId=$correlationId',
        name: 'dlc.customer',
        error: error.runtimeType,
        stackTrace: stack,
        level: 1000,
      );
      throw CustomerApiError(
        'No se pudo conectar con DLC. Comprueba tu conexión.',
        correlationId: correlationId,
      );
    }
  }
}

class CustomerApiError implements Exception {
  const CustomerApiError(this.message, {this.status, this.correlationId});
  final String message;
  final int? status;
  final String? correlationId;
  @override
  String toString() => message;
}

String _safePath(String value) => value
    .split('?')
    .first
    .replaceAll(
      RegExp(r'[0-9a-f]{8}-[0-9a-f-]{27,}', caseSensitive: false),
      ':id',
    );
String _newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class CustomerRoot extends StatefulWidget {
  const CustomerRoot({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  @override
  State<CustomerRoot> createState() => _CustomerRootState();
}

class _CustomerRootState extends State<CustomerRoot> {
  final api = CustomerApi();
  final TextEditingController branchSearch = TextEditingController();
  Session? get session => Supabase.instance.client.auth.currentSession;
  User? get user => Supabase.instance.client.auth.currentUser;
  ColorScheme get _scheme => Theme.of(context).colorScheme;
  Map<String, dynamic>? profile;
  Map<String, dynamic>? loyalty;
  Map<String, dynamic>? qr;
  List<Map<String, dynamic>> rewards = [],
      campaigns = [],
      promotions = [],
      branches = [],
      services = [],
      points = [],
      notifications = [],
      pointPaymentQuotes = [];
  String unreadCount = '0';
  String? selectedPromotionBranchId;
  bool busy = false, checking = true;
  bool recoveringPassword = false;
  String? error;
  int tab = 0;
  late final StreamSubscription<AuthState> authSubscription;

  @override
  void initState() {
    super.initState();
    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.event == AuthChangeEvent.passwordRecovery && mounted)
        setState(() => recoveringPassword = true);
      unawaited(_reload());
    });
    _reload();
  }

  @override
  void dispose() {
    authSubscription.cancel();
    branchSearch.dispose();
    api._client.close();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      checking = true;
      error = null;
    });
    try {
      final publicResults = await Future.wait([
        api.get('/customer/rewards'),
        api.get('/customer/campaigns'),
        api.get(_promotionFeedPath),
        api.get('/customer/branches'),
        api.get('/customer/services'),
      ]);
      rewards = _maps(publicResults[0]);
      campaigns = _maps(publicResults[1]);
      promotions = _maps(publicResults[2]);
      branches = _maps(publicResults[3]);
      services = _maps(publicResults[4]);
      final token = session?.accessToken;
      if (token != null) {
        try {
          final results = await Future.wait([
            api.get('/customer/me', token: token),
            api.get('/customer/me/loyalty', token: token),
            api.get('/customer/me/qr', token: token),
            api.get('/customer/me/points', token: token),
            api.get('/customer/me/notifications', token: token),
            api.get('/customer/me/points-payment-quotes', token: token),
          ]);
          profile = _map(results[0]);
          loyalty = _map(results[1]);
          qr = _map(results[2]);
          points = _maps(_map(results[3])['items']);
          notifications = _maps(_map(results[4])['items']);
          unreadCount = _str(_map(results[4])['unreadCount']);
          pointPaymentQuotes = _maps(results[5]);
        } on CustomerApiError catch (e) {
          if (e.status == 404) {
            profile = null;
            loyalty = null;
            qr = null;
            points = [];
            notifications = [];
            pointPaymentQuotes = [];
            unreadCount = '0';
          } else {
            rethrow;
          }
        }
      } else {
        profile = null;
        loyalty = null;
        qr = null;
        points = [];
        notifications = [];
        pointPaymentQuotes = [];
        unreadCount = '0';
      }
    } on CustomerApiError catch (e) {
      error =
          '${e.message}${e.correlationId == null ? '' : '\nReferencia: ${e.correlationId}'}';
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  /// Runs [action] behind the busy flag. Returns true on success; on failure
  /// it shows the error banner and plays the error haptic.
  Future<bool> _run(Future<void> Function() action) async {
    if (busy) return false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on CustomerApiError catch (e) {
      if (mounted)
        setState(
          () => error =
              '${e.message}${e.correlationId == null ? '' : '\nReferencia: ${e.correlationId}'}',
        );
    } catch (e, stack) {
      developer.log(
        'Customer flow failure',
        name: 'dlc.customer',
        error: e.runtimeType,
        stackTrace: stack,
        level: 1000,
      );
      if (mounted)
        setState(
          () => error = 'No se pudo completar esta acción. Intenta de nuevo.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
    Haptics.error();
    return false;
  }

  Future<bool> _signOut() => _run(() async {
    await Supabase.instance.client.auth.signOut();
    await _reload();
    Haptics.selection();
  });

  @override
  Widget build(BuildContext context) {
    if (checking)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final signedIn = session != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'DLC Clientes',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (signedIn && profile != null)
            IconButton(
              tooltip: unreadCount == '0'
                  ? 'Avisos'
                  : '$unreadCount avisos sin leer',
              onPressed: () => _openNotifications(),
              icon: Badge(
                isLabelVisible: unreadCount != '0',
                label: Text(unreadCount),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          if (signedIn)
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: busy ? null : _signOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (error != null) _errorBanner(context, error!),
            Expanded(
              child: recoveringPassword
                  ? RecoveryPasswordScreen(
                      busy: busy,
                      onSubmit: (password) => _run(() async {
                        await Supabase.instance.client.auth.updateUser(
                          UserAttributes(password: password),
                        );
                        if (mounted) setState(() => recoveringPassword = false);
                        await _reload();
                      }),
                    )
                  : (!signedIn
                        ? AuthScreen(
                            busy: busy,
                            onAction: _run,
                            onChanged: _reload,
                          )
                        : (profile == null
                              ? ProfileScreen(
                                  busy: busy,
                                  onSubmit: _saveProfile,
                                )
                              : _signedBody())),
            ),
          ],
        ),
      ),
      bottomNavigationBar: signedIn && profile != null
          ? NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (v) => setState(() => tab = v),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.stars_outlined),
                  label: 'Puntos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.local_offer_outlined),
                  label: 'Beneficios',
                ),
                NavigationDestination(
                  icon: Icon(Icons.qr_code_2),
                  label: 'Mi código',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Cuenta',
                ),
              ],
            )
          : null,
    );
  }

  Widget _signedBody() => RefreshIndicator(
    onRefresh: _reload,
    child: switch (tab) {
      0 => _loyaltyPage(),
      1 => _benefitsPage(),
      2 => _qrPage(),
      _ => _accountPage(),
    },
  );

  Widget _loyaltyPage() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Hola, ${profile?['fullName'] ?? ''}',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PUNTOS DISPONIBLES',
              style: TextStyle(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: _scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${loyalty?['pointsBalance'] ?? '0'}',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: _scheme.primary,
              ),
            ),
            Text(
              loyalty?['canRedeem'] == true
                  ? 'Valor para canje: ${_usd(loyalty?['availableValueUsd'])} USD'
                  : 'Canje de puntos no habilitado actualmente',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _scheme.primary,
              ),
            ),
            if (loyalty?['canRedeem'] == true)
              Text(
                'Tasa vigente: 1 punto = ${_usd(loyalty?['redemptionUsdPerPoint'])} USD',
                style: TextStyle(color: _scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 8),
            Text(
              loyalty?['message']?.toString() ??
                  'Consulta el historial de puntos.',
              style: TextStyle(color: _scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      if (pointPaymentQuotes.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text(
          'Solicitudes de pago en caja',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          'Revisa el importe y los puntos antes de autorizar. Cada solicitud vence en poco tiempo.',
          style: TextStyle(color: _scheme.onSurfaceVariant),
        ),
        ...pointPaymentQuotes.map(_pointPaymentQuoteCard),
      ],
      const SizedBox(height: 18),
      const Text(
        'Actividad reciente',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      if (points.isEmpty)
        const _Empty(
          text:
              'Tu historial aparecerá aquí cuando existan puntos asociados a compras.',
        ),
      ...points.map(
        (row) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.bolt, color: _scheme.secondary),
          title: Text(row['reason']?.toString() ?? _label(row['type'])),
          trailing: Text('${row['pointsDelta'] ?? ''} pts'),
        ),
      ),
    ],
  );

  Widget _pointPaymentQuoteCard(Map<String, dynamic> quote) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.point_of_sale_outlined, color: _scheme.secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _str(quote['branchName']),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${quote['points']} puntos · USD ${quote['amountUsd']}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        Text('Venta total: USD ${quote['saleTotalUsd'] ?? '—'}'),
        const SizedBox(height: 4),
        Text(
          'Al confirmar, los puntos se descuentan y el importe se aplica a esta venta. Esta acción no se puede deshacer desde la app.',
          style: TextStyle(fontSize: 12, color: _scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: busy ? null : () => _decidePointPayment(quote, false),
              child: const Text('Rechazar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: busy ? null : () => _decidePointPayment(quote, true),
              child: const Text('Confirmar pago'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<bool> _decidePointPayment(
    Map<String, dynamic> quote,
    bool confirm,
  ) => _run(() async {
    final token = session?.accessToken;
    if (token == null)
      throw const CustomerApiError(
        'Inicia sesión para resolver esta solicitud.',
      );
    final id = Uri.encodeComponent(_str(quote['id']));
    final action = confirm ? 'confirm' : 'decline';
    // The quote is single-use, so its UUID is also a durable decision command ID.
    // Retrying after a timeout replays the same confirmation instead of spending twice.
    final result = _map(
      await api.post('/customer/me/points-payment-quotes/$id/$action', {
        'commandId': _str(quote['id']),
      }, token: token),
    );
    await _reload();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _str(result['status']) == 'expired'
                ? 'La solicitud venció. Pide a caja que genere una nueva.'
                : confirm
                ? 'Pago confirmado. Los puntos se aplicaron a la venta.'
                : 'Solicitud rechazada. No se descontaron puntos.',
          ),
        ),
      );
    if (confirm) {
      Haptics.success();
    } else {
      Haptics.selection();
    }
  });

  String get _promotionFeedPath => selectedPromotionBranchId == null
      ? '/customer/promotions'
      : '/customer/promotions?branchId=${Uri.encodeQueryComponent(selectedPromotionBranchId!)}';

  Future<void> _selectPromotionBranch(String? branchId) async {
    setState(() {
      selectedPromotionBranchId = branchId;
      busy = true;
      error = null;
    });
    try {
      promotions = _maps(await api.get(_promotionFeedPath));
    } on CustomerApiError catch (e) {
      if (mounted)
        setState(
          () => error =
              '${e.message}${e.correlationId == null ? '' : '\nReferencia: ${e.correlationId}'}',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _benefitsPage() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Beneficios y novedades',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 14),
      const Text(
        'Recompensas',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      if (rewards.isEmpty)
        const _Empty(text: 'No hay recompensas publicadas en este momento.'),
      ...rewards.map(
        (item) => _card(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.card_giftcard, color: _scheme.secondary),
            title: Text(item['title']?.toString() ?? ''),
            subtitle: Text(item['description']?.toString() ?? ''),
            trailing: Text('${item['pointsCost'] ?? '—'} pts'),
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Promociones con beneficio',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      DropdownButtonFormField<String>(
        initialValue: selectedPromotionBranchId ?? '',
        decoration: const InputDecoration(
          labelText: 'Filtrar promociones por sucursal',
        ),
        items: [
          const DropdownMenuItem(
            value: '',
            child: Text('Todas las sucursales'),
          ),
          ...branches.map(
            (branch) => DropdownMenuItem(
              value: _str(branch['id']),
              child: Text(_str(branch['name'])),
            ),
          ),
        ],
        onChanged: busy
            ? null
            : (value) => _selectPromotionBranch(
                value == null || value.isEmpty ? null : value,
              ),
      ),
      if (promotions.isEmpty)
        const _Empty(text: 'No hay promociones vigentes para esta selección.'),
      ...promotions.map((item) => _promotionCard(item)),
      const SizedBox(height: 14),
      const Text(
        'Novedades',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      if (campaigns.isEmpty) const _Empty(text: 'No hay novedades publicadas.'),
      ...campaigns.map(
        (item) => _card(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.campaign_outlined, color: _scheme.secondary),
            title: Text(item['title']?.toString() ?? ''),
            subtitle: Text(item['body']?.toString() ?? ''),
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Servicios',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      if (services.isEmpty)
        const _Empty(text: 'No hay servicios publicados en este momento.'),
      ...services.map(
        (item) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.build_circle_outlined),
          title: Text(item['description']?.toString() ?? ''),
          subtitle: Text(_str(item['branchName'])),
          trailing: Text('USD ${item['priceUsd'] ?? '—'}'),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Sucursales',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      TextField(
        controller: branchSearch,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Buscar sucursal',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 8),
      if (_matchingBranches.isEmpty)
        _Empty(
          text: branchSearch.text.trim().isEmpty
              ? 'No hay sucursales activas.'
              : 'No hay sucursales que coincidan con la búsqueda.',
        ),
      ..._matchingBranches.map(
        (item) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.place_outlined),
          title: Text(item['name']?.toString() ?? ''),
          subtitle: Text('${item['zone'] ?? ''} · ${item['timezone'] ?? ''}'),
        ),
      ),
    ],
  );

  Widget _promotionCard(Map<String, dynamic> item) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PromotionDetailPage(promotion: item),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_str(item['imageUrl']).isNotEmpty)
              Image.network(
                _str(item['imageUrl']),
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                semanticLabel: _str(item['imageAlt']),
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 80,
                  child: Center(
                    child: Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _str(item['title']),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _promotionHeadline(item),
                    style: TextStyle(
                      color: _scheme.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _str(item['motive']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('Ver condiciones y detalles ›'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _openNotifications() async {
    final token = session?.accessToken;
    if (token == null) return;
    try {
      final result = _map(
        await api.get('/customer/me/notifications', token: token),
      );
      final items = _maps(result['items']);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              CustomerNotificationsPage(api: api, token: token, items: items),
        ),
      );
      await _reload();
    } on CustomerApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  List<Map<String, dynamic>> get _matchingBranches {
    final query = branchSearch.text.trim().toLowerCase();
    if (query.isEmpty) return branches;
    return branches
        .where(
          (branch) => '${branch['name'] ?? ''} ${branch['zone'] ?? ''}'
              .toLowerCase()
              .contains(query),
        )
        .toList(growable: false);
  }

  Widget _qrPage() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _card(
        child: Column(
          children: [
            Icon(Icons.qr_code_2, color: _scheme.primary, size: 38),
            const SizedBox(height: 12),
            const Text(
              'Mi código DLC',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            if (qr?['code'] is String)
              // The QR always sits on white with a quiet zone, in both themes,
              // so scanners can read it in dark mode too.
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: qr!['code'] as String,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              )
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              qr?['message']?.toString() ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: _scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            SelectableText(qr?['code']?.toString() ?? ''),
          ],
        ),
      ),
    ],
  );

  Widget _accountPage() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tu cuenta',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            _detail(context, 'Nombre', profile?['fullName']),
            _detail(context, 'Correo', user?.email),
            _detail(context, 'Teléfono', profile?['phone'] ?? 'No registrado'),
            _detail(context, 'Cuenta desde', profile?['createdAt']),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Apariencia',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Claro'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Oscuro'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('Sistema'),
                ),
              ],
              selected: {widget.themeMode},
              onSelectionChanged: (selection) {
                Haptics.selection();
                widget.onThemeModeChanged(selection.first);
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : _signOut,
        icon: const Icon(Icons.logout),
        label: const Text('Cerrar sesión'),
      ),
    ],
  );

  Future<void> _saveProfile(
    String name,
    String phone,
    bool communicationsConsent,
  ) async {
    await _run(() async {
      final token = session?.accessToken;
      if (token == null)
        throw const CustomerApiError('Inicia sesión nuevamente.');
      await api.post('/customer/me/profile', {
        'fullName': name.trim(),
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
        'termsVersion': _termsVersion,
        'termsAccepted': true,
        'communicationsConsent': communicationsConsent,
      }, token: token);
      await _reload();
    });
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.busy,
    required this.onAction,
    required this.onChanged,
  });
  final bool busy;
  final Future<bool> Function(Future<void> Function()) onAction;
  final VoidCallback onChanged;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false;
  ColorScheme get _scheme => Theme.of(context).colorScheme;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      Haptics.error();
      return;
    }
    await widget.onAction(() async {
      if (register) {
        final result = await Supabase.instance.client.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: _authRedirect,
          data: {'display_name': name.text.trim()},
        );
        if (result.session == null && mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Revisa tu correo'),
              content: const Text(
                'Enviamos un enlace de confirmación. Ábrelo en este dispositivo; luego inicia sesión.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
          setState(() => register = false);
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
      widget.onChanged();
      Haptics.success();
    });
  }

  Future<void> _resetPassword() => widget.onAction(() async {
    final problem = validateEmail(email.text);
    if (problem != null) throw CustomerApiError(problem);
    await Supabase.instance.client.auth.resetPasswordForEmail(
      email.text.trim(),
      redirectTo: _authRedirect,
    );
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Si el correo está registrado, recibirás instrucciones para restablecer tu contraseña.',
          ),
        ),
      );
  });

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Icon(Icons.local_gas_station, color: _scheme.secondary, size: 48),
          const SizedBox(height: 12),
          Text(
            register ? 'Crea tu cuenta' : 'Bienvenido',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _scheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Accede a tus puntos, novedades y beneficios DLC.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (register)
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              validator: validateFullName,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                border: OutlineInputBorder(),
              ),
            ),
          if (register) const SizedBox(height: 12),
          TextFormField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: validateEmail,
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: password,
            obscureText: true,
            autofillHints: [
              register ? AutofillHints.newPassword : AutofillHints.password,
            ],
            validator: validatePassword,
            decoration: const InputDecoration(
              labelText: 'Contraseña',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: widget.busy ? null : _submit,
            child: widget.busy
                ? const CircularProgressIndicator()
                : Text(register ? 'Crear cuenta' : 'Iniciar sesión'),
          ),
          TextButton(
            onPressed: widget.busy
                ? null
                : () => setState(() => register = !register),
            child: Text(register ? 'Ya tengo cuenta' : 'Crear una cuenta'),
          ),
          if (!register)
            TextButton(
              onPressed: widget.busy ? null : _resetPassword,
              child: const Text('Olvidé mi contraseña'),
            ),
          const SizedBox(height: 10),
          Text(
            'Cuenta de prueba: las condiciones legales deben aprobarse antes de activar producción.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _scheme.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}

class RecoveryPasswordScreen extends StatefulWidget {
  const RecoveryPasswordScreen({
    super.key,
    required this.busy,
    required this.onSubmit,
  });
  final bool busy;
  final Future<bool> Function(String password) onSubmit;
  @override
  State<RecoveryPasswordScreen> createState() => _RecoveryPasswordScreenState();
}

class _RecoveryPasswordScreenState extends State<RecoveryPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final password = TextEditingController();
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      Haptics.error();
      return;
    }
    widget.onSubmit(password.text);
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Crea una contraseña nueva',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            validator: validatePassword,
            decoration: const InputDecoration(
              labelText: 'Nueva contraseña',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.busy ? null : _submit,
            child: const Text('Guardar contraseña'),
          ),
        ],
      ),
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.busy, required this.onSubmit});
  final bool busy;
  final Future<void> Function(String name, String phone, bool consent) onSubmit;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final name = TextEditingController(), phone = TextEditingController();
  bool termsAccepted = false, communicationsConsent = false;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      Haptics.error();
      return;
    }
    if (!termsAccepted) {
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes aceptar las condiciones para crear el perfil.'),
        ),
      );
      return;
    }
    widget.onSubmit(name.text, phone.text, communicationsConsent);
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Completa tu perfil',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Correo verificado: ${Supabase.instance.client.auth.currentUser?.email ?? ''}',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            validator: validateFullName,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Teléfono (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            value: termsAccepted,
            onChanged: (v) => setState(() => termsAccepted = v ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Acepto las condiciones vigentes de la cuenta. Las recompensas solo estarán disponibles cuando se publique el programa.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: communicationsConsent,
            onChanged: (v) =>
                setState(() => communicationsConsent = v ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Quiero recibir novedades y comunicaciones promocionales (opcional).',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          FilledButton(
            onPressed: widget.busy ? null : _submit,
            child: const Text('Guardar y continuar'),
          ),
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

Widget _card({required Widget child}) => Card(
  elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  child: Padding(padding: const EdgeInsets.all(18), child: child),
);
Widget _errorBanner(BuildContext context, String text) {
  final scheme = Theme.of(context).colorScheme;
  return Material(
    color: scheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
    ),
  );
}

Widget _detail(BuildContext context, String label, dynamic value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Row(
    children: [
      SizedBox(
        width: 115,
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Expanded(child: Text(value?.toString() ?? '—')),
    ],
  ),
);
List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
    : const [];
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
String _str(dynamic value) => value?.toString() ?? '';
String _label(dynamic value) => (value?.toString() ?? '').replaceAll('_', ' ');
String _usd(dynamic value) =>
    (double.tryParse(value?.toString() ?? '') ?? 0).toStringAsFixed(2);
String _promotionHeadline(Map<String, dynamic> promotion) => switch (_str(
  promotion['kind'],
)) {
  'unit_discount' =>
    'USD ${_str(promotion['value'])} menos por ${_str(promotion['valueUnit']) == 'us_gallon' ? 'galón' : 'litro'}',
  'percent_discount' => '${_str(promotion['value'])}% de descuento',
  'cashback' =>
    '${_str(promotion['value'])}% cashback · tope USD ${_str(promotion['benefitCapUsd'])}',
  'points_multiplier' => '${_str(promotion['value'])}× puntos',
  _ => 'Promoción informativa',
};

class PromotionDetailPage extends StatelessWidget {
  const PromotionDetailPage({super.key, required this.promotion});
  final Map<String, dynamic> promotion;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de promoción')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_str(promotion['imageUrl']).isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                _str(promotion['imageUrl']),
                height: 220,
                fit: BoxFit.cover,
                semanticLabel: _str(promotion['imageAlt']),
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 120,
                  child: Center(
                    child: Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _str(promotion['title']),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _promotionHeadline(promotion),
            style: TextStyle(
              fontSize: 19,
              color: scheme.secondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_str(promotion['branchName']).isNotEmpty)
            Text('Sucursal: ${_str(promotion['branchName'])}'),
          const SizedBox(height: 10),
          Text(_str(promotion['motive'])),
          const SizedBox(height: 18),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vigencia',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_str(promotion['startsAt'])} — ${_str(promotion['endsAt'])}',
                ),
                Text('Zona horaria: ${_str(promotion['timeZone'])}'),
                Text(
                  'Repetición: ${_recurrenceLabel(_map(promotion['recurrence']))}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aplica cuando',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ..._strings(_map(promotion['terms'])['applies']).map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.check_circle_outline,
                      color: scheme.primary,
                    ),
                    title: Text(item),
                  ),
                ),
                if (_strings(
                  _map(promotion['terms'])['excludes'],
                ).isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    'No aplica en',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ..._strings(_map(promotion['terms'])['excludes']).map(
                    (item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.block_outlined),
                      title: Text(item),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_str(promotion['kind']) == 'cashback')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'El cashback queda sujeto a los términos publicados y a la validación de la entidad financiera participante.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class CustomerNotificationsPage extends StatefulWidget {
  const CustomerNotificationsPage({
    super.key,
    required this.api,
    required this.token,
    required this.items,
  });
  final CustomerApi api;
  final String token;
  final List<Map<String, dynamic>> items;
  @override
  State<CustomerNotificationsPage> createState() =>
      _CustomerNotificationsPageState();
}

class _CustomerNotificationsPageState extends State<CustomerNotificationsPage> {
  late List<Map<String, dynamic>> items = widget.items;
  String? error;
  final Set<String> busy = {};
  ColorScheme get _scheme => Theme.of(context).colorScheme;
  Future<void> _read(Map<String, dynamic> item) async {
    final id = _str(item['id']);
    if (id.isEmpty || item['readAt'] != null || busy.contains(id)) return;
    setState(() {
      busy.add(id);
      error = null;
    });
    try {
      await widget.api.post('/customer/me/notifications/read', {
        'notificationId': id,
      }, token: widget.token);
      if (mounted)
        setState(() {
          item['readAt'] = DateTime.now().toUtc().toIso8601String();
        });
    } on CustomerApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Avisos')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null) _errorBanner(context, error!),
        if (items.isEmpty)
          const _Empty(text: 'No tienes avisos por el momento.'),
        ...items.map(
          (item) => Card(
            child: ListTile(
              onTap: () => _read(item),
              leading: Icon(
                item['readAt'] == null
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none,
                color: item['readAt'] == null
                    ? _scheme.secondary
                    : _scheme.onSurfaceVariant,
              ),
              title: Text(
                _str(item['title']),
                style: TextStyle(
                  fontWeight: item['readAt'] == null
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                '${_str(item['body'])}\n${_str(item['createdAt'])}',
              ),
              isThreeLine: true,
              trailing: busy.contains(_str(item['id']))
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          ),
        ),
      ],
    ),
  );
}

String _recurrenceLabel(Map<String, dynamic> recurrence) =>
    switch (_str(recurrence['kind'])) {
      'weekly' => 'Semanal · ${_strings(recurrence['weekdays']).join(', ')}',
      'monthly' => 'Mensual · día ${_str(recurrence['dayOfMonth'])}',
      _ => 'Una vez',
    };
List<String> _strings(dynamic value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];
