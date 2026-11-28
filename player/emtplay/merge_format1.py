"""Optional desktop utility: merge synchronous SMF format 1 to format 0.
Install mido with python -m pip install mido. Does not remap instruments;
EMTPLAY performs that on the TRS-80. Reject unsupported size or SMPTE."""
import sys
from pathlib import Path
import mido
if len(sys.argv)!=3:
    raise SystemExit('Usage: python merge_format1.py input.mid output.mid')
src,dst=map(Path,sys.argv[1:]);mf=mido.MidiFile(src)
if mf.type not in (0,1) or not 1<=mf.ticks_per_beat<=32767:
    raise SystemExit('Only synchronous PPQN format 0/1 supported')
out=mido.MidiFile(type=0,ticks_per_beat=mf.ticks_per_beat)
merged=mido.merge_tracks(mf.tracks)
for msg in merged:
    if not 0<=msg.time<=65535:
        raise SystemExit('Delta exceeds EMTPLAY limit of 65535 ticks')
out.tracks.append(merged)
import io
b=io.BytesIO();out.save(file=b);data=b.getvalue()
if data[14:18]!=b'MTrk' or int.from_bytes(data[18:22],'big')>65535:
    raise SystemExit('Merged track exceeds EMTPLAY 65535-byte limit')
dst.write_bytes(data)
print('Wrote',dst,len(data),'bytes')
