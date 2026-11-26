; SC55PLAY v0.1 prototype for TRS-80 Model III / LDOS 5.3.1 / FreHD.
; Derived from the project's MIDIDRUM v0.3 and MIDISD v0.1, MIT license.
; Native Format 0, PPQN; 32-bit MTrk length, 16-bit event delta/length VLQs.
; MIDI only. No cassette OUT. Existing UART at 9600, Nano MIDI at 31250.
; GS DT1/GM System On validation, bounded message buffer, receiver gap.
; Manual reference: Roland SC-55 Owner's Manual pp. 18-24, 40-41, 66-84.
; FreHD browser/reader credited to George Phillips and Frederic Vecoven.
org 0x6000
start:
ld (savedsp),sp
xor a
ld (opened),a
ld (playing),a
ld (running),a
ld (tx_status),a
ld (display_on),a
ld (buffered),a
ld (natural_end),a
    ld (sd_port_active),a
    call clearbreak
push hl
ld hl,banner
call print
pop hl
call checkbreak
call sd_browser
parse_header:
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
; MTrk length is a full 32-bit big-endian integer.
call rawget
ld d,a
call rawget
ld e,a
ld (remaining+2),de
call rawget
ld d,a
call rawget
ld e,a
ld (remaining),de
ld hl,prompt
call print
ask:
call checkbreak
call 0x002b
cp 1
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
ld a,0xfd
ld (buffered),a
jp hz25
buf30:
ld a,0xf9
ld (buffered),a
jp hz30
hz25:
ld de,40000
make_threshold:
ld bc,(division)
ld hl,0
ld (threshold+2),hl
threshold_loop:
call checkbreak
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
ld hl,0xa120
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
cp 0xc0
jp z,one_data
call get
bit 7,a
jp nz,bad
ld (data2),a
; Forward every channel including channel 10.
call send_status
ld a,(data1)
call send_midi
ld a,(data2)
call send_midi
call observe_three
jp next_event
one_data:
call send_status
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
; Buffer a complete F0 event before transmitting. Only GM System On
; and Roland GS DT1 (model 42h, addresses 40h/41h) are admitted.
; No raw F7 escape, split SysEx or arbitrary bulk/other-model messages.
sysex_f0:
    xor a
    ld (running),a
    call vlq
    ld a,h
    or a
    jp nz,skip
    ld a,l
    cp 5
    jp c,skip
    cp 129
    jp nc,skip
    ld (sxlen),a
    ld b,a
    ld hl,sxdata
sxread:
    call get
    ld (hl),a
    inc hl
    djnz sxread
    dec hl
    ld a,(hl)
    cp 0xf7
    jp nz,next_event
    ; Validate all interior bytes are seven-bit data.
    ld a,(sxlen)
    dec a
    ld b,a
    ld hl,sxdata
sxclean:
    bit 7,(hl)
    jp nz,next_event
    inc hl
    djnz sxclean
    ld a,(sxdata)
    cp 0x7e
    jp z,sxgm
    cp 0x41
    jp nz,next_event
    ld a,(sxlen)
    cp 10
    jp c,next_event
    ld a,(sxdata+1)
    cp 32
    jp nc,next_event
    ld a,(sxdata+2)
    cp 0x42
    jp nz,next_event
    ld a,(sxdata+3)
    cp 0x12
    jp nz,next_event
    ld a,(sxdata+4)
    cp 0x40
    jp z,sxchecksum
    cp 0x41
    jp nz,next_event
sxchecksum:
    ; Roland checksum = negative sum of address and data modulo 128.
    ; Sum address, data, checksum; accepted iff low seven bits are zero.
    ld a,(sxlen)
    sub 5
    ld b,a
    ld hl,sxdata+4
    ld c,0
sxsum:
    ld a,(hl)
    add a,c
    ld c,a
    inc hl
    djnz sxsum
    and 127
    jp nz,next_event
    jp sxsend
sxgm:
    ld a,(sxlen)
    cp 5
    jp nz,next_event
    ld a,(sxdata+2)
    cp 9
    jp nz,next_event
    ld a,(sxdata+3)
    cp 1
    jp nz,next_event
sxsend:
    call checkbreak
    xor a
    ld (tx_status),a
    ld a,0xf0
    call send_midi
    ld hl,sxdata
    ld a,(sxlen)
    ld b,a
sxout:
    ld a,(hl)
    call send_midi
    inc hl
    djnz sxout
    ; Parameter writes may change channel state; show unknown until the
    ; next explicit program/bank selection, conservatively.
    call clear_parts
    ; Allow at least two nominal ticks of receiver processing time.
    ; In raw mode resynchronise to the actual clock before the gap.
    ; In buffered mode schedule the gap using the transmitted tick tokens.
    ld a,(buffered)
    or a
    jp nz,sxgap
    ld a,(0x4288)
    ld (target),a
sxgap:
    call wait_tick
    call wait_tick
    jp next_event
sysex:
xor a
ld (running),a
call vlq
skip:
ld a,h
or l
jp z,next_event
call get
dec hl
jp skip
; Most musical deltas are one-byte VLQs. Avoid seven shifts in that case.
vlq:
call get
ld l,a
ld h,0
bit 7,a
ret z
and 0x7f
ld l,a
ld b,2
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
checkbreak:
ld a,(0x3840)
and 4
jp nz,stop_playback
ld a,(0x429f)
and 1
ret z
stop_playback:
ld hl,stoppedmsg
jp finish
clearbreak:
push hl
ld hl,0x429f
res 0,(hl)
pop hl
ret
get:
    ; Decrement a 32-bit track-byte budget before reading a byte.
    ; Preserve HL, BC and DE, including across a low-word borrow.
    push hl
    ld hl,(remaining)
    ld a,h
    or l
    jp nz,get_low
    ld hl,(remaining+2)
    ld a,h
    or l
    jp z,bad
    dec hl
    ld (remaining+2),hl
    ld hl,0
get_low:
    dec hl
    ld (remaining),hl
    pop hl
rawget:
jp sd_rawget
start_buffer:
ld a,(buffered)
or a
ret z
call send
ld hl,0x3ec0
ld de,buflabel
ld b,32
call vcopy
ret
buffer_tick:
ld a,(buffered)
or a
ret z
ld a,0xf8
jp send
; Independent wire running status in both raw and timed modes.
send_status:
    ld a,(running)
push hl
ld hl,tx_status
cp (hl)
jp z,send_status_same
ld (hl),a
pop hl
jp send_midi
send_status_same:
pop hl
ret
; Record actual transmitted bytes; hexadecimal rendering deferred to display.
send_midi:
call send
push af
push hl
push de
ld e,a
ld a,(stream_head)
ld l,a
ld h,0
push de
ld de,stream_ring
add hl,de
pop de
ld (hl),e
inc a
and 15
ld (stream_head),a
ld a,(stream_count)
cp 16
jp z,stream_full
inc a
ld (stream_count),a
stream_full:
ld a,1
ld (stream_dirty),a
pop de
pop hl
pop af
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
send_timeout:
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
ld a,(natural_end)
or a
ld a,0xfc
jp z,buffer_finish
ld a,0xfa
buffer_finish:
call send
jp closefile
raw_panic:
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
ld a,c
call send
ld a,120
call send
xor a
call send
    inc c
    djnz panic_loop
closefile:
call finish_display
call clearbreak
call sd_close
done:
pop hl
call print
call clearbreak
jp 0x402d
print:
ld a,(hl)
or a
ret z
push hl
call 0x0033
pop hl
inc hl
jp print
; Fixed 64x16 display: 8 rows with two channel cells per row.
; Program numbers and bank values are requested zero-based MIDI values.
; Activity is peak Note On velocity since the last update, not polyphony.
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
    ld de,dash_columns
    ld b,64
    call vcopy
    ld hl,0x3cc0
    ld de,channel_rows
    ld c,8
channel_labels:
    ld b,64
    call vcopy
    dec c
    jp nz,channel_labels
    ld hl,0x3ec0
    ld de,rawlabel
    ld b,32
    call vcopy
    ld hl,0x3f00
    ld de,dash_stream
    ld b,64
    call vcopy
    ld hl,0x3fc0
    ld (0x4020),hl
    call clear_parts
    xor a
    ld (stream_count),a
    ld (stream_head),a
    ld (stream_dirty),a
    ld a,(0x4288)
    ld (stream_tick),a
    ld (last_refresh),a
    ld a,1
    ld (display_on),a
    ret
clear_parts:
    ld hl,part_program
    ld b,32
    ld a,255
clear_part_values:
    ld (hl),a
    inc hl
    djnz clear_part_values
    ld hl,part_peak
    ld b,16
    xor a
clear_peaks:
    ld (hl),a
    inc hl
    djnz clear_peaks
    ret
vcopy:
ld a,(de)
ld (hl),a
inc hl
inc de
djnz vcopy
ret
vblank:
ld (hl),32
inc hl
djnz vblank
ret
; Update shadow state for all channels without touching the MIDI stream.
observe_two:
    ld a,(running)
    and 0xf0
    cp 0xc0
    ret nz
    ld de,part_program
    call part_addr
    ld a,(data1)
    ld (hl),a
    ret
observe_three:
    ld a,(running)
    and 0xf0
    cp 0x90
    jp z,observe_peak
    cp 0xb0
    ret nz
    ld a,(data1)
    or a
    ret nz
    ld de,part_bank
    call part_addr
    ld a,(data2)
    ld (hl),a
    ret
observe_peak:
    ld de,part_peak
    call part_addr
    ld a,(data2)
    cp (hl)
    ret c
    ld (hl),a
    ret
part_addr:
    ld a,(running)
    and 15
    ld l,a
    ld h,0
    add hl,de
    ret
refresh_stream:
ld a,(stream_dirty)
or a
ret z
push hl
ld hl,stream_tick
ld a,(0x4288)
sub (hl)
pop hl
cp 3
ret c
ld a,(0x4288)
ld (stream_tick),a
render_stream:
push bc
push de
push hl
xor a
ld (stream_dirty),a
ld hl,0x3f40
ld b,48
call vblank
ld a,(stream_count)
or a
jp z,stream_render_done
; Right-align short streams, then traverse from oldest to newest.
ld c,a
ld a,16
sub c
ld l,a
ld h,0
ld d,h
ld e,l
add hl,hl
add hl,de
ld de,0x3f40
add hl,de
ld (stream_dest),hl
ld a,(stream_head)
sub c
and 15
ld (stream_index),a
ld b,c
stream_render_loop:
push bc
ld a,(stream_index)
ld l,a
ld h,0
ld de,stream_ring
add hl,de
ld l,(hl)
ld h,0
ld d,h
ld e,l
add hl,hl
add hl,de
ld de,hex_cells
add hl,de
ld d,h
ld e,l
ld hl,(stream_dest)
ld b,3
call vcopy
ld (stream_dest),hl
ld a,(stream_index)
inc a
and 15
ld (stream_index),a
pop bc
djnz stream_render_loop
stream_render_done:
pop hl
pop de
pop bc
ret
refresh_notes:
    call refresh_stream
    push hl
    ld hl,last_refresh
    ld a,(0x4288)
    sub (hl)
    pop hl
    cp 3
    ret c
    ld a,(0x4288)
    ld (last_refresh),a
render_parts:
    push bc
    push de
    push hl
    ld c,0
render_part_loop:
    push bc
    ; Address of channel's two-column row, plus program field offset.
    ld l,c
    ld h,0
    add hl,hl
    ld de,part_cells
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (part_dest),de
    ld l,c
    ld h,0
    ld de,part_program
    add hl,de
    ld a,(hl)
    call draw_part_value
    ld hl,(part_dest)
    ld de,8
    add hl,de
    ld (part_dest),hl
    ld l,c
    ld h,0
    ld de,part_bank
    add hl,de
    ld a,(hl)
    call draw_part_value
    ld hl,(part_dest)
    ld de,9
    add hl,de
    ld (part_dest),hl
    ld l,c
    ld h,0
    ld de,part_peak
    add hl,de
    ld a,(hl)
    ld (hl),0
    call draw_part_value
    pop bc
    inc c
    ld a,c
    cp 16
    jp nz,render_part_loop
    pop hl
    pop de
    pop bc
    ret
draw_part_value:
    cp 255
    jp z,draw_unknown
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
    jp draw_value_copy
draw_unknown:
    ld de,unknown_digits
draw_value_copy:
    ld hl,(part_dest)
    ld b,3
    jp vcopy
finish_display:
    ld a,(display_on)
    or a
    ret z
    xor a
    ld (display_on),a
    call render_stream
    call clear_parts
    call render_parts
    ld hl,0x3c40
    ld de,dash_ended
    ld b,64
    call vcopy
    ld hl,0x3fc0
    ld (0x4020),hl
    ret
header: db 77,84,104,100,0,0,0,6,0,0,0,1
tracktag: db 77,84,114,107
banner: db 13,"TRS-80 MODEL III SC55PLAY v0.1",13,"Press BREAK to Exit",13,0
prompt: db 13,"RAW MIDI: 2=25Hz, 3=30Hz",13,"NANO TIMED: 4=25Hz, 5=30Hz (timed firmware ONLY)",13,"Press BREAK to Exit",13,0
playingmsg: db 13,"Playing MIDI...",13,0
finishedmsg: db 13,"End of MIDI file.",13,0
stoppedmsg: db 13,"Playback stopped.",13,0
usagemsg: db 13,"Usage: SC55PLAY (no filename)",13,0
badmsg: db 13,"Cannot read file or unsupported MIDI format.",13,0
uartmsg: db 13,"Serial UART not ready.",13,0
dash_title: db "TRS-80 MODEL III SC55PLAY V0.1 - ROLAND SOUND CANVAS            "
dash_help: db "PLAYING MIDI - BREAK TO EXIT - 16 CHANNELS (TX ONLY)            "
dash_ended: db "PLAYBACK ENDED - SEE STATUS BELOW                               "
dash_columns: db "CH   PRG     BANK     PEAK      CH   PRG     BANK     PEAK      "
dash_stream: db "MIDI TX HEX - LAST 16 MUSIC BYTES (NEWEST RIGHT)                "
unknown_digits: db "---"
channel_rows:
db "01   ---     ---      000       09   ---     ---      000       "
db "02   ---     ---      000       10   ---     ---      000       "
db "03   ---     ---      000       11   ---     ---      000       "
db "04   ---     ---      000       12   ---     ---      000       "
db "05   ---     ---      000       13   ---     ---      000       "
db "06   ---     ---      000       14   ---     ---      000       "
db "07   ---     ---      000       15   ---     ---      000       "
db "08   ---     ---      000       16   ---     ---      000       "
part_cells:
dw 0x3cc5,0x3d05,0x3d45,0x3d85,0x3dc5,0x3e05,0x3e45,0x3e85
dw 0x3ce5,0x3d25,0x3d65,0x3da5,0x3de5,0x3e25,0x3e65,0x3ea5
program_digits:
db 48,48,48,48,48,49,48,48,50,48,48,51,48,48,52,48,48,53,48,48,54,48,48,55,48,48,56,48,48,57,48,49,48,48,49,49,48,49,50,48,49,51,48,49,52,48,49,53
db 48,49,54,48,49,55,48,49,56,48,49,57,48,50,48,48,50,49,48,50,50,48,50,51,48,50,52,48,50,53,48,50,54,48,50,55,48,50,56,48,50,57,48,51,48,48,51,49
db 48,51,50,48,51,51,48,51,52,48,51,53,48,51,54,48,51,55,48,51,56,48,51,57,48,52,48,48,52,49,48,52,50,48,52,51,48,52,52,48,52,53,48,52,54,48,52,55
db 48,52,56,48,52,57,48,53,48,48,53,49,48,53,50,48,53,51,48,53,52,48,53,53,48,53,54,48,53,55,48,53,56,48,53,57,48,54,48,48,54,49,48,54,50,48,54,51
db 48,54,52,48,54,53,48,54,54,48,54,55,48,54,56,48,54,57,48,55,48,48,55,49,48,55,50,48,55,51,48,55,52,48,55,53,48,55,54,48,55,55,48,55,56,48,55,57
db 48,56,48,48,56,49,48,56,50,48,56,51,48,56,52,48,56,53,48,56,54,48,56,55,48,56,56,48,56,57,48,57,48,48,57,49,48,57,50,48,57,51,48,57,52,48,57,53
db 48,57,54,48,57,55,48,57,56,48,57,57,49,48,48,49,48,49,49,48,50,49,48,51,49,48,52,49,48,53,49,48,54,49,48,55,49,48,56,49,48,57,49,49,48,49,49,49
db 49,49,50,49,49,51,49,49,52,49,49,53,49,49,54,49,49,55,49,49,56,49,49,57,49,50,48,49,50,49,49,50,50,49,50,51,49,50,52,49,50,53,49,50,54,49,50,55
display_on: db 0
last_refresh: db 0
part_dest: dw 0
part_program: ds 16
part_bank: ds 16
part_peak: ds 16
stream_head: db 0
stream_dirty: db 0
stream_tick: db 0
stream_ring: ds 16
stream_count: db 0
stream_index: db 0
stream_dest: dw 0
tx_status: db 0
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
sxlen: db 0
sxdata: ds 128
buffered: db 0
natural_end: db 0
savedsp: dw 0
opened: db 0
playing: db 0
running: db 0
remaining: dw 0,0
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
sd_browser:
xor a
ld (sd_port_active),a
ld (sd_avail),a
ld (sd_eof),a
in a,(0xff)
ld (sd_saved_port),a
or 0x10
out (0xec),a
ld a,1
ld (sd_port_active),a
xor a
out (0xc4),a
call sd_require
and 8
jp z,sd_missing
in a,(0xc3)
cp 6
jp nz,sd_missing
ld hl,sector
ld b,6
ld c,0xc2
inir
ld hl,sd_path
ld (hl),47
inc hl
ld (hl),0
sd_reopen:
call checkbreak
xor a
ld (sd_eof),a
ld hl,sd_path
call sd_strlen
inc a
ld b,a
out (0xc3),a
ld a,8
out (0xc4),a
call sd_require
ld hl,sd_path
sd_dir_send:
ld a,(hl)
out (0xc2),a
inc hl
djnz sd_dir_send
call sd_require
sd_page:
xor a
ld (sd_count),a
ld hl,sd_slots
ld (sd_slotptr),hl
sd_dir_next:
call checkbreak
ld a,9
out (0xc4),a
call sd_require
and 8
jp z,sd_dir_end
in a,(0xc3)
cp 22
jp c,sd_error
ld b,a
ld c,0xc2
ld hl,sector
inir
ld a,(sector+8)
and 14
jp nz,sd_dir_next
ld a,(sector+9)
or a
jp z,sd_dir_next
cp 46
jp z,sd_dir_next
ld hl,sector+9
ld b,13
sd_validate_name:
ld a,(hl)
or a
jp z,sd_name_ok
inc hl
djnz sd_validate_name
jp sd_dir_next
sd_name_ok:
ld a,(sector+8)
and 16
jp nz,sd_add
ld hl,sector+9
sd_ext_scan:
ld a,(hl)
or a
jp z,sd_dir_next
inc hl
cp 46
jp nz,sd_ext_scan
ld a,(hl)
and 0xdf
cp 77
jp nz,sd_dir_next
inc hl
ld a,(hl)
and 0xdf
cp 73
jp nz,sd_dir_next
inc hl
ld a,(hl)
and 0xdf
cp 68
jp nz,sd_dir_next
inc hl
ld a,(hl)
or a
jp nz,sd_dir_next
sd_add:
ld hl,(sd_slotptr)
ld a,(sector+8)
ld (hl),a
inc hl
ld de,sector+9
ld b,13
sd_slot_copy:
ld a,(de)
ld (hl),a
inc de
inc hl
djnz sd_slot_copy
ld (sd_slotptr),hl
ld a,(sd_count)
inc a
ld (sd_count),a
cp 9
jp nz,sd_dir_next
jp sd_render
sd_dir_end:
ld a,1
ld (sd_eof),a
sd_render:
ld a,31
call 0x0033
ld hl,sd_title
call print
ld hl,sd_path
call print
ld hl,sd_cr
call print
xor a
ld (sd_index),a
ld hl,sd_slots
ld (sd_slotptr),hl
sd_render_loop:
ld a,(sd_index)
ld b,a
ld a,(sd_count)
cp b
jp z,sd_render_done
ld a,b
inc a
ld (sd_index),a
ld b,a
ld a,48
sd_digit:
inc a
djnz sd_digit
call 0x0033
ld a,32
call 0x0033
ld hl,(sd_slotptr)
bit 4,(hl)
jp z,sd_render_file
ld a,47
call 0x0033
sd_render_file:
ld hl,(sd_slotptr)
inc hl
call print
ld hl,sd_cr
call print
ld hl,(sd_slotptr)
ld de,14
add hl,de
ld (sd_slotptr),hl
jp sd_render_loop
sd_render_done:
ld a,(sd_count)
or a
jp nz,sd_render_help
ld hl,sd_empty
call print
sd_render_help:
ld hl,sd_help
call print
sd_key:
call checkbreak
call 0x002b
cp 1
jp z,stop_playback
cp 78
jp z,sd_next_page
cp 82
jp z,sd_restart
cp 85
jp z,sd_parent
cp 49
jp c,sd_key
cp 58
jp nc,sd_key
sub 49
ld b,a
ld a,(sd_count)
cp b
jp z,sd_key
jp c,sd_key
ld a,b
ld hl,sd_slots
ld de,14
or a
jp z,sd_pick
sd_slot_seek:
add hl,de
dec a
jp nz,sd_slot_seek
sd_pick:
ld a,(hl)
ld (sd_attr),a
inc hl
ld (sd_nameptr),hl
ld hl,sd_path
call sd_strlen
cp 50
jp nc,sd_path_long
ld hl,sd_path
ld de,sd_file
call sd_copyz
ld hl,sd_path+1
ld a,(hl)
or a
jp z,sd_join
ld a,47
ld (de),a
inc de
sd_join:
ld hl,(sd_nameptr)
call sd_copyz
call sd_release
ld a,(sd_attr)
and 16
jp z,sd_open
ld hl,sd_file
ld de,sd_path
call sd_copyz
jp sd_reopen
sd_path_long:
ld hl,sd_longmsg
call print
call sd_release
jp sd_key
sd_next_page:
call sd_release
ld a,(sd_eof)
or a
jp nz,sd_key
jp sd_page
sd_restart:
call sd_release
jp sd_reopen
sd_parent:
call sd_release
ld hl,sd_path+1
ld a,(hl)
or a
jp z,sd_reopen
ld hl,sd_path
call sd_strlen
ld hl,sd_path
ld e,a
ld d,0
add hl,de
sd_parent_scan:
dec hl
ld a,(hl)
cp 47
jp nz,sd_parent_scan
ld de,sd_path
or a
sbc hl,de
ld a,h
or l
jp nz,sd_parent_nonroot
inc hl
sd_parent_nonroot:
add hl,de
ld (hl),0
jp sd_reopen
sd_release:
call checkbreak
call 0x002b
cp 1
jp z,stop_playback
or a
jp nz,sd_release
ret
sd_strlen:
ld b,0
sd_strlen_loop:
ld a,(hl)
or a
jp z,sd_strlen_done
inc hl
inc b
jp sd_strlen_loop
sd_strlen_done:
ld a,b
ret
sd_copyz:
ld a,(hl)
ld (de),a
or a
ret z
inc hl
inc de
jp sd_copyz
sd_open:
call checkbreak
ld hl,sd_file
call sd_strlen
inc a
inc a
ld b,a
out (0xc3),a
ld a,3
out (0xc4),a
call sd_require
ld a,1
ld (opened),a
out (0xc2),a
dec b
ld hl,sd_file
sd_open_send:
ld a,(hl)
out (0xc2),a
inc hl
djnz sd_open_send
call sd_require
and 8
jp z,sd_error
in a,(0xc3)
cp 4
jp z,sd_open_reply
cp 8
jp nz,sd_error
sd_open_reply:
ld b,a
ld c,0xc2
ld hl,sector
inir
xor a
ld (sd_avail),a
ld hl,sd_selectedmsg
call print
ld hl,sd_file
call print
ld hl,sd_cr
call print
ret
sd_rawget:
call checkbreak
ld a,(sd_avail)
or a
jp z,sd_refill
push hl
dec a
ld (sd_avail),a
ld hl,(sd_readptr)
ld a,(hl)
inc hl
ld (sd_readptr),hl
pop hl
ret
sd_refill:
push bc
push de
push hl
ld a,255
out (0xc3),a
ld a,4
out (0xc4),a
call sd_require
and 8
jp z,bad
in a,(0xc3)
or a
jp z,sd_error
ld (sd_avail),a
ld b,a
ld c,0xc2
ld hl,sector
inir
ld hl,sector
ld (sd_readptr),hl
ld a,(sd_avail)
sd_have:
dec a
ld (sd_avail),a
ld hl,(sd_readptr)
ld a,(hl)
inc hl
ld (sd_readptr),hl
pop hl
pop de
pop bc
ret
sd_wait:
push bc
ld bc,0
sd_wait_loop:
in a,(0xcf)
cp 255
jp z,sd_wait_fail
bit 7,a
jp z,sd_wait_ready
dec bc
ld a,b
or c
jp nz,sd_wait_loop
sd_wait_fail:
pop bc
scf
ret
sd_wait_ready:
pop bc
bit 0,a
jp nz,sd_wait_err
or a
ret
sd_wait_err:
scf
ret
sd_require:
call sd_wait
jp c,sd_error
ret
sd_missing:
ld hl,sd_nofrdmsg
jp finish
sd_error:
ld hl,sd_errmsg
jp finish
sd_close:
ld a,(sd_port_active)
or a
ret z
ld a,(opened)
or a
jp z,sd_restore
xor a
ld (opened),a
ld a,6
out (0xc4),a
call sd_wait
sd_restore:
ld a,(sd_saved_port)
out (0xec),a
xor a
ld (sd_port_active),a
ret
sd_title: db "SC55PLAY - FREHD SD CARD",13,"DIRECTORY:",13,0
sd_help: db "1-9 SELECT  N NEXT  R RESTART  U UP  BREAK EXIT",13,0
sd_empty: db "(NO MIDI FILES OR FOLDERS ON THIS PAGE)",13,0
sd_cr: db 13,0
sd_selectedmsg: db "Selected: ",0
sd_longmsg: db "Path too long. Use U to go up.",13,0
sd_nofrdmsg: db 13,"FreHD not detected or incompatible GETVER response.",13,0
sd_errmsg: db 13,"FreHD I/O error or timeout.",13,0
sd_port_active: db 0
sd_saved_port: db 0
sd_count: db 0
sd_eof: db 0
sd_index: db 0
sd_attr: db 0
sd_avail: db 0
sd_slotptr: dw 0
sd_nameptr: dw 0
sd_readptr: dw 0
sd_path: ds 64
sd_file: ds 64
sd_slots: ds 126
