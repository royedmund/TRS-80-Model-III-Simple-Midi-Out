"""Build EMTPLAY from the exact MIT-licensed MIDISD v0.3 baseline.
No external assembler required. Retains baseline parser and raw UART fallback.
Installs framed MIDI Clock transport for modes 4/5.
"""
from pathlib import Path
import hashlib, sys
from assembler import asm,parse_cmd,record
ROOT=Path(__file__).parent
SHA='6afd5600e2207c987aeea06d9755708356a42067'
def gitsha(b):return hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
def pitch_entry(n):
    letter=['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'][n%12]
    return (letter+str(n//12-1)).encode('ascii').ljust(4,b'\0')
def build(b):
    assert gitsha(b)==SHA,'Unexpected baseline CMD (use exact listed Git blob)'
    m,loaded,entry=parse_cmd(b)
    assert (min(loaded),max(loaded),entry)==(0x6000,0x8300,0x6000)
    clockorg,clockcode,clocklabels,clocklisting=asm((ROOT/'EMTCLOCK.ASM').read_text())
    assert clockorg==0x6af0 and clockorg+len(clockcode)<=0x6ca3
    frame_midi=str(clocklabels['FRAME_MIDI'])
    score_source=(ROOT/'EMTSCORE.ASM').read_text()
    pre,post=score_source.split('raw_cleanup:',1)
    score_source=pre.replace('CALL 65FBH','CALL '+frame_midi)+'raw_cleanup:'+post
    org,code,labels,listing=asm(score_source)
    assert org==0x66b3 and org+len(code)<=0x6950, (hex(org+len(code)),len(code))
    assert m[org:org+3]==bytes.fromhex('21 00 3c')
    m[org:0x6950]=code+bytes(0x6950-org-len(code))
    keyorg,keycode,keylabels,keylisting=asm((ROOT/'EMTKEYS.ASM').read_text())
    assert keyorg==0x6425 and keyorg+len(keycode)<0x65fb
    assert not any(m[keyorg:keyorg+len(keycode)])
    m[keyorg:keyorg+len(keycode)]=keycode
    labels.update(keylabels);listing+=keylisting
    # Other old display entry points reside inside the replacement region.
    # Redirect the caller of refresh and finish, rather than overwrite code.
    def patch(a,old,new):
        old=bytes.fromhex(old)
        assert m[a:a+len(old)]==old,hex(a)
        m[a:a+len(new)]=new
    def jmp(label):return b'\xc3'+labels[label].to_bytes(2,'little')
    def call(label):return b'\xcd'+labels[label].to_bytes(2,'little')
    patch(0x63ca,'3a 40 38',jmp('KEY_POLL'))
    # Normalize only the directory picker's ROM key scan; retain digits and BREAK.
    patch(0x7f07,'cd 2b 00',call('MENU_SCAN'))
    patch(0x669d,'e1 cd a7',jmp('FINISH_DISPATCH'))
    patch(0x6171,'3a 3f 7c',jmp('SEND_THREE'))
    patch(0x6189,'3a 3f 7c',jmp('SEND_TWO'))
    patch(0x63c6,'cd 68 68',call('SCORE_STEP'))
    patch(0x6694,'cd 17 69',call('SCORE_FINISH'))
    patch(0x6659,'06 10 0e',jmp('RAW_CLEANUP'))
    # START still sends the same buffer command; remove old dashboard label.
    patch(0x63f7,'3a 39 7c b7 c8 cd fb 65 21 c0 3d 11 e4 7b 06 20 cd 5c 67 c9',bytes.fromhex('3a 39 7c b7 c8 c3 fb 65')+bytes(12))
    # 128 four-byte note entries. Former dashboard text is unused.
    table=b''.join(pitch_entry(n) for n in range(128))
    assert len(table)==512
    m[0x6aa3:0x6ca3]=table
    # Menu instructions; score contains no text.
    prompt=b'\rRaw: 2=25Hz, 3=30Hz\rClock v0.2: 4=25Hz, 5=30Hz\rCLEAR: menu  BREAK: exit\r\0'
    assert len(prompt)<=0x69ef-0x6993
    m[0x6993:0x69ef]=prompt.ljust(0x69ef-0x6993,b'\0')
    # Text strings occupy fixed-size slots, retaining baseline addresses.
    for addr,end,value in [(0x6960,0x6993,b'\rTRS-80 MODEL III EMTPLAY v1.0\rBREAK: exit\r\0'),
                           (0x80f8,0x811b,b'EMTPLAY - FREHD SD\rDIRECTORY:\r\0'),
                           (0x6a3d,0x6a5b,b'\rUsage: EMTPLAY\r\0')]:
        assert len(value)<=end-addr
        m[addr:end]=value.ljust(end-addr,b'\0')
    from make_gm_tables import tables
    gm_source=(ROOT/'EMTGM.ASM').read_text().replace('CALL 65FBH','CALL '+frame_midi).replace('JP 65FBH','JP '+frame_midi).replace('JP 62ACH','JP '+str(clocklabels['CLOCK_TEMPO']))
    for alias,target in [('native_three','SEND_THREE'),('native_two','SEND_TWO'),('score_draw','DRAW_PITCH')]:
        gm_source=gm_source.replace(alias, str(labels[target]))
    gmorg,gmcode,gmlabels,gmlisting=asm(gm_source+'\n'+tables())
    assert gmorg==0x8301 and gmorg+len(gmcode)<0xa000
    m[gmorg:gmorg+len(gmcode)]=gmcode
    loaded.update(range(gmorg,gmorg+len(gmcode)))
    labels.update(gmlabels);listing+=gmlisting
    info_source=(ROOT/'EMTINFO.ASM').read_text()
    for alias,target in [('gm_mode_addr','GM_MODE'),('cache_on_addr','CACHE_ON'),('selected_patch_addr','SELECTED_PATCH')]:
        info_source=info_source.replace(alias,str(labels[target]))
    infoorg,infocode,infolabels,infolisting=asm(info_source)
    assert infoorg==0x75a9 and infoorg+len(infocode)<=0x7829
    m[infoorg:0x7829]=infocode.ljust(0x7829-infoorg,b'\0')
    labels.update(infolabels);listing+=infolisting
    patch(0x63f4,'c3 5a 80',jmp('CACHE_RAWGET'))
    patch(0x6028,'cd 80 7d',call('NEW_BROWSER'))
    patch(0x607a,'21 93 69',jmp('HEADER_READY'))
    patch(0x6123,'cd 16 63',call('GM_DELAY'))
    patch(0x61dd,'cd ac 62',call('GM_TEMPO'))
    patch(0x61e3,'7c b5 c2 23 66',jmp('GM_END')+bytes(2))
    patch(0x6248,'cd ca 63',jmp('GM_SYSEX'))
    patch(0x610f,'cd f7 63',call('GM_START'))
    patch(0x6171,jmp('SEND_THREE').hex(),jmp('GM_THREE'))
    patch(0x6189,jmp('SEND_TWO').hex(),jmp('GM_TWO'))
    # Former pitch table is now unused: install status compressor and reset.
    wireorg,wirecode,wirelabels,wirelisting=asm((ROOT/'EMTWIRE.ASM').read_text())
    assert wireorg==0x6aa3 and wireorg+len(wirecode)<=0x6ad0
    m[wireorg:wireorg+len(wirecode)]=wirecode
    resetorg,resetcode,_,resetlisting=asm("ORG 6AD0H\n XOR A\n LD (6AE0H),A\n JP 63CAH\n")
    m[resetorg:resetorg+len(resetcode)]=resetcode
    m[0x6ae0]=0
    labels.update(wirelabels);listing+=wirelisting+resetlisting
    # Fast lookup tables occupy the obsolete hex display workspace.
    m[0x7900:0x7b00]=table
    m[0x7b00:0x7b80]=bytes(len(pitch_entry(n).rstrip(b'\0')) for n in range(128))
    m[0x7b80:0x7ba0]=b''.join((0x3c00+64*r).to_bytes(2,'little') for r in range(16))
    fast_source=(ROOT/'EMTFAST.ASM').read_text()
    for alias,target in [('cache_on_addr','CACHE_ON'),('cache_ptr_addr','CACHE_PTR')]:
        fast_source=fast_source.replace(alias,str(labels[target]))
    fastorg,fastcode,fastlabels,fastlisting=asm(fast_source)
    assert fastorg==0x6ca3 and fastorg+len(fastcode)<=0x6ce9
    m[fastorg:fastorg+len(fastcode)]=fastcode
    labels.update(fastlabels);listing+=fastlisting
    # Direct UART fast path: no BC saves or loop setup until actually busy.
    send_source=f"""ORG 65FBH
    PUSH AF
    IN A,(0EAH)
    AND 40H
    JP Z,{labels['UART_SLOW']}
    POP AF
    OUT (0EBH),A
    RET
"""
    sendorg,sendcode,_,sendlisting=asm(send_source)
    assert sendorg==0x65fb and len(sendcode)<=0x6617-0x65fb
    patch(0x65fb,'c5 4f 06 00 db ea cb 77 c2 12 66 10 f7 af 32 3e 7c 21 8a 6a c3 26 66 79 d3 eb c1 c9',sendcode.ljust(0x6617-0x65fb,b'\0'))
    listing+=sendlisting
    patch(0x63e6,'e5 2a 40',jmp('FAST_GET'))
    m[clockorg:clockorg+len(clockcode)]=clockcode
    labels.update(clocklabels);listing+=clocklisting
    patch(0x6aa3,'c3 fb 65',jmp('FRAME_MIDI'))
    patch(0x6422,'c3 fb 65',jmp('FRAME_MIDI'))
    patch(0x63f7,'3a 39 7c',jmp('FRAME_START'))
    patch(0x6418,'3a 39 7c b7 c8 3e f8 c3 fb 65',jmp('FRAME_TICK')+bytes(7))
    patch(0x63ac,'3a 5c 7c 3c 32 5c 7c',call('WAIT_START')+bytes(4))
    patch(0x63c3,'cd 18 64',bytes(3))
    patch(0x6648,'cd fb 65',call('FRAME_FINISH'))
    out=record(entry,bytes(m[0x6000:gmorg+len(gmcode)]))+b'\x02\x02\x00\x60'
    check,loaded2,entry2=parse_cmd(out);assert check==m and loaded2==loaded and entry2==entry
    return out,labels,listing
if __name__=='__main__':
    src=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'MIDISD.CMD'
    b,labels,listing=build(src.read_bytes());(ROOT/'EMTPLAY.CMD').write_bytes(b);(ROOT/'EMTSCORE.lst').write_text(listing)
    print('Built EMTPLAY.CMD',len(b),'bytes',hashlib.sha256(b).hexdigest());print({k:hex(v) for k,v in labels.items()})
