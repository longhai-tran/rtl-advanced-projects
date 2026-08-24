# Async FIFO Gray — Test Plan

| ID  | Scenario                     | Stimulus                                         | Expected Result                                             |
|-----|------------------------------|--------------------------------------------------|-------------------------------------------------------------|
| TC1 | Write 8, Read 8              | Write `0xA0`–`0xA7`; read all back              | `rd_data` matches write order; no `err` increment          |
| TC2 | Fill to FULL                 | Attempt 20 writes into depth-16 FIFO             | `o_full` asserted after 16 valid writes                     |
| TC3 | Drain to EMPTY               | Read all entries after TC2                       | `o_empty` asserted; `rd_count == 0`                        |
| TC4 | Concurrent write > read rate | Writer: 100 MHz; Reader: 62.5 MHz; 12 transfers  | No data loss; no metastability; all reads match writes      |
| TC5 | Concurrent read > write rate | Reader faster; writer stalls when empty          | No spurious reads; EMPTY held until data available          |

## Coverage Goals

| Area               | Metric                              |
|--------------------|-------------------------------------|
| FULL flag          | Assert + deassert observed          |
| EMPTY flag         | Assert + deassert observed          |
| CDC Gray pointers  | All 4 pointers toggling in waveform |
| Reset              | Both `wr_rst_n` and `rd_rst_n` applied |
| Data integrity     | Zero `err` at end of all 5 tests   |

## Pass Criteria

Simulation output must end with:
```
  RESULT: ALL TESTS PASSED
```
