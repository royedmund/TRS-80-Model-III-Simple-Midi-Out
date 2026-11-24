#!/usr/bin/env python3
"""Execute the assembled CMD in a minimal Z80 instruction harness.
Mocks LDOS calls, keyboard, UART and timer. Not a hardware/full-system emulator.
Tests the actual generated opcodes and captured UART bytes.
"""
from pathlib import Path
import struct
ROOT=Path(__file__).resolve().parent
class CPU:
 def __init__(self,smf,clock='3',break_at=None,uart_ok=True):
  self.mem=bytearray(65536);p=0;cmd=(ROOT/'MIDIPLAY.CMD').read_bytes()
  while cmd[p]==1:
   n=cmd[p+1] or 256;adr=int.from_bytes(cmd[p+2:p+4],'little');self.mem[adr:adr+n-2]=cmd[p+4:p+2+n];p+=n+2
  assert cmd[p:p+2]==bytes([2,2]);self.pc=int.from_bytes(cmd[p+2:p+4],'little');self.sp=0xf000
  self.r=[0]*8;self.z=False;self.c=False;self.steps=0;self.ticks=0;self.smf=smf;self.pos=0;self.clock=clock;self.break_at=break_at;self.uart_ok=uart_ok;self.uart=[];self.ports=[];self.text='';self.closed=False
  self.setpair(2,0x5000);self.mem[0x5000:0x500b]=b'TEST/MID:0\r'
 def word(self,a):return self.mem[a]|self.mem[(a+1)&65535]<<8
 def writeword(self,a,x):self.mem[a]=x&255;self.mem[(a+1)&65535]=(x>>8)&255
 def pair(self,i):return self.sp if i==3 else (self.r[2*i]<<8)|self.r[2*i+1]
 def setpair(self,i,x):
  x&=65535
  if i==3:self.sp=x
  else:self.r[2*i]=x>>8;self.r[2*i+1]=x&255
 def get(self,i):
  if i!=6:return self.r[i]
  return self.mem[self.pair(2)]
 def set(self,i,x):
  if i==6:self.mem[self.pair(2)]=x&255
  else:self.r[i]=x&255
 def fetch(self):v=self.mem[self.pc];self.pc=(self.pc+1)&65535;return v
 def fetchw(self):lo=self.fetch();return lo|(self.fetch()<<8)
 def push(self,x):self.sp=(self.sp-2)&65535;self.writeword(self.sp,x)
 def pop(self):x=self.word(self.sp);self.sp=(self.sp+2)&65535;return x
 def cond(self,i):return [not self.z,self.z,not self.c,self.c,False,False,False,False][i]
 def alu(self,op,v):
  a=self.r[7]
  if op==2 or op==7:r=a-v;self.c=r<0
  elif op==4:r=a&v;self.c=False
  elif op==5:r=a^v;self.c=False
  elif op==6:r=a|v;self.c=False
  else:raise AssertionError(op)
  self.z=(r&255)==0
  if op!=7:self.r[7]=r&255
 def run(self,maxsteps=10000000):
  while self.steps<maxsteps:
   self.steps+=1
   # Mock 30/25 Hz ticks using a deterministic instruction-count clock.
   # Real-time performance and interrupt behaviour are not modelled.
   if self.steps%1000==0:self.ticks+=1;self.mem[0x4288]=self.ticks&255
   if self.break_at is not None and self.ticks>=self.break_at:self.mem[0x3840]=4
   p=self.pc
   if p==0x402d:return self
   if p in (0x441c,0x4424,0x4428,0x0013,0x0049,0x0033):
    if p==0x441c:
     de=self.pair(1);self.mem[de:de+9]=b'TEST/MID\x03';self.z=True
    elif p==0x4424:self.z=True
    elif p==0x4428:self.closed=True;self.z=True
    elif p==0x0013:
     if self.pos<len(self.smf):self.r[7]=self.smf[self.pos];self.pos+=1;self.z=True
     else:self.r[7]=0x1c;self.z=False
    elif p==0x0049:self.r[7]=ord(self.clock)
    elif p==0x0033:self.text+=chr(self.r[7])
    self.pc=self.pop();continue
   op=self.fetch()
   if 0x40<=op<=0x7f:self.set((op>>3)&7,self.get(op&7))
   elif op&0xc7==0x06:self.set((op>>3)&7,self.fetch())
   elif op&0xcf==0x01:self.setpair((op>>4)&3,self.fetchw())
   elif op&0xcf in (0x03,0x0b):i=(op>>4)&3;self.setpair(i,self.pair(i)+(1 if op&15==3 else -1))
   elif op&0xc7 in (4,5):i=(op>>3)&7;v=(self.get(i)+(1 if op&7==4 else -1))&255;self.set(i,v);self.z=v==0
   elif op&0xcf==9:
    x=self.pair(2)+self.pair((op>>4)&3);self.setpair(2,x);self.c=x>65535
   elif op==0x3a:self.r[7]=self.mem[self.fetchw()]
   elif op==0x32:self.mem[self.fetchw()]=self.r[7]
   elif op==0x2a:self.setpair(2,self.word(self.fetchw()))
   elif op==0x22:self.writeword(self.fetchw(),self.pair(2))
   elif op==0x1a:self.r[7]=self.mem[self.pair(1)]
   elif 0x80<=op<=0xbf:self.alu((op>>3)&7,self.get(op&7))
   elif op in (0xd6,0xe6,0xee,0xf6,0xfe):self.alu((op>>3)&7,self.fetch())
   elif op==0xed:
    sub=self.fetch();i=(sub>>4)&3
    if sub&0xcf==0x43:self.writeword(self.fetchw(),self.pair(i))
    elif sub&0xcf==0x4b:self.setpair(i,self.word(self.fetchw()))
    elif sub&0xcf in (0x42,0x4a):
     x=self.pair(2);v=self.pair(i)+int(self.c);add=sub&15==10;res=x+v if add else x-v;self.setpair(2,res);self.c=res>65535 if add else res<0;self.z=(res&65535)==0
    else:raise AssertionError((hex(p),hex(op),hex(sub)))
   elif op==0xcb:sub=self.fetch();assert 0x40<=sub<=0x7f;self.z=not (self.get(sub&7)&(1<<((sub>>3)&7)))
   elif op==0xc3:self.pc=self.fetchw()
   elif op&0xc7==0xc2:a=self.fetchw();self.pc=a if self.cond((op>>3)&7) else self.pc
   elif op==0xcd:a=self.fetchw();self.push(self.pc);self.pc=a
   elif op==0xc9:self.pc=self.pop()
   elif op&0xc7==0xc0:
    if self.cond((op>>3)&7):self.pc=self.pop()
   elif op&0xcf==0xc5:i=(op>>4)&3;assert i<3;self.push(self.pair(i))
   elif op&0xcf==0xc1:i=(op>>4)&3;assert i<3;self.setpair(i,self.pop())
   elif op==0x10:
    d=self.fetch();self.r[0]=(self.r[0]-1)&255
    if self.r[0]:self.pc=(self.pc+(d if d<128 else d-256))&65535
   elif op==0xdb:assert self.fetch()==0xea;self.r[7]=64 if self.uart_ok else 0
   elif op==0xd3:
    port=self.fetch();v=self.r[7];self.ports.append((port,v))
    if port==0xeb:self.uart.append((self.ticks,v))
   else:raise AssertionError((hex(p),hex(op)))
  raise AssertionError('step limit exceeded')
def smf(track,division=96):return b'MThd'+struct.pack('>IHHH',6,0,1,division)+b'MTrk'+struct.pack('>I',len(track))+track
# Tempo 500000, note on, running-status note off after 96 ticks, tempo 250000,
# SysEx skip, program change, note-on and note-off after another 96 ticks.
track=bytes.fromhex('00 FF 51 03 07 A1 20 00 90 3C 64 60 3C 00 00 FF 51 03 03 D0 90 00 F0 03 43 00 F7 00 C0 30 00 90 40 50 60 80 40 00 00 FF 2F 00')
expected=bytes.fromhex('90 3C 64 90 3C 00 C0 30 90 40 50 80 40 00')
for rate in ('2','3'):
 c=CPU(smf(track),rate).run();assert 'End of MIDI' in c.text and c.closed,c.text
 actual=bytes(v for _,v in c.uart);assert actual[:len(expected)]==expected,(actual.hex(),expected.hex())
 assert len(actual)==len(expected)+16*12
 assert c.ports[:3]==[(0xe8,0),(0xe9,0xee),(0xea,0x6f)]
 print('PASS clock',rate,'UART stream, running status, tempo, SysEx skip, close and cleanup; ticks', [t for t,_ in c.uart[:len(expected)]])
c=CPU(smf(track),break_at=8).run();assert 'Playback stopped' in c.text and c.closed;print('PASS BREAK cleanup')
c=CPU(smf(track),uart_ok=False).run();assert 'UART not ready' in c.text and c.closed;print('PASS UART timeout cleanup')
c=CPU(smf(bytes.fromhex('00 90 3C'))).run();assert 'unsupported' in c.text and c.closed;print('PASS truncated track rejection')
c=CPU(b'INVALID').run();assert 'unsupported' in c.text and c.closed;print('PASS invalid header rejection')
# Validate complete adapted file against decoded MIDI messages, if available.
if (ROOT/'NYSTATE.MID').exists():
 import mido
 f=ROOT/'NYSTATE.MID';m=mido.MidiFile(f)
 expected=bytes(b for msg in m.tracks[0] if not msg.is_meta and msg.type!='sysex' for b in msg.bytes())
 c=CPU(f.read_bytes()).run(maxsteps=15000000);actual=bytes(v for _,v in c.uart)
 assert actual[:len(expected)]==expected and len(actual)==len(expected)+192 and c.closed,c.text
 print('PASS complete adapted song:',len(expected),'MIDI bytes,',c.steps,'executed instructions (mock clock)')
