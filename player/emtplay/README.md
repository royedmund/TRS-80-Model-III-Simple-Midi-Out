# EMTPLAY v1.0 — framed MIDI Clock transport (experimental)

TRS-80 Model III, 48 KB, LDOS 5.3.1, FreHD, Yamaha EMT-10, MIDICLOCK v0.2 Nano bridge in clock modes. Based on the exact MIT-licensed MIDISD baseline (see LICENSE and build.py). No hardware changes; install MIDICLOCK v0.2 firmware before choosing 4/5.

## Reason for this build
Physical v0.8 playback of the owner's CANYON.MID was reported as choppy and musically incorrect. Two recordings and the exact MIDI file were supplied. The v0.8 arranger discarded all but two source channels, which is a concrete arrangement limitation; it is not proof of the cause of the gaps. This build is a diagnostic candidate, not a verified Canyon correction.

## Use
Import EMTPLAY.CMD as EMTPLAY/CMD. Copy MIDI files to the FreHD SD directory. Run EMTPLAY. Picker 1–9, N/n next, R/r restart, U/u parent. Select G for automatic GM reduction, P for Piano 1 plus selected bass (or Piano 1 alone for a pitched non-bass score), N for native EMT-10 files. Bass-only scores retain the bass voice. Select 2/3 for raw 25/30 Hz or 4/5 for framed MIDI Clock 25/30 Hz, matching actual LDOS timer. For Canyon try P, then compare raw and buffered at the same rate. CLEAR returns to picker; BREAK exits to LDOS. Display shows actual transmitted note onsets, upper and bass streams, explicit sharps/octaves, file, instrument and cache/transport information. Use normal eight-note polyphony, MIDI channel 1 or OMNI, program changes enabled. Use the matched MIDICLOCK v0.2 sketch in modes 4/5; raw modes 2/3 remain compatible.

## v0.9 changes
- GM analysis still selects the busiest non-bass channel and best bass channel by mapped GM program activity. All pitched channels except channel 10 may now contribute notes; selected bass channel goes to bass split, other channels to upper voice. If combined non-bass activity reaches twice the primary voice count, use Piano 1 as a neutral reduction. P forces Piano 1 on scores with a non-bass part. Not melody transcription; no independent GM timbres.
- Track all 16 channels' source keys independently (2048 bytes). Fold pitches into practical native ranges, enforce 8 total or 6 upper + 2 bass, reserve two upper positions for the primary channel by limiting other channels to 4/6 active upper notes. Overlapping output pitches are reference counted and released only when the last source key ends. Excess notes still dropped. GM sustain/other CC, pressure, pitch bend, percussion and SysEx are not reproduced. Native mode unchanged except transport.
- Restore full status bytes in both raw and buffered modes for diagnostic compatibility. This rolls back v0.8 running-status savings, not the faster UART-ready path or cached reader. The v1.0 protocol uses F6 rate, F1 tempo, F2 length and payload, F3 final frame, FC abort. 9600 8N1, 31250 MIDI. Actual serial jitter/underrun not measured.
- Program load 6000h–93B4h; cache starts 93B5h, maximum 27,723 bytes (27.07 KiB) if HIGH$ and stack allow. Additional source identity memory reduces cache by 1,917 bytes compared with v0.8. Checks LDOS HIGH$ (4411h), 512-byte high-stack guard, falls back to SD streaming. Require free RAM through 93B4h. Format 0 SMF, PPQN, one track, 16-bit track/delta limits; use merge_format1.py for desktop conversion.

## Validation
Run `python build.py`, `python test_gm.py`, `python test_fast.py`, `python test_reduction.py`, `python test_clock.py`. Tests execute actual patched Z80 instructions in a restricted CPU model, not a full emulator. New tests cover secondary accompaniment, forced piano, unison release, primary-note reservation, 6+2 cap, and real timing arithmetic for both clock rates under a synthetic timer including tempo changes. No physical UART/audio test. Exact CANYON.MID verified locally with the parser, in both GM and Piano modes at 25/30 Hz (7142 musical bytes in each case), but the song and wire capture are not distributed. See TESTS.txt and PERFORMANCE.md. Retain v0.9 and the original MIDISD v0.3 as fallbacks.

## Sources and credits
Original MIDISD project and Nano firmware: https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out ; George Phillips (TRSvid, trs80gp), Frédéric Vecoven (FreHD), Yamaha EMT-10 manual, General MIDI reference https://en.wikipedia.org/wiki/General_MIDI . MIT license retained. No third-party songs distributed.

## v1.0 transport implementation
- `EMTCLOCK.ASM`: frame assembly, tempo record encoding, start/abort/final, flush before timer wait. Uses 127 bytes of former dashboard RAM; original cache boundary unchanged.
- `EMTGM.ASM`: GM/Piano scan, note reduction and source pitch tracking. `EMTSCORE.ASM` and `EMTINFO.ASM`: note streams and information display. `EMTKEYS.ASM`: CLEAR/BREAK and case-independent picker. `EMTFAST.ASM`: UART ready and cached read paths. `EMTWIRE.ASM`: full-status compatibility. `build.py`: checks original MIDISD blob, assembles overlays and verifies each hook.
- `test_clock.py`: executes the actual parser at both LDOS rates, verifies framed payload matches raw output, emits test fixtures for original demos.
- See central [framed protocol and Nano firmware](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out/tree/main/transport). No clock in raw mode. 25/30 Hz note resolution, 127-byte maximum group; overflow aborts safely. Clock is generated at 24 PPQN by Nano. EMT-10 ignores external clock; it still receives notes normally.

For a GitHub checkout, run `g++ -std=c++17 -O2 -I../../transport/tests/mock -I../../transport/firmware/MIDICLOCK test_transport.cpp -o /tmp/emttransport && /tmp/emttransport *25.wire *30.wire` after `python test_clock.py`. For the local combined package, use `../midiclock-v02` in place of `../../transport` for both include directories.
