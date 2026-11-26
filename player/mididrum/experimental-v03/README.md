# MIDIDRUM v0.3 — experimental performance build

TRS-80 Model III / LDOS 5.3.1 / FreHD / Yamaha EMT-10, with optional compatible Nano firmware. The v0.2 player remains available in the parent project; no hardware changes required. This is an experimental release, not hardware-qualified.

## Installation

1. Back up your LDOS disk and existing Nano sketch. Import `MIDIDRUM.CMD` in binary mode as MIDIDRUM/CMD (load 6000h–8751h, entry 6000h). Keep the v0.2 executable for rollback.
2. Copy GHSTWIRE.MID, NIGHTFAL.MID and SUNSPARK.MID to the FreHD FAT SD card. Run MIDIDRUM and choose a file.
3. Connect the existing RS-232 bridge to the EMT-10 and cassette audio output to a separate mixer input or amplified speaker. Do not connect audio outputs directly together.
4. Choose 6/7 (25/30 Hz) for MIDI channel 10 percussion; 8/9 for automatic beat. Original raw modes 2/3 and timed Nano modes 4/5 remain available. BREAK exits.
5. Test the player with the existing Nano first; then optionally flash `firmware/serial_to_midi_v03/serial_to_midi_v03.ino` on a classic ATmega328P Nano (D10 RX, D1 MIDI TX). Disconnect MIDI during upload/reset. No rewiring. Timed modes require compatible timed firmware. Hybrid modes remain raw, not timestamp-buffered.

## Changes

* Independent outgoing MIDI running status in hybrid modes, reset for transmitted SysEx. Legacy modes preserve the original stream.
* Compact 16-byte TX monitor; deferred hex conversion; refresh throttled to three LDOS ticks.
* Fast common single-byte VLQ and buffered SD read paths.
* Precomputed cassette waveform tables; velocity controls envelope duration, not electrical amplitude. Bounded audio work during UART busy waits; MIDI takes priority. Cassette output is monophonic and remains at levels 0/1.
* Nano raw fast path eliminates ordinary raw-mode `micros()` calls; bounded input/output batches, original timed protocol and 192-entry FIFO, overflow/peak diagnostics. No queue expansion or new timed hybrid protocol.

## Rebuild and test

Python 3 standard library only. `python build.py` produces CMD and MAP. `python test_player.py` exercises assembled opcode routines with mocked I/O; `python benchmark.py` compares against v0.2 binaries in fallback-v02. Run `g++ -std=c++17 -Itests/mock tests/test_firmware.cpp -o test_firmware && ./test_firmware` for host firmware checks. See TESTS.txt for results. Compile the sketch in Arduino IDE for the target before flashing. Host checks are not AVR compilation.

Real-machine audio quality, timing, UART/SD behaviour and firmware are not yet verified. The clock remains 25/30 Hz, no sub-tick scheduler, multi-voice cassette mixing or multi-block read-ahead in this revision. Test SUNSPARK's 30–40 second cassette-only solo, dense piano passages and BREAK/EOF. Compare v0.2 and v0.3 on the same hardware.

MIT license; inherits MIDISD credits to George Phillips and Frédéric Vecoven. Original demo compositions by this project.
