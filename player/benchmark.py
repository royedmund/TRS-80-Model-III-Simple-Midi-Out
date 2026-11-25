#!/usr/bin/env python3
"""Compare v0.6/v0.7 Z80 instructions with identical logical clock.
Mock LDOS clock advances at wait deadlines, excluding idle spinning.
Not a real-time or cycle-accurate benchmark. No song data is distributed.
Usage: python benchmark.py /path/to/v06 [arrangement.mid ...]
"""
from pathlib import Path
import sys, struct, random
ROOT=Path(__file__).resolve().parent

def load_cpu(root):
    p=root/'test_player.py'
    source=p.read_text().split('\ntrack=bytes.fromhex',1)[0]
    old='   if self.steps%1000==0:self.ticks+=1;self.mem[0x4288]=self.ticks&255'
    assert old in source
    source=source.replace(old, '''   if self.pc==SYMS['wait_loop'] and self.mem[0x4288]!=self.mem[SYMS['target']]:
    self.ticks+=1;self.mem[0x4288]=self.ticks&255''')
    scope={'__file__':str(p)};exec(compile(source,str(p),'exec'),scope)
    return scope['CPU']

def smf(track,division=96):
    return b'MThd'+struct.pack('>IHHH',6,0,1,division)+b'MTrk'+struct.pack('>I',len(track))+track

def vlq(n):
    out=[n&127];n>>=7
    while n:out.insert(0,(n&127)|128);n>>=7
    return bytes(out)

def synth(division, pairs):
    track=bytearray();expected=[];elapsed=0
    for n,(delta,tempo) in enumerate(pairs):
        track+=b'\x00\xff\x51\x03'+tempo.to_bytes(3,'big')
        msg=bytes([0x90,60+n%12,100 if n%2==0 else 0]);track+=vlq(delta)+msg
        elapsed+=delta*tempo;expected.append((elapsed,msg))
    track+=b'\x00\xff\x2f\x00'
    return smf(track,division),expected

def check(cpu, data, expected, division, rate):
    c=cpu(data,rate).run(maxsteps=30000000)
    assert c.closed and c.sp==0xf000 and 'End of MIDI' in c.text
    threshold=division*(40000 if rate=='2' else 33333)
    expected_bytes=[(elapsed//threshold,b) for elapsed,msg in expected for b in msg]
    assert c.uart[:len(expected_bytes)]==expected_bytes, (c.uart[:15],expected_bytes[:15])
    panic=bytes(x for ch in range(16) for cc in (64,66,67,123) for x in (0xb0+ch,cc,0))
    assert bytes(b for _,b in c.uart[len(expected_bytes):])==panic
    return c

def compare(label, data, expected, division, rate, old, new):
    a=check(old,data,expected,division,rate); b=check(new,data,expected,division,rate)
    assert a.uart==b.uart and a.ticks==b.ticks
    print(f'PASS {label} {rate}: identical UART bytes and logical tick deadlines; {a.steps:,} -> {b.steps:,} instructions ({100*(1-b.steps/a.steps):.1f}% fewer); {a.ticks:,} elapsed ticks',flush=True)

if __name__=='__main__':
    old=load_cpu(Path(sys.argv[1]).resolve());new=load_cpu(ROOT)
    rng=random.Random(80)
    pairs=[(n,500000) for n in (0,1,2,3,4,5,15,16,17,127,128,129,255,256,257,65535)]
    pairs += [(rng.randrange(0,1000),rng.randrange(1,0x1000000)) for _ in range(30)]
    for rate in ('2','3'):
        for arg in sys.argv[2:]:
            import mido
            p=Path(arg);m=mido.MidiFile(p);tempo=500000;elapsed=0;expected=[]
            for msg in m.tracks[0]:
                elapsed+=msg.time*tempo
                if msg.type=='set_tempo':tempo=msg.tempo
                elif not msg.is_meta and msg.type!='sysex':expected.append((elapsed,bytes(msg.bytes())))
            compare(p.name,p.read_bytes(),expected,m.ticks_per_beat,rate,old,new)
        for name,division,p in [('boundary and random deltas',32767,pairs),('extreme phase and tempo',32767,[(127,0xffffff),(128,0xffffff),(129,0xffffff),(65535,0xffffff)]),('short musical deltas',96,[(n,500000) for n in range(130)]),('small PPQN',1,[(2,0xffffff),(4,40000),(128,1)])]:
            data,expected=synth(division,p);compare(name,data,expected,division,rate,old,new)
