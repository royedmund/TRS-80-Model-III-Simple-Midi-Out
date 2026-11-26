#!/usr/bin/env python3
"""GHOSTWIRE: original alt-rock demo for a single EMT-10 + MIDIDRUM.
Format 0; 96 PPQN; channel 1 native Yamaha programs; channel 10 local FX.
No third-party libraries needed. All times are integer MIDI ticks.
"""
from pathlib import Path
from struct import pack
from collections import Counter
P=96; BAR=384; events=[]
def add(t,data,order=1): events.append((t,order,len(events),bytes(data)))
def note(t,ch,n,v,d):
    add(t,[0x90|ch,n,v],3); add(t+d,[0x80|ch,n,0],0)
def chord(t,notes,v,d):
    for i,n in enumerate(dict.fromkeys(notes)): note(t,0,n,max(1,v-i*3),d)
def tempo(bar,bpm): add(bar*BAR,[0xff,0x51,3,*round(60000000/bpm).to_bytes(3,'big')],-2)
def marker(bar,text):
    data=text.encode('ascii'); add(bar*BAR,[0xff,6,len(data),*data],-1)
def patch(bar,program): add(bar*BAR,[0xc0,program],2)
def hit(t,n,v,d=12): note(t,9,n,v,d)
def vlq(n):
    b=[n&127]; n>>=7
    while n: b.insert(0,128|(n&127)); n>>=7
    return bytes(b)
# E minor, borrowed F major and B7; dark chromatic alternation.
# (bass root, chord voicing, riff intervals above root in the upper octave)
H={
 'Em':(40,[59,64,67],[12,19,24,15,19,18,19,24]),
 'C': (36,[60,64,67],[24,19,28,24,19,26,28,31]),
 'G': (43,[59,62,67],[12,19,24,16,19,21,24,19]),
 'D': (38,[57,62,66],[24,19,28,24,19,27,28,26]),
 'F': (41,[57,60,65],[12,19,24,16,19,18,19,24]),
 'B': (35,[57,63,66],[24,19,28,24,27,29,28,24]),
 'Am':(45,[57,60,64],[12,19,24,15,19,21,24,19]),
}
sections=[(0,'STATIC / INTRO',164,0,['Em','Em','F','B']),
 (4,'VERSE / BROKEN SIGNAL',172,0,['Em','C','Em','F','Em','C','Am','B']),
 (12,'CHORUS / GHOSTWIRE',176,0,['Em','C','G','D','Em','C','F','B']),
 (20,'CHOIR / DEAD FREQUENCY',156,8,['Em','F','C','B']),
 (24,'PIANO / RETURN OF THE SIGNAL',174,0,['Em','C','Em','F','Em','C','Am','B']),
 (32,'CHOIR / TRANSMISSION',168,8,['Em','C','F','B']),
 (36,'FINAL CHORUS / OUT',180,0,['Em','C','B','Em'])]
name=b'GHOSTWIRE - EMT10 + CASSETTE';add(0,[0xff,3,len(name),*name],-3)
add(0,[0xff,0x58,4,4,2,24,8],-3);add(0,[0xb0,64,0],1)
for start,label,bpm,program,progression in sections:
    tempo(start,bpm);marker(start,label);patch(start,program)
    for j,key in enumerate(progression):
        bar=start+j; t=bar*BAR; root,voicing,riff=H[key]
        if program==8:
            # Slow choir harmonic stabs/suspensions over the accelerated rhythm.
            chord(t,[root+12,*voicing],78 if bar<32 else 94,160)
            tension=voicing[-1]+(1 if key in ('F','B') else 2)
            chord(t+192,[root+12,voicing[0],voicing[1],tension],88,150)
            if j==3: note(t+348,0,voicing[1]+12,72,16)
        else:
            chorus=12<=bar<20 or bar>=36
            # Left-hand power octaves and a syncopated, high right-hand motif.
            for slot in [0,3,4,6]:
                u=t+slot*48; d=32 if slot!=6 else 44
                chord(u,[root-12,root],(105 if chorus else 92)-(slot%2)*9,d)
            for i,interval in enumerate(riff):
                u=t+i*48; pitch=root+interval
                if chorus and i in (0,2,4,6):
                    chord(u,[pitch, pitch+12] if i in (0,4) else [pitch,voicing[1]+12],106-(i%3)*5,32)
                elif i in (2,6): chord(u,voicing,88 if not chorus else 100,30)
                else: note(u,0,pitch+12 if chorus and i%2 else pitch,83+(i%3)*6,30)
            if j==len(progression)-1:
                # Chromatic pickup, released before the next program change.
                note(t+360,0,87 if key=='B' else 88,95,8)
        # One percussion hit per eighth note; intentionally monophonic.
        pattern=[36,42,38,42,36,42,38,42]
        if bar<4: pattern=[36,75,38,76,36,42,38,77]
        elif program==8: pattern=[36,78,38,75,36,76,38,77]
        elif chorus: pattern=[36,42,38,75,36,36,38,42]
        if j==len(progression)-1: pattern[-2:]=[77,78]
        elif j%4==2: pattern[3]=76;pattern[7]=79
        for i,n in enumerate(pattern): hit(t+i*48,n,112 if i in (0,2,4,6) else 83,14)
# Final sting, let the last drum decay and leave silence before EOT.
t=40*BAR; chord(t,[40,52,59,64,67],115,128);hit(t,36,127);hit(t+96,78,108)
add(t+192,[0xb0,64,0],1);add(t+288,[0xff,0x2f,0],9)
track=bytearray();last=0
for time,_,__,data in sorted(events):
    track+=vlq(time-last)+data;last=time
assert len(track)<65536
out=Path(__file__).with_name('GHSTWIRE.MID');out.write_bytes(b'MThd'+pack('>IHHH',6,0,1,P)+b'MTrk'+pack('>I',len(track))+track)
print(out.name,len(track)+22,'bytes',len(events),'events')
