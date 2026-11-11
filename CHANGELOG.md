## 0.1.1

* Fix: a payment screen destroyed without a result (its task removed from Recents, or torn down
  while the user is away) no longer leaves the plugin hung. IAP SDK 6.5.2 then neither reports the
  payment nor runs the calls it queued behind it, so a later estorePurchases (e.g. at app
  startup) never completed. The open payment is now reported as cancelled and the queue drained.
## 0.1.0

* Initial release: `in_app_purchase` platform for Samsung Galaxy Store over Samsung IAP SDK 6.5.2.
