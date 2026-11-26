#!/usr/bin/env python3
"""Targeted Z80 opcode harness for assembled routing and cassette routines.
Not a full emulator: file input and display are stubbed; timer is controlled.
"""
from pathlib import Path
from collections import deque, Counter
import struct
ROOT=Path(__file__).resolve().parent
SY={name:int(addr,16) for addr,name in (x.split() for x in (ROOT/'MIDIDRUM.MAP').read_text().splitlines())}
cmd=(ROOT/'MIDIDRUM.CMD').read_bytes(); image=bytearray(65536);i=0
while cmd[i]==1:
    n=cmd[i+1] or 256;a=int.from_bytes(cmd[i+2:i+4],'little');image[a:a+n-2]=cmd[i+4:i+n+2];i+=n+2
assert cmd[i:]==bytes([2,2,0,0x60]);
class CPU:
    def __init__(self):
        self.m=image.copy();self.r=[0]*8;self.sp=0xff00;self.pc=0;self.z=self.c=self.s=False;self.out=[];self.tx=[];self.input=deque();self.calls=Counter();self.uart=deque();self.steps=0
    def byte(self):v=self.m[self.pc];self.pc+=1;return v
    def word(self):return self.byte()+256*self.byte()
    def pair(self,k):return self.sp if k==3 else self.r[k*2]*256+self.r[k*2+1]
    def setpair(self,k,v):
        v&=65535
        if k==3:self.sp=v
        else:self.r[k*2]=v>>8;self.r[k*2+1]=v&255
    def read(self,k):return self.m[self.pair(2)] if k==6 else self.r[k]
    def write(self,k,v):
        if k==6:self.m[self.pair(2)]=v&255
        else:self.r[k]=v&255
    def push(self,v):self.sp-=2;self.m[self.sp:self.sp+2]=v.to_bytes(2,'little')
    def pop(self):v=int.from_bytes(self.m[self.sp:self.sp+2],'little');self.sp+=2;return v
    def flag(self,v):self.z=(v&255)==0;self.s=bool(v&128)
    def cond(self,k):return [not self.z,self.z,not self.c,self.c,True,False,not self.s,self.s][k]
    def poke(self,n,v):self.m[SY[n]]=v
    def peek(self,n):return self.m[SY[n]]
    def run(self,label,until=None,limit=100000,stubs=False):
        self.pc=SY[label];self.push(0xffff);steps=0
        while self.pc!=0xffff:
            if steps and until and self.pc==SY[until]:self.pop();return
            steps+=1;self.steps+=1;assert steps<limit,(label,hex(self.pc),self.r,self.z,self.c)
            if stubs:
                targets={SY[n]:n for n in ('checkbreak','refresh_notes','vlq','delay_ticks','get','send_midi','observe_three','observe_two','send')}
                if self.pc in targets:
                    n=targets[self.pc];self.calls[n]+=1
                    if n=='get':self.r[7]=self.input.popleft()
                    elif n=='vlq':self.setpair(2,0)
                    elif n in ('send_midi','send'):self.tx.append(self.r[7])
                    self.pc=self.pop();continue
            p=self.pc;op=self.byte()
            if 0x40<=op<=0x7f and op!=0x76:self.write((op>>3)&7,self.read(op&7))
            elif op&0xc7==6:self.write((op>>3)&7,self.byte())
            elif op&0xcf==1:self.setpair((op>>4)&3,self.word())
            elif op in (0x3a,0x32,0x2a,0x22):
                a=self.word()
                if op==0x3a:self.r[7]=self.m[a]
                elif op==0x32:self.m[a]=self.r[7]
                elif op==0x2a:self.setpair(2,int.from_bytes(self.m[a:a+2],'little'))
                else:self.m[a:a+2]=self.pair(2).to_bytes(2,'little')
            elif op&0xcf in (3,11):k=(op>>4)&3;self.setpair(k,self.pair(k)+(1 if op&0xcf==3 else -1))
            elif op&0xc7 in (4,5):k=(op>>3)&7;v=self.read(k)+(1 if op&7==4 else -1);self.write(k,v);self.flag(v)
            elif op&0xcf==9:v=self.pair(2)+self.pair((op>>4)&3);self.c=v>65535;self.setpair(2,v)
            elif op&0xcf in (0xc5,0xc1):
                k=(op>>4)&3
                if op&15==5:self.push(self.pair(k) if k!=3 else self.r[7]*256+int(self.c)+64*int(self.z))
                else:
                    v=self.pop()
                    if k!=3:self.setpair(k,v)
                    else:self.r[7]=v>>8;self.c=bool(v&1);self.z=bool(v&64)
            elif 0x90<=op<=0xbf or op in (0xd6,0xe6,0xee,0xf6,0xfe):
                k=(op>>3)&7 if op<0xc0 else {0xd6:2,0xe6:4,0xee:5,0xf6:6,0xfe:7}[op];v=self.read(op&7) if op<0xc0 else self.byte();a=self.r[7]
                if k in (2,7):q=a-v;self.c=q<0
                elif k==4:q=a&v;self.c=False
                elif k==5:q=a^v;self.c=False
                elif k==6:q=a|v;self.c=False
                else:raise AssertionError((p,op))
                self.flag(q)
                if k!=7:self.r[7]=q&255
            elif op==0xcb:
                v=self.byte()
                if 0x38<=v<0x40:
                    q=self.read(v&7);self.c=bool(q&1);self.write(v&7,q>>1);self.flag(q>>1)
                else:
                    assert 0x40<=v<0x80;self.z=not bool(self.read(v&7)&(1<<((v>>3)&7)))
            elif op==0xed:
                v=self.byte();k=(v>>4)&3
                if v&0xcf in (0x42,0x4a):
                    q=self.pair(2)+self.pair(k)+int(self.c) if v&0xcf==0x4a else self.pair(2)-self.pair(k)-int(self.c)
                    self.c=q<0 or q>65535;self.z=(q&65535)==0;self.setpair(2,q)
                elif v&0xcf==0x4b:self.setpair(k,int.from_bytes(self.m[(a:=self.word()):a+2],'little'))
                elif v&0xcf==0x43:a=self.word();self.m[a:a+2]=self.pair(k).to_bytes(2,'little')
                else:raise AssertionError((p,op,v))
            elif op==0xcd:a=self.word();self.push(self.pc);self.pc=a
            elif op==0xc3:self.pc=self.word()
            elif op&0xc7==0xc2:a=self.word();self.pc=a if self.cond((op>>3)&7) else self.pc
            elif op==0xc9:self.pc=self.pop()
            elif op&0xc7==0xc0:
                if self.cond((op>>3)&7):self.pc=self.pop()
            elif op==0xdb:
                port=self.byte();assert port==0xea;self.r[7]=self.uart.popleft() if self.uart else 64
            elif op==0x1a:self.r[7]=self.m[self.pair(1)]
            elif op==0x12:self.m[self.pair(1)]=self.r[7]
            elif op==0xd3:self.out.append((self.byte(),self.r[7]))
            elif op==0x10:
                d=self.byte();self.r[0]=(self.r[0]-1)&255
                if self.r[0]:self.pc+=d if d<128 else d-256
            else:raise AssertionError((hex(p),hex(op)))

def route(cpu,data):
    cpu.input.extend(data);before=len(cpu.tx);cpu.run('next_event',until='next_event',stubs=True);assert not cpu.input;return cpu.tx[before:]
# Wire status is independent from input running status and percussion filtering.
c=CPU();c.poke('drum_mode',1)
assert route(c,[0xc0,0])==[0xc0,0]
assert route(c,[0x90,64,100])==[0x90,64,100]
assert route(c,[67,85])==[67,85]
assert route(c,[0x99,36,100])==[]
assert route(c,[0x90,70,100])==[70,100]
assert route(c,[0xc0,8])==[0xc0,8]
assert route(c,[0xc0,0])==[0]
assert route(c,[0xb9,64,127])==[]
assert route(c,[0xc9,8])==[]
assert route(c,[0xd9,100])==[]
assert route(c,[0x91,71,100])==[0x91,71,100]
# Actual SX send path resets outgoing status; input parser's VLQ mocked as zero
# so call sxsend directly with a whitelisted validated payload.
for i,v in enumerate([0x43,0x73,0x11,0x11,7,0xf7]):c.m[SY['sxdata']+i]=v
c.run('sxsend',until='next_event',stubs=True)
assert c.tx[-7:]==[0xf0,0x43,0x73,0x11,0x11,7,0xf7]
assert route(c,[0x91,73,100])==[0x91,73,100]
for note,kind in [(36,3),(38,2),(42,1),(75,4),(76,5),(77,6),(78,7),(79,7)]:
    lengths=[]
    for vel in (32,72,110):
        c=CPU();c.poke('drum_mode',1)
        assert route(c,[0x99,note,vel])==[] and c.peek('drum_kind')==kind
        lengths.append(c.peek('drum_left'))
        for j in range(150):c.run('drum_slice')
        vals=[v for p,v in c.out if p==255];assert set(vals)=={0,1} and vals[-1]==0 and c.peek('drum_left')==0,(note,vel,vals)
    assert lengths[0]<lengths[1]<lengths[2],lengths
c=CPU();assert route(c,[0x90,36,100])==[0x90,36,100];assert route(c,[36,0])==[0x90,36,0];c.run('drum_quiet');assert not c.out
c=CPU();c.poke('buffered',0xfd);assert route(c,[0x90,36,100])==[0x90,36,100];assert route(c,[36,0])==[0x90,36,0]
c=CPU();c.poke('drum_mode',2);assert route(c,[0x99,36,100])==[] and c.peek('drum_left')==0
c=CPU();c.poke('drum_mode',1);c.m[0x4288]=255;route(c,[0x99,36,90]);route(c,[42,90]);assert c.peek('drum_kind')==3;c.m[0x4288]=1;c.run('drum_slice');assert c.peek('drum_left')==0 and c.out[-1]==(255,0)
for mode,expected in [(0,16),(1,15),(2,15)]:
    c=CPU();c.poke('drum_mode',mode);c.run('raw_panic',until='closefile',stubs=True);assert len(c.tx)==expected*12
    assert (0xb9 in c.tx)==(mode==0)
# UART busy path: actual send and drum code, preserve all parser registers.
c=CPU();c.poke('drum_mode',1);c.poke('playing',1);route(c,[0x99,36,110]);c.uart.extend([0,0,0,64]);c.r=[12,34,56,78,90,123,0,0x90];saved=c.r.copy();c.run('send');assert c.r==saved and c.out[-1]==(0xeb,0x90) and c.out[-2]==(255,0);assert sum(p==255 for p,v in c.out)>=3
# UART failure still exits rather than hanging; no partial-message BREAK polls.
c=CPU();c.poke('drum_mode',1);c.poke('playing',1);route(c,[0x99,36,110]);c.r[7]=0x90;c.uart.extend([0]*257);c.run('send',until='finish');assert c.peek('playing')==0 and not any(port==0xeb for port,v in c.out)
# Actual TX ring rendering, including wrapping and right-aligned short contents.
c=CPU()
for val in (0xc0,0,0x90,0x3c,0x7f):
    c.r[7]=val;c.run('send_midi')
c.run('render_stream');assert bytes(c.m[0x3ec0:0x3ef0]).decode()==' '*33+'C0 00 90 3C 7F '
# Throttled refresh: do not redraw until three clock ticks (including wrap).
c.poke('stream_tick',254);c.m[0x4288]=0;c.poke('stream_dirty',1);c.run('refresh_stream');assert c.peek('stream_dirty')==1
c.m[0x4288]=1;c.run('refresh_stream');assert c.peek('stream_dirty')==0
for val in range(25):c.r[7]=val;c.run('send_midi')
c.run('render_stream');assert bytes(c.m[0x3ec0:0x3ef0]).decode()==''.join(f'{v:02X} ' for v in range(9,25))
# Actual SD fast path; check register preservation and cursor advance.
c=CPU();p=SY['sector'];c.m[p:p+3]=b'xyz';c.m[SY['sd_readptr']:SY['sd_readptr']+2]=p.to_bytes(2,'little');c.poke('sd_avail',3);c.r[:6]=[1,2,3,4,5,6]
for v in b'xyz':c.run('sd_rawget');assert c.r[7]==v and c.r[:6]==[1,2,3,4,5,6]
assert c.peek('sd_avail')==0
# Actual VLQ decoder with memory-backed SD bytes and boundary tests.
for enc,expected in [(b'\x00',0),(b'\x7f',127),(b'\x81\x00',128),(b'\xff\x7f',16383),(b'\x83\xff\x7f',65535)]:
    c=CPU();p=SY['sector'];c.m[p:p+len(enc)]=enc;c.m[SY['sd_readptr']:SY['sd_readptr']+2]=p.to_bytes(2,'little');c.poke('sd_avail',len(enc));c.m[SY['remaining']:SY['remaining']+2]=len(enc).to_bytes(2,'little');c.run('vlq');assert c.pair(2)==expected and c.peek('sd_avail')==0
print('PASS: outgoing status, SysEx reset, percussion velocity/priority/expiry, unchanged legacy modes, panic, UART audio and register preservation, monitor, SD fast path, VLQ boundaries')
# Compare expanded wire events, not raw bytes; status omission is legal MIDI.
for name in ['GHSTWIRE.MID','NIGHTFAL.MID','SUNSPARK.MID']:
    f=(ROOT/name).read_bytes();assert f[:14]==b'MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60';assert int.from_bytes(f[18:22],'big')==len(f)-22
    idx=22;tick=0;tempo=500000;us=0.;wire_status=None;old=0;new=0;c=CPU();c.poke('drum_mode',1);active=set();peak=0;melody=drums=0;patches=set();end=False
    def vlq():
        global idx
        n=0
        while True:
            b=f[idx];idx+=1;n=(n<<7)|(b&127)
            if not b&128:return n
    while idx<len(f):
        delta=vlq();tick+=delta;us+=delta*tempo/96
        status=f[idx];idx+=1
        if status==255:
            kind=f[idx];idx+=1;n=vlq();data=f[idx:idx+n];idx+=n
            if kind==81:tempo=int.from_bytes(data,'big')
            if kind==47:assert n==0 and idx==len(f);end=True
            continue
        assert 0x80<=status<=0xef
        n=1 if status&0xe0==0xc0 else 2;data=list(f[idx:idx+n]);idx+=n;ch=status&15;kind=status&0xf0
        sent=route(c,[status,*data])
        if ch==9:
            assert not sent
            if kind==0x90 and data[1]:drums+=1
            continue
        assert ch==0
        old+=n+1;new+=len(sent)
        if sent[0]&128:wire_status=sent.pop(0)
        assert [wire_status,*sent]==[status,*data],(name,tick,status,data,sent)
        if name=='SUNSPARK.MID' and 6912<=tick<9216:raise AssertionError('piano during solo')
        if kind==0xc0:assert not active;patches.add(data[0])
        if kind==0x90 and data[1]:assert data[0] not in active;active.add(data[0]);peak=max(peak,len(active));melody+=1
        if kind==0x80 or kind==0x90 and not data[1]:assert data[0] in active;active.remove(data[0])
    assert end and not active and peak<=8
    print(f'PASS: {name}: {us/1e6:.2f}s, {melody} piano/choir notes, {drums} percussion hits, {peak} peak voices; {old} -> {new} bytes ({100*(old-new)/old:.1f}% fewer); exact expanded wire events')
