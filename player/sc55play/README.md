# SC55PLAY v0.2 — Experimental Roland Sound Canvas fast-buffer player

TRS-80 Model III (48 KB), LDOS 5.3.1, FreHD native SD FAT filesystem, existing 9600-baud RS-232/MAX3232/Arduino Nano bridge to Roland SC-55 MIDI IN (31,250 baud). Pure MIDI output: no cassette percussion or cassette output writes. Derived from MIDISD v0.1 and earlier experimental playback optimisations. Original players remain unchanged.

**Prototype only:** rebuilt and exact-stream mock Z80/FreHD tests passed for both existing compositions. Compatible with the hardware-tested MIDISD v0.3 fast Nano sketch; SC55PLAY itself has not yet been tested on physical TRS-80/SC-55 hardware. No firmware change is required if the v0.3 fast sketch is already installed.

## Install and play

1. Back up the LDOS disk and FreHD SD card. Import SC55PLAY.CMD in binary mode as SC55PLAY/CMD. Loads 6000h–74CEh, entry 6000h; ensure RAM region is free.
2. Copy SC55DEMO.MID or VELVET.MID directly to the FreHD SD card FAT root or folder, using short 8.3 filenames. No need to import MIDI files into a DOS disk image.
3. Connect the existing MIDI bridge to the SC-55 MIDI IN and stereo outputs to an amplifier or powered speakers. Start at low volume.
4. Run SC55PLAY without arguments. Select entries 1–9; N next page, R restart directory, U parent, BREAK exit.
5. Select 2 (raw 25 Hz) or 3 (raw 30 Hz), according to actual LDOS clock. Select 4 (buffered 25 Hz) or 5 (buffered 30 Hz) using the [shared v0.3 fast Nano firmware](../firmware/serial_to_midi_fast/serial_to_midi_fast.ino); test raw first. Do not use the checked F4/F5 v0.2 protocol or transparent firmware in buffered modes.
6. BREAK or end-of-track returns to LDOS. Raw cleanup sends pedal release, All Notes Off and All Sound Off on all 16 channels.

## Shared Nano buffering

Use exactly the existing MIDISD v0.3 fast firmware; no separate Roland sketch. D10 RX at 9600 8N1, D1 hardware TX at 31250. The 512-byte FIFO stores complete timing groups; 160 ms nominal lookahead, occupancy-based clock slew and rebuffer/resume after short input delays. D13 flashes while buffering, steady on fault, off idle/raw. FD starts 25 Hz; F9 starts 30 Hz; F8 advances one LDOS tick; FA drains at EOF; FC aborts on BREAK. These markers are not forwarded to MIDI OUT. All 16 channels and running status remain supported. The firmware releases pedals and explicitly tracked notes, then CC123 on used channels plus channel 1. Raw SC55PLAY cleanup still also sends CC120; buffered cleanup does not, so release tails can remain. No ACK/retry or flow control; the link cannot guarantee recovery from corrupt/missing bytes. The nominal 9600-baud ceiling is 960 bytes/s before 25 or 30 marker bytes/s and Z80 overhead. GS checksum validation is separate from transport CRC and remains enabled. CLEAR-to-browser is not included in this version; BREAK and natural EOF return to LDOS.

## Support and limitations

- SMF format 0, one MTrk, six-byte header, PPQN 1–32767, 32-bit track length (no former 64 KB track ceiling). Individual delta and meta/SysEx length VLQs remain limited to 65535. Format 1/2 and SMPTE not supported.
- All seven channel voice message classes, all 16 channels including drums on 10. Independent input/output running status. No Yamaha instrument mapping or cassette output.
- Whole GM System On and Roland GS DT1 messages (manufacturer 41h, model 42h, command 12h, device 00h–1Fh, address high byte 40h or 41h, valid 7-bit payload and checksum). Maximum 128-byte F0 payload including F7. Other SysEx and F7 continuations skipped. Two nominal timer ticks added after admitted SysEx. Use trusted files: GS writes can change settings; both demos contain explicit GS reset using device byte 10h.
- Dashboard displays last requested program, CC0 bank and peak Note On velocity for each of 16 channels, not hardware readback or active voice count. The per-byte hexadecimal TX monitor is removed, and dashboard updates occur only during timing waits, at most every three LDOS ticks.
- FreHD read-only native file commands, 255-byte buffer; no firmware changes. Timer resolution 25/30 Hz. Dense songs may exceed RS-232 throughput or overflow the Nano FIFO.

## Original compositions

| File | Style | Duration | Tempo |
|---|---|---|---|
| SC55DEMO.MID | All 16 channels across contrasting ensembles, GS reset, banks, stereo effects | 36.5 s | 120 BPM |
| VELVET.MID | VELVET STATIC: moody alternative rock with 12 parts, layered guitar, piano, bass, pads, choir, drums and atmospheric effects | 106.25 s | 96 BPM |

VELVET uses GS Hall 2 and Chorus 3, independent pan, expression, pitch bend, modulation and reverse cymbal transitions. Score limits held notes to nine to leave headroom for the original SC-55's 24 partials. Actual release tails and partial usage require listening tests.

## Build and validation

Python 3 standard library only: run `python build.py` in this directory to produce SC55PLAY.CMD and SC55PLAY.MAP. Run `node test_sc55.js` (Node.js 18+) to execute the assembled CMD in the restricted Z80/FreHD mock and generate four buffered `.wire` fixtures. From the player directory, compile `g++ -std=c++17 -O2 -Itests/mock tests/test_fast.cpp -o /tmp/test_fast` and run `/tmp/test_fast sc55play/*.wire` to test the actual Nano sketch against those fixtures. The Z80 tests and separate synthetic Nano stress test were run for v0.2; the full cross-runtime demo replay command is provided for reproduction and has not been run here. See TESTS.txt and SHA256SUMS.txt. Physical hardware, actual audio, timing and FreHD bus/directory handling are unverified.

## Next steps

Native Format 1 playback, longer individual VLQs, finer timing, bandwidth profiling, GS instrument names and channel activity/voice accounting.

## References and credits

Roland SC-55 Owner's Manual (1991), printed pp. 18–24, 40–41, 66–71 and 72–84. Inherited FreHD browser derives from George Phillips's TRSvid/GIF-CMD and Frederic Vecoven's FreHD protocol. MIT license included.
