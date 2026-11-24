# MIDI player v0.2 — LDOS 5.3.1

Copy MIDIPLAY.CMD and VOICES.MID in binary mode onto your LDOS disk (MIDIPLAY/CMD and VOICES/MID). Use the documented 9600-baud bridge. Run:

```
MIDIPLAY VOICES/MID:0
```

Choose 2 for 25 Hz or 3 for 30 Hz according to the actual LDOS clock. BREAK stops playback. The original voice demo selects all twelve EMT-10 voices with velocity and pedal examples. Set the EMT-10 to channel 1 or OMNI.

## Original piano and brass test piece

[PIANOBRS.MID](PIANOBRS.MID) is a 38.4-second, 16-bar original composition in C major at 100 BPM, using format 0, 96 PPQN, MIDI channel 1 and the EMT-10's native programs 0 (Piano 1) and 7 (Brass). The two voices alternate every four bars because a single EMT-10 cannot independently play piano and brass at once. It tests arpeggios, staccato chords, velocity, sustain and program changes, with all notes released before voice changes. Maximum simultaneous held notes: four.

Transfer PIANOBRS.MID (1,312 bytes) in binary mode to your LDOS disk as PIANOBRS/MID and run:

```
MIDIPLAY PIANOBRS/MID:0
```

Select the actual LDOS clock rate and use BREAK to stop. This is an EMT-10-specific file, not a General MIDI arrangement. A GM synth will interpret program 7 as Clavinet rather than Brass.

The original piece and its [generator](make_piano_brass.py) are MIT-licensed. To regenerate, install mido and run `python make_piano_brass.py`.

Mock-tested using the assembled CMD: all 1,028 expected channel-message bytes matched at both 25 Hz and 30 Hz, followed by the player's 192-byte cleanup. Audio playback and real hardware remain untested.

## Desktop conversion

Install Python 3 and mido (`python -m pip install mido`). Merge format 1:

```
python convert_midi.py INPUT.MID OUTPUT.MID
```

For a selected bass/piano arrangement, select the correct zero-based tracks:

```
python convert_midi.py INPUT.MID OUTPUT.MID --emt10 --bass 1 --piano 2 3 --basic-data OUTPUT.DAT
```

This maps selected parts to channel 1, Yamaha program 48 (Piano 1 + Upright Bass), limits held notes to two bass and six piano notes, folds pitches across the split as required and omits original sustain automation. It is not general orchestral transcription. Supply your own MIDI files; no copyrighted songs are distributed.

## BASIC player

Transfer NYPLAY.BAS and your generated DAT file as CR-delimited ASCII. In LDOS BASIC, LOAD "NYPLAY/BAS:0" then RUN. Enter 25 or 30 for the actual clock and your data file name. Press Q to stop. BREAK may abort before cleanup. BASIC interprets absolute-millisecond, status, data1, data2 records, with -1 indicating absent data2 or terminal time. It does not parse SMF.

## Native player limits

Format 0, single MTrk, exact six-byte MThd, PPQN only; max track length and each delta/meta length 65,535. Running status, tempo changes, channel messages and end-of-track supported. Other meta events and SysEx skipped. No automatic GM translation. Uses E8–EB UART ports and LDOS TIMER$ at 4288H (25/30 Hz); timing resolution approximately 40/33 ms. No RTS/CTS waiting, no interrupt hooks, no restoration of UART configuration. Requires free RAM 6000H–6541H. DOS disk latency and dense MIDI affect timing; stalls of 128 or more timer ticks cannot be reliably recovered.

## Status

Previously mock-tested Z80 opcodes against UART, DOS and keyboard stubs. This is not a full emulator or hardware timing test. Actual LDOS operation, BASIC, Arduino firmware and Yamaha audio remain to be tested. TRSDOS is not verified.

See the [root README](../README.md) for hardware and [MIT License](../LICENSE).

## Rebuild and run mock tests

From this directory, run `python build.py` followed by `python test_player.py`. The included restricted assembler generates the CMD and symbol map. The harness exercises the actual Z80 opcodes against mock DOS, UART and keyboard calls. See [TESTS.txt](TESTS.txt) for the original local results. The optional NYSTATE.MID test is skipped unless you supply your own converted song file. No song data is included.
