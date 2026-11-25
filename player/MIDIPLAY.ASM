; MIDIPLAY/CMD - Model III LDOS 5.3.1, one-way 9600 baud bridge
; Rev 0.9: 16-byte live hexadecimal MIDI monitor; optional Nano timed FIFO and whitelisted Yamaha SysEx; batched timing and selective display refresh; live EMT-10 voice and held-note dashboard (MIDI channel 1).
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
    ld (buffered),a
    ld (natural_end),a
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
    cp 52
    jp z,buf25
    cp 53
    jp z,buf30
    cp 50
    jp z,hz25
    cp 51
    jp nz,ask
hz30:
    ld de,33333
    jp make_threshold
buf25:
    ld a,0xfd ; buffered START at 25Hz
    ld (buffered),a
    jp hz25
buf30:
    ld a,0xf9 ; buffered START at 30Hz
    ld (buffered),a
    jp hz30
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
    call start_buffer
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
    jp z,sysex_f0
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
    call send_midi
    ld a,(data1)
    call send_midi
    ld a,(data2)
    call send_midi
    call observe_three
    jp next_event
one_data:
    ld a,(running)
    call send_midi
    ld a,(data1)
    call send_midi
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
    ld a,1
    ld (natural_end),a
    ld hl,finishedmsg
    jp finish
; Only complete documented EMT-10 parameter SysEx is forwarded.
; All bytes are read and validated BEFORE transmitting F0; no partial
; SysEx is transmitted if BREAK or disk failure occurs while reading.
sysex_f0:
    xor a
    ld (running),a
    call vlq
    ld a,h
    or a
    jp nz,skip
    ld a,l
    cp 6
    jp nz,skip
    ld hl,sxdata
    ld b,6
sxread:
    call get
    ld (hl),a
    inc hl
    djnz sxread
    ld hl,sxdata
    ld a,(hl)
    cp 0x43
    jp nz,next_event
    inc hl
    ld a,(hl)
    cp 0x73
    jp nz,next_event
    inc hl
    ld a,(hl)
    cp 0x11
    jp nz,next_event
    inc hl
    ld a,(hl)
    cp 0x11
    jp nz,next_event
    inc hl
    ld c,(hl)
    inc hl
    ld a,(hl)
    cp 0xf7
    jp nz,next_event
    ld hl,sxcodes
    ld b,15
sxfind:
    ld a,(hl)
    cp c
    jp z,sxsend
    inc hl
    djnz sxfind
    jp next_event
sxsend:
    call checkbreak
    ld a,0xf0
    call send_midi
    ld hl,sxdata
    ld b,6
sxout:
    ld a,(hl)
    call send_midi
    inc hl
    djnz sxout
    jp next_event
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
    call buffer_tick
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
; The buffered protocol uses reserved transport bytes on RS-232 only.
; Never select buffered mode with the old transparent Nano firmware.
start_buffer:
    ld a,(buffered)
    or a
    ret z
    call send
    ld hl,0x3dc0
    ld de,buflabel
    ld b,32
    call vcopy
    ret
buffer_tick:
    ld a,(buffered)
    or a
    ret z
    ld a,0xf8 ; advance nominal LDOS tick on Nano
    jp send
; Send a musical byte, then record it only after UART accepts it.
; Transport markers and panic use send directly, not this wrapper.
send_midi:
    call send
    push bc
    push de
    push hl
    ; Look up two hex digits and a space. Store in a 16-cell text ring.
    ld l,a
    ld h,0
    ld d,h
    ld e,l
    add hl,hl
    add hl,de
    ld de,hex_cells
    add hl,de
    ld d,h
    ld e,l
    ld a,(stream_head)
    ld l,a
    ld h,0
    ld bc,stream_ring
    add hl,bc
    ld b,3
    call vcopy
    ld a,(stream_head)
    inc a
    inc a
    inc a
    cp 48
    jp nz,stream_save_head
    xor a
stream_save_head:
    ld (stream_head),a
    ld a,1
    ld (stream_dirty),a
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
    ld a,(buffered)
    or a
    jp z,raw_panic
    ; Nano owns the panic in buffered mode. END drains queued music;
    ; STOP discards it immediately. Its local watchdog handles link failure.
    ld a,(natural_end)
    or a
    ld a,0xfc
    jp z,buffer_finish
    ld a,0xfa
buffer_finish:
    call send
    jp closefile
raw_panic:
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
    ld hl,0x3e80
    ld de,dash_stream
    ld b,64
    call vcopy
    ld hl,0x3dc0
    ld de,rawlabel
    ld b,32
    call vcopy
    ld hl,0x3f00
    ld de,dash_split
    ld b,64
    call vcopy
    ; Put ROM cursor on the blank status line, outside the live fields.
    ld hl,0x3f40
    ld (0x4020),hl
    call clear_notes
    ld hl,stream_ring
    ld b,48
    call vblank
    xor a
    ld (stream_head),a
    ld (stream_dirty),a
    ld a,(0x4288)
    ld (stream_tick),a
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
; Refresh monitor independently of note activity (SysEx, CC, other channels).
; Use same clock rate as the note display, with separate dirty flag.
refresh_stream:
    ld a,(stream_dirty)
    or a
    ret z
    push hl
    ld hl,stream_tick
    ld a,(0x4288)
    cp (hl)
    pop hl
    ret z
    ld (stream_tick),a
render_stream:
    push bc
    push de
    push hl
    xor a
    ld (stream_dirty),a
    ; Chronological order: oldest at head, newest at right. Blank cells
    ; lead the display until 16 bytes have been accepted by the UART.
    ld a,(stream_head)
    ld l,a
    ld h,0
    ld de,stream_ring
    add hl,de
    ld d,h
    ld e,l
    ld hl,0x3ec0
    ld a,(stream_head)
    ld b,a
    ld a,48
    sub b
    ld b,a
    call vcopy
    ld a,(stream_head)
    or a
    jp z,stream_render_done
    ld b,a
    ld de,stream_ring
    call vcopy
stream_render_done:
    pop hl
    pop de
    pop bc
    ret
refresh_notes:
    call refresh_stream
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
    call render_stream ; retain final musical bytes even on zero-delta EOF
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
banner: db 13,"TRS-80 MODEL III MIDI PLAYER v0.9",13,"Press BREAK to Exit",13,0
prompt: db 13,"Raw: 2=25Hz, 3=30Hz",13,"Nano buffered: 4=25Hz, 5=30Hz (new firmware ONLY)",13,"Press BREAK to Exit",13,0
playingmsg: db 13,"Playing MIDI...",13,"Press BREAK to Exit",13,0
finishedmsg: db 13,"End of MIDI file.",13,0
stoppedmsg: db 13,"Playback stopped.",13,0
usagemsg: db 13,"Usage: MIDIPLAY NAME/MID:0",13,0
badmsg: db 13,"Cannot read file or unsupported MIDI format.",13,0
uartmsg: db 13,"Serial UART not ready.",13,0
dash_title: db "TRS-80 MODEL III MIDI PLAYER V0.9 - YAMAHA EMT-10               "
dash_help: db "PLAYING MIDI...   PRESS BREAK TO EXIT   DISPLAY: MIDI CH 1      "
dash_ended: db "PLAYBACK ENDED - SEE STATUS BELOW                               "
dash_voice: db "EMT-10 REQUESTED VOICE(S) - PROGRAM NUMBER 0-127:               "
dash_pedal: db "SUSTAIN: ---  (CC64 SENT)                                       "
dash_low: db "LOW KEYS (BELOW G3) - BASS IN SPLIT MODE                        "
dash_high: db "HIGH KEYS (G3 AND ABOVE) - UPPER IN SPLIT MODE                  "
dash_stream: db "MIDI TX HEX - LAST 16 MUSIC BYTES (NEWEST RIGHT):               "
dash_split: db "C4=MIDDLE C. TX ONLY. NO TRANSPORT/PANIC. + = MORE NOTES.       "
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
stream_head: db 0
stream_dirty: db 0
stream_tick: db 0
stream_ring: ds 48
; Lookup avoids per-byte division and repeated nibble conversion.
hex_cells:
    db "00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F "
    db "10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F "
    db "20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F "
    db "30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F "
    db "40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F "
    db "50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F "
    db "60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F "
    db "70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F "
    db "80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F "
    db "90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F "
    db "A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF "
    db "B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF "
    db "C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF "
    db "D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF "
    db "E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF "
    db "F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC FD FE FF "

buflabel: db "NANO BUFFER ON - 160MS LOOKAHEAD"
rawlabel: db "RAW MIDI TX - NO NANO LOOKAHEAD "
sxcodes: db 0x07,0x08,0x09,0x17,0x18,0x19,0x40,0x41,0x50,0x51,0x60,0x61,0x70,0x71,0x72
sxdata: ds 6
buffered: db 0
natural_end: db 0
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
