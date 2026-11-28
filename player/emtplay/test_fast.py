"""Exercise transport optimisations in the actual patched Z80 image.
Not cycle-accurate; UART readiness controlled by mock, no physical line.
"""
from test_score import CPU,L,midi

def three(c,s,n,v):
    c.m[0x7c3f]=s;c.m[0x7c5d]=n;c.m[0x7c5e]=v
    c.pc=L['GM_THREE'];assert c.run()==0x6118

def two(c,s,n):
    c.m[0x7c3f]=s;c.m[0x7c5d]=n
    c.pc=L['GM_TWO'];assert c.run()==0x6118

for mode in (0,0xfd,0xf9):
    c=CPU();c.m[0x7c39]=mode;c.invoke(L['SCORE_INIT']);c.invoke(L['GM_START']);c.writes.clear()
    two(c,0xc0,6);two(c,0xc0,8)
    three(c,0x90,60,80);three(c,0x90,64,90)
    c.invoke(0x6418) # flush one group in framed transport
    three(c,0x90,67,100);three(c,0x80,60,0);three(c,0x80,64,0)
    expected=[0xc0,6,0xc0,8,0x90,60,80,0x90,64,90]+([0xf8] if mode else [])+[0x90,67,100,0x80,60,0,0x80,64,0]
    c.invoke(0x6418)
    if mode:expected=[0xf2,10]+expected[:10]+[0xf2,9]+expected[11:]
    assert midi(c)==expected,(mode,midi(c))
    # Execute actual native SysEx forwarding through the parser hook.
    c.m[0x7c33:0x7c39]=bytes.fromhex('43 73 11 11 40 f7')
    c.pc=0x6248;assert c.run()==0x6118
    three(c,0x80,67,0)
    c.invoke(0x6418)
    assert midi(c)[-10:]==[0xf0,0x43,0x73,0x11,0x11,0x40,0xf7,0x80,67,0]
    print('PASS status transitions, framed boundaries, SysEx reset, mode',hex(mode))
# First ready, busy then ready, preserve registers and AF (ready path).
for delays in (0,1,12,255):
    c=CPU();c.uart_reads=[False]*delays+[True];c.r[7]=0x93;c.z=True;c.c=True;c.pair(0,0x1234);c.pair(1,0x5678);c.pair(2,0x9abc)
    assert c.invoke(0x65fb)==0xffff
    assert midi(c)==[0x93] and c.polls==delays+1
    assert c.r[7]==0x93 and c.z and c.c and (c.pair(0),c.pair(1),c.pair(2))==(0x1234,0x5678,0x9abc)
print('PASS UART immediate ready and busy retry up to 255 polls; registers preserved')
c=CPU();c.uart=False;c.m[0x7c3e]=1;c.m[0x7c3d]=1;c.r[7]=0x90
assert c.invoke(0x65fb)==0x402d and not midi(c) and c.polls==257 and c.m[0x7c3e]==0
print('PASS bounded UART timeout and clean DOS exit')
# Combined cached get: check exact data, bounds, preserved registers.
c=CPU();base=L['CACHE_BASE'];c.m[L['CACHE_ON']]=1;c.word(L['CACHE_PTR'],base);c.word(0x7c40,3);c.m[base:base+3]=b'abc';c.pair(0,0x1234);c.pair(1,0x5678);c.pair(2,0x9abc)
for b in b'abc':
    assert c.invoke(0x63e6)==0xffff and c.r[7]==b
    assert (c.pair(0),c.pair(1),c.pair(2))==(0x1234,0x5678,0x9abc)
assert c.word(0x7c40)==0 and c.word(L['CACHE_PTR'])==base+3
assert c.invoke(0x63e6)==0x402d and c.word(L['CACHE_PTR'])==base+3
print('PASS combined cached get register preservation, exact end boundary')
c=CPU();c.word(0x7c40,1);c.extra_stops={0x805a};assert c.invoke(0x63e6)==0x805a and c.word(0x7c40)==0
print('PASS streaming fallback to original SD reader')
# GM output preserves full MIDI statuses, notes and velocities.
c=CPU();c.m[L['GM_MODE']]=2;c.m[L['UPPER_CH']]=2;c.m[L['BASS_CH']]=4;c.m[L['SPLIT_MODE']]=1;c.m[L['SELECTED_PATCH']]=70;c.m[0x7c39]=0xfd
c.invoke(L['SCORE_INIT']);c.invoke(L['GM_START']);three(c,0x92,60,90);three(c,0x94,40,100);three(c,0x92,64,85);three(c,0x82,60,0);three(c,0x84,40,0);three(c,0x82,64,0)
c.invoke(0x6418)
assert midi(c)==[0xf6,25,0xf2,20,0xc0,70,0x90,60,90,0x90,40,100,0x90,64,85,0x80,60,0,0x80,40,0,0x80,64,0],midi(c)
print('PASS GM buffered explicit status, split voices and cleanup state')
