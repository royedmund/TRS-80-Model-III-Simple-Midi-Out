"""Original short score demo, standard-library format 0 MIDI writer."""
from pathlib import Path
import struct

def vlq(n):
    r=[n&127];n>>=7
    while n:r.append(128|(n&127));n>>=7
    return bytes(reversed(r))
events=[(0,0,b'\xff\x51\x03\x09\x27\xc0'),(0,1,bytes([0xc0,6]))]
for bar,(bass,chord,melody) in enumerate([
    (45,[57,60,64],[69,72,76,72]),(41,[53,57,60],[69,65,72,69]),
    (48,[55,60,64],[67,72,76,74]),(43,[55,59,62],[71,74,67,71]),
    (45,[57,60,64],[69,72,76,79]),(41,[53,57,60],[77,76,72,69]),
    (43,[55,59,62],[71,74,71,67]),(45,[57,60,64],[69,64,60,57])]):
    t=bar*384
    for n in [bass]+chord:
        events.extend([(t,2,bytes([0x90,n,65])),(t+368,0,bytes([0x80,n,0]))])
    for k,n in enumerate(melody):
        events.extend([(t+k*96,3,bytes([0x90,n,88])),(t+k*96+72,0,bytes([0x80,n,0]))])
events.append((8*384+96,0,b'\xff\x2f\x00'))
track=bytearray();last=0
for t,_,b in sorted(events):track+=vlq(t-last)+b;last=t
out=b'MThd'+struct.pack('>IHHH',6,0,1,96)+b'MTrk'+struct.pack('>I',len(track))+track
Path(__file__).with_name('SCORETST.MID').write_bytes(out)
