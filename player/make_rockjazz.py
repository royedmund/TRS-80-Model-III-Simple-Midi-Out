#!/usr/bin/env python3
"""Original EMT-10 jazz-rock demo. MIT project code and original composition.
Run with Python and mido. Native patch numbers, no GM drums or unsupported bends.
ROCKJAZZ includes verified Yamaha parameter SysEx; ROCKRAW omits those events.
"""
import random
from pathlib import Path
from itertools import product
import mido
R=Path(__file__).resolve().parent
PPQN=96; BEAT=96; BAR=384; BPM=176
rng=random.Random(8010)
voices=['Piano 1','Piano 2','Electric Piano 1','Electric Piano 2','Harpsichord','Guitar','Strings','Brass','Choir','Upright Bass','Electric Bass','Slap Bass']
programs=list(range(12))+[48+b*16+u for b in range(3) for u in range(9)]
# Four-bar turnaround with altered dominant; rotate by section through nearby keys.
progression=[(38,[62,65,69,72],[62,64,65,67,69,71,72,74]),(43,[62,65,67,71],[67,69,71,72,74,76,77,79]),(36,[60,64,67,71],[60,62,64,65,67,69,71,72]),(45,[61,64,67,70],[61,64,65,67,69,70,73,76])]
events=[]; seq=0

def add(t,msg):
 global seq
 events.append((t,seq,msg)); seq+=1

def cc(t,c,v):add(t,mido.Message('control_change',control=c,value=v))
def sx(t,n):add(t,mido.Message('sysex',data=[0x43,0x73,0x11,0x11,n]))
def note(t,p,d,v):
 assert 21<=p<=108
 add(t,mido.Message('note_on',note=p,velocity=v));add(t+d,mido.Message('note_off',note=p,velocity=0))

def patch_name(p):
 if p<12:return voices[p]
 b,u=divmod(p-48,16);return voices[9+b]+' + '+voices[u]

add(0,mido.MetaMessage('track_name',name='Silicon After Hours - original jazz-rock for Yamaha EMT-10'))
add(0,mido.MetaMessage('set_tempo',tempo=mido.bpm2tempo(BPM)))
add(0,mido.MetaMessage('time_signature',numerator=4,denominator=4))
# Baseline panel settings, restored again at the end.
for x in (8,24,65,80,96,112):sx(0,x)
for k,p in enumerate(programs):
 start=k*4*BAR; split=p>=48; upper=(p-48)%16 if split else p
 add(start,mido.MetaMessage('marker',text=patch_name(p)))
 for c in (64,66,67,123):cc(start,c,0)
 add(start,mido.Message('program_change',program=p))
 bright,attack=list(product((8,7,9),(24,23,25)))[k%9]
 sx(start+1,bright);sx(start+1,attack)
 # Demonstrate 4 vs 8 polyphony only on solo sustained voices.
 if p in (6,7,8):sx(start+2,64 if p==6 else 65)
 # Touch curve, bass octave, note grouping in dedicated musical passages.
 sx(start+2,81 if k%5==2 else 80)
 sx(start+2,97 if p in (10,11,64,80) else 96)
 sx(start+2,113 if p==4 else 114 if p==5 else 112)
 shift=(0,0,2,0,-2,0,2,0)[k%8]
 for bar,(root,ch,scale) in enumerate(progression):
  t=start+bar*BAR;root+=shift;ch=[n+shift for n in ch];scale=[n+shift for n in scale]
  # Fold root into bass zone; pitch choice explicitly avoids upper zone.
  while root>42:root-=12
  while root<33:root+=12
  # Two alternating grooves, sixteenths and swung syncopation.
  if split or p>=9:
   riff=[(12,0,29),(48,7,30),(96,0,38),(144,10,23),(180,7,28),(216,12,36),(264,7,30),(312,3,21),(348,11,19)] if (bar+k)%2==0 else [(12,0,38),(60,0,23),(96,7,40),(156,12,21),(192,10,34),(240,7,38),(300,3,27),(336,11,31)]
   for j,(off,interval,d) in enumerate(riff):
    pitch=root+interval
    while pitch>54:pitch-=12
    note(t+off,pitch,d, min(122,86+int(p in (11,) or split and p>=80)*12+rng.randrange(-10,16)))
    if split and bar==3 and off==12:
     note(t+off,root+12 if root<=42 else root-12,min(d,32),87)
  if p>=9 and not split:continue
  # Chord stabs and distinct improvised answer; no chord/lead overlap.
  # On solo sustained 4-note mode use at most 4 concurrent keys.
  if upper in (6,7,8):
   for off,d in ((12,68),(120,60),(216,72)):
    voicing=ch[:3]
    if bar==3 and off==12:
     if split:voicing=ch+[ch[0]+12,ch[1]+12]
     elif p in (7,8):voicing=ch+[n+12 for n in ch]
     elif p==6:voicing=ch
    for n in voicing:note(t+off,n,d,82+rng.randrange(-9,14))
   for j,off in enumerate((300,324,348)):
    note(t+off,scale[(k+bar+j*2)%len(scale)],19,96+rng.randrange(-8,15))
  else:
   for off,d in ((12,32),(102,26),(198,25)):
    voicing=ch+[ch[0]+12,ch[1]+12] if split and bar==3 and off==12 else ch[:3]
    for n in voicing:note(t+off,n,d,86+rng.randrange(-12,14))
   for j,off in enumerate((48,72,144,168,240,264,288,312,336,360)):
    degree=(k+bar*2+j*3+rng.randrange(3))%len(scale)
    pitch=scale[degree]+(12 if j in (7,8) and (k+bar)%3==0 else 0)
    note(t+off,pitch, min(19, BAR-off-3),92+rng.randrange(-14,23))
  # Pedals are applied to isolated stabs, released before the next phrase.
  if bar==0 and upper<=5:
   cc(t+10,64,127);cc(t+46,64,0)
  if bar==1 and upper in (6,7,8):
   cc(t+20,66,127);cc(t+85,66,0)
  if bar==2 and upper<=5:
   cc(t+8,67,127);cc(t+85,67,0)
  # Explicit return to normal grouping after first bar, other settings
  # are reset at each new program.
  if bar==0 and p in (4,5):sx(t+BAR-1,112)
end=len(programs)*4*BAR
for c in (64,66,67,123):cc(end,c,0)
for x in (8,24,65,80,96,112):sx(end,x)
add(end+BEAT,mido.MetaMessage('end_of_track'))
for name,fx in [('ROCKJAZZ.MID',True),('ROCKRAW.MID',False)]:
 mf=mido.MidiFile(type=0,ticks_per_beat=PPQN);tr=mido.MidiTrack();mf.tracks.append(tr);prev=0
 for t,_,msg in sorted(events,key=lambda x:(x[0],x[1])):
  if not fx and msg.type=='sysex':continue
  tr.append(msg.copy(time=t-prev));prev=t
 mf.save(R/name)
 # Re-read binary and independently validate program coverage, note pairs,
 # polyphony, all-effects coverage and MIDIPLAY limits.
 m=mido.MidiFile(R/name); held=set(); seen=[]; effects=set(); maxlow=maxhigh=maxall=0; split=False
 for msg in m.tracks[0]:
  assert 0<=msg.time<=65535
  if msg.type=='program_change':
   assert not held;seen.append(msg.program);split=msg.program>=48
  elif msg.type=='sysex':effects.add(msg.data[-1])
  elif msg.type=='note_on' and msg.velocity:
   assert msg.note not in held;held.add(msg.note)
   low=sum(n<55 for n in held);high=len(held)-low
   if split:assert low<=2 and high<=6,(seen[-1],low,high,held);maxlow=max(maxlow,low);maxhigh=max(maxhigh,high)
   maxall=max(maxall,len(held));assert len(held)<=8
  elif msg.type in ('note_on','note_off'):
   assert msg.note in held;held.remove(msg.note)
 assert not held and seen==programs and (R/name).stat().st_size-22<=65535
 assert effects==({7,8,9,23,24,25,64,65,80,81,96,97,112,113,114} if fx else set())
 print(name, (R/name).stat().st_size,'bytes',round(m.length,2),'s',len(seen),'programs',len(effects),'SysEx codes; max held',maxall,'split',maxlow,maxhigh)
