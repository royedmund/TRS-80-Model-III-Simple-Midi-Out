"""Original GM arrangement for the new scanner: strings, electric bass, drums,
and a sparse piano part. No dependencies; writes format 0 at 96 PPQN."""
from pathlib import Path
import struct

def vlq(n):
    out=[n&127];n>>=7
    while n:out.append(128|(n&127));n>>=7
    return bytes(reversed(out))
events=[(0,0,b'\xff\x51\x03\x09\x27\xc0'),(0,1,b'\xc0\x30'),(0,1,b'\xc1\x21'),(0,1,b'\xc2\x00')]
def note(t,d,ch,p,v):
    events.append((t,3,bytes([0x90|ch,p,v])))
    events.append((t+d,2,bytes([0x80|ch,p,0])))
chords=[(45,[57,60,64],[69,72,76,72]),(41,[57,60,65],[69,65,72,69]),(48,[55,60,64],[67,72,76,74]),(43,[55,59,62],[71,74,67,71])]
for i in range(16):
    bass,upper,melody=chords[i%4];t=i*384
    for n in upper:note(t,364,0,n,62)
    for k,n in enumerate(melody):note(t+k*96,78,0,n,88)
    for k,n in enumerate([bass,bass+12,bass,bass+7]):note(t+k*96,80,1,n,78)
    if i%2==0:note(t+192,80,2,84,65)
    for k in range(4):note(t+k*96,24,9,36 if k%2==0 else 38,75)
events.append((16*384+96,0,b'\xff\x2f\x00'))
track=bytearray();last=0
for t,_,b in sorted(events):track+=vlq(t-last)+b;last=t
out=b'MThd'+struct.pack('>IHHH',6,0,1,96)+b'MTrk'+struct.pack('>I',len(track))+track
Path(__file__).with_name('GMDEMO.MID').write_bytes(out)
