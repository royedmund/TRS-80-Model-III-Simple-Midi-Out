#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Generate PIANOBRS.MID, an original EMT-10 test piece (requires mido)."""
from pathlib import Path
import mido

PPQN = 96
BAR = 4 * PPQN
TEMPO = 600000  # 100 BPM
OUT = Path(__file__).with_name('PIANOBRS.MID')
events = []


def event(tick, priority, msg):
    events.append((tick, priority, msg))


def note(tick, pitch, velocity, duration):
    event(tick, 3, mido.Message('note_on', note=pitch, velocity=velocity))
    event(tick + duration, 0, mido.Message('note_off', note=pitch, velocity=0))


def control(tick, cc, value):
    event(tick, 1, mido.Message('control_change', control=cc, value=value))


def voice(tick, program):
    for cc in (64, 66, 67, 123):
        control(tick, cc, 0)
    event(tick, 2, mido.Message('program_change', program=program))


# Original four-bar harmony in C major: C6, Am7, Dm7, G7.
harmony = [(48, (60, 64, 67, 69)), (45, (60, 64, 67, 69)),
           (50, (60, 62, 65, 69)), (43, (59, 62, 65, 67))]
melody = [(72, 76, 79, 81), (76, 72, 69, 67),
          (65, 69, 72, 74), (71, 67, 65, 62)]

for section in range(4):
    piano = section % 2 == 0
    start = section * 4 * BAR
    voice(start, 0 if piano else 7)  # EMT-10 Piano 1 / Brass, not GM
    for bar, (bass, chord) in enumerate(harmony):
        t = start + bar * BAR
        if piano:
            note(t, bass, 65, 160)
            note(t + 192, bass + 7, 72, 144)
            for i, pitch in enumerate(chord + chord[::-1]):
                note(t + i * 48, pitch, 48 + 7 * i, 40)
            if section == 2:
                control(t + 1, 64, 127)
                control(t + 188, 64, 0)
        else:
            for i, pitch in enumerate(melody[bar]):
                note(t + i * 96, pitch, (78, 99, 85, 112)[i], 65)
                if i in (0, 2):
                    for p in chord[:3]:
                        if p == pitch:
                            continue
                        note(t + i * 96, p, 82 + 8 * i, 42)

end = 16 * BAR
for cc in (64, 66, 67, 123):
    control(end, cc, 0)
file = mido.MidiFile(type=0, ticks_per_beat=PPQN)
track = file.add_track('Piano and Brass - original EMT-10 demo')
track.append(mido.MetaMessage('set_tempo', tempo=TEMPO))
last = 0
for tick, _, msg in sorted(events, key=lambda e: e[:2]):
    track.append(msg.copy(time=tick - last))
    last = tick
track.append(mido.MetaMessage('end_of_track', time=end - last))
file.save(OUT)
print(f'{OUT.name}: {OUT.stat().st_size} bytes, {file.length:.1f} seconds')
