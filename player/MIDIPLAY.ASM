; MIDIPLAY/CMD - Model III LDOS 5.3.1, one-way 9600 baud bridge
; Rev 0.7: batched timing and selective display refresh; live EMT-10 voice and held-note dashboard (MIDI channel 1).
; Display is passive: never changes the MIDI byte stream.
; 64x16 video RAM 3C00H-3FFFH; note refresh limited to one per LDOS tick.
; LDOS 5.3.1 KFLAG$ 429FH bit 0: interrupt-latched BREAK.
; Reference: https://www.trs-80.com/sub-disassem-dos-ldos-m3-sys00.htm
; Format 0 SMF, PPQN, 16-bit track size and delta/length VLQs.
; 25 or 30 Hz LDOS TIMER$; no interrupt hooks. ORG 6000H.
org 0x6000
start:
    ld (savedsp),sp
    xor a
    ld (opened),a
    ld (playing),a
    ld (running),a
    ld (display_on),a
    call clearbreak ; Discard a stale DOS BREAK flag, preserve command-tail HL.
    ; Show the instruction immediately, even with no or invalid filename.
    ; The DOS command tail is in HL, so save it across console output.
    push hl
    ld hl,banner
    call print
    pop hl
    call checkbreak
    ld de,fcb
    call 0x441c ; @FSPEC: HL = command tail
    jp nz,usage
    call checkbreak
    ld a,(fcb)
    cp 42
    jp z,usage
    ld de,fcb
    ld hl,sector
    ld b,0
    call 0x4424 ; @OPEN, 256-byte buffer
    jp nz,disk_error
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
    ; Poll the physical BREAK key and the non-blocking ROM keyboard scan.
    ; 0049H waits for a key, so avoid it here.
    call checkbreak
    call 0x002b ; KBSCAN: A=key code or zero if none
    cp 1        ; ROM BREAK character
    jp z,stop_playback
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
    call checkbreak ; Can be lengthy with a high PPQN value.
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
    call scale_tempo
    call checkbreak
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
    call init_display
    ld a,(0x4288)
    ld (target),a
next_event:
    call checkbreak
    call refresh_notes
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
    ; Finish transmitting a complete message before polling BREAK again.
    ld a,(running)
    call send
    ld a,(data1)
    call send
    ld a,(data2)
    call send
    call observe_three
    jp next_event
one_data:
    ld a,(running)
    call send
    ld a,(data1)
    call send
    call observe_two
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
    call scale_tempo
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
    ; get/rawget already checks BREAK before every byte.
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
; Precompute exact 32-bit tempo multiples on initialisation/tempo changes.
; Each doubling propagates carry from the low word to the high word.
scale_tempo:
    ld hl,(tempo)
    ld de,(tempo+2)
    add hl,hl
    ld b,h
    ld c,l
    ld h,d
    ld l,e
    adc hl,hl
    ld d,h
    ld e,l
    ld h,b
    ld l,c
    add hl,hl
    ld b,h
    ld c,l
    ld h,d
    ld l,e
    adc hl,hl
    ld d,h
    ld e,l
    ld h,b
    ld l,c
    ld (tempo4),hl
    ld (tempo4+2),de
    add hl,hl
    ld b,h
    ld c,l
    ld h,d
    ld l,e
    adc hl,hl
    ld d,h
    ld e,l
    ld h,b
    ld l,c
    add hl,hl
    ld b,h
    ld c,l
    ld h,d
    ld l,e
    adc hl,hl
    ld d,h
    ld e,l
    ld h,b
    ld l,c
    ld (tempo16),hl
    ld (tempo16+2),de
    add hl,hl
    ld b,h
    ld c,l
    ld h,d
    ld l,e
    adc hl,hl
    ld d,h
    ld e,l
    ld h,b
    ld l,c
    add hl,hl
    ld b,h
    ld c,l
    ld h,d
    ld l,e
    adc hl,hl
    ld d,h
    ld e,l
    ld h,b
    ld l,c
    add hl,hl
    ld b,h
    ld c,l
    ld h,d
    ld l,e
    adc hl,hl
    ld d,h
    ld e,l
    ld h,b
    ld l,c
    ld (tempo128),hl
    ld (tempo128+2),de
    ret
; Accumulate 128/16/4/1 MIDI ticks at once. The fractional phase and
; number of elapsed LDOS ticks are exactly the same as one-at-a-time.
; Maximum phase + 128 * 0xFFFFFF < 2^32 for any accepted PPQN.
; Every elapsed OS tick is still waited for individually; BREAK checked
; per batch and in every wait. No change to event order or target tempo.
delay_ticks:
    ld a,b
    or c
    ret z
    call checkbreak
    ld a,b
    or a
    jp nz,delay128
    ld a,c
    cp 128
    jp nc,delay128
    cp 16
    jp nc,delay16
    cp 4
    jp nc,delay4
    dec bc
    push bc
    ld de,(tempo)
    ld bc,(tempo+2)
    jp delay_add
delay128:
    ld hl,0xff80
    add hl,bc
    ld b,h
    ld c,l
    push bc
    ld de,(tempo128)
    ld bc,(tempo128+2)
    jp delay_add
delay16:
    ld hl,0xfff0
    add hl,bc
    ld b,h
    ld c,l
    push bc
    ld de,(tempo16)
    ld bc,(tempo16+2)
    jp delay_add
delay4:
    ld hl,0xfffc
    add hl,bc
    ld b,h
    ld c,l
    push bc
    ld de,(tempo4)
    ld bc,(tempo4+2)
    jp delay_add
delay_add:
    ld hl,(phase)
    add hl,de
    ld (phase),hl
    ld hl,(phase+2)
    adc hl,bc
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
    jp delay_ticks
wait_tick:
    ld a,(target)
    inc a
    ld (target),a
wait_loop:
    ; Only redraw once the target clock tick has arrived.
    call checkbreak
    ld a,(target)
    ld b,a
    ld a,(0x4288)
    sub b
    bit 7,a
    jp nz,wait_loop
    call refresh_notes
    ret
; Check the physical key and the LDOS interrupt-latched flag.
; This catches a brief press between polls, e.g. during a disk read.
; Only A and flags are changed when no BREAK is detected.
; On BREAK, abandon nested calls via savedsp in finish.
checkbreak:
    ld a,(0x3840) ; Model III keyboard matrix, bit 2 = BREAK
    and 4
    jp nz,stop_playback
    ld a,(0x429f) ; LDOS KFLAG$, bit 0 = latched BREAK
    and 1
    ret z
stop_playback:
    ld hl,stoppedmsg
    jp finish
clearbreak:
    ; Acknowledge only BREAK; preserve other KFLAG$ bits atomically.
    push hl
    ld hl,0x429f
    res 0,(hl)
    pop hl
    ret
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
    call checkbreak ; Poll before each byte, including the SMF header.
    push bc
    push de
    push hl
    ld de,fcb
    call 0x0013 ; @GET, Z on success
    jp nz,disk_error
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
    call checkbreak
    ld hl,usagemsg
    jp finish
disk_error:
    ; A DOS read/open error may coincide with a user BREAK.
    call checkbreak
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
    ; No BREAK polling during cleanup: held BREAK cannot interrupt it.
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
    call finish_display ; MIDI cleanup has priority over display.
    call clearbreak ; Acknowledge BREAK before calling DOS.
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
    call clearbreak ; Do not pass a pending BREAK flag back to DOS.
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
; ---------------------------------------------------------------
; Passive EMT-10 display, channel 1. Other channels still transmitted.
; Voice names show the last requested program, not the panel state.
; Key lists track Note On / Off, not sustain tails or voice stealing.
; The compact lists show 12 distinct notes per range, + if more.
; All video writes go to fixed 64-column VRAM rows; no scrolling in play.
; ---------------------------------------------------------------
init_display:
    ld hl,0x3c00
    ld bc,1024
    ld d,32
screen_clear:
    ld (hl),d
    inc hl
    dec bc
    ld a,b
    or c
    jp nz,screen_clear
    ld hl,0x3c00
    ld de,dash_title
    ld b,64
    call vcopy
    ld hl,0x3c40
    ld de,dash_help
    ld b,64
    call vcopy
    ld hl,0x3c80
    ld de,dash_voice
    ld b,64
    call vcopy
    ld hl,0x3cc0
    ld de,voice_unknown
    ld b,40
    call vcopy
    ld hl,0x3d00
    ld de,dash_pedal
    ld b,64
    call vcopy
    ld hl,0x3d40
    ld de,dash_low
    ld b,64
    call vcopy
    ld hl,0x3e00
    ld de,dash_high
    ld b,64
    call vcopy
    ld hl,0x3ec0
    ld de,dash_explain
    ld b,64
    call vcopy
    ld hl,0x3f00
    ld de,dash_split
    ld b,64
    call vcopy
    ; Put ROM cursor on the blank status line, outside the live fields.
    ld hl,0x3f40
    ld (0x4020),hl
    call clear_notes
    ld a,(0x4288)
    ld (last_refresh),a
    xor a
    ld (notes_dirty),a
    ld a,1
    ld (display_on),a
    ret
; Copy B bytes from DE to HL. No console calls in the hot path.
vcopy:
    ld a,(de)
    ld (hl),a
    inc hl
    inc de
    djnz vcopy
    ret
; Clear B characters at HL, leaving HL one byte past the cleared region.
vblank:
    ld (hl),32
    inc hl
    djnz vblank
    ret
observe_two:
    ld a,(running)
    cp 0xc0 ; Program change, channel 1 only.
    ret nz
    ld a,(data1)
    ld l,a
    ld h,0
    add hl,hl
    ld de,program_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld hl,0x3cc0
    ld b,40
    call vcopy
    ; Display original wire program number as three decimal digits.
    ld a,(data1)
    ld l,a
    ld h,0
    ld d,h
    ld e,l
    add hl,hl
    add hl,de
    ld de,program_digits
    add hl,de
    ld d,h
    ld e,l
    ld hl,0x3ce8
    ld b,3
    call vcopy
observe_program_done:
    ret
observe_three:
    ld a,(running)
    cp 0x90
    jp z,observe_on
    cp 0x80
    jp z,observe_off
    cp 0xb0
    ret nz
    ld a,(data1)
    cp 64
    jp z,observe_sustain
    cp 121
    jp z,pedal_off
    cp 120
    jp z,clear_notes
    cp 123
    jp nc,clear_notes ; 123-127: All Notes Off / channel mode changes.
    ret
observe_sustain:
    ld a,(data2)
    cp 64
    jp c,pedal_off
    ld de,pedal_on_text
    jp pedal_draw
pedal_off:
    ld de,pedal_off_text
pedal_draw:
    ld hl,0x3d09
    ld b,3
    call vcopy
    ret
observe_on:
    ld a,(data2)
    or a
    jp z,observe_off ; Note On velocity zero is Note Off.
    ld c,1
    jp update_note
observe_off:
    ld c,0
update_note:
    ld a,(data1)
    ld l,a
    ld h,0
    ld de,active_notes
    add hl,de
    ld a,(hl)
    cp c
    ret z
    ld (hl),c
    ; Only the affected register needs repainting (bit 0 low, bit 1 high).
    ld a,(data1)
    cp 55
    ld a,1
    jp c,mark_range
    ld a,2
mark_range:
    ld hl,notes_dirty
    or (hl)
    ld (hl),a
    ret
clear_notes:
    ld hl,active_notes
    ld b,128
    xor a
clear_note_loop:
    ld (hl),a
    inc hl
    djnz clear_note_loop
    ld a,3
    ld (notes_dirty),a
    ret
; Coalesce simultaneous events; refresh at most once per OS tick.
; Preserve BC/DE/HL because wait_tick uses them in nested timing loops.
refresh_notes:
    ld a,(notes_dirty)
    or a
    ret z
    ld a,(last_refresh)
    ld (refresh_tmp),a
    ld a,(0x4288)
    push hl
    ld hl,refresh_tmp
    cp (hl)
    pop hl
    ret z
    ld (last_refresh),a
    push bc
    push de
    push hl
    ld a,(notes_dirty)
    ld (refresh_mask),a
    xor a
    ld (notes_dirty),a
    ld a,(refresh_mask)
    bit 0,a
    jp z,refresh_high
    ld hl,0x3d80
    ld (note_dest),hl
    ld hl,active_notes
    ld bc,0x3700 ; B=55 notes, C=0 first MIDI note
    call render_range
refresh_high:
    ld a,(refresh_mask)
    bit 1,a
    jp z,render_done
    ld hl,0x3e40
    ld (note_dest),hl
    ld hl,active_notes+55
    ld bc,0x4937 ; B=73 notes, C=55 first upper note
    call render_range
render_done:
    pop hl
    pop de
    pop bc
    ret
; Render active note flags for one range in ascending pitch order.
; B=count, C=first pitch, HL=flags. Each cell is five characters.
render_range:
    ld a,12
    ld (slots),a
render_loop:
    ld a,(hl)
    or a
    jp z,render_next
    ld a,(slots)
    or a
    jp z,render_overflow
    dec a
    ld (slots),a
    push hl
    push bc
    ld l,c
    ld h,0
    ld e,l
    ld d,h
    add hl,hl
    add hl,hl
    add hl,de ; note index * 5
    ld de,note_names
    add hl,de
    ld d,h
    ld e,l
    ld hl,(note_dest)
    ld b,5
    call vcopy
    ld (note_dest),hl
    pop bc
    pop hl
render_next:
    inc hl
    inc c
    djnz render_loop
    jp render_tail
render_overflow:
    ld hl,(note_dest)
    ld (hl),43 ; + means more active notes than display slots.
    inc hl
    ld (note_dest),hl
render_tail:
    ; Replace only the trailing old characters, not the entire row first.
    ld hl,(note_dest)
    ld a,l
    and 0x3f
    ld b,a
    ld a,64
    sub b
    ld b,a
    jp vblank
finish_display:
    ld a,(display_on)
    or a
    ret z
    xor a
    ld (display_on),a
    ld hl,0x3c40
    ld de,dash_ended
    ld b,64
    call vcopy
    call clear_notes
    ld hl,0x3d80
    ld b,64
    call vblank
    ld hl,0x3e40
    ld b,64
    call vblank
    ld hl,0x3d09
    ld b,3
    call vblank
    ld hl,0x3f40
    ld (0x4020),hl
    ret

header: db 77,84,104,100,0,0,0,6,0,0,0,1
tracktag: db 77,84,114,107
banner: db 13,"TRS-80 MODEL III MIDI PLAYER v0.7",13,"Press BREAK to Exit",13,0
prompt: db 13,"Clock: 2=25Hz (50Hz video), 3=30Hz (60Hz video)",13,"Press BREAK to Exit",13,0
playingmsg: db 13,"Playing MIDI...",13,"Press BREAK to Exit",13,0
finishedmsg: db 13,"End of MIDI file.",13,0
stoppedmsg: db 13,"Playback stopped.",13,0
usagemsg: db 13,"Usage: MIDIPLAY NAME/MID:0",13,0
badmsg: db 13,"Cannot read file or unsupported MIDI format.",13,0
uartmsg: db 13,"Serial UART not ready.",13,0
dash_title: db "TRS-80 MODEL III MIDI PLAYER V0.7 - YAMAHA EMT-10               "
dash_help: db "PLAYING MIDI...   PRESS BREAK TO EXIT   DISPLAY: MIDI CH 1      "
dash_ended: db "PLAYBACK ENDED - SEE STATUS BELOW                               "
dash_voice: db "REQUESTED INSTRUMENT (PROGRAM NUMBER, 0-127):                   "
dash_pedal: db "SUSTAIN: ---  (CC64 SENT)                                       "
dash_low: db "LOW KEYS (BELOW G3) - BASS IN SPLIT MODE                        "
dash_high: db "HIGH KEYS (G3 AND ABOVE) - UPPER IN SPLIT MODE                  "
dash_explain: db "HELD NOTES / CHORD TONES. + = MORE THAN 12 IN RANGE             "
dash_split: db "C4=MIDDLE C. DISPLAY SHOWS SENT DATA, NOT AUDIO.                "
pedal_on_text: db "ON "
pedal_off_text: db "OFF"
voice_unknown: db "PANEL SETTING / NO PROGRAM SENT         "
voice0: db "PIANO 1                                 "
voice1: db "PIANO 2                                 "
voice2: db "ELEC. PIANO 1                           "
voice3: db "ELEC. PIANO 2                           "
voice4: db "HARPSICHORD                             "
voice5: db "GUITAR                                  "
voice6: db "STRINGS                                 "
voice7: db "BRASS                                   "
voice8: db "CHOIR                                   "
voice9: db "UPRIGHT BASS                            "
voice10: db "ELECTRIC BASS                           "
voice11: db "SLAP BASS                               "
voice12: db "UPRIGHT BASS + PIANO 1                  "
voice13: db "UPRIGHT BASS + PIANO 2                  "
voice14: db "UPRIGHT BASS + ELEC. PIANO 1            "
voice15: db "UPRIGHT BASS + ELEC. PIANO 2            "
voice16: db "UPRIGHT BASS + HARPSICHORD              "
voice17: db "UPRIGHT BASS + GUITAR                   "
voice18: db "UPRIGHT BASS + STRINGS                  "
voice19: db "UPRIGHT BASS + BRASS                    "
voice20: db "UPRIGHT BASS + CHOIR                    "
voice21: db "ELECTRIC BASS + PIANO 1                 "
voice22: db "ELECTRIC BASS + PIANO 2                 "
voice23: db "ELECTRIC BASS + ELEC. PIANO 1           "
voice24: db "ELECTRIC BASS + ELEC. PIANO 2           "
voice25: db "ELECTRIC BASS + HARPSICHORD             "
voice26: db "ELECTRIC BASS + GUITAR                  "
voice27: db "ELECTRIC BASS + STRINGS                 "
voice28: db "ELECTRIC BASS + BRASS                   "
voice29: db "ELECTRIC BASS + CHOIR                   "
voice30: db "SLAP BASS + PIANO 1                     "
voice31: db "SLAP BASS + PIANO 2                     "
voice32: db "SLAP BASS + ELEC. PIANO 1               "
voice33: db "SLAP BASS + ELEC. PIANO 2               "
voice34: db "SLAP BASS + HARPSICHORD                 "
voice35: db "SLAP BASS + GUITAR                      "
voice36: db "SLAP BASS + STRINGS                     "
voice37: db "SLAP BASS + BRASS                       "
voice38: db "SLAP BASS + CHOIR                       "
program_table:
    dw voice0,voice1,voice2,voice3,voice4,voice5,voice6,voice7
    dw voice8,voice9,voice10,voice11,voice0,voice1,voice2,voice3
    dw voice4,voice5,voice6,voice7,voice8,voice9,voice10,voice11
    dw voice0,voice1,voice2,voice3,voice4,voice5,voice6,voice7
    dw voice8,voice9,voice10,voice11,voice0,voice1,voice2,voice3
    dw voice4,voice5,voice6,voice7,voice8,voice9,voice10,voice11
    dw voice12,voice13,voice14,voice15,voice16,voice17,voice18,voice19
    dw voice20,voice12,voice13,voice14,voice15,voice16,voice17,voice18
    dw voice21,voice22,voice23,voice24,voice25,voice26,voice27,voice28
    dw voice29,voice21,voice22,voice23,voice24,voice25,voice26,voice27
    dw voice30,voice31,voice32,voice33,voice34,voice35,voice36,voice37
    dw voice38,voice30,voice31,voice32,voice33,voice34,voice35,voice36
    dw voice0,voice1,voice2,voice3,voice4,voice5,voice6,voice7
    dw voice8,voice9,voice10,voice11,voice0,voice1,voice2,voice3
    dw voice4,voice5,voice6,voice7,voice8,voice9,voice10,voice11
    dw voice0,voice1,voice2,voice3,voice4,voice5,voice6,voice7
program_digits:
    db 48,48,48,48,48,49,48,48,50,48,48,51,48,48,52,48,48,53,48,48,54,48,48,55,48,48,56,48,48,57,48,49,48,48,49,49,48,49,50,48,49,51,48,49,52,48,49,53
    db 48,49,54,48,49,55,48,49,56,48,49,57,48,50,48,48,50,49,48,50,50,48,50,51,48,50,52,48,50,53,48,50,54,48,50,55,48,50,56,48,50,57,48,51,48,48,51,49
    db 48,51,50,48,51,51,48,51,52,48,51,53,48,51,54,48,51,55,48,51,56,48,51,57,48,52,48,48,52,49,48,52,50,48,52,51,48,52,52,48,52,53,48,52,54,48,52,55
    db 48,52,56,48,52,57,48,53,48,48,53,49,48,53,50,48,53,51,48,53,52,48,53,53,48,53,54,48,53,55,48,53,56,48,53,57,48,54,48,48,54,49,48,54,50,48,54,51
    db 48,54,52,48,54,53,48,54,54,48,54,55,48,54,56,48,54,57,48,55,48,48,55,49,48,55,50,48,55,51,48,55,52,48,55,53,48,55,54,48,55,55,48,55,56,48,55,57
    db 48,56,48,48,56,49,48,56,50,48,56,51,48,56,52,48,56,53,48,56,54,48,56,55,48,56,56,48,56,57,48,57,48,48,57,49,48,57,50,48,57,51,48,57,52,48,57,53
    db 48,57,54,48,57,55,48,57,56,48,57,57,49,48,48,49,48,49,49,48,50,49,48,51,49,48,52,49,48,53,49,48,54,49,48,55,49,48,56,49,48,57,49,49,48,49,49,49
    db 49,49,50,49,49,51,49,49,52,49,49,53,49,49,54,49,49,55,49,49,56,49,49,57,49,50,48,49,50,49,49,50,50,49,50,51,49,50,52,49,50,53,49,50,54,49,50,55
note_names:
    db "C-1  C#-1 D-1  D#-1 E-1  F-1  F#-1 G-1  G#-1 A-1  A#-1 B-1  "
    db "C0   C#0  D0   D#0  E0   F0   F#0  G0   G#0  A0   A#0  B0   "
    db "C1   C#1  D1   D#1  E1   F1   F#1  G1   G#1  A1   A#1  B1   "
    db "C2   C#2  D2   D#2  E2   F2   F#2  G2   G#2  A2   A#2  B2   "
    db "C3   C#3  D3   D#3  E3   F3   F#3  G3   G#3  A3   A#3  B3   "
    db "C4   C#4  D4   D#4  E4   F4   F#4  G4   G#4  A4   A#4  B4   "
    db "C5   C#5  D5   D#5  E5   F5   F#5  G5   G#5  A5   A#5  B5   "
    db "C6   C#6  D6   D#6  E6   F6   F#6  G6   G#6  A6   A#6  B6   "
    db "C7   C#7  D7   D#7  E7   F7   F#7  G7   G#7  A7   A#7  B7   "
    db "C8   C#8  D8   D#8  E8   F8   F#8  G8   G#8  A8   A#8  B8   "
    db "C9   C#9  D9   D#9  E9   F9   F#9  G9   "
display_on: db 0
last_refresh: db 0
refresh_tmp: db 0
notes_dirty: db 0
refresh_mask: db 0
slots: db 0
note_dest: dw 0
active_notes: ds 128

savedsp: dw 0
opened: db 0
playing: db 0
running: db 0
remaining: dw 0
division: dw 0
threshold: dw 0,0
phase: dw 0,0
tempo: dw 0,0
tempo4: dw 0,0
tempo16: dw 0,0
tempo128: dw 0,0
target: db 0
data1: db 0
data2: db 0
metatype: db 0
fcb: ds 32
sector: ds 256
