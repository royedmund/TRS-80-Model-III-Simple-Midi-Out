# MIDISD v0.3 — hardware-tested fast buffer

Install the matching player and firmware together. On 27 November 2026 the owner reported successful playback on a physical Model III after v0.2 had produced no sound. This is the recommended baseline; the precise cause of the v0.2 failure was not isolated.

## Installation

1. Disconnect MIDI OUT while uploading or resetting. Open [serial_to_midi_fast.ino](firmware/serial_to_midi_fast/serial_to_midi_fast.ino) in Arduino IDE; classic Nano ATmega328P, correct bootloader and COM port. Verify SRAM usage, compile/upload, reconnect MIDI OUT.
2. Existing wiring: MAX3232 logic RX to D10, D1 MIDI TX, D11 unused; 9600 8N1 input, 31250 MIDI output. No hardware or FreHD firmware modification.
3. Import [MIDISD.CMD](MIDISD.CMD) as MIDISD/CMD into LDOS 5.3.1. Copy [LINKTEST.MID](LINKTEST.MID) to the native FreHD FAT card using an 8.3 name.
4. Run MIDISD, select the file, then mode 2 raw 25 Hz for four piano notes followed by three chords. Repeat mode 4 buffered 25 Hz. Modes 3/5 are the equivalent 30 Hz modes; match actual LDOS clock.
5. D13 blinks during buffered playback, steady on means fault, off idle/raw. Test clean BREAK, natural EOF and long songs.

## Implementation

FD/F9 start 25/30 Hz, F8 advances timing, FA drains, FC aborts. The old checked F4/F5 protocol is incompatible. Full status bytes, no CRC, sequence numbers or trailers. One timing byte per tick. The 512-byte circular FIFO releases complete timing groups with nominal 160 ms lead. Short delays rebuffer rather than abort; occupancy-based slew up to 200 us/tick outside the normal range; fractional 30 Hz clock. Two-second link watchdog, RX/FIFO overflow protection, nonblocking hardware UART. 256-byte held-key bitmap; release pedals, explicit tracked note-offs and CC123 for used channels plus channel 1. Terminate partial SysEx on abort. Internal faults: 1 FIFO overflow, 2 SoftwareSerial overflow, 3 watchdog, 4 incompatible checked START. LED indicates fault, not its code.

FreHD ports C2/C3/C4/CF: GETVER, OPENDIR, READDIR, OPENFILE (read-only), READFILE, CLOSEFILE. 255-byte read buffer; short names and nested directories, 9 entries/page; 63-character path buffer with conservative join limit. Standard MIDI format 0, PPQN, 16-bit track/delta/length limits, documented Yamaha SysEx whitelist. Instrument/held-note dashboard refreshes at most every three LDOS ticks during waits; no per-byte hex monitor. Display reports outgoing requests, not audio readback.

## Build and tests

Run `python3 build_midisd.py` from player. The assembly preserves the load layout of the hardware-tested executable; unused checked code is zero-filled. CMD size 9109 bytes, load 6000h–8300h. Git blob SHA of tested CMD: 6afd5600e2207c987aeea06d9755708356a42067.

Run `python3 tests/test_midisd_fast.py LINKTEST.MID` to test actual CMD in the restricted Z80/LDOS/FreHD mock and create buffered wire fixtures. Then `g++ -std=c++17 -O2 -Itests/mock tests/test_fast.cpp -o /tmp/test_fast && /tmp/test_fast tests/*.wire`. See [regression results](MIDISD-TESTS.md). Third-party song files and their byte streams are not distributed.

## Limits

No ACK/retransmission or flow control on one-way RS-232. No arbitrary corruption detection. Actual overflow stops playback; lost note-off could remain stuck until cleanup. EMT-10 voice stealing is independent of transport. Host tests not cycle-accurate, AVR SRAM measurement and precise physical timing remain unrecorded. Legacy MIDIPLAY and its firmware remain available; checked v0.2 branch is historical.

Credits: George Phillips, [TRSvid](https://48k.ca/trsvid.html) and GIF/CMD, and Frédéric Vecoven, [FreHD](https://www.vecoven.com/trs80/trs80.html); native file and directory command behavior. No third-party firmware redistributed.
