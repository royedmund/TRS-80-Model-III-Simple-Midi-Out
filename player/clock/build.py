from pathlib import Path
from assembler import asm,parse_cmd,record
import hashlib
p=Path(__file__).resolve().parent
b=(p/'MIDISD-base.CMD').read_bytes()
assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()=='6afd5600e2207c987aeea06d9755708356a42067'
m,loaded,entry=parse_cmd(b)
org,code,L,lst=asm((p/'CLOCKHOOK.ASM').read_text())
assert org==0x6425 and org+len(code)<0x65fb and not any(m[org:org+len(code)])
m[org:org+len(code)]=code
def patch(a,old,new):
 assert m[a:a+len(old)]==old,(hex(a),m[a:a+len(old)].hex())
 assert len(old)==len(new)
 m[a:a+len(new)]=new
def hook(addr,old,label,opcode=0xcd):
 patch(addr,old,bytes([opcode])+L[label].to_bytes(2,'little'))
hook(0x63fc,b'\xcd\xfb\x65','FRAME_START')
hook(0x61dd,b'\xcd\xac\x62','CLOCK_TEMPO')
hook(0x6422,b'\xc3\xfb\x65','FRAME_MIDI',0xc3)
# Replace complete 10-byte buffer_tick routine with a jump and padding.
patch(0x6418,b'\x3a\x39\x7c\xb7\xc8\x3e\xf8\xc3\xfb\x65',b'\xc3'+L['FRAME_TICK'].to_bytes(2,'little')+bytes(7))
patch(0x63ac,bytes.fromhex('3a5c7c3c325c7c'),b'\xcd'+L['WAIT_START'].to_bytes(2,'little')+bytes(4))
patch(0x63c3,b'\xcd\x18\x64',bytes(3))
hook(0x6648,b'\xcd\xfb\x65','FRAME_FINISH')
for a,end,v in [(0x6960,0x6993,b'\rTRS-80 MODEL III MIDISD v0.4\rBREAK: Exit\r\0'),(0x6993,0x69ef,b'\rRaw: 2=25Hz, 3=30Hz\rFramed clock: 4=25Hz, 5=30Hz (v0.2 firmware)\rBREAK: Exit\r\0'),(0x80f8,0x811b,b'MIDISD - FREHD SD\rDIRECTORY:\r\0')]:
 assert len(v)<=end-a
 m[a:end]=v.ljust(end-a,b'\0')
cmd=record(entry,bytes(m[entry:max(loaded)+1]))+b'\x02\x02\x00\x60'
assert parse_cmd(cmd)==(m,loaded,entry)
(p/'MIDISD.CMD').write_bytes(cmd);(p/'CLOCKHOOK.lst').write_text(lst)
print('Built',len(cmd),'bytes',hashlib.sha256(cmd).hexdigest())
