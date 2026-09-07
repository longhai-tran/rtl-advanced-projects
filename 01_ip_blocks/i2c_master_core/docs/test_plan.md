# I2C master verification plan

## Scope

The testbench verifies the APB register interface and the externally visible I2C
waveform for one-byte 7-bit-address transfers. The slave model drives only low or
high-impedance on SDA, matching open-drain behavior.

## Checks

| ID | Stimulus | Required checks |
|---:|---|---|
| T1 | Reset, APB reads/writes, unmapped read | Reset values, register readback, zero for unmapped address |
| T2 | Write `0x3C` to target `0x50`, ACK both bytes | START/STOP, address frame `0xA0`, data `0x3C`, no ACK error, sticky DONE |
| T3 | Read `0xD6` from target `0x50` | Address frame `0xA1`, RXDATA `0xD6`, master NACK after byte |
| T4 | NACK address | No data phase, ACK error set, valid STOP, finite completion |
| T5 | ACK address then NACK data | ACK error set, valid STOP, finite completion |
| T6 | START while previous DONE is set, then reset while BUSY | DONE clears on accepted START, BUSY sets, reset releases both bus lines and clears status |

Every APB transfer follows Setup then Access. Tests use divider values 2, 3, and
4 to exercise the programmable divider and its minimum supported boundary.

## Pass criteria

- Compile has zero errors and warnings.
- The scoreboard error count remains zero.
- The watchdog does not expire at 200 us.
- A failed check or timeout invokes `$fatal` so batch simulation exits as FAIL.
- Both Questa and Vivado xsim produce `RESULT: ALL TESTS PASSED`.
