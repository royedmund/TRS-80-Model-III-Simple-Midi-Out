# MIDISD v0.2 — checked Nano buffer (experimental)

This is a matched player and firmware upgrade for the Model III, LDOS 5.3.1 and FreHD. Original main-branch executables and firmware remain the fallback. Import this MIDISD.CMD into LDOS; copy MIDI files directly to the FreHD FAT SD card. Flash the companion serial_to_midi_checked sketch before selecting 4 (25 Hz) or 5 (30 Hz). Modes 2/3 are raw legacy output. Do not use checked 4/5 with the old sketch.

Wiring unchanged: MAX3232 output to Nano D10, D1 to MIDI OUT, 9600 8N1 input / 31250 MIDI. Disconnect MIDI during programming/reset.

Protocol: F4 (25 Hz) or F5 (30 Hz) starts. Each frame carries up to 64 MIDI bytes, followed by F6 (continue same tick), F8 (advance tick) or FA (drain/end), then a modulo-128 sequence, CRC-8/ATM low seven bits and high bit. CRC includes payload, marker and sequence. FC is immediate abort. Outgoing MIDI running status is compressed; SysEx resets it. Display shows logical events, not the compressed wire bytes. Screen redraw throttled to three OS ticks. Single-byte VLQ fast path. Native FreHD read-only streaming unchanged.

The companion Nano uses a 768-byte compact FIFO including tick markers, 240 ms nominal lead, bounded output service, CRC/sequence checking, overflow/late/link watchdog protection and explicit active-note release on fault/stop. The link is one-way: no ACK, retransmission or backpressure to the TRS-80. CRC-8 is error detection, not a guarantee. SoftwareSerial and physical link errors remain possible. Dense events beyond the link capacity cannot be recovered. LED high = latched fault; reset/restart a song to clear. No debug text on the MIDI UART.

Build: copy the main branch player/build_midisd.py into this directory and run python3 build_midisd.py. The restricted assembler was independently ported and validated byte-for-byte on the original CMD before assembling this candidate. Load 6000h–8300h, CMD 9109 bytes. Real-machine timing, AVR build/SRAM report and FreHD end-to-end operation of this revision are not yet verified.
