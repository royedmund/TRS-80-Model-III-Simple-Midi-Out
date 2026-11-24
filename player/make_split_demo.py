#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Original EMT-10 two-voice demo. Python 3, standard library only."""
from pathlib import Path
import struct

def vlq(n):
    out = [n & 127]
    while n >= 128:
        n >>= 7
        out.insert(0, (n & 127) | 128)
    return bytes(out)

def make():
    track = bytearray()
    def event(delta, *data):
        track.extend(vlq(delta))
        track.extend(data)
    event(0, 0xff, 0x51, 3, 7, 161, 32)  # 120 BPM
    # Each combination gets 2 bars (4 seconds), with actual overlapping voices.
    for bass in range(3):
        for upper in range(9):
            for cc in (64, 66, 67, 123):
                event(0, 0xb0, cc, 0)
            event(0, 0xc0, 48 + 16 * bass + upper)
            for root, chord in ((36, (60,64,67)), (43, (59,62,67)),
                                (45, (60,64,69)), (41, (60,65,69))):
                event(0, 0x90, root, 88)
                for n in chord:
                    event(0, 0x90, n, 76)
                for j,n in enumerate(chord):
                    event(72 if j == 0 else 0, 0x80, n, 0)
                event(0, 0x80, root, 0)
                event(24, 0x90, root + 7, 70)
                event(0, 0x90, chord[-1] + 12, 96)
                event(72, 0x80, root + 7, 0)
                event(0, 0x80, chord[-1] + 12, 0)
                # 24 ticks of silence before the next beat pair.
                event(24, 0xff, 1, 0)
    for cc in (64, 66, 67, 123):
        event(0, 0xb0, cc, 0)
    event(0, 0xff, 0x2f, 0)
    return b'MThd' + struct.pack('>IHHH', 6, 0, 1, 96) + b'MTrk' + struct.pack('>I', len(track)) + track

if __name__ == '__main__':
    p = Path(__file__).with_name('SPLIT27.MID')
    p.write_bytes(make())
    print(f'{p.name}: {p.stat().st_size} bytes, 108 seconds, 27 combinations')
