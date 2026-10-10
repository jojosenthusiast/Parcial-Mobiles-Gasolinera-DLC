import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _baseUrl = String.fromEnvironment(
  'DLC_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:4000/api/v1',
);

class DlcApiException implements Exception {
  const DlcApiException(
    this.message, {
    this.code,
    this.correlationId,
    this.statusCode,
  });

  final String message;
  final String? code;
  final String? correlationId;
  final int? statusCode;

  @override
  String toString() => message;
}

class EmployeeIdentity {
  const EmployeeIdentity({
    required this.id,
    required this.organizationId,
    required this.displayName,
    required this.email,
    required this.roles,
  });

  final String id;
  final String organizationId;
  final String displayName;
  final String email;
  final List<EmployeeRole> roles;

  bool get isGeneralManager => roles.any((role) {
    final roleText = '${role.code} ${role.name}'.toLowerCase();
    return roleText.contains('general');
  });

  factory EmployeeIdentity.fromJson(Map<String, dynamic> json) =>
      EmployeeIdentity(
        id: _string(json['id']),
        organizationId: _string(json['organizationId']),
        displayName: _string(json['displayName']),
        email: _string(json['email']),
        roles: (json['roles'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EmployeeRole.fromJson)
            .toList(growable: false),
      );
}

class EmployeeRole {
  const EmployeeRole({required this.code, required this.name, this.branchId});

  final String code;
  final String name;
  final String? branchId;

  factory EmployeeRole.fromJson(Map<String, dynamic> json) => EmployeeRole(
    code: _string(json['code']),
    name: _string(json['name']),
    branchId: json['branchId'] as String?,
  );
}

class BranchSummary {
  const BranchSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.zone,
    required this.timezone,
    this.status = 'active',
    this.onboardingVersion = 1,
  });

  final String id;
  final String code;
  final String name;
  final String zone;
  final String timezone;
  final String status;
  final int onboardingVersion;

  factory BranchSummary.fromJson(Map<String, dynamic> json) => BranchSummary(
    id: _string(json['id']),
    code: _string(json['code']),
    name: _string(json['name']),
    zone: _string(json['zone']),
    timezone: _string(json['timezone']),
    status: _string(json['status']).isEmpty
        ? 'active'
        : _string(json['status']),
    onboardingVersion: int.tryParse('${json['onboardingVersion'] ?? 1}') ?? 1,
  );
}

class EmployeeSession {
  EmployeeSession({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;
  String? _accessToken;
  String? _refreshToken;
  String? _sessionId;
  Future<void>? _refreshing;

  Future<EmployeeIdentity> login(String email, String password) async {
    if (email.trim().isEmpty || !email.contains('@')) {
      throw const DlcApiException('Escribe un correo válido.');
    }
    if (password.isEmpty || password.length > 256) {
      throw const DlcApiException('La contraseña no es válida.');
    }
    final token = await _request(
      'POST',
      '/auth/login',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'deviceLabel': 'DLC Operaciones Flutter',
      },
      authenticated: false,
    );
    await _saveToken(token);
    try {
      return await _identity();
    } catch (_) {
      await clear();
      rethrow;
    }
  }

  Future<EmployeeIdentity?> restore() async {
    _accessToken = await _storage.read(key: 'operations.access');
    _refreshToken = await _storage.read(key: 'operations.refresh');
    _sessionId = await _storage.read(key: 'operations.session');
    if ((_accessToken ?? '').isEmpty || (_refreshToken ?? '').isEmpty) {
      await clear();
      return null;
    }
    try {
      await _refresh();
      return await _identity();
    } on DlcApiException catch (error) {
      if (error.code == 'UNAUTHORIZED' || error.code == 'SESSION_INVALID') {
        await clear();
        return null;
      }
      rethrow;
    }
  }

  Future<List<String>> capabilities({String? branchId}) async {
    final query = branchId == null
        ? ''
        : '?branchId=${Uri.encodeQueryComponent(branchId)}';
    final payload = await _request('GET', '/auth/me/capabilities$query');
    return (payload['data']?['permissions'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
  }

  Future<EmployeeIdentity> currentIdentity() => _identity();

  Future<List<BranchSummary>> branches({String status = 'active'}) async {
    final payload = await _request(
      'GET',
      '/branches?status=${Uri.encodeQueryComponent(status)}&limit=100',
    );
    final rows = payload['data'] as List<dynamic>? ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(BranchSummary.fromJson)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createBranchDraft({
    required String code,
    required String name,
    required String zone,
    required String timezone,
    required String profile,
    required int expectedDispenserCount,
  }) async => _data(
    await _request(
      'POST',
      '/branches',
      body: {
        'code': code.trim().toUpperCase(),
        'name': name.trim(),
        'zone': zone,
        'timezone': timezone.trim(),
        'profile': profile,
        'expectedDispenserCount': expectedDispenserCount,
      },
    ),
  );

  Future<Map<String, dynamic>> branchDetail(String branchId) async => _data(
    await _request('GET', '/branches/${Uri.encodeComponent(branchId)}'),
  );

  Future<Map<String, dynamic>> branchReadiness(String branchId) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/readiness',
    ),
  );

  Future<Map<String, dynamic>> saveBranchStep(
    String branchId, {
    required int expectedVersion,
    required String step,
    required Map<String, dynamic> data,
  }) async => _data(
    await _request(
      'PATCH',
      '/branches/${Uri.encodeComponent(branchId)}/onboarding',
      body: {'expectedVersion': expectedVersion, 'step': step, 'data': data},
    ),
  );

  Future<Map<String, dynamic>> activateBranch(
    String branchId,
    int expectedVersion,
  ) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/activate',
      body: {'expectedVersion': expectedVersion},
    ),
  );

  Future<List<Map<String, dynamic>>> fuelPriceProposals(String branchId) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/fuel-price-proposals',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> proposeFuelPrice(
    String branchId, {
    required String fuelProductId,
    required String serviceMode,
    required String price,
    required DateTime effectiveAt,
    required String reason,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/fuel-price-proposals',
      body: {
        'fuelProductId': fuelProductId,
        'serviceMode': serviceMode,
        'priceUsdPerUnit': price.trim(),
        'unit': 'liter',
        'effectiveAt': effectiveAt.toUtc().toIso8601String(),
        'reason': reason.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> decideFuelPrice(
    String proposalId,
    int expectedVersion,
  ) async => _data(
    await _request(
      'POST',
      '/fuel-price-proposals/${Uri.encodeComponent(proposalId)}/approve',
      body: {'expectedVersion': expectedVersion},
    ),
  );

  Future<Map<String, dynamic>> scheduleFuelPrice(
    String proposalId,
    int expectedVersion,
  ) async => _data(
    await _request(
      'POST',
      '/fuel-price-proposals/${Uri.encodeComponent(proposalId)}/schedule',
      body: {'expectedVersion': expectedVersion},
    ),
  );

  Future<List<Map<String, dynamic>>> promotions({String? branchId}) async {
    final query = branchId == null
        ? ''
        : '?branchId=${Uri.encodeQueryComponent(branchId)}';
    final payload = await _request('GET', '/promotions$query');
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> cashbackPartners() async {
    final payload = await _request('GET', '/promotions/cashback-partners');
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createCashbackPartner(
    String code,
    String displayName,
  ) async => _data(
    await _request(
      'POST',
      '/promotions/cashback-partners',
      body: {
        'commandId': _uuidV4(),
        'code': code.trim().toUpperCase(),
        'displayName': displayName.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> uploadPromotionImage(
    Uint8List imageBytes,
    String mimeType, {
    required String commandId,
    required String scope,
    String? branchId,
  }) async => _data(
    await _request(
      'POST',
      '/promotions/images',
      body: {
        'commandId': commandId,
        'scope': scope,
        if (branchId != null) 'branchId': branchId,
        'mimeType': mimeType,
        'dataBase64': base64Encode(imageBytes),
      },
    ),
  );

  Future<Map<String, dynamic>> setCashbackPartnerStatus(
    String code,
    String status,
  ) async => _data(
    await _request(
      'POST',
      '/promotions/cashback-partners/${Uri.encodeComponent(code)}/status',
      body: {'commandId': _uuidV4(), 'status': status},
    ),
  );

  Future<Map<String, dynamic>> previewPromotion(
    Map<String, dynamic> definition,
  ) async => _data(
    await _request(
      'POST',
      '/promotions/preview',
      body: {...definition, 'commandId': _uuidV4()},
    ),
  );

  Future<Map<String, dynamic>> createPromotion(
    Map<String, dynamic> definition,
  ) async => _data(
    await _request(
      'POST',
      '/promotions',
      body: {...definition, 'commandId': _uuidV4()},
    ),
  );

  Future<Map<String, dynamic>> createPromotionVersion(
    String id,
    Map<String, dynamic> definition,
  ) async => _data(
    await _request(
      'POST',
      '/promotions/${Uri.encodeComponent(id)}/versions',
      body: {...definition, 'commandId': _uuidV4()},
    ),
  );

  Future<Map<String, dynamic>> submitPromotion(String id) async => _data(
    await _request(
      'POST',
      '/promotions/${Uri.encodeComponent(id)}/submit',
      body: {'commandId': _uuidV4()},
    ),
  );

  Future<Map<String, dynamic>> decidePromotion(
    String id,
    String decision,
    String reason,
  ) async => _data(
    await _request(
      'POST',
      '/promotions/${Uri.encodeComponent(id)}/decision',
      body: {
        'commandId': _uuidV4(),
        'decision': decision,
        'reason': reason.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> pausePromotion(String id, String reason) async =>
      _data(
        await _request(
          'POST',
          '/promotions/${Uri.encodeComponent(id)}/pause',
          body: {'commandId': _uuidV4(), 'reason': reason.trim()},
        ),
      );

  Future<Map<String, dynamic>> resumePromotion(String id) async => _data(
    await _request(
      'POST',
      '/promotions/${Uri.encodeComponent(id)}/resume',
      body: {'commandId': _uuidV4()},
    ),
  );

  Future<List<Map<String, dynamic>>> loyaltyPrograms() async {
    final payload = await _request('GET', '/loyalty/programs');
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createLoyaltyProgram({
    required double pointsPerEligibleUsd,
    required double minimumEligibleUsd,
    required double redemptionUsdPerPoint,
  }) async => _data(
    await _request(
      'POST',
      '/loyalty/programs',
      body: {
        'commandId': _uuidV4(),
        'pointsPerEligibleUsd': pointsPerEligibleUsd,
        'minimumEligibleUsd': minimumEligibleUsd,
        'redemptionUsdPerPoint': redemptionUsdPerPoint,
      },
    ),
  );

  Future<Map<String, dynamic>> submitLoyaltyProgram(String id) async => _data(
    await _request(
      'POST',
      '/loyalty/programs/${Uri.encodeComponent(id)}/submit',
      body: {'commandId': _uuidV4()},
    ),
  );

  Future<Map<String, dynamic>> decideLoyaltyProgram(
    String id,
    String decision, {
    String? reason,
  }) async => _data(
    await _request(
      'POST',
      '/loyalty/programs/${Uri.encodeComponent(id)}/decision',
      body: {
        'commandId': _uuidV4(),
        'decision': decision,
        if (reason != null) 'reason': reason.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> retireLoyaltyProgram(String id) async => _data(
    await _request(
      'POST',
      '/loyalty/programs/${Uri.encodeComponent(id)}/retire',
      body: {'commandId': _uuidV4()},
    ),
  );

  Future<Map<String, dynamic>> operationalAssetsSummary(String branchId) async =>
      _data(await _request('GET', '/branches/' + Uri.encodeComponent(branchId) + '/operational-assets/summary'));

  Future<List<Map<String, dynamic>>> operationalAssets(String branchId, {String? status, String? assetType, String? query, String? cursor, int limit = 50}) async {
    final params = <String, String>{'limit': limit.toString()};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (assetType != null && assetType.isNotEmpty) params['assetType'] = assetType;
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (cursor != null && cursor.isNotEmpty) params['cursor'] = cursor;
    final payload = await _request('GET', '/branches/' + Uri.encodeComponent(branchId) + '/operational-assets?' + Uri(queryParameters: params).query);
    return (payload['data'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<Map<String, dynamic>> operationalAssetDetail(String branchId, String assetId) async =>
      _data(await _request('GET', '/branches/' + Uri.encodeComponent(branchId) + '/operational-assets/' + Uri.encodeComponent(assetId)));

  Future<Map<String, dynamic>> createOperationalAsset(String branchId, Map<String, dynamic> values) async =>
      _data(await _request('POST', '/branches/' + Uri.encodeComponent(branchId) + '/operational-assets', body: {'commandId': _uuidV4(), ...values}));

  Future<Map<String, dynamic>> updateOperationalAsset(String branchId, String assetId, {required int expectedVersion, required Map<String, dynamic> values}) async =>
      _data(await _request('POST', '/branches/' + Uri.encodeComponent(branchId) + '/operational-assets/' + Uri.encodeComponent(assetId) + '/profile', body: {'commandId': _uuidV4(), 'expectedVersion': expectedVersion, ...values}));

  Future<Map<String, dynamic>> assignOperationalAsset(String branchId, String assetId, {required int expectedVersion, String? custodianEmployeeId, required String note}) async =>
      _data(await _request('POST', '/branches/' + Uri.encodeComponent(branchId) + '/operational-assets/' + Uri.encodeComponent(assetId) + '/assignment', body: {'commandId': _uuidV4(), 'expectedVersion': expectedVersion, 'custodianEmployeeId': custodianEmployeeId, 'note': note.trim()}));

  Future<Map<String, dynamic>> changeOperationalAssetStatus(String branchId, String assetId, {required int expectedVersion, required String status, required String note}) async =>
      _data(await _request('POST', '/branches/' + Uri.encodeComponent(branchId) + '/operational-assets/' + Uri.encodeComponent(assetId) + '/status', body: {'commandId': _uuidV4(), 'expectedVersion': expectedVersion, 'status': status, 'note': note.trim()}));

  Future<Map<String, dynamic>> transferOperationalAsset(String branchId, String assetId, {required int expectedVersion, required String targetBranchId, required String note}) async =>
      _data(await _request('POST', '/branches/' + Uri.encodeComponent(branchId) + '/operational-assets/' + Uri.encodeComponent(assetId) + '/transfer', body: {'commandId': _uuidV4(), 'expectedVersion': expectedVersion, 'targetBranchId': targetBranchId, 'note': note.trim()}));

  Future<List<Map<String, dynamic>>> maintenanceAssets(String branchId) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/maintenance/assets',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> maintenanceOrders(String branchId) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/maintenance/orders?limit=100',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createMaintenanceOrder(
    String branchId, {
    required String assetProfileId,
    required String kind,
    required String dueKey,
    required String description,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/maintenance/orders',
      body: {
        'assetProfileId': assetProfileId,
        'kind': kind,
        'dueKey': dueKey,
        'description': description.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> advanceMaintenanceOrder(
    String branchId,
    String orderId,
    int version,
    String nextStatus, {
    String? diagnosis,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/maintenance/orders/${Uri.encodeComponent(orderId)}/transition',
      body: {
        'expectedVersion': version,
        'nextStatus': nextStatus,
        if (diagnosis != null) 'diagnosis': diagnosis.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> addMaintenanceTask(
    String branchId,
    String orderId, {
    required String description,
    required String result,
    int? laborMinutes,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/maintenance/orders/${Uri.encodeComponent(orderId)}/tasks',
      body: {
        'description': description.trim(),
        'result': result.trim(),
        if (laborMinutes != null) 'laborMinutes': laborMinutes,
      },
    ),
  );

  Future<List<Map<String, dynamic>>> suppliers() async {
    final payload = await _request('GET', '/suppliers?limit=100');
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createSupplier({
    required String legalName,
    required String fuelProductId,
  }) async => _data(
    await _request(
      'POST',
      '/suppliers',
      body: {
        'legalName': legalName.trim(),
        'offers': [
          {'fuelProductId': fuelProductId},
        ],
      },
    ),
  );

  Future<List<Map<String, dynamic>>> purchaseOrders(String branchId) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/purchase-orders?limit=100',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createPurchaseOrder(
    String branchId, {
    required String supplierId,
    required String orderNumber,
    required String fuelProductId,
    required String quantity,
    required String unitPrice,
    required String tankId,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/purchase-orders',
      body: {
        'supplierId': supplierId,
        'orderNumber': orderNumber,
        'lines': [
          {
            'fuelProductId': fuelProductId,
            'quantity': quantity,
            'unit': 'liter',
            'agreedUnitPriceUsd': unitPrice,
            'tankId': tankId,
          },
        ],
      },
    ),
  );

  Future<Map<String, dynamic>> purchaseOrderCommand(
    String branchId,
    String orderId,
    String action,
    int expectedVersion, {
    String? reason,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/purchase-orders/${Uri.encodeComponent(orderId)}/$action',
      body: {
        'expectedVersion': expectedVersion,
        if (reason != null) 'reason': reason,
      },
    ),
  );

  Future<Map<String, dynamic>> receivePurchaseOrder(
    String branchId,
    String orderId, {
    required String lineId,
    required String tankId,
    required String quantity,
    required String supplierDeliveryReference,
    required String documentReference,
    required String totalCostUsd,
  }) async {
    final path =
        '/branches/${Uri.encodeComponent(branchId)}/purchase-orders/${Uri.encodeComponent(orderId)}/receipts';
    final body = <String, dynamic>{
      'purchaseOrderLineId': lineId,
      'tankId': tankId,
      'supplierDeliveryReference': supplierDeliveryReference.trim(),
      'documentReference': documentReference.trim(),
      'inventory': {
        'quantity': quantity,
        'unit': 'liter',
        'volumeBasis': 'observed',
        'totalCostUsd': totalCostUsd,
        'reasonCode': 'purchase_receipt',
        'reason': 'Recepción de compra física',
        'documentReference': documentReference.trim(),
      },
    };
    return _data(
      await _durableCommand(
        'purchase-receipt-$branchId-$orderId-$lineId',
        path,
        body,
        commandField: 'inventory.commandId',
      ),
    );
  }

  Future<List<Map<String, dynamic>>> refundSales(
    String branchId,
    String query,
  ) async {
    final payload = await _request(
      'GET',
      '/branches/$branchId/sales?limit=100&q=${Uri.encodeQueryComponent(query)}',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>> pointRefunds(
    String branchId,
    String saleId,
  ) async => _data(
    await _request('GET', '/branches/$branchId/sales/$saleId/point-refunds'),
  );
  Future<Map<String, dynamic>> pointRefundCommand(
    String branchId,
    String saleId,
    bool decision,
    Map<String, dynamic> body,
  ) async => _data(
    await _durableCommand(
      'point-refund-$branchId-$saleId-${decision ? 'decision' : 'request'}-${body[decision ? 'requestId' : 'paymentId']}',
      '/branches/$branchId/sales/$saleId/point-refunds/${decision ? 'decisions' : 'requests'}',
      body,
    ),
  );
  Future<Map<String, dynamic>> contaminationPreview(
    String branchId,
    String tankId,
  ) async => _data(
    await _request(
      'GET',
      '/branches/$branchId/tanks/$tankId/contamination-preview',
    ),
  );
  Future<Map<String, dynamic>> reportContamination(
    String branchId,
    String orderId,
    Map<String, dynamic> body,
  ) async => _data(
    await _durableCommand(
      'contamination-$branchId-$orderId-${body['purchaseOrderLineId']}',
      '/branches/$branchId/purchase-orders/$orderId/contaminations',
      body,
    ),
  );
  Future<Map<String, dynamic>> resolveContamination(
    String branchId,
    String id,
    String action,
    Map<String, dynamic> body,
  ) async => _data(
    await _durableCommand(
      'contamination-$action-$branchId-$id',
      '/branches/$branchId/contaminations/$id/$action',
      body,
    ),
  );
  Future<List<Map<String, dynamic>>> contaminatedDeliveries(
    String branchId,
    String orderId,
  ) async {
    final payload = await _request(
      'GET',
      '/branches/$branchId/purchase-orders/$orderId/contaminations',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> cashRegisters(String branchId) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/cash/registers',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createCashRegister(
    String branchId,
    String code,
  ) async => _data(
    await _durableCommand(
      'cash-register-$branchId-${code.trim().toUpperCase()}',
      '/branches/${Uri.encodeComponent(branchId)}/cash/registers',
      {'code': code.trim().toUpperCase()},
    ),
  );

  Future<Map<String, dynamic>> openCashSession(
    String branchId,
    String registerId,
    String openingUsd,
  ) async => _data(
    await _durableCommand(
      'cash-open-$branchId-$registerId',
      '/branches/${Uri.encodeComponent(branchId)}/cash/sessions',
      {'registerId': registerId, 'openingUsd': openingUsd.trim()},
    ),
  );

  Future<Map<String, dynamic>> cashSession(
    String branchId,
    String sessionId,
  ) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/cash/sessions/${Uri.encodeComponent(sessionId)}',
    ),
  );

  Future<List<Map<String, dynamic>>> cashMovements(
    String branchId,
    String sessionId,
  ) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/cash/sessions/${Uri.encodeComponent(sessionId)}/movements?limit=100',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> cashMovement(
    String branchId,
    String sessionId,
    String kind,
    String amount,
    String reason,
  ) async => _data(
    await _durableCommand(
      'cash-movement-$branchId-$sessionId-$kind',
      '/branches/${Uri.encodeComponent(branchId)}/cash/sessions/${Uri.encodeComponent(sessionId)}/movements',
      {'kind': kind, 'amountUsd': amount.trim(), 'reason': reason.trim()},
    ),
  );

  Future<Map<String, dynamic>> closeCashSession(
    String branchId,
    String sessionId,
    String countedCashUsd,
    String settledCardUsd,
    String reason,
  ) async => _data(
    await _durableCommand(
      'cash-close-$branchId-$sessionId',
      '/branches/${Uri.encodeComponent(branchId)}/cash/sessions/${Uri.encodeComponent(sessionId)}/close',
      {
        'countedCashUsd': countedCashUsd.trim(),
        'settledCardUsd': settledCardUsd.trim(),
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    ),
  );

  Future<List<Map<String, dynamic>>> posCatalog(
    String branchId, {
    String query = '',
  }) async {
    final suffix = query.trim().isEmpty
        ? ''
        : '?q=${Uri.encodeQueryComponent(query.trim())}';
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/pos/catalog$suffix',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createPosSale(
    String branchId,
    List<Map<String, String>> items, {
    String? customerCode,
  }) async {
    if (items.isEmpty || items.length > 50)
      throw const DlcApiException(
        'Agrega productos antes de guardar la venta.',
      );
    final normalizedItems = items
        .map(
          (item) => <String, dynamic>{
            'productId': item['productId'],
            'offerVersionId': item['offerVersionId'],
            'quantity': item['quantity'],
          },
        )
        .toList(growable: false);
    final fingerprint = jsonEncode(normalizedItems);
    final pending = await _readPendingPosSale(branchId);
    final commandId =
        pending?['fingerprint'] == fingerprint &&
            pending?['commandId'] is String
        ? pending!['commandId'] as String
        : _uuidV4();
    await _writePendingPosSale(branchId, {
      'fingerprint': fingerprint,
      'commandId': commandId,
      'items': normalizedItems,
      if (customerCode?.trim().isNotEmpty == true)
        'customerCode': customerCode!.trim(),
      if (pending?['fingerprint'] == fingerprint && pending?['sale'] is Map)
        'sale': pending!['sale'],
      if (pending?['fingerprint'] == fingerprint && pending?['payment'] is Map)
        'payment': pending!['payment'],
    });
    final result = _data(
      await _request(
        'POST',
        '/branches/${Uri.encodeComponent(branchId)}/sales/pos',
        body: {'commandId': commandId, 'items': normalizedItems},
      ),
    );
    final sale = await result;
    await _writePendingPosSale(branchId, {
      'fingerprint': fingerprint,
      'commandId': commandId,
      'items': normalizedItems,
      'sale': sale,
      if (customerCode?.trim().isNotEmpty == true)
        'customerCode': customerCode!.trim(),
      if (pending?['fingerprint'] == fingerprint && pending?['payment'] is Map)
        'payment': pending!['payment'],
    });
    return sale;
  }

  Future<Map<String, dynamic>> linkCustomerToSale(
    String branchId,
    String saleId,
    String customerCode,
  ) async {
    final pending = await _readPendingPosSale(branchId);
    final result = await _data(
      await _durableCommand(
        'customer-link-$branchId-$saleId',
        '/branches/${Uri.encodeComponent(branchId)}/sales/${Uri.encodeComponent(saleId)}/customer',
        {'customerCode': customerCode.trim()},
      ),
    );
    if (pending != null &&
        _string((pending['sale'] as Map?)?['id']) == saleId) {
      await _writePendingPosSale(branchId, {
        ...pending,
        'customerCode': customerCode.trim(),
        'customerLinked': true,
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> requestPointPaymentQuote(
    String branchId,
    String saleId,
    String sessionId,
    int points,
  ) async {
    if (points < 1 || points > 2000000000)
      throw const DlcApiException('La cantidad de puntos no es válida.');
    final body = {'cashSessionId': sessionId, 'points': points};
    return _data(
      await _durableCommand(
        'point-payment-quote-$branchId-$saleId',
        '/branches/${Uri.encodeComponent(branchId)}/sales/${Uri.encodeComponent(saleId)}/customer/points/quotes',
        body,
      ),
    );
  }

  Future<Map<String, dynamic>> saleDetail(
    String branchId,
    String saleId,
  ) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/sales/${Uri.encodeComponent(saleId)}',
    ),
  );

  Future<Map<String, dynamic>> collectPayment(
    String branchId, {
    required String saleId,
    required String sessionId,
    required String method,
    required String amountUsd,
    required String outcome,
    String? evidenceReference,
  }) async {
    final body = <String, dynamic>{
      'saleId': saleId,
      'cashSessionId': sessionId,
      'method': method,
      'mode': 'manual',
      'amountUsd': amountUsd.trim(),
      'outcome': outcome,
      if (evidenceReference != null && evidenceReference.trim().isNotEmpty)
        'evidenceReference': evidenceReference.trim(),
    };
    final pending = await _readPendingPosSale(branchId);
    if (pending == null || _string((pending['sale'] as Map?)?['id']) != saleId)
      throw const DlcApiException(
        'No se encontró el contexto guardado de esta venta.',
      );
    final existing = pending['payment'] is Map
        ? Map<String, dynamic>.from(pending['payment'] as Map)
        : <String, dynamic>{};
    final fingerprint = jsonEncode(body);
    final commandId =
        existing['fingerprint'] == fingerprint &&
            existing['commandId'] is String
        ? existing['commandId'] as String
        : _uuidV4();
    await _writePendingPosSale(branchId, {
      ...pending,
      'payment': {
        'fingerprint': fingerprint,
        'commandId': commandId,
        'body': body,
        'status': 'sending',
      },
    });
    final response = await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/payments',
      body: {'commandId': commandId, ...body},
    );
    final result = await _data(response);
    await _writePendingPosSale(branchId, {
      ...pending,
      'payment': {
        'fingerprint': fingerprint,
        'commandId': commandId,
        'body': body,
        'status': outcome == 'confirmed' ? 'paid' : outcome,
        'attemptId': result['id'],
      },
    });
    return result;
  }

  Future<Map<String, dynamic>> resolvePayment(
    String branchId,
    String attemptId,
    String outcome,
    String evidenceReference,
  ) async {
    final pending = await _readPendingPosSale(branchId);
    if (pending == null)
      throw const DlcApiException(
        'No se encontró la venta pendiente de conciliación.',
      );
    final body = {
      'outcome': outcome,
      'evidenceReference': evidenceReference.trim(),
    };
    final fingerprint = jsonEncode(body);
    final old = pending['resolution'] is Map
        ? Map<String, dynamic>.from(pending['resolution'] as Map)
        : <String, dynamic>{};
    final commandId =
        old['fingerprint'] == fingerprint && old['commandId'] is String
        ? old['commandId'] as String
        : _uuidV4();
    await _writePendingPosSale(branchId, {
      ...pending,
      'resolution': {
        'fingerprint': fingerprint,
        'commandId': commandId,
        'body': body,
        'status': 'sending',
      },
    });
    final response = await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/payments/${Uri.encodeComponent(attemptId)}/resolve',
      body: {'commandId': commandId, ...body},
    );
    final result = await _data(response);
    await _writePendingPosSale(branchId, {
      ...pending,
      'resolution': {
        'fingerprint': fingerprint,
        'commandId': commandId,
        'body': body,
        'status': outcome,
      },
      'payment': {
        ...Map<String, dynamic>.from(pending['payment'] as Map),
        'status': outcome == 'confirmed' ? 'paid' : 'declined',
      },
    });
    return result;
  }

  Future<Map<String, dynamic>> retryPendingPayment(String branchId) async {
    final pending = await _readPendingPosSale(branchId);
    final payment = pending?['payment'] is Map
        ? Map<String, dynamic>.from(pending!['payment'] as Map)
        : null;
    if (pending == null ||
        payment == null ||
        payment['status'] != 'sending' ||
        payment['body'] is! Map) {
      throw const DlcApiException(
        'No hay un cobro incierto listo para reintentar.',
      );
    }
    final body = Map<String, dynamic>.from(payment['body'] as Map);
    final response = await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/payments',
      body: {'commandId': payment['commandId'], ...body},
    );
    final result = await _data(response);
    final outcome = _string(body['outcome']);
    await _writePendingPosSale(branchId, {
      ...pending,
      'payment': {
        ...payment,
        'status': outcome == 'confirmed' ? 'paid' : outcome,
        'attemptId': result['id'],
      },
    });
    return result;
  }

  Future<Map<String, dynamic>> retryPendingResolution(String branchId) async {
    final pending = await _readPendingPosSale(branchId);
    final resolution = pending?['resolution'] is Map
        ? Map<String, dynamic>.from(pending!['resolution'] as Map)
        : null;
    final payment = pending?['payment'] is Map
        ? Map<String, dynamic>.from(pending!['payment'] as Map)
        : null;
    if (pending == null ||
        resolution == null ||
        resolution['status'] != 'sending' ||
        resolution['body'] is! Map ||
        payment?['attemptId'] is! String) {
      throw const DlcApiException(
        'No hay una conciliación incierta lista para reintentar.',
      );
    }
    final body = Map<String, dynamic>.from(resolution['body'] as Map);
    final response = await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/payments/${Uri.encodeComponent(payment!['attemptId'] as String)}/resolve',
      body: {'commandId': resolution['commandId'], ...body},
    );
    final result = await _data(response);
    final outcome = _string(body['outcome']);
    await _writePendingPosSale(branchId, {
      ...pending,
      'resolution': {...resolution, 'status': outcome},
      'payment': {
        ...payment,
        'status': outcome == 'confirmed' ? 'paid' : 'declined',
      },
    });
    return result;
  }

  Future<Map<String, dynamic>?> pendingPosSale(String branchId) =>
      _readPendingPosSale(branchId);
  Future<void> completePosSale(String branchId) =>
      _storage.delete(key: _pendingPosSaleKey(branchId));

  String _pendingPosSaleKey(String branchId) {
    final scope = _sessionId ?? 'signed-out';
    return 'operations.pending.pos-sale.$scope.$branchId';
  }

  Future<Map<String, dynamic>?> _readPendingPosSale(String branchId) async {
    final value = await _storage.read(key: _pendingPosSaleKey(branchId));
    if (value == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _writePendingPosSale(
    String branchId,
    Map<String, dynamic> value,
  ) => _storage.write(
    key: _pendingPosSaleKey(branchId),
    value: jsonEncode(value),
  );

  Future<Map<String, dynamic>> _durableCommand(
    String key,
    String path,
    Map<String, dynamic> body, {
    String commandField = 'commandId',
  }) async {
    final storageKey = 'operations.command.$key';
    final fingerprint = jsonEncode(body);
    var commandId = _uuidV4();
    final storedText = await _storage.read(key: storageKey);
    if (storedText != null) {
      try {
        final stored = jsonDecode(storedText) as Map<String, dynamic>;
        if (stored['fingerprint'] == fingerprint &&
            stored['commandId'] is String) {
          commandId = stored['commandId'] as String;
        }
      } on FormatException {}
    }
    final fieldPath = commandField.split('.');
    if (fieldPath.length == 1) {
      body[commandField] = commandId;
    } else {
      final parent = Map<String, dynamic>.from(body[fieldPath.first] as Map);
      parent[fieldPath.last] = commandId;
      body[fieldPath.first] = parent;
    }
    await _storage.write(
      key: storageKey,
      value: jsonEncode({'commandId': commandId, 'fingerprint': fingerprint}),
    );
    try {
      final result = await _request('POST', path, body: body);
      await _storage.delete(key: storageKey);
      return result;
    } on DlcApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500)
        await _storage.delete(key: storageKey);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> branchDashboard(String branchId) async {
    final payload = await _request(
      'GET',
      '/metrics/branches/${Uri.encodeComponent(branchId)}/dashboard',
    );
    return Map<String, dynamic>.from(payload['data'] as Map? ?? const {});
  }

  Future<List<Map<String, dynamic>>> dispensers(String branchId) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/dispensers?limit=100',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> branchConfiguration(String branchId) async =>
      _data(
        await _request(
          'GET',
          '/branches/${Uri.encodeComponent(branchId)}/configuration',
        ),
      );

  Future<List<Map<String, dynamic>>> fuelProducts({String? branchId}) async {
    final query = <String, String>{'status': 'active', 'limit': '100'};
    if (branchId != null) query['branchId'] = branchId;
    final payload = await _request(
      'GET',
      '/fuel-products?${Uri(queryParameters: query).query}',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> activateFuelOffer(
    String branchId,
    String fuelProductId,
  ) async => _data(
    await _request(
      'PUT',
      '/branches/${Uri.encodeComponent(branchId)}/fuel-offers/${Uri.encodeComponent(fuelProductId)}',
    ),
  );

  Future<Map<String, dynamic>> createTank(
    String branchId, {
    required String code,
    required String name,
    required String fuelProductId,
    required String nominalCapacityL,
    required String safeFillLimitL,
    required String unusableReserveL,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/tanks',
      body: {
        'code': code.trim(),
        'name': name.trim(),
        'fuelProductId': fuelProductId,
        'nominalCapacityL': nominalCapacityL,
        'safeFillLimitL': safeFillLimitL,
        'unusableReserveL': unusableReserveL,
      },
    ),
  );

  Future<Map<String, dynamic>> createDispenser(
    String branchId, {
    required String code,
    String? name,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/dispensers',
      body: {
        'code': code.trim(),
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> createNozzle(
    String branchId,
    String dispenserId, {
    required String code,
    required String productCode,
    required String fuelProductId,
    required String serviceMode,
    required String meterUnit,
    required int meterPrecision,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/dispensers/${Uri.encodeComponent(dispenserId)}/nozzles',
      body: {
        'code': code.trim(),
        'productCode': productCode.trim(),
        'fuelProductId': fuelProductId,
        'serviceMode': serviceMode,
        'meterUnit': meterUnit,
        'meterPrecision': meterPrecision,
      },
    ),
  );

  Future<Map<String, dynamic>> connectNozzle(
    String branchId,
    String nozzleId,
    String tankId,
    String reason,
  ) async => _data(
    await _request(
      'PUT',
      '/branches/${Uri.encodeComponent(branchId)}/nozzles/${Uri.encodeComponent(nozzleId)}/tank-connection',
      body: {'tankId': tankId, 'reason': reason.trim()},
    ),
  );

  Future<Map<String, dynamic>> openTankInventory(
    String branchId,
    String tankId, {
    required String quantity,
    required String valuationQuality,
    String? reason,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/tanks/${Uri.encodeComponent(tankId)}/inventory/opening',
      body: {
        'commandId': _uuidV4(),
        'quantity': quantity,
        'unit': 'liter',
        'volumeBasis': 'observed',
        'valuationQuality': valuationQuality,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> tankInventory(
    String branchId,
    String tankId,
  ) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/tanks/${Uri.encodeComponent(tankId)}/inventory',
    ),
  );

  Future<List<Map<String, dynamic>>> staffEmployees(String branchId) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/staff/employees?status=active&limit=100',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createStaffEmployee(
    String branchId, {
    required String employeeCode,
    required String legalName,
    required String positionTitle,
    String? contactEmail,
  }) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/staff/employees',
      body: {
        'employeeCode': employeeCode.trim(),
        'legalName': legalName.trim(),
        'positionTitle': positionTitle.trim(),
        if (contactEmail != null && contactEmail.trim().isNotEmpty)
          'contactEmail': contactEmail.trim(),
      },
    ),
  );

  Future<List<Map<String, dynamic>>> staffShifts(
    String branchId,
    DateTime from,
    DateTime to,
  ) async {
    final query = Uri(
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    ).query;
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/staff/shifts?$query',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> scheduleStaffShift(
    String branchId, {
    required String employeeId,
    required String position,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    if (!endsAt.isAfter(startsAt) ||
        endsAt.difference(startsAt) > const Duration(hours: 24)) {
      throw const DlcApiException(
        'El turno debe terminar después de iniciar y durar máximo 24 horas.',
      );
    }
    return _data(
      await _request(
        'POST',
        '/branches/${Uri.encodeComponent(branchId)}/staff/shifts',
        body: {
          'commandId': _uuidV4(),
          'employeeId': employeeId,
          'position': position,
          'startsAt': startsAt.toUtc().toIso8601String(),
          'endsAt': endsAt.toUtc().toIso8601String(),
        },
      ),
    );
  }

  Future<Map<String, dynamic>> cancelStaffShift(
    String branchId,
    String shiftId,
    String reason,
  ) async {
    if (reason.trim().length < 10 || reason.trim().length > 500)
      throw const DlcApiException(
        'Explica la cancelación con 10 a 500 caracteres.',
      );
    return _data(
      await _request(
        'POST',
        '/branches/${Uri.encodeComponent(branchId)}/staff/shifts/${Uri.encodeComponent(shiftId)}/cancel',
        body: {'commandId': _uuidV4(), 'reason': reason.trim()},
      ),
    );
  }

  Future<Map<String, dynamic>> recordStaffAttendance(
    String branchId,
    String shiftId,
    String kind,
  ) async {
    if (!['clock_in', 'clock_out'].contains(kind))
      throw const DlcApiException('Tipo de marcación no válido.');
    return _data(
      await _request(
        'POST',
        '/branches/${Uri.encodeComponent(branchId)}/staff/shifts/${Uri.encodeComponent(shiftId)}/attendance',
        body: {
          'commandId': _uuidV4(),
          'kind': kind,
          'occurredAt': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );
  }

  Future<Map<String, dynamic>> dispenser(
    String branchId,
    String dispenserId,
  ) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/dispensers/${Uri.encodeComponent(dispenserId)}',
    );
    final data = payload['data'];
    return Map<String, dynamic>.from(data as Map? ?? payload);
  }

  Future<List<Map<String, dynamic>>> dispenseAuthorizations(
    String branchId, {
    String? status,
  }) async {
    final query = Uri(
      queryParameters: {'limit': '100', if (status != null) 'status': status},
    ).query;
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/dispense-authorizations?$query',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> dispenseDetail(
    String branchId,
    String authorizationId,
  ) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/dispense-authorizations/${Uri.encodeComponent(authorizationId)}',
    ),
  );

  Future<Map<String, dynamic>> authorizeDispense(
    String branchId,
    String nozzleId,
    String value, {
    String mode = 'volume',
    String volumeUnit = 'liter',
  }) async {
    if (!['volume', 'amount'].contains(mode) ||
        !['liter', 'gallon_us'].contains(volumeUnit)) {
      throw const DlcApiException(
        'La cantidad o unidad del despacho no es válida.',
      );
    }
    final path =
        '/branches/${Uri.encodeComponent(branchId)}/nozzles/${Uri.encodeComponent(nozzleId)}/dispense-authorizations';
    return _data(
      await _durableCommand('dispense-authorize-$branchId-$nozzleId', path, {
        if (mode == 'amount') 'requestedAmountUsd': value.trim(),
        if (mode == 'volume') 'requestedVolume': value.trim(),
        if (mode == 'volume') 'volumeUnit': volumeUnit,
      }),
    );
  }

  Future<Map<String, dynamic>> startDispense(
    String branchId,
    String authorizationId,
    int version, {
    String? reason,
  }) async => _data(
    await _durableCommand(
      'dispense-start-$authorizationId',
      '/branches/${Uri.encodeComponent(branchId)}/dispense-authorizations/${Uri.encodeComponent(authorizationId)}/start',
      {
        'expectedVersion': version,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> completeDispense(
    String branchId,
    String authorizationId,
    int version,
    String liters, {
    String? documentReference,
  }) async => _data(
    await _durableCommand(
      'dispense-complete-$authorizationId',
      '/branches/${Uri.encodeComponent(branchId)}/dispense-authorizations/${Uri.encodeComponent(authorizationId)}/complete',
      {
        'quantity': liters.trim(),
        'unit': 'liter',
        'expectedVersion': version,
        if (documentReference != null && documentReference.trim().isNotEmpty)
          'documentReference': documentReference.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> createSaleFromDispatch(
    String branchId,
    String authorizationId,
  ) async => _data(
    await _durableCommand(
      'sale-from-dispatch-$authorizationId',
      '/branches/${Uri.encodeComponent(branchId)}/sales/from-dispatch',
      {'authorizationId': authorizationId},
    ),
  );

  Future<Map<String, dynamic>> createIncident({
    required String branchId,
    required String assetId,
    required String description,
    required String severity,
    String category = 'equipment_damage',
    String assetType = 'dispenser',
  }) async {
    if (description.trim().length < 12 || description.trim().length > 2000) {
      throw const DlcApiException(
        'Describe el problema con al menos 12 caracteres.',
      );
    }
    final payload = await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/incidents',
      body: {
        'commandId': _uuidV4(),
        'category': category,
        'severity': severity,
        'assetType': assetType,
        'assetId': assetId,
        'description': description.trim(),
        'occurredAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(payload['data'] as Map? ?? payload);
  }

  Future<List<Map<String, dynamic>>> incidents(
    String branchId, {
    String? status,
    String? query,
  }) async {
    final params = <String, String>{'limit': '50'};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/incidents?${Uri(queryParameters: params).query}',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> incident(
    String branchId,
    String incidentId,
  ) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/incidents/${Uri.encodeComponent(incidentId)}',
    ),
  );

  Future<Map<String, dynamic>> transitionIncident(
    String branchId,
    String incidentId,
    int version,
    String nextStatus,
    String note,
  ) async {
    if (note.trim().length < 5 || note.trim().length > 1000)
      throw const DlcApiException(
        'La nota debe tener entre 5 y 1000 caracteres.',
      );
    return _data(
      await _request(
        'POST',
        '/branches/${Uri.encodeComponent(branchId)}/incidents/${Uri.encodeComponent(incidentId)}/transition',
        body: {
          'expectedVersion': version,
          'nextStatus': nextStatus,
          'note': note.trim(),
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> dailyCuts(
    String branchId,
    DateTime date,
  ) async {
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/cuts?date=$day',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> generateDailyCuts(
    String branchId,
    DateTime date,
  ) async {
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final payload = await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/generate',
      body: {'operationalDate': day},
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> openCut(
    String branchId,
    String cutId,
    int version,
  ) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/${Uri.encodeComponent(cutId)}/open',
      body: {'expectedVersion': version},
    ),
  );

  Future<Map<String, dynamic>> cutAssets(
    String branchId,
    String cutId,
  ) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/${Uri.encodeComponent(cutId)}/assets',
    ),
  );

  Future<Map<String, dynamic>> captureReading(
    String branchId,
    String nozzleId,
    String value,
    int version,
  ) async {
    if (!RegExp(r'^(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$').hasMatch(value)) {
      throw const DlcApiException(
        'La lectura debe ser un totalizador válido, sin separadores de miles.',
      );
    }
    return _data(
      await _request(
        'POST',
        '/branches/${Uri.encodeComponent(branchId)}/nozzles/${Uri.encodeComponent(nozzleId)}/meter-readings',
        body: {
          'commandId': _uuidV4(),
          'value': value,
          'source': 'manual',
          'expectedVersion': version,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> captureBaseline(
    String branchId,
    String nozzleId,
    String value, {
    String? serial,
    String? note,
  }) async {
    if (!RegExp(r'^(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$').hasMatch(value)) {
      throw const DlcApiException(
        'La línea base debe ser un totalizador válido.',
      );
    }
    return _data(
      await _request(
        'POST',
        '/branches/${Uri.encodeComponent(branchId)}/nozzles/${Uri.encodeComponent(nozzleId)}/meter-readings/baseline',
        body: {
          'commandId': _uuidV4(),
          'value': value,
          'source': 'manual',
          'expectedVersion': 0,
          if (serial != null && serial.trim().isNotEmpty)
            'meterSerial': serial.trim(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      ),
    );
  }

  Future<void> attachCutMeter(
    String branchId,
    String cutId,
    String nozzleId,
    String readingId,
    int version,
  ) async {
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/${Uri.encodeComponent(cutId)}/meters',
      body: {
        'nozzleId': nozzleId,
        'readingId': readingId,
        'expectedVersion': version,
      },
    );
  }

  Future<void> captureTankMeasure(
    String branchId,
    String cutId,
    String tankId,
    int version,
    String liters,
    String waterLiters,
    String temperatureC,
  ) async {
    final decimal = RegExp(r'^(0|[1-9]\d{0,8})(\.\d{1,9})?$');
    if (!decimal.hasMatch(liters) ||
        waterLiters.isNotEmpty && !decimal.hasMatch(waterLiters) ||
        temperatureC.isNotEmpty &&
            !RegExp(r'^-?\d{1,3}(\.\d{1,4})?$').hasMatch(temperatureC)) {
      throw const DlcApiException(
        'Revisa litros, agua y temperatura. Usa punto decimal y valores válidos.',
      );
    }
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/${Uri.encodeComponent(cutId)}/tanks',
      body: {
        'tankId': tankId,
        'expectedVersion': version,
        'measuredL': liters,
        if (waterLiters.isNotEmpty) 'waterL': waterLiters,
        if (temperatureC.isNotEmpty) 'temperatureC': temperatureC,
        'observedAt': DateTime.now().toUtc().toIso8601String(),
        'source': 'manual',
      },
    );
  }

  Future<Map<String, dynamic>> cutProgress(
    String branchId,
    String cutId,
  ) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/${Uri.encodeComponent(cutId)}/progress',
    ),
  );

  Future<Map<String, dynamic>> prepareCut(
    String branchId,
    String cutId,
    int version,
  ) async => _data(
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/${Uri.encodeComponent(cutId)}/prepare',
      body: {'expectedVersion': version},
    ),
  );

  Future<Map<String, dynamic>> cutReconciliation(
    String branchId,
    String cutId,
  ) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/${Uri.encodeComponent(cutId)}/reconciliation',
    ),
  );

  Future<void> reviewCut(
    String branchId,
    String cutId,
    int version,
    String reason,
  ) async {
    if (reason.trim().length < 8 || reason.trim().length > 500) {
      throw const DlcApiException(
        'Indica un motivo de revisión de 8 a 500 caracteres.',
      );
    }
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/${Uri.encodeComponent(cutId)}/review',
      body: {'expectedVersion': version, 'reason': reason.trim()},
    );
  }

  Future<void> closeCut(String branchId, String cutId, int version) async {
    await _request(
      'POST',
      '/branches/${Uri.encodeComponent(branchId)}/cuts/${Uri.encodeComponent(cutId)}/close',
      body: {'expectedVersion': version},
    );
  }

  Future<Map<String, dynamic>> _data(Map<String, dynamic> payload) =>
      Future.value(
        Map<String, dynamic>.from(payload['data'] as Map? ?? payload),
      );

  Future<List<Map<String, dynamic>>> reportRuns(String branchId) async {
    final payload = await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/reports/runs',
    );
    return (payload['data'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String newCommandId() => _uuidV4();

  Future<Map<String, dynamic>> createReport(
    String branchId,
    String type,
    DateTime from,
    DateTime to, {
    String? commandId,
  }) async {
    if (to.isBefore(from))
      throw const DlcApiException(
        'El fin del período debe ser igual o posterior al inicio.',
      );
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return _data(
      await _request(
        'POST',
        '/branches/${Uri.encodeComponent(branchId)}/reports/runs',
        body: {
          'type': type,
          'from': day(from),
          'to': day(to),
          'commandId': commandId ?? _uuidV4(),
          if (type == 'fuel_sales') 'groupBy': 'day',
        },
      ),
    );
  }

  Future<Map<String, dynamic>> reportPage(
    String branchId,
    String runId, {
    int offset = 0,
  }) async => _data(
    await _request(
      'GET',
      '/branches/${Uri.encodeComponent(branchId)}/reports/runs/${Uri.encodeComponent(runId)}?offset=$offset',
    ),
  );

  Future<Uint8List> saleReceiptPdf(String branchId, String saleId) async {
    final base = Uri.parse(_baseUrl);
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final path =
        '/branches/${Uri.encodeComponent(branchId)}/sales/${Uri.encodeComponent(saleId)}/receipt.pdf';
    final uri = base.replace(path: '$prefix$path');
    final requestId = _uuidV4();
    final response = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/pdf',
            'Authorization': 'Bearer $_accessToken',
            'X-Request-ID': requestId,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DlcApiException(
        'No se pudo descargar el comprobante (HTTP ${response.statusCode}).',
        correlationId: requestId,
      );
    }
    return response.bodyBytes;
  }

  Future<Uint8List> exportReport(
    String branchId,
    String runId, {
    required bool pdf,
  }) async {
    final base = Uri.parse(_baseUrl);
    final path =
        '/branches/${Uri.encodeComponent(branchId)}/reports/runs/${Uri.encodeComponent(runId)}/export.${pdf ? 'pdf' : 'xlsx'}';
    final normalizedBase = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final uri = base.replace(path: '$normalizedBase$path');
    final requestId = _uuidV4();
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': pdf
                  ? 'application/pdf'
                  : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              'Authorization': 'Bearer $_accessToken',
              'X-Request-ID': requestId,
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message =
            'No se pudo exportar el reporte (HTTP ${response.statusCode}).';
        String? code, correlationId;
        try {
          final body = jsonDecode(response.body);
          if (body is Map) {
            final nested = body['error'] is Map ? body['error'] as Map : body;
            message = (nested['message'] ?? message).toString();
            code = nested['code'] as String?;
            correlationId = nested['correlationId'] as String?;
          }
        } on FormatException {}
        correlationId ??= requestId;
        developer.log(
          'Export HTTP ${response.statusCode} GET ${_safeRoute(path)}${code == null ? '' : ' code=$code'} correlationId=$correlationId',
          name: 'dlc.api',
          level: 900,
        );
        throw DlcApiException(
          message,
          code: code,
          correlationId: correlationId,
        );
      }
      return response.bodyBytes;
    } on DlcApiException {
      rethrow;
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Export network failure GET ${_safeRoute(path)} correlationId=$requestId',
        name: 'dlc.api',
        error: error.runtimeType,
        stackTrace: stackTrace,
        level: 1000,
      );
      throw DlcApiException(
        'No se pudo descargar el archivo. Comprueba la conexión e inténtalo de nuevo.',
        correlationId: requestId,
      );
    }
  }

  Future<void> logout() async {
    try {
      await _request('POST', '/auth/logout');
    } finally {
      await clear();
    }
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _sessionId = null;
    await Future.wait([
      _storage.delete(key: 'operations.access'),
      _storage.delete(key: 'operations.refresh'),
      _storage.delete(key: 'operations.session'),
    ]);
  }

  Future<EmployeeIdentity> _identity() async {
    final payload = await _request('GET', '/auth/me');
    return EmployeeIdentity.fromJson(
      Map<String, dynamic>.from(payload['data'] as Map? ?? const {}),
    );
  }

  Future<void> _refresh() async {
    final existing = _refreshing;
    if (existing != null) return existing;
    final completer = _performRefresh();
    _refreshing = completer;
    try {
      await completer;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _performRefresh() async {
    final payload = await _request(
      'POST',
      '/auth/refresh',
      body: {'refreshToken': _refreshToken},
      authenticated: false,
    );
    await _saveToken(payload);
  }

  Future<void> _saveToken(Map<String, dynamic> token) async {
    _accessToken = _string(token['accessToken']);
    _refreshToken = _string(token['refreshToken']);
    _sessionId = _string(token['sessionId']);
    if (_accessToken!.isEmpty ||
        _refreshToken!.isEmpty ||
        _sessionId!.isEmpty) {
      throw const DlcApiException(
        'El servidor devolvió una sesión incompleta.',
      );
    }
    await Future.wait([
      _storage.write(key: 'operations.access', value: _accessToken),
      _storage.write(key: 'operations.refresh', value: _refreshToken),
      _storage.write(key: 'operations.session', value: _sessionId),
    ]);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final base = Uri.parse(_baseUrl);
    final endpoint = Uri.parse(path);
    final normalizedBase = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final uri = base.replace(
      path: '$normalizedBase${endpoint.path}',
      query: endpoint.hasQuery ? endpoint.query : null,
    );
    final requestId = _uuidV4();
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Request-ID': requestId,
    };
    if (body != null) headers['Content-Type'] = 'application/json';
    if (authenticated && (_accessToken ?? '').isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    late http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 18));
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Network failure ${method.toUpperCase()} ${_safeRoute(path)} correlationId=$requestId',
        name: 'dlc.api',
        error: error.runtimeType,
        stackTrace: stackTrace,
        level: 1000,
      );
      throw DlcApiException(
        'No se pudo conectar con el servidor. Revisa la red y la dirección de la API.',
        correlationId: requestId,
      );
    }
    final dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      developer.log(
        'Invalid JSON response ${method.toUpperCase()} ${_safeRoute(path)} HTTP ${response.statusCode} correlationId=$requestId',
        name: 'dlc.api',
        level: 900,
      );
      throw DlcApiException(
        'El servidor respondió con un formato inesperado (HTTP ${response.statusCode}).',
        correlationId: requestId,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded : const {};
      final nested = error['error'] is Map ? error['error'] as Map : error;
      final message = nested['message'];
      final code = nested['code'] as String?;
      final correlationId = nested['correlationId'] as String? ?? requestId;
      developer.log(
        'HTTP ${response.statusCode} ${method.toUpperCase()} ${_safeRoute(path)}${code == null ? '' : ' code=$code'}${correlationId == null ? '' : ' correlationId=$correlationId'}',
        name: 'dlc.api',
        level: 900,
      );
      throw DlcApiException(
        message is String
            ? message
            : 'La solicitud no se completó (HTTP ${response.statusCode}).',
        code: code,
        correlationId: correlationId,
        statusCode: response.statusCode,
      );
    }
    return Map<String, dynamic>.from(decoded as Map? ?? const {});
  }
}

String _string(dynamic value) => value is String ? value : '';

String _safeRoute(String path) => path
    .split('?')
    .first
    .replaceAll(
      RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}',
        caseSensitive: false,
      ),
      ':id',
    );

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
