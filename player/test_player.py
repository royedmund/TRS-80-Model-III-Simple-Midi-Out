#!/usr/bin/env python3
"""Mock Z80 execution of CMD, based on the repository test harness.
Not full-system emulation; DOS, UART and keyboard behaviour are simulated.
"""
from pathlib import Path
import struct
ROOT=Path(__file__).resolve().parent
SYMS={k:int(v,16) for v,k in (l.split() for l in (ROOT/'MIDIPLAY.MAP').read_text().splitlines())}
class CPU:
 def __init__(self,smf,clock='3',break_at=None,uart_ok=True,break_pc=None,break_after_bytes=None,latched_pc=None,stale_flag=False,no_file=False, capture=False):
  self.mem=bytearray(65536);p=0;cmd=(ROOT/'MIDIPLAY.CMD').read_bytes()
  while cmd[p]==1:
   n=cmd[p+1] or 256;adr=int.from_bytes(cmd[p+2:p+4],'little');self.mem[adr:adr+n-2]=cmd[p+4:p+2+n];p+=n+2
  assert cmd[p:p+2]==bytes([2,2]);self.pc=int.from_bytes(cmd[p+2:p+4],'little');self.sp=0xf000
  self.r=[0]*8;self.z=False;self.c=False;self.steps=0;self.ticks=0;self.smf=smf;self.pos=0;self.clock=clock;self.break_at=break_at;self.uart_ok=uart_ok;self.uart=[];self.ports=[];self.text='';self.closed=False;self.break_pc=break_pc;self.break_after_bytes=break_after_bytes;self.opened=False
  self.capture=capture;self.frames=[];self.programs=[];self.stream_frames=[]
  self.no_file=no_file;self.latched_pc=latched_pc;self.latched_fired=False;self.mem[0x429f]=0x42|int(stale_flag)
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
   if self.steps%1000==0:self.ticks+=1;self.mem[0x4288]=self.ticks&255
   if (self.break_at is not None and self.ticks>=self.break_at) or self.pc==self.break_pc or (self.break_after_bytes is not None and len(self.uart)>=self.break_after_bytes):self.mem[0x3840]=4
   if self.pc==self.latched_pc and not self.latched_fired:self.mem[0x429f]|=1;self.latched_fired=True
   p=self.pc
   if self.capture and p==SYMS['stream_render_done']:self.stream_frames.append((self.ticks,bytes(self.mem[0x3ec0:0x3f00])))
   if self.capture and p==SYMS['render_done']:self.frames.append((self.ticks,bytes(self.mem[0x3c00:0x4000])))
   if self.capture and p==SYMS['observe_program_done']:self.programs.append(bytes(self.mem[0x3cc0:0x3d00]))
   if p==0x402d:return self
   if p in (0x441c,0x4424,0x4428,0x0013,0x002b,0x0033):
    if p==0x441c:
     assert self.pair(2)==0x5000, 'DOS command tail lost'
     assert self.text.startswith('\rTRS-80 MODEL III MIDI PLAYER v0.9\rPress BREAK to Exit\r'), 'launch banner not displayed before FSPEC'
     de=self.pair(1);self.mem[de:de+9]=b'TEST/MID\x03';self.z=not self.no_file
    elif p==0x4424:self.z=True;self.opened=True
    elif p==0x4428:assert self.opened and not self.closed;self.closed=True;self.z=True
    elif p==0x0013:
     if self.pos<len(self.smf):self.r[7]=self.smf[self.pos];self.pos+=1;self.z=True
     else:self.r[7]=0x1c;self.z=False
    elif p==0x002b:self.r[7]=ord(self.clock) if self.clock else 0
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
   elif op==0xcb:
    sub=self.fetch();mask=1<<((sub>>3)&7);reg=sub&7
    if 0x40<=sub<=0x7f:self.z=not (self.get(reg)&mask)
    elif 0x80<=sub<=0xbf:self.set(reg,self.get(reg)&~mask)
    else:raise AssertionError(hex(sub))
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
track=bytes.fromhex('00 FF 51 03 07 A1 20 00 90 3C 64 60 3C 00 00 FF 51 03 03 D0 90 00 F0 03 43 00 F7 00 C0 30 00 90 40 50 60 80 40 00 00 FF 2F 00')
expected=bytes.fromhex('90 3C 64 90 3C 00 C0 30 90 40 50 80 40 00')
panic=bytes(x for ch in range(16) for cc in (64,66,67,123) for x in (0xb0+ch,cc,0))
def sent(c):return bytes(v for _,v in c.uart)
def stopped(c,cleanup):
 assert 'Playback stopped' in c.text and c.closed and c.sp==0xf000 and c.pc==0x402d,c.text
 assert c.mem[0x429f]==0x42, 'BREAK flag not cleared or unrelated flags changed'
 if cleanup:assert sent(c).endswith(panic)
 else:assert not c.uart and not c.ports
for rate in ('2','3'):
 c=CPU(smf(track),rate).run();assert 'End of MIDI' in c.text and c.closed and c.sp==0xf000
 assert sent(c)==expected+panic
 assert c.text.count("Press BREAK to Exit")==3 and c.mem[0x429f]==0x42
 assert c.ports[:3]==[(0xe8,0),(0xe9,0xee),(0xea,0x6f)]
 print('PASS normal playback',rate,'complete MIDI stream and cleanup')
for label in ('header_loop','ask','threshold_loop'):
 c=CPU(smf(track),break_pc=SYMS[label]).run();stopped(c,False);print('PASS BREAK at',label)
c=CPU(smf(track),clock='',break_at=4).run();stopped(c,False);print('PASS BREAK while waiting for clock selection')
c=CPU(smf(track),clock='\x01').run();stopped(c,False);print('PASS ROM BREAK code at clock selection')
c=CPU(smf(track),break_pc=SYMS['wait_loop']).run();stopped(c,True);assert sent(c)==expected[:3]+panic;print('PASS BREAK during playback delay, held key, full cleanup')
c=CPU(smf(track),break_after_bytes=1).run();stopped(c,True);assert sent(c)==expected[:3]+panic;print('PASS BREAK mid-message completes message before cleanup')
c=CPU(smf(track),break_pc=SYMS['skip']).run();stopped(c,True);assert sent(c)==expected[:6]+panic;print('PASS BREAK during SysEx skip')
c=CPU(smf(track),uart_ok=False).run();assert 'UART not ready' in c.text and c.closed and c.sp==0xf000;print('PASS UART timeout exit')
c=CPU(smf(bytes.fromhex('00 90 3C'))).run();assert 'unsupported' in c.text and c.closed;print('PASS truncated track rejection')
c=CPU(b'INVALID').run();assert 'unsupported' in c.text and c.closed;print('PASS invalid header rejection')

# LDOS interrupt latch captures a short BREAK even after physical key release.
c=CPU(smf(track),latched_pc=SYMS['ask']).run();stopped(c,False);assert 'Press BREAK to Exit' in c.text and c.mem[0x3840]==0;print('PASS latched BREAK at clock prompt')
c=CPU(smf(track),latched_pc=SYMS['wait_loop']).run();stopped(c,True);assert sent(c)==expected[:3]+panic and c.mem[0x3840]==0;print('PASS latched BREAK during playback delay')
c=CPU(smf(track),latched_pc=0x0013).run();stopped(c,False);print('PASS latched BREAK during DOS disk read')
c=CPU(smf(track),stale_flag=True).run();assert sent(c)==expected+panic and c.closed and c.mem[0x429f]==0x42;print('PASS stale BREAK cleared at entry, other flags preserved')
c=CPU(smf(track),break_pc=SYMS['start']).run();assert 'Playback stopped' in c.text and not c.opened and not c.uart and c.sp==0xf000;print('PASS BREAK before file open')

c=CPU(smf(track),no_file=True).run();assert 'Press BREAK to Exit' in c.text and 'Usage:' in c.text and not c.opened and c.sp==0xf000;print('PASS launch banner before usage, no filename')
c=CPU(b'INVALID').run();assert c.text.index('Press BREAK to Exit')<c.text.index('unsupported');print('PASS launch banner before invalid file error')
c=CPU(smf(track),break_pc=0x0033).run();assert 'Press BREAK to Exit' in c.text and 'Playback stopped' in c.text and not c.opened and c.sp==0xf000;print('PASS BREAK during launch banner, no file open')
c=CPU(b'',latched_pc=0x0013).run();stopped(c,False);print('PASS BREAK during failing DOS read')

# Live display tests: snapshots taken from actual executed writes to VRAM.
def row(frame,n):return frame[n*64:(n+1)*64].decode('ascii').rstrip()
def snap(c):return [f for _,f in c.frames]
# Bass note C2, C major upper chord, then note-off (including velocity zero).
# Use 96-tick waits to allow a refresh between each distinct state.
ui_track=bytes.fromhex('00 C0 30 00 B0 40 7F 00 90 24 60 00 90 3C 60 00 90 40 60 00 90 43 60 60 80 40 00 60 90 43 00 60 B0 7B 00 60 B0 40 00 60 FF 2F 00')
c=CPU(smf(ui_track),capture=True).run(); f=snap(c)
assert any(row(x,3).startswith('UPRIGHT BASS + PIANO 1') and row(x,6).strip()=='C2' and row(x,9).split()==['C4','E4','G4'] and 'ON' in row(x,4) for x in f),[row(x,9) for x in f]
print('PASS live split voice, bass, C major chord tones and sustain ON')
assert any(row(x,9).split()==['C4','G4'] for x in f)
assert any(row(x,9).split()==['C4'] for x in f)
assert any(not row(x,6).strip() and not row(x,9).strip() for x in f)
print('PASS Note Off, zero velocity Note On, All Notes Off remove held notes')
assert bytes(c.mem[0x3d80:0x3dc0])==b' '*64 and bytes(c.mem[0x3e40:0x3e80])==b' '*64
assert bytes(c.mem[SYMS['active_notes']:SYMS['active_notes']+128])==b'\0'*128
print('PASS exit clears live note fields')
# Full 128-program mapping, including all Yamaha aliases and decimal fields.
program_track=b''.join(bytes([0,0xc0,p]) for p in range(128))+bytes.fromhex('00 FF 2F 00')
c=CPU(smf(program_track),capture=True).run();assert len(c.programs)==128
voice=['PIANO 1','PIANO 2','ELEC. PIANO 1','ELEC. PIANO 2','HARPSICHORD','GUITAR','STRINGS','BRASS','CHOIR','UPRIGHT BASS','ELECTRIC BASS','SLAP BASS']
for i,line in enumerate(c.programs):
 if 48<=i<96:
  b,u=divmod(i-48,16);v=voice[9+b]+' + '+voice[u%9]
 else:v=voice[(i if i<48 else i-96)%12]
 assert line[:40].decode().rstrip()==v and line[40:43].decode()==f'{i:03d}',(i,line,v)
assert sent(c)==b''.join(bytes([0xc0,p]) for p in range(128))+panic
print('PASS all 128 native program numbers and aliases; MIDI stream unchanged')
# Boundary pitches and display overflow; other channels pass through unmodified.
notes=[0,1,54,55,127]+list(range(60,73))
t=b''.join(bytes([0,0x90,n,90]) for n in notes)+bytes.fromhex('00 91 3B 60 60 FF 2F 00')
c=CPU(smf(t),capture=True).run();f=snap(c)
assert any(row(x,6).split()==['C-1','C#-1','F#3'] for x in f)
assert any(row(x,9).startswith('G3') and row(x,9).endswith('+') for x in f)
assert all('B3' not in row(x,9).split() for x in f)
assert sent(c)==b''.join(bytes([0x90,n,90]) for n in notes)+bytes.fromhex('91 3B 60')+panic
print('PASS boundary notes, overflow indicator, other channels forwarded')
# Top note alone and G3 split boundary.
c=CPU(smf(bytes.fromhex('00 90 7F 60 00 90 37 60 60 FF 2F 00')),capture=True).run()
assert any(row(x,9).split()==['G3','G9'] for x in snap(c))
print('PASS upper MIDI pitch 127 and split boundary 55')
c=CPU(smf(ui_track),break_pc=SYMS['render_loop']).run();stopped(c,True)
assert bytes(c.mem[0x3d80:0x3dc0])==b' '*64 and bytes(c.mem[0x3e40:0x3e80])==b' '*64
print('PASS BREAK during live redraw, cleanup and note fields cleared')
# Optional complete file test; supply an EMT-10 arrangement on command line.
if __name__=='__main__':
 import sys
 for arg in sys.argv[1:]:
  import mido
  p=Path(arg); mf=mido.MidiFile(p)
  expected_song=bytes(b for msg in mf.tracks[0] if not msg.is_meta and (msg.type!='sysex' or (tuple(msg.data[:4])==(0x43,0x73,0x11,0x11) and len(msg.data)==5 and msg.data[4] in (7,8,9,23,24,25,64,65,80,81,96,97,112,113,114))) for b in msg.bytes())
  c=CPU(p.read_bytes()).run(maxsteps=20000000)
  assert sent(c)==expected_song+panic and c.closed and c.sp==0xf000 and 'End of MIDI' in c.text
  print('PASS full arrangement',p.name,len(expected_song),'MIDI bytes + cleanup; mock clock')

# Timed Nano protocol: raw MIDI events remain unaltered between markers.
for rate,start_token in [('4',0xfd),('5',0xf9)]:
 c=CPU(smf(track),clock=rate).run(); wire=sent(c)
 assert wire[0]==start_token and wire[-1]==0xfa and 0xf8 in wire
 assert bytes(b for b in wire[1:-1] if b!=0xf8)==expected
 assert c.closed and c.sp==0xf000
 print('PASS buffered mode',rate,'START/tick/END protocol and exact MIDI data')
 c=CPU(smf(track),clock=rate,break_pc=SYMS['wait_loop']).run();wire=sent(c)
 assert wire==bytes([start_token])+expected[:3]+bytes([0xfc]),wire.hex()
 assert 'Playback stopped' in c.text and c.closed and c.sp==0xf000
 print('PASS buffered BREAK sends immediate STOP, no duplicate host panic',rate)
# Accepted Yamaha SysEx, unknown vendor/command, F7 escape, malformed end.
valid=bytes.fromhex('43 73 11 11 07 F7')
unknown=bytes.fromhex('43 73 11 11 06 F7')
for rate in ('2','4'):
 t=b'\x00\xf0\x06'+valid+b'\x00\xf0\x06'+unknown+b'\x00\xf7\x06'+valid+b'\x00\xf0\x06'+valid[:-1]+b'\x00'+b'\x00\xff\x2f\x00'
 c=CPU(smf(t),clock=rate).run();wire=sent(c)
 assert wire==(b'\xf0'+valid+panic if rate=='2' else b'\xfd\xf0'+valid+b'\xfa'),wire.hex()
 print('PASS complete whitelisted SysEx, unknown/escape/malformed skip',rate)
c=CPU(smf(b'\x00\xf0\x06'+valid+b'\x00\xff\x2f\x00'),clock='4',break_pc=SYMS['sxread']).run()
assert sent(c)==b'\xfd\xfc' and c.closed
print('PASS BREAK while reading SysEx emits no partial message')

# TX monitor tests: actual screen output, final partial tick, wrap and filtering.
def txrow(c): return bytes(c.mem[0x3ec0:0x3f00]).decode('ascii').split()
for rate in ('2','3','4','5'):
 c=CPU(smf(track),clock=rate,capture=True).run()
 assert txrow(c)==[f'{b:02X}' for b in expected],txrow(c)
 assert len(c.stream_frames)>1
 assert any(b'90 3C 64' in f for _,f in c.stream_frames)
 print('PASS live hex stream, final partial tick and transport/cleanup filtering',rate)
# More than 16 bytes, another channel and whitelisted SysEx.
t=b''.join(bytes([0,0x91,n,0x7f]) for n in range(40,49))+b'\x00\xf0\x06'+valid+b'\x00\xff\x2f\x00'
want=b''.join(bytes([0x91,n,0x7f]) for n in range(40,49))+b'\xf0'+valid
for rate in ('2','4'):
 c=CPU(smf(t),clock=rate,capture=True).run()
 assert txrow(c)==[f'{b:02X}' for b in want[-16:]],txrow(c)
 assert b' '.join(f'{b:02X}'.encode() for b in want[-16:]) in c.stream_frames[-1][1]
 print('PASS monitor ring wrap, other-channel bytes and full SysEx',rate)
c=CPU(smf(track),clock='4',break_pc=SYMS['wait_loop']).run()
assert txrow(c)==['90','3C','64'] and sent(c)==b'\xfd'+expected[:3]+b'\xfc'
print('PASS BREAK retains last musical bytes and sends STOP')
