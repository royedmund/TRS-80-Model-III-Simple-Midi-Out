#!/usr/bin/env python3
"""Two-pass assembler for the restricted Z80 syntax used by MIDISD.ASM.
Also emits a TRS-80 DOS CMD (type 1 load blocks and type 2 transfer).
No third-party dependencies. Not a general purpose assembler.
"""
from pathlib import Path
import re,csv,struct
root=Path(__file__).resolve().parent
lines=(root/'MIDISD.ASM').read_text().splitlines()
symbols={}; origin=0x6000
r8={r:i for i,r in enumerate(['b','c','d','e','h','l','(hl)','a'])}
r16={r:i for i,r in enumerate(['bc','de','hl','sp'])}
conds={r:i for i,r in enumerate(['nz','z','nc','c','po','pe','p','m'])}
stack={r:i for i,r in enumerate(['bc','de','hl','af'])}
def assemble(passno):
 pc=origin; out=bytearray()
 def val(s):
  s=s.strip().lower(); terms=s.split('+'); n=0
  for t in terms:
   if t in symbols:n+=symbols[t]
   else:
    try:n+=int(t,0)
    except ValueError:
     if passno==2:raise ValueError('unknown symbol '+t)
  return n
 def w(x):return [x&255,(x>>8)&255]
 def ins(op,args):
  nonlocal pc
  a=args.split(',') if args else [];a=[x.strip().lower() for x in a]
  if op=='ld':
   x,y=a
   if x in r8 and y in r8:return [0x40+8*r8[x]+r8[y]]
   if x=='a' and y=='(de)':return [0x1a]
   if x=='(de)' and y=='a':return [0x12]
   if x=='a' and y.startswith('('):return [0x3a]+w(val(y[1:-1]))
   if x.startswith('(') and x!='(hl)':
    if y=='a':return [0x32]+w(val(x[1:-1]))
    if y=='hl':return [0x22]+w(val(x[1:-1]))
    if y in r16:return [0xed,0x43+16*r16[y]]+w(val(x[1:-1]))
   if x in r16 and y.startswith('('):
    if x=='hl':return [0x2a]+w(val(y[1:-1]))
    return [0xed,0x4b+16*r16[x]]+w(val(y[1:-1]))
   if x in r16:return [0x01+16*r16[x]]+w(val(y))
   if x in r8:return [0x06+8*r8[x],val(y)&255]
  if op in ['push','pop']:return [(0xc5 if op=='push' else 0xc1)+16*stack[a[0]]]
  if op in ['inc','dec']:
   x=a[0]
   if x in r16:return [(3 if op=='inc' else 11)+16*r16[x]]
   return [(4 if op=='inc' else 5)+8*r8[x]]
  if op in ['add','adc','sbc'] and a[0]=='hl':
   if op=='add':return [9+16*r16[a[1]]]
   return [0xed,(0x4a if op=='adc' else 0x42)+16*r16[a[1]]]
  if op in ['and','or','xor','cp','sub']:
   x=a[0];base={'and':0xa0,'or':0xb0,'xor':0xa8,'cp':0xb8,'sub':0x90}[op]
   if x in r8:return [base+r8[x]]
   return [{'and':0xe6,'or':0xf6,'xor':0xee,'cp':0xfe,'sub':0xd6}[op],val(x)&255]
  if op in ('bit','res'):return [0xcb,(0x40 if op=='bit' else 0x80)+8*val(a[0])+r8[a[1]]]
  if op=='jp':return ([0xc3]+w(val(a[0]))) if len(a)==1 else [0xc2+8*conds[a[0]]]+w(val(a[1]))
  if op=='call':return [0xcd]+w(val(a[0]))
  if op=='ret':return [0xc9] if not a else [0xc0+8*conds[a[0]]]
  if op=='djnz':
   d=val(a[0])-pc-2
   if passno==2 and not -128<=d<=127:raise ValueError('relative jump out of range')
   return [0x10,d&255]
  if op=='in':return [0xdb,val(a[1][1:-1])&255]
  if op=='out':return [0xd3,val(a[0][1:-1])&255]
  if op=='inir':return [0xed,0xb2]
  if op=='scf':return [0x37]
  raise ValueError((op,args))
 for ln,raw in enumerate(lines,1):
  s=raw.split(';',1)[0].strip()
  if not s:continue
  if ':' in s and re.match(r'^\w+:',s):
   label,s=s.split(':',1);symbols[label.lower()]=pc;s=s.strip()
   if not s:continue
  op,*rest=s.split(None,1);args=rest[0] if rest else '';op=op.lower()
  try:
   if op=='org':assert val(args)==origin;continue
   if op=='ds':b=[0]*val(args)
   elif op=='dw':b=sum([w(val(x)) for x in args.split(',')],[])
   elif op=='db':
    b=[]
    for x in next(csv.reader([args],skipinitialspace=True)):
     try:b.append(int(x,0)&255)
     except ValueError:b.extend(x.encode('ascii'))
   else:b=ins(op,args)
  except Exception as e:raise ValueError(f'line {ln}: {s}: {e}') from e
  out.extend(b);pc+=len(b)
 return bytes(out)
assemble(1);data=assemble(2)
cmd=bytearray()
for i in range(0,len(data),254):
 b=data[i:i+254];cmd+=bytes([1,(len(b)+2)&255])+struct.pack('<H',origin+i)+b
cmd+=bytes([2,2])+struct.pack('<H',symbols['start'])
(root/'MIDISD.CMD').write_bytes(cmd)
# Round-trip verification of all load records and transfer address.
i=0;recovered=bytearray()
while cmd[i]==1:
 n=cmd[i+1] or 256;addr=int.from_bytes(cmd[i+2:i+4],'little');assert addr==origin+len(recovered)
 recovered+=cmd[i+4:i+2+n];i+=2+n
assert recovered==data and cmd[i:]==b'\x02\x02'+struct.pack('<H',origin)
(root/'MIDISD.MAP').write_text('\n'.join(f'{v:04X} {k}' for k,v in sorted(symbols.items(),key=lambda x:x[1]))+'\n')
print(f'Built MIDISD.CMD: {len(cmd)} bytes, load {origin:04X}-{origin+len(data)-1:04X}, entry {origin:04X}')
