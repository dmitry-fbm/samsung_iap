import 'dart:async';

import 'package:flutter/services.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'messages.g.dart';
import 'types.dart';

/// `in_app_purchase` platform implementation on top of Samsung IAP SDK 6.5.
///
/// Error convention: non-payment host calls throw [PlatformException] whose
/// code is Samsung's errorCode; payment calls report failure as an [ErrorMsg]
/// inside [PurchaseResultMsg].
class SamsungIapPlatform extends InAppPurchasePlatform {
  SamsungIapPlatform({
    this._mode = SamsungIapMode.production,
    SamsungIapHostApi? api,
    DateTime Function()? now,
  }) : _api = api ?? SamsungIapHostApi(),
       _now = now ?? DateTime.now;

  /// `IAP_PAYMENT_IS_CANCELED` in the SDK's `HelperDefine`.
  static const samsungPaymentCanceled = 1;

  /// `IAP_ERROR_NONE`: success status of acknowledge/consume results.
  static const samsungStatusOk = 0;

  /// [PurchaseVerificationData.source] and [IAPError.source].
  static const source = 'samsung_iap';

  static const _subscription = 'subscription';

  /// Registers a Samsung platform as the `in_app_purchase` implementation.
  static SamsungIapPlatform register({
    SamsungIapMode mode = SamsungIapMode.production,
    SamsungIapHostApi? api,
  }) {
    final platform = SamsungIapPlatform(mode: mode, api: api);
    InAppPurchasePlatform.instance = platform;
    _registerAddition(platform);
    return platform;
  }

  /// Hook for Task 4: set `InAppPurchasePlatformAddition.instance` to the
  /// Samsung addition here. Intentionally empty until the addition exists.
  static void _registerAddition(SamsungIapPlatform platform) {}

  final SamsungIapMode _mode;
  final SamsungIapHostApi _api;
  final DateTime Function() _now;
  final _purchases = StreamController<List<PurchaseDetails>>.broadcast(
    sync: true,
  );
  Future<void>? _modeApplied;

  /// The host API, after the operation mode has been applied. For the
  /// platform addition, which shares this platform's host and mode.
  Future<SamsungIapHostApi> readyHostApi() async {
    final applied = _modeApplied ??= _api
        .setOperationMode(_mode.wire)
        .catchError((Object e, StackTrace s) {
          _modeApplied = null; // let the next call retry
          Error.throwWithStackTrace(e, s);
        });
    await applied;
    return _api;
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _purchases.stream;

  @override
  Future<bool> isAvailable() async {
    try {
      return await (await readyHostApi()).isAvailable();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    // An empty csv means "all products" to the host; nothing was asked for.
    if (identifiers.isEmpty) {
      return ProductDetailsResponse(productDetails: [], notFoundIDs: []);
    }
    try {
      final api = await readyHostApi();
      final products = await api.getProductsDetails(identifiers.join(','));
      final found = [
        for (final p in products)
          if (identifiers.contains(p.itemId)) SamsungProductDetails(p),
      ];
      final foundIds = {for (final p in found) p.id};
      return ProductDetailsResponse(
        productDetails: found,
        notFoundIDs: [
          for (final id in identifiers)
            if (!foundIds.contains(id)) id,
        ],
      );
    } on PlatformException catch (e) {
      return ProductDetailsResponse(
        productDetails: [],
        notFoundIDs: identifiers.toList(),
        error: IAPError(source: source, code: e.code, message: e.message ?? ''),
      );
    }
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      _buy(purchaseParam, consume: false);

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) => _buy(purchaseParam, consume: autoConsume);

  /// Emits `[pending]`, starts the payment and returns; the outcome arrives
  /// on [purchaseStream].
  Future<bool> _buy(PurchaseParam param, {required bool consume}) async {
    final itemId = param.productDetails.id;
    final (accountId, profileId) = switch (param) {
      SamsungPurchaseParam p => (p.obfuscatedAccountId, p.obfuscatedProfileId),
      _ => (param.applicationUserName, null),
    };
    _purchases.add([_noPurchase(itemId, PurchaseStatus.pending)]);
    unawaited(
      _pay(
        itemId,
        accountId,
        profileId,
        consume: consume,
      ).then((details) => _purchases.add([details])),
    );
    return true;
  }

  Future<PurchaseDetails> _pay(
    String itemId,
    String? accountId,
    String? profileId, {
    required bool consume,
  }) async {
    try {
      final api = await readyHostApi();
      final result = await api.startPayment(itemId, accountId, profileId);
      final purchase = result.purchase;
      final error = result.error;
      if (purchase != null) {
        return consume
            ? await _consumed(api, purchase)
            : _fromPurchase(purchase, PurchaseStatus.purchased);
      }
      if (error == null) {
        return _failed(itemId, 'no_result', 'Payment returned no result');
      }
      if (error.code == samsungPaymentCanceled) {
        return _noPurchase(itemId, PurchaseStatus.canceled);
      }
      return _failed(itemId, '${error.code}', error.message);
    } on PlatformException catch (e) {
      // Payment calls should not throw; treat it like an ErrorMsg anyway.
      return _failed(itemId, e.code, e.message ?? '');
    } catch (e) {
      // Never leave the caller stuck on `pending`.
      return _failed(itemId, 'unknown', '$e');
    }
  }

  /// Consumes a just-bought consumable; a consumed purchase needs no
  /// completion. A consume failure is reported as an error update.
  Future<PurchaseDetails> _consumed(
    SamsungIapHostApi api,
    PurchaseMsg purchase,
  ) async {
    final details = _fromPurchase(purchase, PurchaseStatus.purchased);
    final failure = await _settle(
      () => api.consumePurchasedItems([purchase.purchaseId]),
      purchase.purchaseId,
    );
    details.pendingCompletePurchase = false;
    if (failure != null) {
      details
        ..status = PurchaseStatus.error
        ..error = IAPError(
          source: source,
          code: failure.code,
          message: failure.message ?? '',
        );
    }
    return details;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    final purchaseId = purchase.purchaseID;
    if (purchaseId == null) {
      throw InAppPurchaseException(
        source: source,
        code: 'no_purchase_id',
        message: 'Cannot complete a purchase without a purchaseID',
      );
    }
    final failure = await _settle(
      () async => (await readyHostApi()).acknowledgePurchases([purchaseId]),
      purchaseId,
    );
    if (failure != null) throw failure;
    purchase.pendingCompletePurchase = false;
  }

  /// Runs an acknowledge/consume [call]; returns null on success, otherwise
  /// the failure as an [InAppPurchaseException].
  Future<InAppPurchaseException?> _settle(
    Future<List<AckResultMsg>> Function() call,
    String purchaseId,
  ) async {
    try {
      final results = await call();
      final mine = results.where((r) => r.purchaseId == purchaseId).firstOrNull;
      if (mine == null) {
        return InAppPurchaseException(
          source: source,
          code: 'no_result',
          message: 'No result for purchase $purchaseId',
        );
      }
      if (mine.statusCode == samsungStatusOk) return null;
      return InAppPurchaseException(
        source: source,
        code: '${mine.statusCode}',
        message: mine.statusString,
      );
    } on PlatformException catch (e) {
      return InAppPurchaseException(
        source: source,
        code: e.code,
        message: e.message,
      );
    }
  }

  /// Emits the owned list (always exactly one list, possibly empty) before
  /// completing. Host failures are rethrown.
  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    final owned = await (await readyHostApi()).getOwnedList('all');
    final now = _now();
    _purchases.add([
      for (final p in owned)
        if (_isActive(p, now)) _fromPurchase(p, PurchaseStatus.restored),
    ]);
  }

  /// Items are always active; a subscription is inactive only when its end
  /// date parses and is in the past. Unknown end dates are left to the backend.
  bool _isActive(PurchaseMsg p, DateTime now) {
    if (p.type != _subscription) return true;
    final end = _parseSamsungDate(p.subscriptionEndDate);
    return end == null || !end.isBefore(now);
  }

  static final _samsungDate = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');

  /// Parses Samsung's `yyyy-MM-dd HH:mm:ss` as UTC; null if malformed.
  static DateTime? _parseSamsungDate(String? value) =>
      value != null && _samsungDate.hasMatch(value)
      ? DateTime.tryParse('${value.replaceFirst(' ', 'T')}Z')
      : null;

  SamsungPurchaseDetails _fromPurchase(PurchaseMsg p, PurchaseStatus status) =>
      SamsungPurchaseDetails(
        productID: p.itemId,
        purchaseID: p.purchaseId,
        transactionDate:
            _parseSamsungDate(p.purchaseDate)?.millisecondsSinceEpoch
                .toString() ??
            p.purchaseDate,
        verificationData: PurchaseVerificationData(
          localVerificationData: p.jsonString,
          serverVerificationData: p.purchaseId,
          source: source,
        ),
        status: status,
        raw: p,
      )..pendingCompletePurchase = !p.acknowledged;

  SamsungPurchaseDetails _noPurchase(String itemId, PurchaseStatus status) =>
      SamsungPurchaseDetails(
        productID: itemId,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: '',
          source: source,
        ),
        status: status,
      );

  SamsungPurchaseDetails _failed(String itemId, String code, String message) =>
      _noPurchase(itemId, PurchaseStatus.error)
        ..error = IAPError(source: source, code: code, message: message);

  /// The app never asks the store for a country.
  @override
  Future<String> countryCode() =>
      throw UnimplementedError('countryCode() is not supported by Samsung IAP');
}
