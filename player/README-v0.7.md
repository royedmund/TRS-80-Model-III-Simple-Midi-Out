# Historical v0.7 documentation (retained for earlier demos and conversion utilities)

This page describes the earlier v0.7 release and its historical testing status. For current v0.9 instructions and tests, see [README.md](README.md). File links may now point to newer versions; the original v0.7 tree is available at https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out/tree/d8e206618e8a7cb6dc14d10b64df7cc5e2ca5563/player.

# MIDI player v0.7 — LDOS 5.3.1

**Hardware milestone:** The project owner confirmed music playback, BREAK exit and end-of-file exit on physical Model III hardware using v0.5 on 25 November 2026. v0.7 adds a live channel-1 EMT-10 dashboard and optimised batched timing, retaining the same serial interface. See [v0.7 usage and limits](README.txt), [tests](TESTS.txt), and [benchmarks](BENCHMARK.txt). v0.7 is mock-tested only. Historical test notes below refer to their original versions.

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

## Two-voice Bass Split mode (EMT-10)

The native MIDIPLAY.CMD already sends program changes and overlapping notes. A single EMT-10 supports one bass voice below MIDI note 55, and one of its nine other voices at note 55 or above. It allocates two bass and six upper voices. Piano + Brass without a bass voice is not supported on one module.

Program numbers (zero-based MIDI): 48 + 16 * bass_voice + upper_voice. Bass index 0 = Upright, 1 = Electric, 2 = Slap; upper index 0–8 is the native non-bass voice number. See Yamaha EMT-10 user's guide printed pages 6 and 8. The demo uses the first listed program number for each combination.

Run the original MIT-licensed [SPLIT27.MID](SPLIT27.MID) in LDOS:

```
MIDIPLAY SPLIT27/MID:0
```

All 27 pairs play for four seconds each (108 seconds total), grouped by bass type then upper voice. Each pair plays overlapping bass and upper notes. The file is format 0, channel 1, 96 PPQN, 120 BPM, 6178 bytes. Copy in binary mode. Regenerate using `python make_split_demo.py` (standard library only).

MIDI byte-stream structure validated: all 27 unique program changes, overlap in every pair, 648 matched note-on/off pairs, max 1 held bass and 3 upper notes; no held notes at patch changes. Real hardware and Z80 execution of this new demo have not been tested.

To convert your own two-part MIDI file, choose zero-based tracks and voices. Example: Electric Bass + Brass:

```
python convert_midi.py INPUT.MID OUTPUT.MID --emt10 --bass 1 --piano 2 --bass-voice 1 --upper-voice 7
```

The existing `--piano` option names the upper-part tracks regardless of chosen voice. The converter folds notes to their respective ranges and limits held notes to the hardware allocation. The old default (Upright Bass + Piano 1) is unchanged. Use the resulting format-0 file with MIDIPLAY.CMD. This converter extension is not yet execution-tested.

## Desktop conversion

Install Python 3 and mido (`python -m pip install mido`). Merge format 1:

```
python convert_midi.py INPUT.MID OUTPUT.MID
```

For a selected bass/piano arrangement, select the correct zero-based tracks:

```
python convert_midi.py INPUT.MID OUTPUT.MID --emt10 --bass 1 --piano 2 3 --basic-data OUTPUT.DAT
```

This maps selected parts to channel 1, the selected Yamaha Bass Split program (default 48, Piano 1 + Upright Bass), limits held notes to two bass and six piano notes, folds pitches across the split as required and omits original sustain automation. It is not general orchestral transcription. Supply your own MIDI files; no copyrighted songs are distributed.

## BASIC player

Transfer NYPLAY.BAS and your generated DAT file as CR-delimited ASCII. In LDOS BASIC, LOAD "NYPLAY/BAS:0" then RUN. Enter 25 or 30 for the actual clock and your data file name. Press Q to stop. BREAK may abort before cleanup. BASIC interprets absolute-millisecond, status, data1, data2 records, with -1 indicating absent data2 or terminal time. It does not parse SMF.

## Native player limits

Format 0, single MTrk, exact six-byte MThd, PPQN only; max track length and each delta/meta length 65,535. Running status, tempo changes, channel messages and end-of-track supported. Other meta events and SysEx skipped. No automatic GM translation. Uses E8–EB UART ports and LDOS TIMER$ at 4288H (25/30 Hz); timing resolution approximately 40/33 ms. No RTS/CTS waiting, no interrupt hooks, no restoration of UART configuration. Requires free RAM 6000H–76E9H. DOS disk latency and dense MIDI affect timing; stalls of 128 or more timer ticks cannot be reliably recovered.

## Status

Previously mock-tested Z80 opcodes against UART, DOS and keyboard stubs. This is not a full emulator or hardware timing test. Actual v0.5 LDOS operation, Nano bridge and Yamaha audio have now been verified by the project owner. v0.7 timing, BASIC and TRSDOS remain unverified on physical hardware.

See the [root README](../README.md) for hardware and [MIT License](../LICENSE).

## Rebuild and run mock tests

From this directory, run `python build.py` followed by `python test_player.py`. The included restricted assembler generates the CMD and symbol map. The harness exercises the actual Z80 opcodes against mock DOS, UART and keyboard calls. See [TESTS.txt](TESTS.txt) for v0.7 mock regression results and [BENCHMARK.txt](BENCHMARK.txt) for controlled-clock comparisons. Optional arrangement tests accept your own format-0 MIDI file paths as arguments. No song data is included.
