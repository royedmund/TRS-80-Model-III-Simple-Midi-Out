# MIDIPLAY v0.9 — live MIDI TX monitor, timed Nano buffer and EMT-10 effects

This version is based on MIDIPLAY v0.8 and retains the live channel-1 dashboard, optimized timing, raw 9600 baud mode and clean LDOS exit. The hardware-tested version is v0.5; v0.9 has been tested with a mock Z80 and host-compiled firmware, not on actual AVR hardware.

## Alternative: direct FreHD SD-card playback (MIDISD v0.1)

Use [MIDISD.CMD](MIDISD.CMD) to browse native FAT folders and play compatible .MID files directly from the FreHD SD card, without importing the songs into DOS images. Import the executable once, then run `MIDISD` in LDOS. The v0.9 MIDI engine, timing modes, dashboard and Nano firmware are retained; MIDIPLAY remains unchanged. The experimental FreHD edition passed 11 mocked tests but has not been verified on physical hardware. See [setup and build instructions](README-MIDISD.md), [source](MIDISD.ASM) and [test results](MIDISD-TESTS.md).

## Install and test

1. Keep a backup of the existing MIDIPLAY/CMD and Arduino sketch. Transfer `MIDIPLAY.CMD`, `ROCKJAZZ.MID` and `ROCKRAW.MID` in binary mode. LDOS names are `MIDIPLAY/CMD`, `ROCKJAZZ/MID` and `ROCKRAW/MID`.
2. With the MIDI module disconnected, open `firmware/serial_to_midi_buffered/serial_to_midi_buffered.ino` in Arduino IDE. Board: classic Arduino Nano, processor ATmega328P (Old Bootloader if required), correct COM port. Verify, check the reported SRAM usage, upload. No wiring changes: MAX3232 TTL output D10, D1 MIDI TX, D11 unused, USB power.
3. Reconnect the EMT-10; set channel 1 or OMNI, receive program/control changes, all-note grouping. At LDOS Ready: `MIDIPLAY ROCKJAZZ/MID:0`.
4. Select 2 (25 Hz raw) or 3 (30 Hz raw) first. Verify the voices and effects, then run again with 4 (25 Hz buffered) or 5 (30 Hz buffered). Select the actual LDOS timer rate. **Do not select 4/5 with old firmware.** The buffered sketch is backward-compatible with existing raw MIDIPLAY channel messages and complete EMT-10 parameter SysEx, but reserves five MIDI real-time bytes for transport; do not use as a general-purpose MIDI clock bridge.
5. Test BREAK during a busy section; it should cancel pending buffered music and return to LDOS. Natural EOF drains queued data before panic. Wait for the last buffered notes and cleanup (normally less than a second) before starting raw playback again. If the LED stays lit, a queue/input overflow or link watchdog occurred; stop, reset the Nano and investigate. The next buffered START also resets the fault. No return telemetry, so MIDIPLAY cannot report Nano errors.

## Live MIDI TX monitor (v0.9)

The display shows the requested channel-1 program (native EMT-10 solo or combined Bass Split voice), its decimal program number, held pitches and sustain state. The lower row displays the last 16 successfully written musical bytes in hexadecimal, oldest to newest from left to right. Empty cells precede the first bytes. Includes all channels and forwarded complete Yamaha SysEx. Excludes Nano transport markers and end/BREAK panic traffic, preserving the last music bytes at exit. For example, C0 47 selects program 71 (Electric Bass + Brass), 90 3C 64 plays middle C at velocity 100, and 80 3C 00 releases it. The display uses sharp note names. It is a local UART TX monitor, not a hardware MIDI OUT readback: the unidirectional bridge cannot report the module's panel or audio state. Buffered display leads playback by the nominal 160 ms.

A 48-byte text ring and precomputed hex lookup store three characters per musical byte, only after the UART accepts it. Repaint only a dirty stream row, at most once per LDOS tick (plus final refresh). Notes retain independent dirty flags. No per-byte ROM console output. The firmware and protocol are unchanged from v0.8. Monitor processing introduces some CPU overhead; actual playback timing has not been measured.

## Original music: Silicon After Hours

176 BPM, 4/4, 96 PPQN, format 0, channel 1. Approximately 3:33. Four bars per patch: 12 solo voices followed by the 27 Bass Split combinations, with syncopated chords, bass riffs, improvised runs and sustained voice passages. The composition is original; no third-party songs are included. `ROCKJAZZ.MID` includes 15 documented EMT-10 parameter SysEx commands, covering all nine brightness/attack combinations, 4/8-note modes, both touch curves, bass octave down/normal and all note grouping settings. Includes CC64, CC66, CC67 and CC123. Grouping intentionally suppresses some notes in two short demonstrations. No unsupported GM drums, pitch bend, aftertouch or modulation. `ROCKRAW.MID` omits SysEx for v0.7 compatibility; pedal messages and all patches remain. For ROCKRAW, set all-note grouping and eight-note polyphony on the panel first. The raw version cannot change those parameters; a 4-note sustained mode may steal notes. Both files validate at max 8 held notes, including max 2 bass and 6 upper in split mode. Sustained release tails and actual audio were not tested. The full demo ends with neutral effects, 8-note mode, standard touch curve, normal bass octave, and all-note grouping; it does not restore the prior panel patch or settings. BREAK may leave effects in their current state.

Regenerate: `python -m pip install mido`, `python make_rockjazz.py`.

## Timed FIFO design

The Nano uses 192 queue entries: 1 MIDI byte plus a 32-bit microsecond deadline (parallel arrays, 960 bytes of SRAM). The ATmega328P has 2048 bytes of SRAM; the queue uses 46.875%, leaving 1088 bytes before other variables, Arduino serial buffers and stack. No dynamic allocation in the sketch. Actual Arduino linker SRAM report and stack margin must be checked on the classic Nano before relying on this prototype.

Buffered mode adds about 160 ms of lead time between host transmission and MIDI playout. The Z80 still paces events using its 25/30 Hz LDOS tick; the Nano independently schedules them and can absorb moderate delivery jitter from disk or screen updates. It adjusts its nominal tick deadline toward the host clock by at most 100 us per received tick. This does not increase the 9600 baud source bandwidth, change musical tempo, improve the original LDOS timing granularity, or recover delays exceeding the queue lead. The on-screen dashboard reports transmitted events and leads audio by the buffer delay. Dense messages sharing one tick are sent sequentially at MIDI speed, not literally simultaneously. There is no hardware flow control; a full queue aborts playback and lights the onboard LED. The two-second watchdog aborts an active stream with no transport input, including UART failure. Markers continue even during long musical rests.

Transport bytes on TRS-80-to-Nano link only: FD = start 25 Hz, F9 = start 30 Hz, F8 = next tick, FA = drain and panic at EOF, FC = immediate cancel and panic. All other bytes are raw MIDI channel messages or complete validated Yamaha SysEx. These tokens are never sent to MIDI OUT. Raw mode uses immediate forwarding through the same FIFO. The firmware limits hardware UART backlog; panic interrupts pending music and releases CC64/66/67 and sends CC123 on all 16 channels. If necessary an F7 terminates a partial transmitted SysEx. The transport has no checksum, ACK or retransmission; electrical errors can still corrupt data. For unrelated MIDI real-time applications use the original transparent firmware.

## Build and validation

- `python build.py` rebuilds CMD and MAP. Load range 6000H–7BF8H.
- `python test_player.py ROCKJAZZ.MID ROCKRAW.MID` runs the Z80 mock suite, raw streams, buffered protocol and SysEx whitelist tests.
- `python check_timed.py` compares every emitted byte and tick against independent timing and estimates queue occupancy with an ideal 9600-to-31250 link simulation. It does not model disk latency, UART interrupt timing or actual AVR scheduling.
- `g++ -std=c++11 -Wall -Wextra -Itests/mock tests/test_buffer.cpp -o test_buffer` then `./test_buffer` compiles and exercises the actual sketch on a desktop with mock Arduino APIs. It is NOT an AVR/Arduino IDE compile.

See TESTS.txt, BUFFER_TESTS.txt and TIMED_TESTS.txt. No full-system emulator, AVR compilation, real hardware timing or audio test of this release has been completed.

References: Yamaha EMT-10 user's guide (printed pp. 8–10 and implementation chart): https://ru.yamaha.com/files/download/other_assets/2/320652/EMT10E.PDF ; Arduino Nano specifications: https://store.arduino.cc/arduino-nano ; MIDI specs: https://midi.org/specs ; project: https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out

## Earlier demos and conversion utilities

See the [historical v0.7 documentation](README-v0.7.md) for the original VOICES, SPLIT27 and PIANOBRS demos, desktop MIDI conversion, BASIC player and earlier limitations. The original transparent Nano firmware remains available [here](../firmware/serial_to_midi/serial_to_midi.ino).
