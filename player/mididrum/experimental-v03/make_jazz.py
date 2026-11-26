#!/usr/bin/env python3
"""SUNSPARK — original jazz piano and cassette percussion for MIDIDRUM v0.2.
Python standard library. Format 0, 96 PPQN, Yamaha native piano 1 (ch 1),
MIDIDRUM percussion (ch 10). Nominal solo 30–40 s at 144 BPM.
"""
from pathlib import Path
from struct import pack
from collections import Counter
import random
P=96; B=P*4; TEMPO=416667; rng=random.Random(8096)
events=[]
def event(t,msg,order=1): events.append((t,order,bytes(msg)))
def meta(t,k,body): event(t,[255,k,len(body),*body],0)
def note(t,n,d,v,ch=0):
    assert 0<=n<128 and d>0 and 0<v<128
    event(t,[0x90|ch,n,v],3 if ch==0 else 2)
    event(t+d,[0x80|ch,n,0],1)
def chord(t,notes,d,v):
    for i,n in enumerate(notes): note(t+i*2,n,d-i*2,max(1,v+i*2))
def hit(t,n,v=90): note(t,n,9,v,9)
# Chord labels, bass root, compact rootless voicings, melodic pools (MIDI pitches).
H={
'Dmaj9': (38,[54,57,61,64],[66,69,71,73,74,76,78,81]),
'Bm9': (35,[57,61,62,66],[66,69,71,73,74,76,78,81]),
'Em9': (40,[55,59,62,66],[67,69,71,74,76,78,79,81]),
'A13': (45,[55,59,61,66],[66,67,69,71,73,76,78,79]),
'F#m9': (42,[57,61,64,68],[66,68,69,71,73,76,78,80]),
'B13b9':(35,[57,60,63,68],[66,68,69,71,72,75,78,80]),
'Gmaj9':(43,[54,57,59,62],[66,67,69,71,74,76,78,79]),
'Gm9':(43,[53,57,58,62],[65,67,69,70,74,77,79,81]),
'C13':(36,[58,62,64,69],[64,67,69,70,72,74,76,79]),
'C#m7b5':(37,[55,59,61,64],[64,67,69,71,73,76,79,81]),
'F#7alt':(42,[52,58,62,67],[66,67,69,70,72,74,76,79]),
'Bm11':(35,[57,61,64,66],[66,69,71,73,74,76,78,81]),
'Bb13':(34,[56,60,62,67],[65,67,68,70,72,74,77,79]),
'A7alt':(45,[55,58,61,65],[65,67,69,70,73,75,77,79]),
}
# 2-bar pickup, 16-bar head; 6-bar percussion solo; 24-bar reprise/outro.
head=['Dmaj9','A13','Dmaj9','Bm9','Em9','A13','F#m9','B13b9','Em9','A13','Gmaj9','Gm9','F#m9','B13b9','Em9','A13','Dmaj9','A7alt']
reprise=['Dmaj9','Bm9','Em9','A13','F#m9','B13b9','Em9','A13','Gmaj9','Gm9','Dmaj9','Bb13','C#m7b5','F#7alt','Bm11','A13','Dmaj9','Bm9','Em9','A13','Gmaj9','Gm9','A7alt','Dmaj9']
# Swing eighths 0/64, 96/160, etc; percussion avoids simultaneous hits.
patterns=[[(0,36),(64,42),(96,38),(160,75),(192,36),(256,42),(288,38),(352,42)],[(0,36),(64,75),(96,38),(160,42),(192,42),(256,36),(288,38),(352,75)],[(0,36),(64,42),(96,38),(160,76),(192,42),(256,36),(288,38),(352,42)],[(0,36),(64,75),(96,38),(160,42),(192,36),(256,42),(288,38),(352,77)]]
meta(0,3,b'SUNSPARK - modern jazz piano and cassette drums'); meta(0,81,TEMPO.to_bytes(3,'big')); meta(0,88,bytes([4,2,24,8])); meta(0,89,bytes([2,0])); event(0,[0xc0,0]); event(0,[0xb0,64,0]);
# melody: rhythmic cells and contour chosen deliberately, scale/chord pools
rhythms=[[(0,48),(64,25),(96,53),(192,49),(256,26),(288,68)],[(32,26),(64,29),(128,24),(160,51),(256,24),(288,50),(352,23)],[(0,75),(96,48),(160,28),(192,52),(288,80)],[(0,40),(64,25),(96,48),(160,28),(224,25),(256,25),(288,52)],[(32,25),(64,25),(96,50),(192,76),(288,49),(352,22)]]
contours=[[1,2,3,1,0,2],[2,3,5,4,2,1,0],[4,3,2,3,1],[0,2,3,4,5,3,2],[3,2,1,3,5,4]]
def play_bar(bar,name,nextname,section,idx):
    t=bar*B; root,voicing,pool=H[name]; nextroot=H[nextname][0]
    # left hand: walking or buoyant broken bass. Keep all four attacks distinct.
    if section=='intro':
        bass=[(0,root,72),(192,root+7,70)]
    elif section=='coda' and idx==23:
        bass=[(0,root,288)]
    else:
        approach=nextroot+(1 if idx%2 else -1)
        bass=[(0,root,70),(96,root+7,64),(192,root+12,66),(288,approach,60)]
    for at,n,d in bass: note(t+at,n,d,68+rng.randrange(-5,8))
    # Four-note voicings are separate from high melody; no same-note overlap.
    vnotes=[n for n in voicing if n<=68]
    if section=='intro': comps=[(64,105),(256,70)]
    elif section=='coda' and idx==23: comps=[(0,310)]
    else: comps=[[(64,66),(224,42)],[(0,62),(160,27),(288,52)],[(64,27),(160,65),(256,52)],[(32,55),(192,52),(352,20)]][idx%4]
    for at,d in comps: chord(t+at,vnotes,d,62+rng.randrange(-7,9))
    if section=='coda' and idx==23: note(t+6,74,310,79)
    else:
        # Keep the lead in a register that cannot overlap the comping.
        high=[n for n in pool if n>=69]
        rr=(idx+(1 if section=='reprise' else 0))%len(rhythms)
        if section=='intro': rr=2
        for j,(at,d) in enumerate(rhythms[rr]):
            k=contours[rr][j%len(contours[rr])]
            if section=='reprise' and idx%8 in (4,5,6): k+=1
            n=high[k%len(high)]
            note(t+at,n,d,84+rng.randrange(-8,10)+(6 if j==0 else 0))
    if section=='coda' and idx==23:
        for at,n in [(0,36),(96,75),(192,76),(288,75)]:hit(t+at,n,85)
    else:
        for at,n in patterns[idx%4]: hit(t+at,n,85 if n in (36,38) else 66)
for i,name in enumerate(head): play_bar(i,name,head[i+1] if i+1<len(head) else 'Dmaj9','intro' if i<2 else 'head',i)
# Six bars exactly: 24 beats = 10 seconds. No piano events during the break.
# Tom fills, metallic syncopation, chirp call/response and a final drum roll.
solo=[
[(0,36),(64,75),(96,38),(160,42),(192,36),(256,75),(288,38),(352,76)],
[(0,77),(64,42),(96,41),(160,43),(192,45),(256,47),(288,38),(352,75)],
[(0,36),(32,42),(64,75),(96,38),(128,75),(160,42),(192,36),(224,42),(256,75),(288,38),(320,42),(352,75)],
[(0,76),(96,77),(192,75),(256,76),(352,77)],
[(0,36),(64,38),(96,42),(160,75),(192,76),(288,77),(352,42)],
[(0,36),(64,75),(96,38),(160,41),(192,43),(224,45),(256,47),(288,38),(320,38),(352,76)]
]
meta(18*B,6,b'CASSETTE SOLO 30 seconds')
for i,pat in enumerate(solo):
    for at,n in pat: hit((18+i)*B+at,n,93)
meta(24*B,6,b'PIANO RETURNS 40 seconds')
for i,name in enumerate(reprise): play_bar(24+i,name,reprise[i+1] if i+1<len(reprise) else 'Dmaj9','coda' if i>=20 else 'reprise',i)
# Leave a beat of silence after final note-off for the cassette tail.
event(48*B+P,[255,47,0],9)
def vlq(n):
    a=[n&127];n>>=7
    while n:a.append(128|(n&127));n>>=7
    return bytes(reversed(a))
track=bytearray();last=0;active=set();peak=0;counts=Counter()
for t,order,msg in sorted(events):
    if msg[0] in (0x90,0x99):
        key=(msg[0]&15,msg[1]);assert key not in active,(t,key);active.add(key);counts[key[0]]+=1
        if key[0]==0:assert not 18*B<=t<24*B
    elif msg[0] in (0x80,0x89):
        key=(msg[0]&15,msg[1]);assert key in active,(t,key);active.remove(key)
    if 18*B<=t<24*B: assert not any(ch==0 for ch,n in active)
    peak=max(peak,sum(ch==0 for ch,n in active))
    track.extend(vlq(t-last));track.extend(msg);last=t
assert not active and peak<=8 and len(track)<=65535
out=Path(__file__).with_name('SUNSPARK.MID');out.write_bytes(b'MThd'+pack('>IHHH',6,0,1,P)+b'MTrk'+pack('>I',len(track))+track)
print(f'{out.name}: {out.stat().st_size} bytes; {last* TEMPO/P/1e6:.3f}s; piano {counts[0]}, drums {counts[9]}, peak {peak}; solo {18*B*TEMPO/P/1e6:.6f}–{24*B*TEMPO/P/1e6:.6f}s')
