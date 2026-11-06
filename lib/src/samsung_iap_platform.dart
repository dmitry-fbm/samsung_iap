import 'dart:async';

import 'package:flutter/services.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'messages.g.dart';
import 'purchase_mapping.dart';
import 'samsung_iap_addition.dart';
import 'types.dart';

/// `in_app_purchase` platform implementation on top of Samsung IAP SDK 6.5.
///
/// Error convention: non-payment host calls throw [PlatformException] whose
/// code is Samsung's errorCode; payment calls report failure as an [ErrorMsg]
/// inside [PurchaseResultMsg].
///
/// Use an instance directly. Do not go through `InAppPurchase.instance`: on
/// Android it registers the Google Play platform in place of this one.
class SamsungIapPlatform extends InAppPurchasePlatform {
  /// Creates the platform for [mode].
  ///
  /// Construction installs this instance's [SamsungIapPlatformAddition] as
  /// the global `InAppPurchasePlatformAddition.instance` (the last one
  /// constructed wins), so create one per app.
  SamsungIapPlatform({
    this._mode = SamsungIapMode.production,
    SamsungIapHostApi? api,
  }) : _api = api ?? SamsungIapHostApi() {
    InAppPurchasePlatformAddition.instance = SamsungIapPlatformAddition(this);
  }

  /// `IAP_PAYMENT_IS_CANCELED` in the SDK's `HelperDefine`.
  static const samsungPaymentCanceled = 1;

  /// `IAP_ERROR_ALREADY_PURCHASED` in the SDK's `HelperDefine`: the item is
  /// already owned. Treat it as owned and run [restorePurchases].
  static const samsungAlreadyOwned = -1003;

  /// `IAP_ERROR_NONE`: success status of acknowledge/consume results.
  static const samsungStatusOk = 0;

  /// [PurchaseVerificationData.source] and [IAPError.source].
  static const source = samsungIapSource;

  final SamsungIapMode _mode;
  final SamsungIapHostApi _api;

  /// Asynchronous delivery: a listener may call buy*/restore from its
  /// callback without a re-entrant add.
  final _purchases = StreamController<List<PurchaseDetails>>.broadcast();
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

  /// Overlapping buys are not serialized: each call emits its own pending
  /// and result updates.
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      _buy(purchaseParam, consume: false);

  /// Overlapping buys are not serialized: each call emits its own pending
  /// and result updates. With [autoConsume] the purchase is consumed before
  /// its result is emitted.
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
    _emit([_noPurchase(itemId, PurchaseStatus.pending)]);
    unawaited(
      _pay(
        itemId,
        accountId,
        profileId,
        consume: consume,
      ).then((details) => _emit([details])),
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
            : samsungPurchaseDetails(purchase, PurchaseStatus.purchased);
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
    final details = samsungPurchaseDetails(purchase, PurchaseStatus.purchased);
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

  /// Emits every owned purchase as `restored` (always exactly one list,
  /// possibly empty) before completing. Host failures are rethrown.
  ///
  /// Subscriptions are included even past their end date: the owned list
  /// lags expiry, so entitlement must come from your backend.
  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    final owned = await (await readyHostApi()).getOwnedList('all');
    _emit([
      for (final p in owned) samsungPurchaseDetails(p, PurchaseStatus.restored),
    ]);
    // Async delivery runs in a microtask; let it reach listeners before the
    // returned Future completes (the app counts what arrived after awaiting).
    await Future<void>.delayed(Duration.zero);
  }

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

  /// Not supported: completes with an [UnimplementedError].
  @override
  Future<String> countryCode() async =>
      throw UnimplementedError('countryCode() is not supported by Samsung IAP');

  /// Closes [purchaseStream]. The platform must not be used afterwards; a
  /// payment still running at that point completes without being emitted.
  Future<void> dispose() => _purchases.close();

  /// Adds to [purchaseStream] unless [dispose] already closed it, so an
  /// in-flight payment finishing after [dispose] is dropped instead of
  /// throwing an unhandled `StateError`.
  void _emit(List<PurchaseDetails> purchases) {
    if (!_purchases.isClosed) _purchases.add(purchases);
  }
}
