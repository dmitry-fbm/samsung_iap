# Restore spike, November 2026

Gate for the app integration: does each product restore reliably through
`getOwnedList`? Run with the example app (`example/`, package
`com.asol.safedrive`, signed with the registered key).

| Field | Value |
|---|---|
| Date | |
| Device(s) | |
| Samsung IAP SDK | 6.5.2 |
| Mode | test / production |
| Account | owner's tester account |

Result: PASS / FAIL / not run ("—"). Evidence: paste the relevant log lines
from the example's "Copy log".

Checks:

1. After purchase plus acknowledge (Complete), the item is in `getOwnedList` (Restore).
2. It survives uninstall and reinstall.
3. It appears on a second Samsung device (or a remote one) with the same account.
4. Buying lifetime again is refused (record the error code).
5. After cancelling the subscription in Galaxy Store, record how `getOwnedList` presents it (end date or absence).

## online.as.safedrive.lifetime

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | In owned list after purchase + acknowledge | — | |
| 2 | Survives uninstall/reinstall | — | |
| 3 | Appears on a second device | — | |
| 4 | Repeat purchase refused (error code: ) | — | |
| 5 | Cancel in Galaxy Store (n/a for an item) | — | |

## online.as.safedrive.1m

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | In owned list after purchase + acknowledge | — | |
| 2 | Survives uninstall/reinstall | — | |
| 3 | Appears on a second device | — | |
| 4 | Repeat purchase refused (error code: ) | — | |
| 5 | After cancel: end date or absence in owned list | — | |

## Observations

Capture, when visible:

- Receipt `mode` / `realMode` in the `jsonString` of the raw purchase (`raw=` log lines).
- Error code (and message) on the repeat lifetime purchase.
- Whether a -1002 "operation running" error or a hang occurs (which call, how often).
- Whether the Galaxy Store update dialog appears, and when.
- Owned-list date fields (purchase date, subscription end date): format and values, before and after cancel.
- Anything else unexpected.
