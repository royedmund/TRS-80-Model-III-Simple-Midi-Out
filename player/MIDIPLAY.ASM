; MIDIPLAY/CMD - Model III LDOS 5.3.1, one-way 9600 baud bridge
; Format 0 SMF, PPQN, 16-bit track size and delta/length VLQs.
; 25 or 30 Hz LDOS TIMER$; no interrupt hooks. ORG 6000H.
org 0x6000
start:
    ld (savedsp),sp
    xor a
    ld (opened),a
    ld (playing),a
    ld (running),a
    ld de,fcb
    call 0x441c ; @FSPEC: HL = command tail
    jp nz,usage
    ld a,(fcb)
    cp 42
    jp z,usage
    ld de,fcb
    ld hl,sector
    ld b,0
    call 0x4424 ; @OPEN, 256-byte buffer
    jp nz,bad
    ld a,1
    ld (opened),a
    ld hl,header
    ld b,12
header_loop:
    call rawget
    cp (hl)
    jp nz,bad
    inc hl
    djnz header_loop
    call rawget
    ld d,a
    call rawget
    ld e,a
    ld a,d
    and 0x80
    jp nz,bad
    ld a,d
    or e
    jp z,bad
    ld (division),de
    ld hl,tracktag
    ld b,4
track_loop:
    call rawget
    cp (hl)
    jp nz,bad
    inc hl
    djnz track_loop
    call rawget
    or a
    jp nz,bad
    call rawget
    or a
    jp nz,bad
    call rawget
    ld d,a
    call rawget
    ld e,a
    ld (remaining),de
    ld hl,prompt
    call print
ask:
    call 0x0049 ; @KEY
    cp 50
    jp z,hz25
    cp 51
    jp nz,ask
    ld de,33333
    jp make_threshold
hz25:
    ld de,40000
make_threshold:
    ; threshold = PPQN * microseconds per OS tick, 32-bit
    ld bc,(division)
    ld hl,0
    ld (threshold+2),hl
threshold_loop:
    add hl,de
    jp nc,no_carry
    push hl
    ld hl,(threshold+2)
    inc hl
    ld (threshold+2),hl
    pop hl
no_carry:
    dec bc
    ld a,b
    or c
    jp nz,threshold_loop
    ld (threshold),hl
    ld hl,0
    ld (phase),hl
    ld (phase+2),hl
    ld hl,0xa120 ; 500000 = 0007A120h
    ld (tempo),hl
    ld hl,7
    ld (tempo+2),hl
    xor a
    out (0xe8),a
    ld a,0xee
    out (0xe9),a
    ld a,0x6f
    out (0xea),a
    ld a,1
    ld (playing),a
    ld hl,playingmsg
    call print
    ld a,(0x4288)
    ld (target),a
next_event:
    call checkbreak
    call vlq
    ld b,h
    ld c,l
    call delay_ticks
    call get
    cp 0xff
    jp z,meta
    cp 0xf0
    jp z,sysex
    cp 0xf7
    jp z,sysex
    cp 0xf0
    jp nc,bad
    bit 7,a
    jp z,run_data
    ld (running),a
    call get
    jp first_data
run_data:
    ld c,a
    ld a,(running)
    or a
    jp z,bad
    ld a,c
first_data:
    bit 7,a
    jp nz,bad
    ld (data1),a
    ld a,(running)
    and 0xe0
    cp 0xc0 ; Cn/Dn have one data byte
    jp z,one_data
    call get
    bit 7,a
    jp nz,bad
    ld (data2),a
    ld a,(running)
    call send
    ld a,(data1)
    call send
    ld a,(data2)
    call send
    jp next_event
one_data:
    ld a,(running)
    call send
    ld a,(data1)
    call send
    jp next_event
meta:
    xor a
    ld (running),a
    call get
    ld (metatype),a
    call vlq
    ld a,(metatype)
    cp 0x2f
    jp z,endtrack
    cp 0x51
    jp nz,skip
    ld a,h
    or a
    jp nz,bad
    ld a,l
    cp 3
    jp nz,bad
    call get
    ld (tempo+2),a
    call get
    ld (tempo+1),a
    call get
    ld (tempo),a
    ld hl,(tempo)
    ld a,(tempo+2)
    or h
    or l
    jp z,bad
    jp next_event
endtrack:
    ld a,h
    or l
    jp nz,bad
    ld hl,finishedmsg
    jp finish
sysex:
    xor a
    ld (running),a
    call vlq ; deliberately skip SysEx payload
skip:
    ld a,h
    or l
    jp z,next_event
    call checkbreak
    call get
    dec hl
    jp skip
; Read 16-bit variable-length quantity (up to 3 bytes).
vlq:
    ld hl,0
    ld b,3
vlq_loop:
    call get
    ld c,a
    add hl,hl
    jp c,bad
    add hl,hl
    jp c,bad
    add hl,hl
    jp c,bad
    add hl,hl
    jp c,bad
    add hl,hl
    jp c,bad
    add hl,hl
    jp c,bad
    add hl,hl
    jp c,bad
    and 0x7f
    or l
    ld l,a
    bit 7,c
    ret z
    djnz vlq_loop
    jp bad
; add tempo to phase for every MIDI tick, then emit elapsed OS ticks.
delay_ticks:
    ld a,b
    or c
    ret z
    call checkbreak
    push bc
    ld hl,(phase)
    ld de,(tempo)
    add hl,de
    ld (phase),hl
    ld hl,(phase+2)
    ld de,(tempo+2)
    adc hl,de
    ld (phase+2),hl
phase_compare:
    ld hl,(phase)
    ld de,(threshold)
    or a
    sbc hl,de
    push hl
    ld hl,(phase+2)
    ld de,(threshold+2)
    sbc hl,de
    jp c,phase_less
    ld (phase+2),hl
    pop hl
    ld (phase),hl
    call wait_tick
    jp phase_compare
phase_less:
    pop hl
    pop bc
    dec bc
    jp delay_ticks
wait_tick:
    ld a,(target)
    inc a
    ld (target),a
wait_loop:
    call checkbreak
    ld a,(target)
    ld b,a
    ld a,(0x4288)
    sub b
    bit 7,a
    jp nz,wait_loop
    ret
checkbreak:
    ld a,(0x3840)
    and 4
    ret z
    ld hl,stoppedmsg
    jp finish
get:
    push hl
    ld hl,(remaining)
    ld a,h
    or l
    jp z,bad
    dec hl
    ld (remaining),hl
    pop hl
rawget:
    push bc
    push de
    push hl
    ld de,fcb
    call 0x0013 ; @GET, Z on success
    jp nz,bad
    pop hl
    pop de
    pop bc
    ret
send:
    push bc
    ld c,a
    ld b,0
send_poll:
    in a,(0xea)
    bit 6,a
    jp nz,send_ready
    djnz send_poll
    ; bounded polling; skip panic on UART failure
    xor a
    ld (playing),a
    ld hl,uartmsg
    jp finish
send_ready:
    ld a,c
    out (0xeb),a
    pop bc
    ret
usage:
    ld hl,usagemsg
    jp finish
bad:
    ld hl,badmsg
finish:
    ld sp,(savedsp)
    push hl
    ld a,(playing)
    or a
    jp z,closefile
    xor a
    ld (playing),a
    ; release sustain/sostenuto/soft and all notes on every channel
    ld b,16
    ld c,0xb0
panic_loop:
    ld a,c
    call send
    ld a,64
    call send
    xor a
    call send
    ld a,c
    call send
    ld a,66
    call send
    xor a
    call send
    ld a,c
    call send
    ld a,67
    call send
    xor a
    call send
    ld a,c
    call send
    ld a,123
    call send
    xor a
    call send
    inc c
    djnz panic_loop
closefile:
    ld a,(opened)
    or a
    jp z,done
    xor a
    ld (opened),a
    ld de,fcb
    call 0x4428 ; @CLOSE
 done:
    pop hl
    call print
    jp 0x402d ; @EXIT
print:
    ld a,(hl)
    or a
    ret z
    push hl
    call 0x0033
    pop hl
    inc hl
    jp print
header: db 77,84,104,100,0,0,0,6,0,0,0,1
tracktag: db 77,84,114,107
prompt: db 13,"Clock: 2=25Hz (50Hz video), 3=30Hz (60Hz video)",13,0
playingmsg: db 13,"Playing MIDI. BREAK stops.",13,0
finishedmsg: db 13,"End of MIDI file.",13,0
stoppedmsg: db 13,"Playback stopped.",13,0
usagemsg: db 13,"Usage: MIDIPLAY NAME/MID:0",13,0
badmsg: db 13,"Cannot read file or unsupported MIDI format.",13,0
uartmsg: db 13,"Serial UART not ready.",13,0
savedsp: dw 0
opened: db 0
playing: db 0
running: db 0
remaining: dw 0
division: dw 0
threshold: dw 0,0
phase: dw 0,0
tempo: dw 0,0
target: db 0
data1: db 0
data2: db 0
metatype: db 0
fcb: ds 32
sector: ds 256
