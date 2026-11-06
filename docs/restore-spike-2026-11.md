# Restore spike, November 2026

Gate for the app integration: does each product restore reliably through
`getOwnedList`? Run with the example app (`example/`, package
`com.asol.safedrive`, signed with the registered key).

| Field | Value |
|---|---|
| Date | 2026-11-06, 19:40–20:50 (Europe/Riga, UTC+2) |
| Device(s) | Galaxy S10e SM-G970F (Android 12); Galaxy S23 SM-S911B (second device, check 3) |
| Samsung IAP SDK | 6.5.2 (Maven Central `com.samsung.developer:iap`) |
| Mode | test (`OPERATION_MODE_TEST`); payment sheet showed "Sandbox" |
| Account | owner's licence-tester account, same on both devices |

**Result: all checks PASS for both products. Gate passed.**

Server-side state was cross-checked with Samsung's receipt API
(`GET https://iap.samsungapps.com/iap/v6/receipt?purchaseID=…`).

## online.as.safedrive.lifetime

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | In owned list after purchase + acknowledge | PASS | Bought 19:43:45 (`df1e70be…`), Complete 19:47:39, Restore 19:48:05 → `status=restored`, `acknowledgeYN:"Y"`. |
| 2 | Survives uninstall/reinstall | PASS | Bought 20:26:59 (`a27e797f…`), app uninstalled + reinstalled 20:27:44, Restore 20:27:55 → `status=restored`. |
| 3 | Appears on a second device | PASS | Bought on S10e 20:49:17 (`a7df7467…`), Restore on S23 20:50:12 → `status=restored`; receipt `acknowledgeDeviceModel: SM-G970F`. |
| 4 | Repeat purchase refused (error code: **-1003**) | PASS | 20:18:17 `status=error error=-1003: Already purchased.` while purchase `1b024d72…` was valid. |
| 5 | Cancel in Galaxy Store (n/a for an item) | — | n/a |

## online.as.safedrive.1m

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | In owned list after purchase + acknowledge | PASS | Bought 19:59:43 (`ef645ee4…`), Complete 20:06:16, Restore 20:06:25 → `status=restored`, `acknowledgeYN:"Y"`. |
| 2 | Survives uninstall/reinstall | PASS | Bought 20:45:03 (`60549d18…`), S10e reinstalled 20:48:19, Restore 20:48:38 → `status=restored`. |
| 3 | Appears on a second device | PASS | Same purchase, Restore on S23 20:45:51 and 20:50:12 → `status=restored`. |
| 4 | Repeat purchase refused | — | n/a (not run for the subscription) |
| 5 | After cancel: end date or absence in owned list | PASS (observed) | Cancelled in Galaxy Store ~20:07; Restore 20:07:21 still lists it with the unchanged `mSubscriptionEndDate` and no cancel flag; by 20:15:52 it was no longer listed (end date was 20:19:43). The app must take expiry from the backend, not from the owned list. |

## Observations

- **Sandbox voids test item purchases after 10 minutes.** Samsung's test guide:
  a licence tester can repurchase a non-consumable every 10 minutes in test
  mode. It is applied lazily: at the first `getOwnedList` after 10 minutes the
  receipt turns `status:"cancel"` with `cancelDate` = that moment (lifetime
  `df1e70be…` 20:06:26, `1b024d72…` 20:23:24), and the item leaves the owned
  list. Checks 2 and 3 therefore have to run within 10 minutes of a purchase.
  Real purchases are not affected.
- **Sandbox subscription period** is short and varies (20 min the first time,
  then ~10 min). Renewals happen early and **keep the original purchase id**:
  `60549d18…` had `mSubscriptionEndDate` 20:55:03 at 20:45:53 and 21:05:03 at
  20:50:13.
- **Receipt mode.** The receipt API returns `"mode":"TEST"` for licence-tester
  purchases; there is no `realMode` field. The app-side `jsonString` carries
  neither.
- **Payment methods.** The lifetime item offered PayPal; the subscription
  offered only a card, and the first sandbox subscription caused a real €0.15
  card-verification charge (not the €2.66 price).
- **Cancellation is per account**: cancelling the subscription in Galaxy Store on one device showed it cancelled on the other device too.
- **Consumable flag.** The purchase result has `mConsumableYN:"Y"` for the
  lifetime item; the owned list shows `"N"` once it is acknowledged.
- **Dates.** `mPurchaseDate` is device-local (`2026-11-06 19:43:45`); the
  plugin's UTC conversion gave `1793987025000` = 17:43:45 UTC. Correct.
- **Repeat purchase** surfaces as `PurchaseStatus.error` with code `-1003`. The
  app should treat it as "already owned" and run a restore.
- No `-1002` "operation running" errors, no hangs, no Galaxy Store update
  dialog. Every `completePurchase` returned in under 1 s; `restorePurchases`
  in under 2 s.
