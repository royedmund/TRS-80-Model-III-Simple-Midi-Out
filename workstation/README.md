# TRS-80 Model III MIDI Workstation — v0.1 experimental

First milestone: bidirectional serial bridge and native MIDI input monitor. The Model III is the workstation; the Nano only transports, filters and buffers events. Existing PIANO and EMTPLAY remain separate applications. No recording, sequencer or MIDI THRU yet.

## Build / install

1. Keep a copy of the original working `serial_to_midi_fast` firmware. Do not replace it on the only working interface until you are ready to test.
2. With power disconnected, wire the new interface following `MIDIWORK-schematic.svg` or `.png`. Classic 5 V ATmega328P Nano, a dual-channel MAX3232 module with its charge pump capacitors, 6N137 optocoupler, 1N4148, three 220-ohm resistors, one 1k pull-up, 100nF capacitor, two 180-degree DIN-5 sockets, JP1 removable jumper and SW1 switch/jumper. Verify actual connector numbering, module pin labels, and supply polarity. Do not apply RS-232 voltage directly to the Nano. Use regulated 5 V and a shared logic ground; no power from the DB25. MIDI IN pin 2 and shell remain isolated. MIDI OUT uses the existing 5 V two-resistor direct-driver circuit; verify output current and receiver compatibility.
3. **Important:** classic Nano clones differ. D0 is shared with the onboard USB-UART transmitter. For reliable operation isolate that transmitter from D0 using the board-specific series link/resistor (or a suitable external programming arrangement). JP1 disconnects the optocoupler output from D0 during upload. Restore the USB-UART path for USB uploading if you have isolated it; remove MIDI OUT cable during reset/upload. Do not connect two driven outputs together. Upload with Arduino IDE, install AltSoftSerial by Paul Stoffregen, select classic Nano and correct bootloader. No AVR toolchain available here; compile and check SRAM before uploading. The fixed application arrays consume 960 bytes plus scalar state, serial buffers and stack; classic Nano has 2048 bytes total. Actual SRAM utilisation is not measured.
4. Rewire the old D10 input to D8 (MAX3232 R1OUT). Add D9 -> MAX3232 T1IN -> T1OUT -> DB25 pin 3. D0 receives optoisolated MIDI; D1 retains existing MIDI OUT. DB25 pin 2 -> R1IN; pin 7 -> GND. SW1 grounds D4 at reset to enable MIDI input. Open SW1 and reset for legacy output-only use. Firmware samples switch at boot.
5. Copy `MIDIIN.CMD` in binary as MIDIIN/CMD onto LDOS 5.3.1. Connect MIDI source to IN, then run `MIDIIN`. The display shows twelve recent events in hex. CLEAR clears log; BREAK exits. It does not send MIDI or sound the EMT-10 from external input; no automatic THRU. For first output compatibility test, use legacy output-only mode, then try the current PIANO or EMTPLAY raw mode, then buffered mode.

## Input protocol

RS-232 9600 8N1 in both directions. MIDI hardware UART 31250 8N1. Host-bound frames always 3 bytes: status (>=80h), data1, data2. Channel voice messages normalized from MIDI running status; Cn/Dn padded with zero. FA/FB/FC transport events have two zero bytes. Active sensing, clock, system common and SysEx input are ignored. F4 00 00 indicates input software FIFO overflow; applications must clear held-key state and resynchronize, as a note-off may have been lost. Arduino hardware UART RX overrun may not be observable through the stock Serial API; this is not a lossless recorder. Up to 64 normalized events queued (192 bytes), delivered at approximately 317 frames/sec maximum. Incoming dense MIDI can exceed that; no hardware flow control. Avoid dense controller streams during initial testing.

Examples: 90 3C 64 = channel 1 C4 on, velocity 100; 90 3C 00 = off; B0 40 7F = sustain on; C0 06 00 = program 6; FA 00 00 = start. Monitor logs status/data in hex; status low nibble is zero-based channel. UART errors set ! and reset the parser. A new status always resynchronizes. The monitor polls EAh bit 7 and reads EBh; no interrupts installed, LDOS clock remains enabled. It uses a 12-line circular log, not a recording buffer. Test with normal LDOS configuration, no active DOS serial driver competing for the UART.

## Output compatibility

Raw channel messages and the previous fast Nano protocol: FD/F9 START (25/30Hz), F8 tick, FA drain, FC abort. 512-byte output FIFO, 160 ms nominal lead, watchdog, held-note cleanup. The reserved protocol bytes are not forwarded as raw MIDI real-time commands. No external MIDI THRU or mixing in this release, so no competing output MIDI streams. Legacy checked protocol is not supported. No guarantee of timing parity with original SoftwareSerial firmware until measured. Keep original firmware and wiring notes.

## Build and tests

`python build.py` assembles the documented Z80 source, creates CMD and listing, validates the CMD records. `python test_monitor.py` exercises the actual assembled opcodes with a mock UART, keyboard, VRAM and LDOS exit. `g++ -std=c++17 -Itests/mock tests/test_bridge.cpp -o /tmp/test_bridge && /tmp/test_bridge` executes the bridge logic with a mock Arduino serial environment. Results in TESTS.txt. These are not cycle-accurate emulator, AVR compilation, electrical or physical hardware tests. The schematic is a prototype wiring design, not a verified PCB.

## References

- TRS-80 port reference: https://www.trs-80.com/main-internal-ports-and-i-o.htm (Model III E8–EB, UART flags).
- AltSoftSerial: https://www.pjrc.com/teensy/td_libs_AltSoftSerial.html (ATmega328P pins D8/D9, Timer1).
- MIDI electrical specification: https://midi.org/5-pin-din-electrical-specs
- MIDI optocoupler design: https://www.kieranreck.co.uk/MIDI-6N137-vs-6N138-vs-6N139/
- Original project: https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out — existing MIT-licensed fast bridge and player design.
