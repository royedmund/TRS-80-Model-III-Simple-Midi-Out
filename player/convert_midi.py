#!/usr/bin/env python3
"""Convert an SMF to format 0, or make an EMT-10 Piano 1/Upright Bass demo.
Requires mido (python -m pip install mido). Never changes the input file.
"""
import argparse, collections, heapq
from pathlib import Path
import mido

def merge(src):
    if src.type==2 or src.ticks_per_beat<=0: raise ValueError('Only synchronous PPQN type 0/1 files supported')
    dst=mido.MidiFile(type=0,ticks_per_beat=src.ticks_per_beat)
    dst.tracks.append(mido.merge_tracks(src.tracks))
    return dst

def adapt(src, bass_tracks, piano_tracks):
    # All timing comes from the supplied file's merged tempo map.
    if src.type==2 or src.ticks_per_beat<=0: raise ValueError('Expected synchronous PPQN MIDI')
    events=[]
    for ti,tr in enumerate(src.tracks):
        tick=0
        for j,msg in enumerate(tr):
            tick+=msg.time
            if msg.type=='set_tempo' or (ti in bass_tracks+piano_tracks and msg.type in ('note_on','note_off')):
                events.append((tick,ti,j,msg))
    events.sort(key=lambda x:x[:3]); last=0; elapsed=0.; tempo=500000
    # Each record is (absolute ms, status, data1, data2 or -1).
    out=[(0,0xb0,64,0),(0,0xb0,123,0),(0,0xc0,48,-1)]
    # Each sounding note has an ID, to avoid old note-offs silencing a newer note.
    live={}; queues=collections.defaultdict(collections.deque); serial=0; steals=0
    def emit(ms,st,n,v):out.append((ms,st,n,v))
    def release(ms,uid):
        if uid in live:
            note,_,_=live.pop(uid);emit(ms,0x90,note,0)
    for tick,ti,j,msg in events:
        elapsed+=(tick-last)*tempo/src.ticks_per_beat/1000;last=tick;ms=round(elapsed)
        if msg.type=='set_tempo':tempo=msg.tempo;continue
        key=(ti,msg.channel,msg.note)
        if msg.type=='note_off' or msg.velocity==0:
            if queues[key]:release(ms,queues[key].popleft())
            continue
        bass=ti in bass_tracks; note=msg.note
        # Yamaha C3=60: F#2=54, G2=55. Keep each part on its side.
        if bass:
            while note>54:note-=12
            while note<21:note+=12
        else:
            while note<55:note+=12
            while note>108:note-=12
        # Retriggering a pitch first releases the previous instance.
        for uid,(n,_,_) in list(live.items()):
            if n==note:release(ms,uid)
        group=[u for u,(n,g,p) in live.items() if g==bass]
        if len(group)>=(2 if bass else 6):
            victim=min(group,key=lambda u:(live[u][2],u));release(ms,victim);steals+=1
        serial+=1;queues[key].append(serial)
        # Higher piano track numbers get priority during voice stealing.
        live[serial]=(note,bass,ti);emit(ms,0x90,note,msg.velocity)
    end=max(round(src.length*1000),round(elapsed))
    for uid in list(live):release(end,uid)
    emit(end,0xb0,64,0);emit(end,0xb0,123,0)
    # 500 PPQN at 500000 us/qn = 1 ms per tick.
    dst=mido.MidiFile(type=0,ticks_per_beat=500); tr=mido.MidiTrack();dst.tracks.append(tr)
    tr.append(mido.MetaMessage('set_tempo',tempo=500000,time=0));prev=0
    for ms,st,a,b in out:
        data=[st,a] if b<0 else [st,a,b];msg=mido.Message.from_bytes(data);msg.time=ms-prev;tr.append(msg);prev=ms
    tr.append(mido.MetaMessage('end_of_track',time=0))
    print(f'{len(out)} events; duration {end/1000:.3f}s; {steals} explicit voice steals')
    return dst,out

def check(path):
    import struct
    data=path.read_bytes();size=struct.unpack('>I',data[18:22])[0]
    if size>65535:raise ValueError('Track exceeds MIDIPLAY 65535-byte limit')
    for msg in mido.MidiFile(path).tracks[0]:
        if msg.time>65535:raise ValueError('Delta exceeds MIDIPLAY 65535-tick limit')
        if msg.type=='sysex' and len(msg.data)>65534:raise ValueError('SysEx too large')
    print(f'{path.name}: {size} track bytes')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('input',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--emt10',action='store_true');p.add_argument('--bass',type=int,nargs='+',default=[1]);p.add_argument('--piano',type=int,nargs='+',default=[2,3]);p.add_argument('--basic-data',type=Path)
    a=p.parse_args();src=mido.MidiFile(a.input)
    if a.input.resolve()==a.output.resolve():p.error('Output must not overwrite input')
    if a.emt10:
        if any(i<0 or i>=len(src.tracks) for i in a.bass+a.piano):p.error('Track index out of range')
        if set(a.bass)&set(a.piano):p.error('Bass and piano tracks must not overlap')
        dst,events=adapt(src,a.bass,a.piano)
        if a.basic_data:
            # LDOS text records: absolute milliseconds, status, data1, data2.
            a.basic_data.write_bytes(('\r'.join(','.join(map(str,x)) for x in events)+'\r-1,0,0,0\r').encode('ascii'))
    else:
        if a.basic_data:p.error('--basic-data requires --emt10')
        dst=merge(src)
    dst.save(a.output);check(a.output)
if __name__=='__main__':main()
