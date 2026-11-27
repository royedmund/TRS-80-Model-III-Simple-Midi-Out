# SC55PLAY v0.1 — Experimental Roland Sound Canvas MIDI player

TRS-80 Model III (48 KB), LDOS 5.3.1, FreHD native SD FAT filesystem, existing 9600-baud RS-232/MAX3232/Arduino Nano bridge to Roland SC-55 MIDI IN (31,250 baud). Pure MIDI output: no cassette percussion or cassette output writes. Derived from MIDISD v0.1 and earlier experimental playback optimisations. Original players remain unchanged.

**Prototype only:** assembled and targeted mock Z80 tests passed. Not tested on physical TRS-80 or SC-55 hardware. No firmware update required for initial raw-mode testing.

## Install and play

1. Back up the LDOS disk and FreHD SD card. Import SC55PLAY.CMD in binary mode as SC55PLAY/CMD. Loads 6000h–78AAh, entry 6000h; ensure RAM region is free.
2. Copy SC55DEMO.MID or VELVET.MID directly to the FreHD SD card FAT root or folder, using short 8.3 filenames. No need to import MIDI files into a DOS disk image.
3. Connect the existing MIDI bridge to the SC-55 MIDI IN and stereo outputs to an amplifier or powered speakers. Start at low volume.
4. Run SC55PLAY without arguments. Select entries 1–9; N next page, R restart directory, U parent, BREAK exit.
5. Select 2 (raw 25 Hz) or 3 (raw 30 Hz), according to actual LDOS clock. Optional 4/5 modes require compatible timed Nano firmware; test raw first.
6. BREAK or end-of-track returns to LDOS. Raw cleanup sends pedal release, All Notes Off and All Sound Off on all 16 channels.

## Support and limitations

- SMF format 0, one MTrk, six-byte header, PPQN 1–32767, 32-bit track length (no former 64 KB track ceiling). Individual delta and meta/SysEx length VLQs remain limited to 65535. Format 1/2 and SMPTE not supported.
- All seven channel voice message classes, all 16 channels including drums on 10. Independent input/output running status. No Yamaha instrument mapping or cassette output.
- Whole GM System On and Roland GS DT1 messages (manufacturer 41h, model 42h, command 12h, device 00h–1Fh, address high byte 40h or 41h, valid 7-bit payload and checksum). Maximum 128-byte F0 payload including F7. Other SysEx and F7 continuations skipped. Two nominal timer ticks added after admitted SysEx. Use trusted files: GS writes can change settings; both demos contain explicit GS reset using device byte 10h.
- Dashboard displays last requested program, CC0 bank and peak Note On velocity for each of 16 channels, not hardware readback or active voice count. TX monitor shows last 16 musical bytes.
- FreHD read-only native file commands, 255-byte buffer; no firmware changes. Timer resolution 25/30 Hz. Dense songs may overflow timed bridge FIFO.

## Original compositions

| File | Style | Duration | Tempo |
|---|---|---|---|
| SC55DEMO.MID | All 16 channels across contrasting ensembles, GS reset, banks, stereo effects | 36.5 s | 120 BPM |
| VELVET.MID | VELVET STATIC: moody alternative rock with 12 parts, layered guitar, piano, bass, pads, choir, drums and atmospheric effects | 106.25 s | 96 BPM |

VELVET uses GS Hall 2 and Chorus 3, independent pan, expression, pitch bend, modulation and reverse cymbal transitions. Score limits held notes to nine to leave headroom for the original SC-55's 24 partials. Actual release tails and partial usage require listening tests.

## Build and validation

Python 3 standard library only: run `python build.py` in this directory to produce SC55PLAY.CMD and SC55PLAY.MAP. See TESTS.txt and SHA256SUMS.txt for local mock regression results and binary checksums. Physical hardware, actual audio, timing and FreHD bus/directory handling are unverified.

## Next steps

Native Format 1 playback, longer individual VLQs, finer timing, bandwidth profiling, GS instrument names and channel activity/voice accounting.

## References and credits

Roland SC-55 Owner's Manual (1991), printed pp. 18–24, 40–41, 66–71 and 72–84. Inherited FreHD browser derives from George Phillips's TRSvid/GIF-CMD and Frederic Vecoven's FreHD protocol. MIT license included.
