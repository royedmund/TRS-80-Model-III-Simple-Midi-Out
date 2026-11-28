# MIDISD v0.4 — framed MIDI Clock (experimental)

This is the clock-enabled successor to the hardware-tested MIDISD v0.3. The original player remains available unchanged in the parent `player` directory. No hardware change: install the output-only MIDICLOCK v0.2 Nano firmware before using clock modes. See [shared transport](../../transport/README.md), [wire format](../../transport/PROTOCOL.md), [schematic](../../transport/hardware/MIDI-CLOCK-OUT.svg).

Import `MIDISD.CMD` as MIDISD/CMD under LDOS 5.3.1. Select `CLOCKTST.MID` on the FreHD SD card. 2/3 = raw 25/30 Hz (no clock); 4/5 = new F6 framed transport at 25/30 Hz (requires new firmware). BREAK exits. Original picker and display retained; no new CLEAR behaviour in this build. Yamaha EMT-10 ignores MIDI Clock; clock-following devices or an analyser are needed to measure pulses.

## Source and build

`MIDISD-base.CMD` is the unchanged MIT-licensed v0.3 executable, verified by Git blob SHA. The original [documented parser](../MIDISD.ASM) remains the baseline; `CLOCKHOOK.ASM` is the new, documented Z80 overlay, `build.py` assembles it and checks the original instructions at every patch site. Run `python build.py` then `python test_hook.py` in this folder. See TESTS.txt; generated wire fixtures are not required in source control. The actual Nano decoder is tested in the shared transport directory. The new CMD is 9,109 bytes.

- F6 + rate starts a session; F1 encodes tempo; F2 and F3 carry complete musical event groups; FC aborts.
- The hook buffers up to 127 musical bytes per tick in unused baseline workspace, flushes before the timer wait and keeps original timing and raw output.
- 25/30 Hz musical resolution, 160 ms nominal Nano lead, 512 byte FIFO, no CRC/ACK. Unsupported dense frames fail closed.
- Instruction-level and host simulation tests passed; AVR compilation, physical hardware and sound verification pending.
