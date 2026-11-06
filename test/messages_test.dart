import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_iap/src/messages.g.dart';

void main() {
  test('PurchaseResultMsg round-trips through encode/decode', () {
    final original = PurchaseResultMsg(
      error: ErrorMsg(code: -1, message: 'no activity'),
    );
    final result = PurchaseResultMsg.decode(original.encode());
    expect(result.purchase, isNull);
    expect(result.error?.code, -1);
    expect(result.error?.message, 'no activity');
  });
}
