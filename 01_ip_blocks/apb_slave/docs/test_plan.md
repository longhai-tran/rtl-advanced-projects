# APB slave verification plan

## Scope

The testbench verifies an APB4 zero-wait-state register slave. Every transfer
uses the required Setup phase followed by the Access phase.

## Tests

| ID | Stimulus | Required checks |
|---:|---|---|
| T1 | Reset and idle bus | Reset values, `PREADY=1`, clean idle outputs |
| T2 | Full-word write and read | Register readback, no slave error |
| T3 | Partial and zero-strobe writes | Only selected byte lanes change |
| T4 | Read and write STATUS | Live status readback; writes have no effect |
| T5 | Out-of-range and misaligned access | `PSLVERR=1`, read data zero, no register corruption |
| T6 | Two writes without an idle cycle | Both transfers complete exactly once |

## Pass criteria

- Compile has no errors.
- The scoreboard error count remains zero.
- The 100 us watchdog does not expire.
- Any failed check invokes `$fatal` and returns a non-zero simulator status.
