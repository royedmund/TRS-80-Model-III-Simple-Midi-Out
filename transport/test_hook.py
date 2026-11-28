from pathlib import Path
from assembler import parse_cmd,asm
_,_,L,_=asm(Path("CLOCKHOOK.ASM").read_text())
class CPU:
    def __init__(self):
        self.m,_,_=parse_cmd(Path('MIDICLK.CMD').read_bytes())
        self.pc=0;self.sp=0xf000;self.r=[0]*8;self.z=False;self.c=False
        self.writes=[];self.video_writes=[];self.uart=True;self.uart_reads=[];self.polls=0;self.stop_after=None;self.calls=[];self.key=0;self.extra_stops=set();self.auto_clock=False
        self.word(0x7c3b,0xf000);self.track=None;self.trackpos=0
    def invoke(self,addr):
        self.push(0xffff);self.pc=addr;return self.run()
    def word(self,a,v=None):
        if v is None:return self.m[a]|self.m[a+1]<<8
        self.m[a:a+2]=v.to_bytes(2,'little')
    def byte(self):
        a=self.m[self.pc]; self.pc+=1;return a
    def imm(self):
        a=self.byte();return a|(self.byte()<<8)
    def pair(self,n,v=None):
        if n==3:
            if v is None:return self.sp
            self.sp=v&65535;return
        if v is None:return self.r[n*2]*256+self.r[n*2+1]
        self.r[n*2]=(v>>8)&255;self.r[n*2+1]=v&255
    def get(self,n):
        if n!=6:return self.r[n]
        return self.m[self.pair(2)]
    def put(self,n,v):
        if n!=6:self.r[n]=v&255
        else:
            addr=self.pair(2)
            self.m[addr]=v&255
            if 0x3c00<=addr<0x4000:self.video_writes.append(addr)
    def push(self,v):self.sp-=2;self.word(self.sp,v)
    def pop(self):v=self.word(self.sp);self.sp+=2;return v
    def cond(self,n):return [not self.z,self.z,not self.c,self.c][n]
    def alu(self,n,v):
        a=self.r[7];out={0:a+v,2:a-v,4:a&v,5:a^v,6:a|v,7:a-v}[n]
        self.c=not 0<=out<=255 if n in (0,2,7) else False
        self.z=(out&255)==0
        if n!=7:self.r[7]=out&255
    def run(self):
        for _ in range(200000):
            if self.pc in (0xffff,0x6000,0x402d,0x6118) or self.pc in self.extra_stops:return self.pc
            if self.track is not None:
                if self.pc==0x63f4:
                    assert self.trackpos<len(self.track)
                    self.r[7]=self.track[self.trackpos];self.trackpos+=1;self.pc=self.pop();continue
                if self.pc in (0x679e,0x6769,0x6868):
                    self.pc=self.pop();continue
            if self.pc==0x002b:
                self.r[7]=self.key;self.pc=self.pop();continue
            if self.pc in (0x63de,0x80d7,0x66a7):
                self.calls.append(self.pc)
                if self.pc==0x63de:self.m[0x429f]&=254
                if self.pc==0x80d7:
                    self.m[0x7c3d]=0;self.m[0x81f6]=0
                    # Mock user releases CLEAR while file closes.
                    self.m[0x3840]&=253
                self.pc=self.pop();continue
            op=self.byte();x,y,z=op>>6,(op>>3)&7,op&7; p=y>>1
            if op==0:continue
            if x==1:self.put(y,self.get(z));continue
            if x==2:self.alu(y,self.get(z));continue
            if op in (0xc3,0xcd):
                addr=self.imm()
                if op==0xcd:self.push(self.pc)
                self.pc=addr;continue
            if op in (0x10,0x18,0x20,0x28,0x30,0x38):
                d=self.byte();d=d if d<128 else d-256
                if op==0x10:self.r[0]=(self.r[0]-1)&255;take=self.r[0]!=0
                else:take=op==0x18 or self.cond((op-0x20)//8)
                if take:self.pc+=d
                continue
            if op==0xc9:self.pc=self.pop();continue
            if x==3 and z in (0,2,4) and y<4:
                if z==0:
                    if self.cond(y):self.pc=self.pop()
                else:
                    addr=self.imm()
                    if self.cond(y):
                        if z==4:self.push(self.pc)
                        self.pc=addr
                continue
            if op in (0xc5,0xd5,0xe5,0xf5,0xc1,0xd1,0xe1,0xf1):
                if p==3:
                    if op&4:self.push(self.r[7]*256+64*self.z+self.c)
                    else:
                        v=self.pop();self.r[7]=v>>8;self.z=bool(v&64);self.c=bool(v&1)
                elif op&4:self.push(self.pair(p))
                else:self.pair(p,self.pop())
                continue
            if x==3 and z==6:self.alu(y,self.byte());continue
            if x==0 and z==6:self.put(y,self.byte());continue
            if x==0 and z in (4,5):
                v=(self.get(y)+(1 if z==4 else -1))&255; self.put(y,v);self.z=v==0;continue
            if x==0 and z==1:
                if y&1:
                    v=self.pair(2)+self.pair(p);self.c=v>65535;self.pair(2,v)
                else:self.pair(p,self.imm())
                continue
            if x==0 and z==3:self.pair(p,self.pair(p)+(1 if not y&1 else -1));continue
            if op in (0x12,0x1a):
                if op==0x12:
                    addr=self.pair(1);self.m[addr]=self.r[7]
                    if 0x3c00<=addr<0x4000:self.video_writes.append(addr)
                else:self.r[7]=self.m[self.pair(1)]
                continue
            if op in (0x22,0x2a,0x32,0x3a):
                a=self.imm()
                if op==0x22:self.word(a,self.pair(2))
                elif op==0x2a:self.pair(2,self.word(a))
                elif op==0x32:self.m[a]=self.r[7]
                else:
                    if a==0x4288 and self.auto_clock:self.m[a]=(self.m[a]+1)&255
                    self.r[7]=self.m[a]
                    if a==0x3840 and self.stop_after is not None and len([v for port,v in self.writes if port==0xeb])>=self.stop_after:self.r[7]=4
                continue
            if op==0xeb:v=self.pair(1);self.pair(1,self.pair(2));self.pair(2,v);continue
            if op in (0xd3,0xdb):
                port=self.byte()
                if op==0xd3:self.writes.append((port,self.r[7]))
                else:
                    self.polls+=1
                    ready=self.uart_reads.pop(0) if self.uart_reads else self.uart
                    self.r[7]=0x40 if ready else 0
                continue
            if op==0xcb:
                q=self.byte();n=q&7
                if 0x38<=q<=0x3f:
                    v=self.get(n);self.c=bool(v&1);self.put(n,v>>1);self.z=(v>>1)==0
                elif 0x40<=q<=0x7f:self.z=not bool(self.get(n)&(1<<((q>>3)&7)))
                else:raise AssertionError(hex(q))
                continue
            if op==0xed:
                q=self.byte();p=(q>>4)&3
                if q&0xcf==0x42:
                    v=self.pair(2)-self.pair(p)-int(self.c);self.c=v<0;self.z=(v&65535)==0;self.pair(2,v)
                elif q&0xcf==0x4a:
                    v=self.pair(2)+self.pair(p)+int(self.c);self.c=v>65535;self.z=(v&65535)==0;self.pair(2,v)
                elif q&0xcf==0x43:self.word(self.imm(),self.pair(p))
                elif q&0xcf==0x4b:self.pair(p,self.word(self.imm()))
                elif q==0xb0:
                    for _ in range(self.pair(0)):
                        self.m[self.pair(1)]=self.m[self.pair(2)];self.pair(1,self.pair(1)+1);self.pair(2,self.pair(2)+1)
                    self.pair(0,0)
                else:raise AssertionError(hex(q))
                continue
            raise AssertionError(f'Unsupported opcode {op:02x} at {self.pc-1:04x}')
        raise AssertionError('instruction limit')

def wire(c):return [v for port,v in c.writes if port==0xeb]
for mode,rate in ((0xfd,25),(0xf9,30)):
 c=CPU();c.m[0x7c39]=mode;c.invoke(L['FRAME_START']);assert wire(c)==[0xf6,rate]
 c.m[0x7c4c:0x7c50]=(500000).to_bytes(4,'little');c.extra_stops={0x62ac};c.invoke(L['CLOCK_TEMPO']);c.extra_stops=set();assert wire(c)[2:]==[0xf1,0,7,10,1,2,0]
 for b in (0x90,60,100,0x90,64,90):
  c.r[7]=b;c.pair(0,0xabcd);c.pair(2,0x1234);c.invoke(0x6422);assert c.pair(0)==0xabcd and c.pair(2)==0x1234 and c.r[7]==b
 assert len(wire(c))==9
 c.m[0x7c5c]=255;c.invoke(L['WAIT_START']);assert c.m[0x7c5c]==0
 assert wire(c)[9:]==[0xf2,6,0x90,60,100,0x90,64,90]
 c.invoke(L['FRAME_TICK']);assert wire(c)[-2:]==[0xf2,0]
 for b in (0x80,60,0,0x80,64,0):c.r[7]=b;c.invoke(0x6422)
 c.r[7]=0xfa;c.invoke(L['FRAME_FINISH']);assert wire(c)[-8:]==[0xf3,6,0x80,60,0,0x80,64,0]
 Path(f'tests/host{rate}.wire').write_bytes(bytes(wire(c)))
 print('PASS actual Z80 frame start, tempo, MIDI buffering, tick, empty frame, final at',rate,'Hz')
c=CPU();c.m[0x7c39]=0;c.r[7]=0x90;c.invoke(0x6422);c.invoke(L['WAIT_START']);assert wire(c)==[0x90];print('PASS raw compatibility')
c=CPU();c.m[0x7c39]=0xfd;c.r[7]=0xfc;c.invoke(L['FRAME_FINISH']);assert wire(c)==[0xfc];print('PASS immediate abort')
c=CPU();c.m[0x7c39]=0xfd;c.m[L['FRAME_LEN']]=127;c.extra_stops={0x6623};c.r[7]=0x90;assert c.invoke(0x6422)==0x6623;assert not wire(c);print('PASS oversized tick abort before writes')

# Execute the baseline SMF event parser, patched timing engine and sender.
# SD byte retrieval and display are mocked; the TIMER$ read advances one tick.
import struct
f=Path('CLOCKTST.MID').read_bytes();assert f[:4]==b'MThd' and f[14:18]==b'MTrk'
track=f[22:22+int.from_bytes(f[18:22],'big')];ppqn=int.from_bytes(f[12:14],'big')
for mode,rate in ((0xfd,25),(0xf9,30)):
 c=CPU();c.track=track;c.auto_clock=True;c.m[0x7c39]=mode;c.word(0x7c40,len(track));c.word(0x7c42,ppqn)
 threshold=ppqn*(40000 if rate==25 else 33333);c.m[0x7c44:0x7c48]=threshold.to_bytes(4,'little');c.m[0x7c4c:0x7c50]=(500000).to_bytes(4,'little');c.invoke(0x62ac);c.invoke(L['FRAME_START'])
 c.extra_stops={0x6626}
 for n in range(1000):
  c.pc=0x611e;r=c.run()
  if r==0x6626:break
  assert r==0x6118
 else:raise AssertionError('event limit')
 assert c.m[0x7c3a]==1 and c.trackpos==len(track)
 c.extra_stops=set();c.r[7]=0xfa;c.invoke(L['FRAME_FINISH']);w=wire(c);assert w[:2]==[0xf6,rate]
 i=2;tempo=[];groups=0;music=[]
 while i<len(w):
  tag=w[i];i+=1
  if tag==0xf1:
   t=0
   for b in w[i:i+6]:t=(t<<4)|b
   tempo.append(t);i+=6
  elif tag in (0xf2,0xf3):
   n=w[i];i+=1;music+=w[i:i+n];i+=n
   if tag==0xf2:groups+=1
   else:assert i==len(w)
  else:raise AssertionError(hex(tag))
 assert tempo==[500000,1000000] and groups==rate*6,(tempo,groups,rate)
 Path(f'tests/demo{rate}.wire').write_bytes(bytes(w))
 print(f'PASS actual SMF event parser: {rate}Hz, {groups} tick frames, {len(music)} music bytes, two tempo changes')
