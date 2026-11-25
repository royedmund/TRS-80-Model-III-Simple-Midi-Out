MIDIPLAY v0.7 - TRS-80 Model III / LDOS 5.3.1
Live Yamaha EMT-10 instrument and note display

INSTALL
Transfer MIDIPLAY.CMD as MIDIPLAY/CMD in binary mode. At LDOS Ready:
  MIDIPLAY NYEMT10/MID
Select 2 for 25 Hz or 3 for 30 Hz, according to the actual LDOS timer.
Press BREAK to Exit. Requires normal 64-column mode and free memory
6000H-76E9H. The serial interface and Arduino firmware are unchanged.

DISPLAY
The dashboard is passive and uses fixed video RAM fields. It displays the
last channel-1 Program Change sent (0-127), with all 12 Yamaha single voices,
27 bass split combinations and aliases. Until a Program Change is sent,
the panel setting is unknown. The module must be set to receive channel 1
or OMNI with Program Change reception enabled. Other channels are forwarded
unchanged but not displayed. The display cannot read the EMT-10 panel state.

Held notes are shown in ascending pitch order, C4 = MIDI note 60. Low keys
are notes 0-54, high keys 55-127; these correspond to the bass/upper split
in standard Bass Split mode. In single voice mode the same two pitch ranges
are shown. Up to 12 distinct pitches per range are listed, with + for more.
Chords are displayed as their constituent notes, not inferred chord names.
A Note On of zero velocity is handled as Note Off. Repeated Note On for the
same pitch is represented by one held-key flag. Sustain CC64 state is shown
separately; sustained release tails, transposition, voice stealing and module
settings are not inferred. Lists update at most once per LDOS clock tick
(25/30 Hz); very brief notes between refreshes may not be visible.

MIDI AND EXIT
The program observes completed outgoing channel messages; it does not add,
filter or modify MIDI messages for the display. Original format-0 SMF limits,
SysEx skipping, UART timeout and serial configuration remain as in v0.5.
BREAK completes the current message, sends the existing 192-byte pedal-off /
All Notes Off cleanup if the UART is available, clears display note fields,
closes the file, clears the BREAK latch and returns to LDOS. End-of-file and
UART errors also clear the display. No Arduino firmware changes required.

BUILD AND TEST
  python build.py
  python test_player.py
Optional complete arrangement tests (mido installed):
  python test_player.py /path/to/NYEMT10.MID /path/to/NYPIANO.MID
The 29 standard mock checks passed. In addition, 12 controlled-clock
comparisons against v0.6 passed, including both full arrangements at both
clock rates. See BENCHMARK.txt. Song data is not distributed here.
Mock tests do not model video hardware, UART baud timing or real CPU timing.
No full-system emulator or physical hardware test of v0.7 has been performed.

PERFORMANCE
Timing uses precomputed 4x, 16x and 128x tempo multiples, retaining the
exact fractional phase and scheduled OS ticks. Only dirty note ranges
are redrawn, with trailing stale characters cleared after rendering.
Refresh is no longer polled repeatedly inside the timer busy-wait.
MIDI panic output precedes display cleanup.

Benchmark (requires the v0.6 package extracted separately):
  python benchmark.py /path/to/midiplay_v06 [arrangement.mid ...]
The benchmark advances the simulated timer at each wait deadline,
checks event deadlines against independent integer arithmetic, and
compares all UART bytes and instruction counts with v0.6. The counts
exclude idle spinning and are not cycle-accurate or wall-clock timings.
The original 25/30 Hz timing resolution, 9600 baud throughput and DOS
disk latency limits still apply.

REFERENCES
https://ru.yamaha.com/files/download/other_assets/2/320652/EMT10E.PDF
https://www.trs-80.com/main-internal-rom-model-3-labels-ram.htm
https://www.trs-80.com/main-internal-ports-and-i-o.htm
https://www.trs-80.com/sub-disassem-dos-ldos-m3-sys00.htm
https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out
