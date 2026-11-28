"""Run assembled GM hooks and cache checks in existing restricted Z80 model."""
from test_score import CPU,L,midi
from make_gm_tables import MAP

def msg(c,status,n,v=None):
    c.m[0x7c3f]=status;c.m[0x7c5d]=n
    if v is not None:c.m[0x7c5e]=v
    c.pc=L['GM_TWO' if v is None else 'GM_THREE']
    assert c.run()==0x6118

def scan_fixture(c):
    c.m[L['GM_MODE']]=1
    for ch,prog,num in [(2,48,8),(4,33,5),(9,0,50),(0,0,2)]:
        msg(c,0xc0+ch,prog)
        for n in range(num):msg(c,0x90+ch,40+n,90)
        msg(c,0x90+ch,60,0)
    assert midi(c)==[]
    assert c.invoke(L['CHOOSE_VOICES'])==0xffff
    assert c.m[L['UPPER_CH']]==2 and c.m[L['BASS_CH']]==4
    assert c.m[L['SELECTED_PATCH']]==70 # 48+16+6
    assert c.m[L['SPLIT_MODE']]==1

c=CPU();scan_fixture(c);print('PASS scan silence, program mapping, percussion exclusion and electric bass + strings selection')
assert len(MAP)==128 and max(MAP)<=11
# Send selected native patch in raw mode, then note events from selected channels.
c.m[L['GM_MODE']]=2;c.invoke(L['SCORE_INIT']);assert c.invoke(L['GM_START'])==0xffff
assert midi(c)==[0xc0,70]
assert c.m[0x3c40:0x3c50].rstrip()==b'GM AUTO ARRANGE'
assert c.m[0x3c88:0x3cb0].rstrip()==b'ELECTRIC BASS + STRINGS'
msg(c,0x92,48,88);msg(c,0x94,60,90);msg(c,0x99,38,100);msg(c,0x90,64,100)
assert midi(c)==[0xc0,70,0x90,60,88,0x90,48,90,0x90,64,100],midi(c)
msg(c,0x82,48,0);msg(c,0x94,60,0)
assert midi(c)[-6:]==[0x80,60,0,0x80,48,0]
msg(c,0x80,64,0)
assert not any(c.m[0x7831:0x78b1]);assert c.m[0x3d00:0x3d02]==b'C4' and c.m[0x3e80:0x3e82]==b'C3';print('PASS GM multichannel mix, octave split, matching note-offs and score state')
# Cap at 6 upper and 2 bass; reject folded collision; ignored offs not transmitted.
c.writes.clear()
for n in range(60,69):msg(c,0x92,n,90)
for n in (36,37,38):msg(c,0x94,n,90)
assert c.m[L['UPPER_HELD']]==6 and c.m[L['BASS_HELD']]==2
assert len(midi(c))==24
msg(c,0x82,66,0);msg(c,0x84,38,0);msg(c,0x92,48,90);assert len(midi(c))==24
for n in range(60,69):msg(c,0x82,n,0)
msg(c,0x82,48,0)
for n in (36,37,38):msg(c,0x84,n,0)
assert len(midi(c))==48 and not any(c.m[0x7831:0x78b1]);print('PASS 6+2 budget, merged folded unisons, unmatched off suppression')
# Single voice fallback.
c=CPU();c.m[L['GM_MODE']]=1;msg(c,0xc1,32)
for n in range(3):msg(c,0x91,40+n,90)
c.invoke(L['CHOOSE_VOICES']);assert c.m[L['SELECTED_PATCH']]==9 and c.m[L['UPPER_CH']]==1 and c.m[L['SPLIT_MODE']]==0
print('PASS bass-only fallback')
# Cache eligibility boundary. Stub at start of actual copy (original SD reader mocked separately).
base=L['CACHE_BASE']; print('Cache starts',hex(base))
for high,sp,size,expected in [(0xffff,0x525b,0x1000,True),(base+255,0x525b,256,True),(base+254,0x525b,256,False),(0xffff,0xf000,0x7000,False),(0xffff,0xf000,0x1000,True),(0xffff,0xf000,0x8000,False),(0xffff,0xf000,0,False),(0xffff,base+100,50,False)]:
    c=CPU();c.word(0x4411,high);c.word(0x7c3b,sp);c.word(0x7c40,size);c.extra_stops={L['CACHE_FIT']}
    assert (c.invoke(L['CACHE_LOAD'])==L['CACHE_FIT'])==expected,(high,sp,size)
print('PASS cache boundaries, resident HIGH$, stack guard and address wrap')
c=CPU();c.m[L['CACHE_ON']]=1;c.word(L['CACHE_PTR'],base);c.m[base:base+3]=b'abc';c.pair(0,0x1234);c.pair(1,0x5678);c.pair(2,0x9abc)
for b in b'abc':
    assert c.invoke(L['CACHE_RAWGET'])==0xffff and c.r[7]==b
    assert (c.pair(0),c.pair(1),c.pair(2))==(0x1234,0x5678,0x9abc)
assert c.word(L['CACHE_PTR'])==base+3
print('PASS cache reader pointer and register preservation')
# EOT scan must rewind without output and return to original clock menu.
c=CPU();scan_fixture(c);c.m[L['CACHE_ON']]=1;c.word(L['CACHE_SIZE'],321);c.pair(2,0);c.extra_stops={0x607d};c.pc=L['GM_END'];assert c.run()==0x607d
assert c.word(L['CACHE_PTR'])==base and c.word(0x7c40)==321 and c.m[L['GM_MODE']]==2 and midi(c)==[]
print('PASS scan EOT cache rewind, no MIDI before playback')
# Actual original SMF event parser, using cached input, not direct hook calls.
# Delta 128, tempo, running status, native whitelisted SysEx, ignored GM drums.
track=bytes.fromhex('00 ff 51 03 07 a1 20 00 c2 30 00 c4 21 00 92 3c 50 81 00 40 55 00 94 30 50 00 99 24 7f 00 f0 06 43 73 11 11 40 f7 00 ff 2f 00')
c=CPU();c.m[L['GM_MODE']]=1;c.m[L['CACHE_ON']]=1;c.word(L['CACHE_PTR'],base);c.word(L['CACHE_SIZE'],len(track));c.word(0x7c40,len(track));c.m[base:base+len(track)]=track;c.extra_stops={0x607d}
for i in range(8):
    c.pc=0x611e;assert c.run()==0x6118,(i,hex(c.pc))
c.pc=0x611e;assert c.run()==0x607d
assert c.m[L['SELECTED_PATCH']]==70 and not midi(c) and c.word(L['CACHE_PTR'])==base
print('PASS actual parser scan: variable delta, tempo, running status, Yamaha SysEx suppressed, EOT rewind')
