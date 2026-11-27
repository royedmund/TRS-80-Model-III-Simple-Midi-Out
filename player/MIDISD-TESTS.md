# MIDISD v0.3 validation

- Hardware: owner reported successful physical Model III / Yamaha EMT-10 playback with the new pair on 27 November 2026, following the unsuccessful v0.2 test. Exact long-duration metrics not recorded.
- Binary: tested CMD 9109 bytes, 6000h–8300h, Git blob 6afd5600e2207c987aeea06d9755708356a42067. Reconstructed full assembly matches byte for byte.
- Z80 mock: all seven files passed buffered modes 4/5 and raw mode 2, exact outgoing musical bytes against independent reference decoder, file closed and port restored at exit.
- Nano host C++ mock: raw MIDI, complete groups, late-start recovery, EOF at both clocks, temporary 600 ms stall, BREAK releases held notes/pedals, partial SysEx termination, FIFO overflow/restart, RX overflow/watchdog, incompatible v0.2 START, micros rollover and UART backpressure all passed.
- All fourteen buffered wire streams replayed with modeled 9600 baud, 100 ms input delay and output pressure; no missing musical bytes or underruns in those runs. Peak modeled FIFO occupancy 87/512.

| Test song | Musical bytes | Peak 25 Hz | Peak 30 Hz |
| --- | ---: | ---: | ---: |
| LINKTEST | 113 | 31 | 31 |
| AFTRGLOW | 4492 | 42 | 46 |
| ALLENTWN | 9976 | 57 | 57 |
| COMPTMAX | 8112 | 87 | 87 |
| CORNFLAK | 11223 | 57 | 57 |
| SHESAWAY | 5157 | 60 | 60 |
| SILENT | 12369 | 60 | 60 |

Only LINKTEST is needed for the published test scripts. Third-party arrangements and their wire streams are excluded. Tests are host simulations, not cycle-accurate or electrical models. Historical v0.1 results remain in Git history.
