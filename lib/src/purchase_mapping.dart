import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'messages.g.dart';
import 'types.dart';

/// [PurchaseVerificationData.source] and [IAPError.source].
const samsungIapSource = 'samsung_iap';

final _samsungDate = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');

/// Parses Samsung's `yyyy-MM-dd HH:mm:ss` as UTC; null if malformed.
DateTime? parseSamsungDate(String? value) =>
    value != null && _samsungDate.hasMatch(value)
    ? DateTime.tryParse('${value.replaceFirst(' ', 'T')}Z')
    : null;

/// Maps a host purchase to the plugin's [PurchaseDetails].
SamsungPurchaseDetails samsungPurchaseDetails(
  PurchaseMsg p,
  PurchaseStatus status,
) => SamsungPurchaseDetails(
  productID: p.itemId,
  purchaseID: p.purchaseId,
  transactionDate:
      parseSamsungDate(p.purchaseDate)?.millisecondsSinceEpoch.toString() ??
      p.purchaseDate,
  verificationData: PurchaseVerificationData(
    localVerificationData: p.jsonString,
    serverVerificationData: p.purchaseId,
    source: samsungIapSource,
  ),
  status: status,
  raw: p,
)..pendingCompletePurchase = !p.acknowledged;
