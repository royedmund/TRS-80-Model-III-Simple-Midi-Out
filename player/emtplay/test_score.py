"""Restricted Z80 opcode tests for the patched display and keyboard paths.
FreHD close, DOS exit/print and LDOS flag acknowledge are mocked. Not a full emulator.
"""
from pathlib import Path
from assembler import parse_cmd
from build import build
_,L,_=build(Path('MIDISD.CMD').read_bytes())
class CPU:
    def __init__(self):
        self.m,_,_=parse_cmd(Path('EMTPLAY.CMD').read_bytes())
        self.pc=0;self.sp=0xf000;self.r=[0]*8;self.z=False;self.c=False
        self.writes=[];self.video_writes=[];self.uart=True;self.uart_reads=[];self.polls=0;self.stop_after=None;self.calls=[];self.key=0;self.extra_stops=set();self.auto_clock=False
        self.word(0x7c3b,0xf000)
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

def midi(c):return [v for port,v in c.writes if port==0xeb]
c=CPU();assert c.invoke(L['SCORE_INIT'])==0xffff
assert c.m[0x3c40:0x3c50].rstrip()==b'NATIVE EMT-10'
assert c.m[0x3c50:0x3c60].rstrip()==b'SD STREAM'
assert c.m[0x3c60:0x3c80].rstrip()==b'RAW MIDI'
assert c.m[0x3c88:0x3cb0].rstrip()==b'PANEL SETTING / NO PROGRAM SENT'
assert c.m[0x3cc0:0x3d00].rstrip()==b'UPPER NOTES (G3 AND ABOVE)'
assert c.m[0x3e40:0x3e80].rstrip()==b'BASS NOTES (BELOW G3)'
assert c.m[0x3d00:0x3e40]==c.m[0x3e80:0x3fc0]==b' '*320
assert (c.m[L['UPPER_ROW']],c.m[L['UPPER_COL']],c.m[L['BASS_ROW']],c.m[L['BASS_COL']])==(4,0,10,0)
print('PASS information header, independent upper and bass streams')
c.video_writes.clear()
def note(status,pitch,velocity):
    c.m[0x7c3f]=status;c.m[0x7c5d]=pitch;c.m[0x7c5e]=velocity
    c.pc=L['SEND_THREE'];assert c.run()==0x6118
note(0x90,60,75);note(0x90,61,80);note(0x90,42,90);note(0x90,55,90)
assert midi(c)==[0x90,60,75,0x90,61,80,0x90,42,90,0x90,55,90]
assert c.m[0x3d00:0x3d07]==b'C4C#4G3'
assert c.m[0x3e80:0x3e83]==b'F#2'
assert c.m[0x7831+60]==1
before=len(c.video_writes)
for _ in range(100):assert c.invoke(L['SCORE_STEP'])==0xffff
note(0x80,60,0);note(0x90,61,0)
assert c.m[0x7831+60]==c.m[0x7831+61]==0
assert len(c.video_writes)==before
before=midi(c);note(0x91,64,70);assert midi(c)==before
print('PASS explicit accidentals and octaves, compact split routing, no timing redraw, channel filter')
# Independent Python model of row wrap, run real renderer for every pitch
# repeated until both bands wrap several times. Compare all 1024 cells.
from build import pitch_entry
c=CPU();c.invoke(L['SCORE_INIT']);c.video_writes.clear()
expected=bytearray(c.m[0x3c00:0x4000]);rows=[4,10];cols=[0,0];starts=[4,10]
for n in list(range(128))*10:
    token=pitch_entry(n).rstrip(b'\0'); band=int(n<55)
    if cols[band]+len(token)>64:
        rows[band]=(rows[band]-starts[band]+1)%5+starts[band];cols[band]=0
        addr=rows[band]*64;expected[addr:addr+64]=b' '*64
    addr=rows[band]*64+cols[band];expected[addr:addr+len(token)]=token;cols[band]+=len(token)
    c.r[7]=n;assert c.invoke(L['DRAW_PITCH'])==0xffff
    assert c.m[0x3c00:0x4000]==expected,(n,rows,cols)
assert all((a-0x3c00)//64 in (*range(4,9),*range(10,15)) for a in c.video_writes)
assert c.m[0x3e40:0x3e80].rstrip()==b'BASS NOTES (BELOW G3)'
assert c.m[0x3fc0:0x4000].rstrip()==b'CLEAR: MENU   BREAK: EXIT'
print('PASS all 128 pitches, 1,280 note tokens, independent row wrap, protected header and labels')
for mode in (0,0xfd):
    c=CPU();c.invoke(L['SCORE_INIT']);c.m[0x7c3d]=1;c.m[0x7c3e]=1;c.m[0x7c39]=mode;c.m[0x7831+60]=1;c.m[0x3840]=2
    c.pc=0x63ca;assert c.run()==0x6000;assert c.sp==0xf000;assert 0x80d7 in c.calls
    assert midi(c)==([0xfc] if mode else [0xb0,64,0,0xb0,66,0,0xb0,67,0,0x80,60,0,0xb0,123,0]),midi(c)
    print('PASS CLEAR cleanup and picker restart, mode',hex(mode))
c=CPU();c.m[0x7c3d]=1;c.m[0x7c3e]=1;c.m[0x7c39]=0xfd;c.m[0x3840]=6;c.pc=0x63ca;assert c.run()==0x402d;assert midi(c)==[0xfc];assert c.sp==0xf000;print('PASS BREAK priority over CLEAR, DOS exit')
c=CPU();c.m[0x3840]=2;assert c.invoke(0x63ca)==0xffff;print('PASS CLEAR ignored in picker')
c=CPU();c.m[0x7c3a]=1;c.m[0x7c39]=0xfd;c.m[0x7c3e]=1;c.m[0x3840]=4;c.pc=0x6626;c.pair(2,0x6a15);assert c.run()==0x402d;assert midi(c)==[0xf3,0,0xfc];print('PASS natural EOF drain then BREAK cancels pending drain')

# Verify actual picker dispatch, not just ASCII conversion.
for key,target in [('N',0x7f96),('n',0x7f96),('R',0x7fa3),('r',0x7fa3),('U',0x7fa9),('u',0x7fa9),('1',0x7f45),('9',0x7f40),('\x01',0x63d8)]:
    c=CPU();c.key=ord(key);c.m[0x81f8]=9;c.extra_stops={target};c.pc=0x7f04
    assert c.run()==target,(key,hex(c.pc))
for key in [0,1,ord('1'),ord('9'),ord('['),ord('{'),255]:
    c=CPU();c.key=key;assert c.invoke(L['MENU_SCAN'])==0xffff;assert c.r[7]==key
print('PASS actual picker N/n, R/r, U/u dispatch; selection digits and BREAK unchanged')

from assembler import parse_cmd
base,_,_=parse_cmd(Path('MIDISD.CMD').read_bytes())
c=CPU();c.m[0x8243:0x8243+13]=b'/DEMO/ABC.MID';c.m[0x8250]=0;c.m[L['CACHE_ON']]=1;c.m[0x7c39]=0xfd;c.invoke(L['SCORE_INIT'])
assert c.m[0x3c00:0x3c40].rstrip()==b'/DEMO/ABC.MID'
assert c.m[0x3c50:0x3c60].rstrip()==b'RAM CACHE' and c.m[0x3c60:0x3c80].rstrip()==b'NANO CLOCK'
for n in range(128):
    before=bytes(c.m[0x3c00:0x4000]);c.video_writes.clear();c.m[0x7c3f]=0xc0;c.m[0x7c5d]=n;c.pc=L['SEND_TWO'];assert c.run()==0x6118
    assert c.invoke(0x6418)==0xffff
    ptr=int.from_bytes(base[0x7329+n*2:0x732b+n*2],'little');assert c.m[0x3c88:0x3cb0]==base[ptr:ptr+40]
    assert c.m[0x3c00:0x3c88]==before[:0x88] and c.m[0x3cb0:0x4000]==before[0xb0:]
    assert all(0x3c88<=a<0x3cb0 for a in c.video_writes); c.invoke(0x6418)
print('PASS filename, cache and transport info; all 128 native patch aliases update only voice line')
