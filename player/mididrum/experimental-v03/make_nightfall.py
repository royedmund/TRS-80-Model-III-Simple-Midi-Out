#!/usr/bin/env python3
"""NIGHTFALL: original dark alternative rock for MIDIDRUM v0.2 + EMT-10.
No external dependencies. Native Yamaha program 0 / 8, MIDI channel 1;
channel 10 exclusively for the cassette engine. Format 0, 96 PPQN.
"""
from pathlib import Path
from struct import pack
from collections import Counter
P=96; B=384; ev=[]
def add(t,d,p=1): ev.append((t,p,len(ev),bytes(d)))
def note(t,n,v,d,ch=0):
    assert 0<=n<=127 and 0<v<128 and d>0
    add(t,[0x90|ch,n,v],4 if ch==9 else 3);add(t+d,[0x80|ch,n,0],0)
def chord(t,ns,v,d,spread=0):
    for i,n in enumerate(ns):note(t+i*spread,n,v-i*3,d-i*spread)
def meta(t,k,d,p=-1):add(t,[255,k,len(d),*d],p)
def tempo(t,bpm):meta(t,81,round(60_000_000/bpm).to_bytes(3,'big'),-3)
def vlq(n):
    a=[n&127];n>>=7
    while n:a.insert(0,128|(n&127));n>>=7
    return bytes(a)
# root, inner piano dyad, upper ostinato/melody, choir voicing.
# Bass, middle and high voices occupy separate registers to avoid overlaps.
H={
 'Em9': (40,[55,62],[66,67,71,74],[52,55,59,62,66]),
 'Cmaj7':(36,[55,60],[64,67,71,74],[48,55,59,64,67]),
 'Gmaj7':(43,[54,59],[66,67,71,74],[50,55,59,62,66]),
 'Dadd9':(38,[54,57],[64,66,69,76],[50,54,57,64,69]),
 'Am9': (45,[55,60],[64,67,71,72],[48,55,57,60,71]),
 'Fmaj7':(41,[57,60],[64,65,69,72],[53,57,60,64,69]),
 'B7b9':(35,[57,63],[66,69,72,75],[47,54,57,63,72]),
 'Em/D':(38,[55,59],[64,66,67,71],[50,55,59,64,66]),
}
sections=[
 (0,'I. DISTANT SIGNAL',132,0,['Em9','Em9','Cmaj7','Cmaj7','Am9','Am9','Fmaj7','B7b9'],'intro'),
 (8,'II. BELOW THE SURFACE',140,0,['Em9','Cmaj7','Gmaj7','Dadd9','Em9','Cmaj7','Am9','B7b9'],'verse'),
 (16,'III. SHADOW CHOIR',134,8,['Em9','Em/D','Cmaj7','Cmaj7','Am9','Fmaj7','B7b9','Em9'],'choir'),
 (24,'IV. BLACK TIDE',148,0,['Em9','Cmaj7','Gmaj7','Dadd9','Em9','Cmaj7','Fmaj7','B7b9'],'climax'),
 (32,'V. THE HOLLOW SKY',138,8,['Em9','Cmaj7','Am9','Fmaj7','Em/D','Cmaj7','B7b9','B7b9'],'choir2'),
 (40,'VI. LAST LIGHT',136,0,['Em9','Cmaj7','Am9','Fmaj7','Em9','Em/D','B7b9','Em9'],'outro'),
]
meta(0,3,b'NIGHTFALL - EMT10 + CASSETTE',-4);meta(0,88,bytes([4,2,24,8]),-4)
add(0,[0xb0,64,0],1)
for start,label,bpm,program,prog,style in sections:
    t0=start*B;tempo(t0,bpm);meta(t0,6,label.encode());add(t0,[0xc0,program],2)
    for j,key in enumerate(prog):
        bar=start+j;t=bar*B;root,inner,top,voices=H[key];last=j==7
        if program==0:
            if style=='intro':
                note(t,root,68+j*2,330 if not last else 300)
                chord(t+48,inner,61+j,240,5)
                motif=[0,2,1,3] if j%2==0 else [2,1,0,2]
                for off,k in zip((0,96,192,288),motif):note(t+off,top[k],76+(off==0)*8,74 if off<288 else 54)
                if j>=4:note(t+144,top[0]+12,58,110)
            elif style in ('verse','climax'):
                strong=style=='climax';base=95 if strong else 79
                # Sustained root and octave pulse, inner chords, independent upper line.
                note(t,root,base,166);note(t+192,root,base-5,164 if not last else 134)
                if strong:
                    note(t,root-12,base-4,134);note(t+192,root-12,base-8,120)
                else:note(t+144,root-12,base-8,42)
                chord(t+24,inner,base-12,142,4);chord(t+216,inner,base-9,128 if not last else 96,4)
                motif=[0,2,1,2,3,2,1,0] if j%2==0 else [2,1,0,2,1,3,2,1]
                for i,k in enumerate(motif):
                    pitch=top[k];off=i*48
                    note(t+off,pitch,base+(i in (0,4))*8-(i%3)*4,37 if i<7 else 25)
                # Long octave counter-melody above the right-hand riff.
                if strong:
                    note(t+48,top[2]+12,79,120);note(t+240,top[0]+24,75,104 if not last else 74)
                elif j%2==1:note(t+96,top[3]+12,61,154)
            else:
                fade=8*j;v=max(53,92-fade//2)
                note(t,root,v-8,318);chord(t+48,inner,v-12,256,5)
                for off,k in zip((0,72,144,240,312),[2,1,0,2,3] if j%2==0 else [0,1,2,1,0]):note(t+off,top[k],v-(off%3),46)
                if j<4:note(t+96,top[2]+12,v-18,120)
        else:
            # Choir: staggered entries and a shifting top voice over a dark pad.
            # Six held notes max, no simultaneous piano / choir patch assumption.
            v=78 if style=='choir' else 88
            if key=='B7b9':v+=4
            chord(t,voices[:4],v,340 if not last else 300,5)
            note(t+24,voices[4],v-4,146)
            high=voices[4]+(1 if key in ('B7b9','Fmaj7') else 2)
            note(t+192,high,v+2,138 if not last else 96)
            if style=='choir2':note(t+96,voices[4]+12,v-13,178)
            elif j in (2,5):note(t+96,voices[4]+12,v-15,160)
        # Sparse monophonic percussion with separate slots for longer eerie FX.
        if style=='intro':
            pat=[(0,36),(144,75),(240,78),(336,77)] if j%2==0 else [(0,36),(96,42),(192,38),(288,76)]
            if j>=4:pat=[(0,36),(48,42),(96,38),(168,75),(192,36),(264,42),(288,38),(336,78)]
        elif style=='verse':
            pat=[(0,36),(48,42),(96,38),(144,75),(192,36),(240,42),(288,38),(336,42 if j%2==0 else 77)]
        elif style=='climax':
            pat=[(0,36),(48,42),(96,38),(144,75),(192,36),(240,36),(288,38),(336,78 if j%2 else 76)]
            if j%4==2:pat.extend([(72,42),(264,75)])
        elif style=='choir':
            pat=[(0,36),(96,75),(168,78),(240,42),(288,38),(336,77)] if j%2==0 else [(0,36),(96,38),(192,79),(288,75),(336,76)]
        elif style=='choir2':
            pat=[(0,36),(72,75),(144,78),(192,36),(288,38),(336,77 if j%2 else 76)]
        else:
            pat=[(0,36),(96,38),(192,75),(288,78)] if j<4 else [(0,36),(144,75),(240,77)]
            if j==7:pat=[(0,36),(192,78)]
        if last and style!='outro':pat=[(o,n) for o,n in pat if o<336]+[(336,79)]
        for off,n in sorted(pat):note(t+off,n,110 if n==36 else 91,12,9)
# Four-beat final resolving chord with a second sparse echo and extended silence.
t=48*B;tempo(t,128);meta(t,6,b'CODA - SIGNAL LOST');chord(t,[40,52,55,59,62,66],73,300,6)
note(t,36,96,12,9);note(t+192,77,82,12,9);note(t+384,78,79,12,9);note(t+480,75,70,12,9)
add(t+600,[0xb0,64,0]);meta(t+768,47,b'',9)
# Validate logical notes, polyphony, channel routing and maximum hit density.
active={0:set(),9:set()};peak=0;stats=Counter();last_hit=None;prev=0;track=bytearray();us=0;mpq=500000
for tick,_,__,msg in sorted(ev):
    us+=(tick-prev)*mpq/P;track+=vlq(tick-prev)+msg;prev=tick
    s=msg[0]
    if s==255 and msg[1]==81:mpq=int.from_bytes(msg[3:],'big')
    if s==192:assert not active[0],(tick,'voice change',active[0]);stats['patches']+=1
    if s in (144,153):
        ch=s&15;n=msg[1];assert n not in active[ch],(tick,n,ch)
        active[ch].add(n);stats['melody' if ch==0 else 'drums']+=1
        if ch==0:peak=max(peak,len(active[0]))
        else:
            assert len(active[9])==1 and (last_hit is None or tick-last_hit>=24);last_hit=tick
    if s in (128,137):active[s&15].remove(msg[1])
assert not active[0] and not active[9] and peak<=6 and len(track)<65536
out=Path(__file__).with_name('NIGHTFAL.MID');out.write_bytes(b'MThd'+pack('>IHHH',6,0,1,P)+b'MTrk'+pack('>I',len(track))+track)
print(out.name,out.stat().st_size,'bytes',f'{us/1e6:.2f} sec',dict(stats),'peak held notes',peak)
