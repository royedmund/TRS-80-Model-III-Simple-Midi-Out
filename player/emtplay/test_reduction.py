"""Instruction-level regression for missing accompaniment and timing arithmetic."""
from test_score import CPU,L,midi

def event(c,s,n,v=None):
    c.m[0x7c3f]=s;c.m[0x7c5d]=n
    if v is not None:c.m[0x7c5e]=v
    c.pc=L['GM_TWO' if v is None else 'GM_THREE'];assert c.run()==0x6118

def fixture(piano=False):
    c=CPU();c.m[L['GM_MODE']]=1;c.m[L['FORCE_PIANO']]=int(piano)
    for ch,pg,n in [(0,24,9),(1,0,8),(2,33,4),(9,0,30)]:
        event(c,0xc0+ch,pg)
        for i in range(n):event(c,0x90+ch,60+i,90)
    c.invoke(L['CHOOSE_VOICES']);assert c.m[L['UPPER_CH']]==0 and c.m[L['BASS_CH']]==2
    assert c.m[L['SELECTED_PATCH']]==(64 if piano else 69)
    c.m[L['GM_MODE']]=2;c.invoke(L['SCORE_INIT']);c.invoke(L['GM_START']);c.writes.clear();return c
c=fixture(True)
event(c,0x91,64,80);event(c,0x91,67,70);event(c,0x90,64,100)
assert midi(c)==[0x90,64,80,0x90,67,70]
event(c,0x81,64,0);assert len(midi(c))==6
event(c,0x80,64,0);assert midi(c)[-3:]==[0x80,64,0]
event(c,0x81,67,0);assert c.m[L['UPPER_HELD']]==0
print('PASS Piano Reduction, secondary accompaniment, overlapping unison held until final release')
c=fixture();
for n in range(60,67):event(c,0x91,n,80)
assert c.m[L['UPPER_HELD']]==4
for n in (72,74,76):event(c,0x90,n,100)
assert c.m[L['UPPER_HELD']]==6
for n in (36,40,43):event(c,0x92,n,90)
assert c.m[L['BASS_HELD']]==2
for n in range(60,67):event(c,0x81,n,0)
for n in (72,74,76):event(c,0x80,n,0)
for n in (36,40,43):event(c,0x82,n,0)
assert not any(c.m[0x7831:0x78b1]);assert c.m[L['UPPER_HELD']]==c.m[L['BASS_HELD']]==0
print('PASS primary note reservation, 6+2 budget, source-channel releases')
# Real baseline 32-bit timing code under a synthetic LDOS timer that advances
# on read: checks tick count and fractional phase, not real CPU/wire timing.
for rate,mode in [(40000,0xfd),(33333,0xf9)]:
    c=CPU();c.auto_clock=True;c.m[0x7c39]=mode;c.word(0x7c44,96*rate &65535);c.word(0x7c46,(96*rate)>>16)
    elapsed=0
    for tempo,deltas in [(500000,[1,95,96,192,384]),(333333,[96,64,128,1,7]),(777777,[127,128,129,480])]:
        c.word(0x7c4c,tempo&65535);c.word(0x7c4e,tempo>>16);assert c.invoke(0x62ac)==0xffff
        for d in deltas:
            c.pair(0,d);assert c.invoke(0x6316)==0xffff;elapsed+=d*tempo
            expected=elapsed//(96*rate);phase=elapsed%(96*rate)
            assert midi(c)==[0xf2,0]*expected,(d,tempo,rate,len(midi(c))//2,expected)
            assert c.word(0x7c48)+(c.word(0x7c4a)<<16)==phase
    print('PASS real timing arithmetic, tempo changes and timer wrap model',rate,'us/tick')
