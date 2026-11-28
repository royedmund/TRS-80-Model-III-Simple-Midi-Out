"""Small two-pass Z80 assembler and CMD record utilities."""
from pathlib import Path
import hashlib, re, sys
ROOT=Path(__file__).resolve().parent
ORIGINAL_SHA='c1a7efeb81039ca86ac06d8b5fba15af7fa4196f031f5d077a67da43cea7a898'
REG=['B','C','D','E','H','L','(HL)','A']; PAIR=['BC','DE','HL','SP']; COND=['NZ','Z','NC','C','PO','PE','P','M']
def asm(source):
    labels={}; result=bytearray(); listing=[]
    for phase in (0,1):
        pc=0; result.clear(); listing.clear(); origin=None
        def val(s):
            if "+" in s:
                base,offset=s.split("+",1);return val(base)+val(offset)
            if s in labels:return labels[s]
            if s.endswith('H') and re.fullmatch('[0-9A-F]+H',s):return int(s[:-1],16)
            if s.isdecimal():return int(s)
            if not phase:return 0
            raise ValueError('Unknown symbol '+s)
        def word(s):return list(val(s).to_bytes(2,'little'))
        for ln,line in enumerate(source.splitlines(),1):
            s=line.split(';',1)[0].strip().upper()
            if not s:continue
            if ':' in s:
                lab,s=s.split(':',1); labels[lab.strip()]=pc;s=s.strip()
                if not s:continue
            op,*tail=s.split(None,1); args=[x.strip() for x in tail[0].split(',')] if tail else []
            a=args[0] if args else '';b=args[1] if len(args)>1 else ''
            out=None
            if op=='ORG':pc=origin=val(a);continue
            if op=='DB':out=[val(x) for x in args]
            elif op=='DW':out=sum([word(x) for x in args],[])
            elif op=='LD':
                if a in REG and b in REG:out=[0x40+REG.index(a)*8+REG.index(b)]
                elif a=='A' and b=='(DE)':out=[0x1a]
                elif a=='(DE)' and b=='A':out=[0x12]
                elif a in PAIR and b.startswith('('):out=([0x2a] if a=='HL' else [0xed,0x4b+PAIR.index(a)*16])+word(b[1:-1])
                elif a.startswith('(') and a not in REG and b in PAIR:out=([0x22] if b=='HL' else [0xed,0x43+PAIR.index(b)*16])+word(a[1:-1])
                elif a=='A' and b.startswith('('):out=[0x3a]+word(b[1:-1])
                elif a.startswith('(') and a not in REG and b=='A':out=[0x32]+word(a[1:-1])
                elif a in REG:out=[6+8*REG.index(a),val(b)]
                elif a in PAIR:out=[1+16*PAIR.index(a)]+word(b)
            elif op in ('JP','CALL'):
                if b:out=[(0xc2 if op=='JP' else 0xc4)+8*COND.index(a)]+word(b)
                else:out=[0xc3 if op=='JP' else 0xcd]+word(a)
            elif op in ('JR','DJNZ'):
                target=b or a; d=val(target)-(pc+2)
                if phase and not -128<=d<=127:raise ValueError(f'line {ln}: relative branch out of range {d}')
                out=[0x10 if op=='DJNZ' else (0x20+8*COND.index(a) if b else 0x18),d&255]
            elif op=='RET':out=[0xc0+8*COND.index(a) if a else 0xc9]
            elif op in ('INC','DEC'):
                if a in REG:out=[(4 if op=='INC' else 5)+8*REG.index(a)]
                elif a in PAIR:out=[(3 if op=='INC' else 0xb)+16*PAIR.index(a)]
            elif op in ('PUSH','POP'):
                out=[(0xc5 if op=='PUSH' else 0xc1)+16*['BC','DE','HL','AF'].index(a)]
            elif op=='ADD' and a=='HL':out=[9+16*PAIR.index(b)]
            elif op=='SBC' and a=='HL':out=[0xed,0x42+16*PAIR.index(b)]
            elif op in ('ADD','SUB','AND','XOR','OR','CP'):
                arg=b or a; idx={'ADD':0,'SUB':2,'AND':4,'XOR':5,'OR':6,'CP':7}[op]
                out=[0x80+idx*8+REG.index(arg)] if arg in REG else [0xc6+idx*8,val(arg)]
            elif op=='SRL':out=[0xcb,0x38+REG.index(a)]
            elif op=='BIT':out=[0xcb,0x40+8*val(a)+REG.index(b)]
            elif op=='EX' and a=='DE' and b=='HL':out=[0xeb]
            elif op=='LDIR':out=[0xed,0xb0]
            elif op=='OUT' and b=='A':out=[0xd3,val(a[1:-1])]
            elif op=='IN' and a=='A':out=[0xdb,val(b[1:-1])]
            if out is None:raise ValueError(f'Unsupported instruction at line {ln}: {line}')
            if phase:listing.append(f'{pc:04X}  {bytes(out).hex(" "):16} {line.strip()}')
            result.extend(out);pc+=len(out)
    return origin,bytes(result),labels,'\n'.join(listing)+'\n'

def parse_cmd(b):
    i=0;m=bytearray(65536); loaded=set();entry=None
    while i<len(b):
        typ,n=b[i:i+2]; i+=2
        if typ==1:
            k=(n-2)%256 or 256; addr=int.from_bytes(b[i:i+2],'little'); i+=2
            assert i+k<=len(b);m[addr:addr+k]=b[i:i+k];loaded.update(range(addr,addr+k));i+=k
        elif typ==2:
            assert n==2;entry=int.from_bytes(b[i:i+2],'little');i+=2;break
        else:raise ValueError(f'Unsupported CMD record {typ}')
    assert entry is not None and i==len(b)
    return m,loaded,entry

def record(addr,data):
    return b''.join(bytes([1,(len(data[i:i+256])+2)&255])+ (addr+i).to_bytes(2,'little')+data[i:i+256] for i in range(0,len(data),256))

