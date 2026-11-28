"""Execute real parser and clock hooks at both LDOS rates; no physical UART.
Compare musical payloads byte-for-byte against unframed playback. Generate
wire fixtures for independent Nano decoder testing. No third-party file copied.
"""
from pathlib import Path
from test_score import CPU,L,midi

def play(path,gm,mode,piano=False):
    data=Path(path).read_bytes(); assert data[:4]==b'MThd' and data[14:18]==b'MTrk'
    assert data[8:12]==b'\0\0\0\1'
    track=data[22:22+int.from_bytes(data[18:22],'big')]
    c=CPU();base=L['CACHE_BASE'];c.m[L['CACHE_ON']]=1;c.word(L['CACHE_PTR'],base);c.word(L['CACHE_SIZE'],len(track));c.word(0x7c40,len(track));c.m[base:base+len(track)]=track
    ppqn=int.from_bytes(data[12:14],'big');c.word(0x7c42,ppqn)
    rate=30 if mode==0xf9 else 25;threshold=ppqn*(33333 if rate==30 else 40000)
    c.m[0x7c44:0x7c48]=threshold.to_bytes(4,'little');c.m[0x7c4c:0x7c50]=(500000).to_bytes(4,'little');c.auto_clock=True
    assert c.invoke(0x62ac)==0xffff
    def events(stop):
        c.extra_stops={stop}
        for i in range(20000):
            c.pc=0x611e;r=c.run()
            if r==stop:return i+1
            assert r==0x6118,hex(r)
        raise AssertionError('event limit')
    if gm:
        c.m[L['GM_MODE']]=1;c.m[L['FORCE_PIANO']]=int(piano);events(0x607d);assert not midi(c)
    c.extra_stops=set();c.m[0x7c39]=mode;c.invoke(L['SCORE_INIT']);c.invoke(L['GM_START']);events(0x61e8)
    c.extra_stops=set()
    if mode:c.r[7]=0xfa;assert c.invoke(L['FRAME_FINISH'])==0xffff
    return bytes(midi(c))

def decode(w):
    assert w[:1]==b'\xf6' and w[1] in (25,30);i=2;music=bytearray();tempos=[];ticks=0;final=False
    while i<len(w):
        tag=w[i];i+=1
        if tag==0xf1:
            t=0
            for b in w[i:i+6]:assert b<16;t=(t<<4)|b
            tempos.append((ticks,t));i+=6
        elif tag in (0xf2,0xf3):
            n=w[i];i+=1;assert n<=127 and i+n<=len(w);music+=w[i:i+n];i+=n
            if tag==0xf2:ticks+=1
            else:assert i==len(w);final=True
        else:raise AssertionError(hex(tag))
    assert final
    return bytes(music),ticks,tempos

if __name__=='__main__':
    for path,gm,piano in [('SCORETST.MID',False,False),('GMDEMO.MID',True,False),('GMDEMO.MID',True,True),('CLOCKTST.MID',False,False)]:
        raw=play(path,gm,0,piano)
        for mode,rate in ((0xfd,25),(0xf9,30)):
            wire=play(path,gm,mode,piano);musical,ticks,tempos=decode(wire)
            assert raw==musical,(path,rate,len(raw),len(musical))
            assert tempos
            fn=f'{Path(path).stem.lower()}{"p" if piano else ""}{rate}.wire';Path(fn).write_bytes(wire)
            print(f'PASS {path} {"Piano" if piano else "GM" if gm else "native"} {rate}Hz: {len(musical)} music bytes, {ticks} frames, {len(tempos)} tempo records')
