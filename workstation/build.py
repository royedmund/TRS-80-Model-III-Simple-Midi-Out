from pathlib import Path
from assembler import asm,record,parse_cmd
p=Path(__file__).resolve().parent
org,b,labels,lst=asm((p/'MIDIIN.ASM').read_text()); cmd=record(org,b)+bytes([2,2])+org.to_bytes(2,'little'); (p/'MIDIIN.CMD').write_bytes(cmd); (p/'MIDIIN.lst').write_text(lst); (p/'MIDIIN.map').write_text('\n'.join(f'{a:04X} {k}' for k,a in labels.items())+'\n'); m,_,entry=parse_cmd(cmd);assert entry==org and m[org:org+len(b)]==b;print('CMD',len(cmd),'bytes',hex(org),hex(org+len(b)-1))
