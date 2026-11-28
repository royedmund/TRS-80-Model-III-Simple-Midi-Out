# MIDICLK v0.2 — output-only framed transport (experimental)

Experimental reference implementation based on hardware-tested MIDISD v0.3. The original player and legacy firmware remain available unchanged. This release concentrates only on MIDI OUT and MIDI Clock with the existing D10/MAX3232 wiring. See [protocol specification](PROTOCOL.md) and [corrected schematic](hardware/MIDI-CLOCK-OUT.svg). The schematic is a module-level wiring diagram, not an electrically validated PCB design.

## Install/test

1. Keep the working original firmware and player as fallback. Disconnect MIDI OUT during upload/reset. Open `firmware/MIDICLOCK/MIDICLOCK.ino` in Arduino IDE, select classic Nano ATmega328P 5V and correct bootloader/port. Standard SoftwareSerial; no new wiring or AltSoftSerial needed. Compile and check AVR SRAM usage before uploading. The new firmware uses D10 RX, D1 TX. No MIDI IN.
2. Connect MAX3232 R1OUT -> D10, TRS-80 DB25 pin 2 -> R1IN, DB25 pin 7 -> logic GND. Power module/Nano from regulated 5V per module rating. MIDI OUT DIN pin 4 -> +5V via 220 ohm, pin 5 -> D1 via 220 ohm, pin 2 -> output-side ground; pins 1/3 NC. Use actual connector pin numbering, not a pictorial socket layout. Do not use the earlier AI-generated illustrations as wiring references: their DIN connections were incorrect. Never connect RS-232 voltages directly to Nano pins. Direct Nano TX driver is a prototype; verify loop current and consider a compliant buffered transmitter for production.
3. Import MIDICLK.CMD in binary as MIDICLK/CMD under LDOS 5.3.1. Copy CLOCKTST.MID to FreHD SD. Run MIDICLK, select demo, choose 4=25Hz or 5=30Hz to match LDOS timer. These modes require v0.2 firmware. BREAK exits. Raw 2/3 do not emit clock. The picker and original display remain as in MIDISD v0.3.
4. Monitor D1 at 31250 8N1 (logic analyser) or DIN OUT using a MIDI monitor. Expect FA, 193 F8 messages including initial beat-zero pulse in the six-second test, 52 musical bytes before cleanup, FC at EOF. 120 BPM for two seconds then 60 BPM for four seconds. Check BREAK mid-song, legacy MIDISD modes 4/5, and longer tracks. EMT-10 ignores clock; use an external clock-following device or monitor to verify the clock itself.

## Build and regression

`python build.py` verifies the original CMD blob SHA, assembles `CLOCKHOOK.ASM` in unused memory, patches the five sender/timing call sites plus the original tick call, and produces MIDICLK.CMD and listing. `python test_hook.py` runs instruction-level hook tests and the assembled SMF parser with mocked SD byte reads, display and LDOS TIMER$. It generates host and demo wire fixtures. `g++ -std=c++17 -O2 -Itests/mock tests/test_clock.cpp -o /tmp/clock && /tmp/clock` exercises actual firmware source with mock UART, including the assembled demo wire streams paced at 9600 baud. See TESTS.txt. No AVR toolchain, cycle-accurate emulator, physical timing or electrical validation performed. Note scheduling still 25/30Hz, 127 bytes per group, no CRC or flow control. See protocol for limits.

MIT licence. Baseline from https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out (MIDISD v0.3). MIDI electrical specification: https://midi.org/5-pin-din-electrical-specs. Original project credits: George Phillips (TRSvid) and Frédéric Vecoven (FreHD).

Related applications: [MIDISD v0.4](../player/clock/README.md) and [EMTPLAY v1.0](../player/emtplay/README.md).
