import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut: 'android/src/main/kotlin/online/as/samsung_iap/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'online.`as`.samsung_iap'),
    dartPackageName: 'samsung_iap',
  ),
)
class ProductMsg {
  ProductMsg({
    required this.itemId,
    required this.itemName,
    required this.itemPriceString,
    required this.itemPrice,
    required this.currencyCode,
    required this.itemDesc,
    required this.type,
    this.subscriptionDurationUnit,
    this.subscriptionDurationMultiplier,
    this.freeTrialPeriod,
  });

  String itemId;
  String itemName;
  String itemPriceString;
  double itemPrice;
  String currencyCode;
  String itemDesc;

  /// 'item' | 'subscription'
  String type;
  String? subscriptionDurationUnit;
  int? subscriptionDurationMultiplier;
  String? freeTrialPeriod;
}

class PurchaseMsg {
  PurchaseMsg({
    required this.itemId,
    required this.purchaseId,
    required this.paymentId,
    required this.orderId,
    required this.purchaseDate,
    required this.type,
    required this.acknowledged,
    required this.jsonString,
    this.subscriptionEndDate,
    this.obfuscatedAccountId,
    this.obfuscatedProfileId,
  });

  String itemId;
  String purchaseId;
  String paymentId;
  String orderId;
  String purchaseDate;
  String type;
  bool acknowledged;
  String? subscriptionEndDate;
  String? obfuscatedAccountId;
  String? obfuscatedProfileId;
  String jsonString;
}

class ErrorMsg {
  ErrorMsg({required this.code, required this.message});

  int code;
  String message;
}

class PurchaseResultMsg {
  PurchaseResultMsg({this.purchase, this.error});

  PurchaseMsg? purchase;
  ErrorMsg? error;
}

class AckResultMsg {
  AckResultMsg({
    required this.purchaseId,
    required this.statusCode,
    this.statusString,
  });

  String purchaseId;
  int statusCode;
  String? statusString;
}

@HostApi()
abstract class SamsungIapHostApi {
  bool isAvailable();

  /// 'production' | 'test' | 'test_failure'
  void setOperationMode(String mode);

  /// '' = all
  @async
  List<ProductMsg> getProductsDetails(String itemIdsCsv);

  /// 'item' | 'subscription' | 'all'
  @async
  List<PurchaseMsg> getOwnedList(String productType);

  @async
  PurchaseResultMsg startPayment(
    String itemId,
    String? obfuscatedAccountId,
    String? obfuscatedProfileId,
  );

  @async
  List<AckResultMsg> acknowledgePurchases(List<String> purchaseIds);

  @async
  List<AckResultMsg> consumePurchasedItems(List<String> purchaseIds);

  /// Raw JSON passthrough.
  @async
  String getPromotionEligibility(String itemIdsCsv);

  @async
  PurchaseResultMsg changeSubscriptionPlan(
    String oldItemId,
    String newItemId,
    String prorationMode,
  );
}
