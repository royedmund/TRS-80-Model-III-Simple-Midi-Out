#!/usr/bin/env python3
"""Controlled logical-clock validation of every event and tick in timed mode."""
from pathlib import Path
from fractions import Fraction
import mido
ROOT=Path(__file__).resolve().parent
p=ROOT/'test_player.py'
s=p.read_text().split('\ntrack=bytes.fromhex',1)[0]
s=s.replace('   if self.steps%1000==0:self.ticks+=1;self.mem[0x4288]=self.ticks&255', '''   if self.pc==SYMS['wait_loop'] and self.mem[0x4288]!=self.mem[SYMS['target']]:
    self.ticks+=1;self.mem[0x4288]=self.ticks&255''')
scope={'__file__':str(p)};exec(compile(s,str(p),'exec'),scope);CPU=scope['CPU']
for name in ('ROCKJAZZ.MID','ROCKRAW.MID'):
 m=mido.MidiFile(ROOT/name)
 for rate,period,start in [('4',40000,0xfd),('5',33333,0xf9)]:
  tempo=500000;elapsed=0;events=[];bytes_by_tick={}
  for msg in m.tracks[0]:
   elapsed+=msg.time*tempo;tick=elapsed//(m.ticks_per_beat*period)
   if msg.type=='set_tempo':tempo=msg.tempo
   elif not msg.is_meta:
    for b in msg.bytes():events.append((tick,b));bytes_by_tick[tick]=bytes_by_tick.get(tick,0)+1
  c=CPU((ROOT/name).read_bytes(),clock=rate).run(maxsteps=30000000)
  assert c.closed and c.sp==0xf000 and c.uart[0]==(0,start)
  assert c.uart[-1]==(tick,0xfa)
  assert [(t,b) for t,b in c.uart[1:-1] if b!=0xf8]==events
  markers=[t for t,b in c.uart if b==0xf8];assert markers==list(range(1,tick+1))
  # Simulated RS-232 link serialization at 9600 (10 bits per byte),
  # nominal LDOS deadlines, ideal MIDI output service. Delayed disk reads
  # and AVR interrupt behaviour are not modelled.
  from collections import deque
  pending=deque();peak=0;link=0;out_free=0;late=0;due=160000
  for t,b in c.uart[1:-1]:
   link=max(link,t*period)+Fraction(10000000,9600)
   while pending and pending[0]<=link:pending.popleft()
   if b==0xf8:
    due+=period
    error=max(-100,min(100,int(link+160000-due)));due+=error
   else:
    late+=int(link>due);out_free=max(out_free,link,due)+320
    pending.append(out_free);peak=max(peak,len(pending))
  assert peak<=192 and late==0,(name,rate,peak,late)
  print(f'PASS {name} mode {rate}: {len(events)} MIDI bytes, {tick} timed ticks, peak {peak}/192 queue bytes, zero late arrivals (ideal model)')
