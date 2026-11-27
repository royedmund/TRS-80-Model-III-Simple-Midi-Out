#!/usr/bin/env python3
"""Restricted Z80 instruction simulation, with accelerated idle clock.
Checks actual CMD bytes with mocked ROM, UART, LDOS timer and FreHD.
Not cycle accurate; no physical SD write or audio test."""
from pathlib import Path
R=Path(__file__).resolve().parent
SY={'wait_loop':0x63b3,'sd_release':0x7fda,'next_event':0x6118,'send_midi':0x6422}
CMD=(R.parent/'MIDISD.CMD').read_bytes()
class CPU:
 def __init__(self,keys,break_pc=None,files=None,reply=4):
  self.mem=bytearray(65536);i=0
  while CMD[i]==1:
   n=CMD[i+1] or 256;a=int.from_bytes(CMD[i+2:i+4],'little');self.mem[a:a+n-2]=CMD[i+4:i+2+n];i+=n+2
  self.pc=int.from_bytes(CMD[i+2:i+4],'little');self.sp=0xf000;self.r=[0]*8;self.z=self.c=False;self.keys=iter(keys);self.out=[];self.text='';self.break_pc=break_pc;self.mem[0x4288]=250;self.files={} if files is None else dict(files);self.reply=reply;self.port=0x20;self.size=0;self.state=0;self.response=[];self.payload=[];self.status=0x58;self.openname=None;self.pos=0;self.events=[];self.ticks=0;self.screen=[];self.break_once=False;self.live_frames=[]
 def word(self,a):return self.mem[a]|self.mem[(a+1)&65535]<<8
 def wr(self,a,x):self.mem[a]=x&255;self.mem[(a+1)&65535]=x>>8&255
 def pair(self,i):return self.sp if i==3 else self.r[2*i]*256+self.r[2*i+1]
 def setpair(self,i,x):
  x&=65535
  if i==3:self.sp=x
  else:self.r[2*i]=x>>8;self.r[2*i+1]=x&255
 def get(self,i):return self.mem[self.pair(2)] if i==6 else self.r[i]
 def set(self,i,v):
  if i==6:self.mem[self.pair(2)]=v&255
  else:self.r[i]=v&255
 def f(self):x=self.mem[self.pc];self.pc=(self.pc+1)&65535;return x
 def fw(self):a=self.f();return a+256*self.f()
 def push(self,x):self.sp=(self.sp-2)&65535;self.wr(self.sp,x)
 def pop(self):x=self.word(self.sp);self.sp=(self.sp+2)&65535;return x
 def cond(self,i):return [not self.z,self.z,not self.c,self.c,False,False,False,False][i]
 def alu(self,i,v):
  a=self.r[7]
  if i==0:x=a+v;self.c=x>255
  elif i in (2,7):x=a-v;self.c=x<0
  elif i==4:x=a&v;self.c=False
  elif i==5:x=a^v;self.c=False
  elif i==6:x=a|v;self.c=False
  else:raise AssertionError(i)
  self.z=(x&255)==0
  if i!=7:self.r[7]=x&255
 def run(self):
  for steps in range(20000000):
   p=self.pc
   if p==self.break_pc and not self.break_once:self.mem[0x3840]=4;self.break_once=True
   if p==0x402d:return self
   if p==0x002b:self.r[7]=next(self.keys,0);self.pc=self.pop();continue
   if p==0x0033:self.text+=chr(self.r[7]);self.pc=self.pop();continue
   if p==SY['wait_loop']:
    self.mem[0x4288]=(self.mem[0x4288]+1)&255;self.ticks+=1
   op=self.f()
   if 0x40<=op<=0x7f:self.set((op>>3)&7,self.get(op&7))
   elif op&0xc7==6:self.set((op>>3)&7,self.f())
   elif op&0xcf==1:self.setpair((op>>4)&3,self.fw())
   elif op&0xcf in (3,11):i=(op>>4)&3;self.setpair(i,self.pair(i)+(1 if op&15==3 else -1))
   elif op&0xc7 in (4,5):i=(op>>3)&7;v=(self.get(i)+(1 if op&7==4 else -1))&255;self.set(i,v);self.z=v==0
   elif op&0xcf==9:x=self.pair(2)+self.pair((op>>4)&3);self.setpair(2,x);self.c=x>65535
   elif op==0x00:pass
   elif op==0x1a:self.r[7]=self.mem[self.pair(1)]
   elif op==0x12:self.mem[self.pair(1)]=self.r[7]
   elif op==0xeb:x=self.pair(1);self.setpair(1,self.pair(2));self.setpair(2,x)
   elif op==0x0f:a=self.r[7];self.r[7]=(a>>1)|((a&1)<<7);self.c=bool(a&1)
   elif op==0x37:self.c=True
   elif op==0x3a:self.r[7]=self.mem[self.fw()]
   elif op==0x32:self.mem[self.fw()]=self.r[7]
   elif op==0x2a:self.setpair(2,self.word(self.fw()))
   elif op==0x22:self.wr(self.fw(),self.pair(2))
   elif 0x80<=op<=0xbf:self.alu((op>>3)&7,self.get(op&7))
   elif op in (0xc6,0xd6,0xe6,0xee,0xf6,0xfe):self.alu((op>>3)&7,self.f())
   elif op==0xed:
    s=self.f();i=(s>>4)&3
    if s==0xb2:
     b=self.r[0] or 256;hl=self.pair(2)
     for _ in range(b):self.mem[hl]=self.readport(self.r[1]);hl=(hl+1)&65535
     self.setpair(2,hl);self.r[0]=0
    elif s==0xb0:
     bc=self.pair(0) or 65536;hl=self.pair(2);de=self.pair(1)
     for _ in range(bc):self.mem[de]=self.mem[hl];hl=(hl+1)&65535;de=(de+1)&65535
     self.setpair(0,0);self.setpair(1,de);self.setpair(2,hl)
    elif s&0xcf==0x43:self.wr(self.fw(),self.pair(i))
    elif s&0xcf==0x4b:self.setpair(i,self.word(self.fw()))
    elif s&0xcf==0x42:
     x=self.pair(2)-self.pair(i)-int(self.c);self.c=x<0;self.z=(x&65535)==0;self.setpair(2,x)
    elif s&0xcf==0x4a:
     x=self.pair(2)+self.pair(i)+int(self.c);self.c=x>65535;self.z=(x&65535)==0;self.setpair(2,x)
    else:raise AssertionError((p,s))
   elif op==0xcb:
    s=self.f();i=s&7;mask=1<<((s>>3)&7)
    if 0x40<=s<=0x7f:self.z=not(self.get(i)&mask)
    elif 0x80<=s<=0xbf:self.set(i,self.get(i)&~mask)
    elif 0x38<=s<=0x3f:v=self.get(i);self.c=bool(v&1);self.set(i,v>>1);self.z=v>>1==0
    else:raise AssertionError(s)
   elif op==0xc3:self.pc=self.fw()
   elif op&0xc7==0xc2:a=self.fw();self.pc=a if self.cond((op>>3)&7) else self.pc
   elif op==0xcd:a=self.fw();self.push(self.pc);self.pc=a
   elif op==0xc9:self.pc=self.pop()
   elif op&0xc7==0xc0:
    if self.cond((op>>3)&7):self.pc=self.pop()
   elif op&0xcf==0xc5:
    i=(op>>4)&3;self.push(self.pair(i) if i!=3 else (self.r[7]<<8)|(64 if self.z else 0)|int(self.c))
   elif op&0xcf==0xc1:
    i=(op>>4)&3;v=self.pop()
    if i==3:self.r[7]=v>>8;self.z=bool(v&64);self.c=bool(v&1)
    else:self.setpair(i,v)
   elif op==0x10:
    d=self.f();self.r[0]=(self.r[0]-1)&255
    if self.r[0]:self.pc=(self.pc+(d if d<128 else d-256))&65535
   elif op==0xd3:
    port=self.f();self.writeport(port,self.r[7])
   elif op==0xdb:self.r[7]=self.readport(self.f())
   else:raise AssertionError((hex(p),hex(op)))
  raise AssertionError(('step limit',hex(self.pc),self.text,self.screen[-1][-64:] if self.screen else ''))
 def readport(self,p):
  if p==0xea:return 64
  if p==0xff:return self.port
  if p==0xcf:return self.status
  if p==0xc3:return len(self.response)&255
  if p==0xc2:return self.response.pop(0)
  raise AssertionError(p)
 def writeport(self,p,v):
  if p==0xec:self.port=v;return
  if p in (0xe8,0xe9,0xea):return
  if p==0xeb:self.out.append(v);return
  if p==0xc3:self.size=v or 256;return
  if p==0xc4:
   self.payload=[];self.response=[];self.status=0x58;self.state=v
   if v==0:self.response=[1,2,3,4,5,6]
   elif v in (3,8):pass
   elif v==9:
    if self.dirents:self.response=list(self.dirents.pop(0))
    else:self.status=0x50
   elif v==4:
    assert self.openname is not None
    self.response=list(self.files[self.openname][self.pos:self.pos+self.size]);self.pos+=len(self.response)
    if not self.response:self.status=0x50
   elif v==5:
    assert self.openname is not None;self.size=256
   elif v==6:self.openname=None;self.status=0x50
   else:raise AssertionError(v)
   return
  if p==0xc2:
   self.payload.append(v)
   if len(self.payload)==self.size:
    if self.state==3:
     mode=self.payload[0];name=bytes(self.payload[1:]).rstrip(b'\0').decode()
     assert mode in (1,6)
     if (mode==1 and name not in self.files) or (mode==6 and name in self.files):self.status=0x51;return
     if mode==6:self.files[name]=b''
     self.openname=name;self.pos=0;self.response=list(len(self.files[name]).to_bytes(4,'little'))+[0]*(self.reply-4)
    elif self.state==8:
     name=bytes(self.payload).rstrip(b'\0').decode();prefix=name.rstrip('/')+'/'
     entries={}
     for fn,data in self.files.items():
      if not fn.startswith(prefix):continue
      tail=fn[len(prefix):];part,sep,_=tail.partition('/')
      if not part:continue
      entries[part]=(16 if sep else 32,0 if sep else len(data))
     self.dirents=[size.to_bytes(4,'little')+b'\0'*4+bytes([attr])+part.encode().ljust(13,b'\0') for part,(attr,size) in entries.items()]
     self.status=0x50
    elif self.state==5:
     self.files[self.openname]+=bytes(self.payload);self.status=0x58
    else:raise AssertionError(self.state)
   return
  raise AssertionError(p)


# Independent format-0 decoder: compare wire bytes, excluding transport.
def reference(mid):
 p=22;run=0;out=[]
 def vlq():
  nonlocal p
  n=0
  while True:
   b=mid[p];p+=1;n=(n<<7)|(b&127)
   if not b&128:return n
 while p<len(mid):
  vlq();b=mid[p];p+=1
  if b==255:
   k=mid[p];p+=1;n=vlq();p+=n;run=0
   if k==47:break
  elif b in (240,247):
   n=vlq();a=mid[p:p+n];p+=n;run=0
   if b==240 and n==6 and a[:4]==bytes([67,115,17,17]) and a[4] in [7,8,9,23,24,25,64,65,80,81,96,97,112,113,114] and a[5]==247:out.extend([240,*a])
  else:
   if b&128:run=b
   else:p-=1
   n=1 if run&0xe0==0xc0 else 2;out.extend([run,*mid[p:p+n]]);p+=n
 return bytes(out)
if __name__=='__main__':
 import sys
 paths=[Path(x) for x in sys.argv[1:]]
 for path in paths:
  mid=path.read_bytes();ref=reference(mid)
  for mode,start in [('4',253),('5',249),('2',None)]:
   c=CPU([49,0,ord(mode),0],files={'/TEST.MID':mid}).run();w=bytes(c.out)
   assert 'End of MIDI file.' in c.text,(c.text,w[:40])
   assert c.openname is None and c.port==0x20
   if start:
    assert w[0]==start and w[-1]==250 and bytes(b for b in w[1:-1] if b!=248)==ref,(len(w),len(ref))
    (R/(path.stem+'-'+mode+'.wire')).write_bytes(w)
   else:assert w[:len(ref)]==ref and len(w)==len(ref)+192
   print('PASS',path.name,'mode',mode,'music bytes',len(ref),'ticks',c.ticks,'wire',len(w))
