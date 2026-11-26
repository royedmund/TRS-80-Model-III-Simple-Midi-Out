#!/usr/bin/env python3
"""Compare executed instruction counts on the assembled v0.2/v0.3 CMDs.
Mocked I/O, controlled clock; not measured Z80 T-states or hardware timing.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parent
prefix=(ROOT/'test_player.py').read_text().split('# Wire status is independent')[0]
def load(root):
 ns={'__file__':str(root/'test_player.py')};exec(compile(prefix,'cpu_harness','exec'),ns);return ns
old=load(ROOT/'fallback-v02');new=load(ROOT)
def measure(ns):
 CPU=ns['CPU'];SY=ns['SY'];route=ns['route'];result={}
 def prep(data):
  c=CPU();p=SY['sector'];c.m[p:p+len(data)]=data;c.m[SY['sd_readptr']:SY['sd_readptr']+2]=p.to_bytes(2,'little');c.poke('sd_avail',len(data));c.m[SY['remaining']:SY['remaining']+2]=len(data).to_bytes(2,'little');return c
 c=prep(b'x');c.run('sd_rawget');result['Buffered SD byte']=c.steps
 for name,enc in [('One-byte VLQ',b'\x7f'),('Two-byte VLQ',b'\x81\x00')]:
  c=prep(enc);c.run('vlq');result[name]=c.steps
 c=CPU();c.r[7]=0x90;c.run('send_midi');result['TX byte and monitor record']=c.steps
 for name,note in [('Kick',36),('Snare',38),('Ghost',78)]:
  c=CPU();c.poke('drum_mode',1);route(c,[0x99,note,110]);before=c.steps;n=c.peek('drum_left');
  for i in range(n):c.run('drum_slice')
  result[f'{name} (average per sample incl. delay)']=(c.steps-before)/n
 return result
print('Targeted assembled-opcode counts (mock CPU; not T-states or timing):')
a=measure(old);b=measure(new)
for name in a:print(f'{name}: {a[name]:.1f} -> {b[name]:.1f} ({100*(a[name]-b[name])/a[name]:+.1f}% fewer instructions)')
