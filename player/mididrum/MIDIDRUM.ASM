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
    ld (sd_port_active),a
    ld (drum_mode),a
    ld (drum_left),a
    call clearbreak
push hl
ld hl,banner
call print
pop hl
call checkbreak
call sd_browser
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
call checkbreak
call 0x002b
cp 1
jp z,stop_playback
    cp 54
    jp z,drum25
    cp 55
    jp z,drum30
    cp 56
    jp z,beat25
    cp 57
    jp z,beat30
    cp 52
    jp z,buf25
cp 53
jp z,buf30
cp 50
jp z,hz25
cp 51
jp nz,ask
drum25:
    ld a,1
    ld (drum_mode),a
    jp hz25
drum30:
    ld a,1
    ld (drum_mode),a
    jp hz30
beat25:
    ld a,2
    ld (drum_mode),a
    jp hz25
beat30:
    ld a,2
    ld (drum_mode),a
    jp hz30
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
    ; Both supported timer periods exceed 32767 us, so 2*period has
    ; high word 1. Store the low word for the automatic beat clock.
    ld h,d
    ld l,e
    add hl,hl
    ld (drum_period),hl
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
    call drum_start
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
    ld a,(drum_mode)
    or a
    jp z,drum_forward3
    ld a,(running)
    and 15
    cp 9
    jp nz,drum_forward3
    call drum_midi
    jp next_event
drum_forward3:
    ; Finish transmitting
ld a,(running)
call send_midi
ld a,(data1)
call send_midi
ld a,(data2)
call send_midi
call observe_three
jp next_event
one_data:
    ld a,(drum_mode)
    or a
    jp z,drum_forward2
    ld a,(running)
    and 15
    cp 9
    jp z,next_event
drum_forward2:
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
call vlq
skip:
ld a,h
or l
jp z,next_event
call get
dec hl
jp skip
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
    jp z,drum_wait_arrived
    ; Only spend otherwise-idle time on cassette audio.
    ld a,(drum_mode)
    or a
    jp z,wait_loop
    call drum_slice
    jp wait_loop
drum_wait_arrived:
    call drum_quiet
    call buffer_tick
    call drum_clock
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
push hl
ld hl,(remaining)
ld a,h
or l
jp z,bad
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
ld hl,0x3dc0
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
send_midi:
call send
push bc
push de
push hl
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
    call drum_quiet
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
    ld a,(drum_mode)
    or a
    jp z,drum_panic_send
    ld a,c
    cp 0xb9
    jp z,drum_panic_next
 drum_panic_send:
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
drum_panic_next:
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
observe_two:
ld a,(running)
cp 0xc0
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
jp nc,clear_notes
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
jp z,observe_off
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
ld bc,0x3700
call render_range
refresh_high:
ld a,(refresh_mask)
bit 1,a
jp z,render_done
ld hl,0x3e40
ld (note_dest),hl
ld hl,active_notes+55
ld bc,0x4937
call render_range
render_done:
pop hl
pop de
pop bc
ret
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
add hl,de
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
ld (hl),43
inc hl
ld (note_dest),hl
render_tail:
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
call render_stream
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
banner: db 13,"TRS-80 MODEL III MIDIDRUM v0.2",13,"Press BREAK to Exit",13,0
prompt: db 13,"Raw: 2=25Hz, 3=30Hz",13,"Nano buffered: 4=25Hz, 5=30Hz (new firmware ONLY)",13,"Cassette MIDI drums: 6=25Hz, 7=30Hz",13,"Cassette auto beat: 8=25Hz, 9=30Hz",13,"Press BREAK to Exit",13,0
playingmsg: db 13,"Playing MIDI...",13,"Press BREAK to Exit",13,0
finishedmsg: db 13,"End of MIDI file.",13,0
stoppedmsg: db 13,"Playback stopped.",13,0
usagemsg: db 13,"Usage: MIDIDRUM (no filename)",13,0
badmsg: db 13,"Cannot read file or unsupported MIDI format.",13,0
uartmsg: db 13,"Serial UART not ready.",13,0
dash_title: db "TRS-80 MODEL III DRUMSD V0.2      - YAMAHA EMT-10               "
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
push bc
push de
push hl
ld a,(sd_avail)
or a
jp nz,sd_have
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
sd_title: db "MIDIDRUM - FREHD SD CARD",13,"DIRECTORY:",13,0
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

; Cassette percussion extension for Model III MIDISD v0.1.
; Mode 0: original playback; 1: GM channel 10; 2: automatic 4/4.
; FFH write bits 0/1 are audio on Model III. EC control remains untouched.
; No interrupt hooks, no DI, no additional SD accesses, no Nano protocol.
; All sound generation occurs in short slices of the existing idle wait.
; A/B/C/D/E/H/L and flags may be clobbered by drum routines.

drum_start:
    ld a,(drum_mode)
    or a
    ret z
    xor a
    ld (drum_left),a
    ld (drum_step),a
    ld (drum_wave),a
    ld (drum_phase),a
    ld (drum_phase+1),a
    ld (drum_phase+2),a
    ld (drum_phase+3),a
    out (0xff),a
    ld a,0x5d
    ld (drum_rng),a
    ld hl,0x3dc0
    ld de,drum_midi_label
    ld a,(drum_mode)
    cp 2
    jp nz,drum_label_draw
    ld de,drum_auto_label
drum_label_draw:
    ld b,32
    call vcopy
    ld a,(drum_mode)
    cp 2
    ret nz
    jp drum_beat

; Turn the output off between events and on all exit paths.
; Do not touch the cassette port in the original playback modes.
drum_quiet:
    ld a,(drum_mode)
    or a
    ret z
    xor a
    out (0xff),a
    ret

; MIDI channel 10 handler: Note On with nonzero velocity only.
; Other channel-10 messages are deliberately not sent to the EMT-10.
drum_midi:
    ld a,(drum_mode)
    cp 1
    ret nz
    ld a,(running)
    cp 0x99
    ret nz
    ld a,(data2)
    or a
    ret z
    ld a,(data1)
    cp 35
    ret c
    cp 82
    ret nc
    ; GM percussion notes 75-79 get distinct experimental sounds.
    cp 75
    jp z,drum_metal
    cp 76
    jp z,drum_rise
    cp 77
    jp z,drum_fall
    cp 78
    jp z,drum_ghost
    cp 79
    jp z,drum_ghost
    cp 37
    jp c,drum_kick
    cp 41
    jp c,drum_snare
    jp z,drum_kick
    cp 43
    jp z,drum_kick
    cp 45
    jp z,drum_kick
    cp 47
    jp z,drum_kick
    cp 48
    jp z,drum_kick
    cp 50
    jp z,drum_kick
    jp drum_hat

; One software voice: eerie FX > kick > snare > hat when hits overlap.
; GM toms 41/43/45/47/48/50 use a rough kick approximation.
drum_kick:
    ld a,3
    ld b,100
    jp drum_trigger
drum_snare:
    ld a,2
    ld b,68
    jp drum_trigger
drum_hat:
    ld a,1
    ld b,25
    jp drum_trigger
; Extended effects, priority higher than ordinary drums. In the demo these
; occupy their own subdivisions, avoiding retrigger collisions.
drum_metal:
    ld a,4
    ld b,50
    jp drum_trigger
drum_rise:
    ld a,5
    ld b,135
    jp drum_trigger
drum_fall:
    ld a,6
    ld b,135
    jp drum_trigger
drum_ghost:
    ld a,7
    ld b,145
drum_trigger:
    ld c,a
    ld a,(drum_left)
    or a
    jp z,drum_accept
    ld a,(0x4288)
    ld d,a
    ld a,(drum_expire)
    ld e,a
    ld a,d
    sub e
    bit 7,a
    jp z,drum_accept
    ld a,(drum_kind)
    cp c
    jp c,drum_accept
    jp z,drum_accept
    ret
drum_accept:
    ld a,c
    ld (drum_kind),a
    ld a,b
    ld (drum_left),a
    ld a,(0x4288)
    inc a
    inc a
    ld (drum_expire),a
    ld a,1
    ld (drum_hold),a
    xor a
    ld (drum_wave),a
    ret

; Automatic 4/4: 8th-note phase += twice the nominal timer period.
; Compare against the current SMF microseconds-per-quarter-note value.
; Retain fractional phase across tempo changes. Cap at one hit per OS tick.
drum_clock:
    ld a,(drum_mode)
    cp 2
    ret nz
    ld hl,(drum_phase)
    ld de,(drum_period)
    add hl,de
    ld (drum_phase),hl
    ld hl,(drum_phase+2)
    ld de,1
    adc hl,de
    ld (drum_phase+2),hl
    ld hl,(drum_phase)
    ld de,(tempo)
    or a
    sbc hl,de
    push hl
    ld hl,(drum_phase+2)
    ld de,(tempo+2)
    sbc hl,de
    jp c,drum_clock_less
    ld (drum_phase+2),hl
    pop hl
    ld (drum_phase),hl
    ; If another subdivision is already due, discard backlog rather
    ; than producing a burst of late hits (very fast MIDI tempo only).
    ld de,(tempo)
    or a
    sbc hl,de
    ld hl,(drum_phase+2)
    ld de,(tempo+2)
    sbc hl,de
    jp c,drum_beat
    ld hl,0
    ld (drum_phase),hl
    ld (drum_phase+2),hl
    jp drum_beat
drum_clock_less:
    pop hl
    ret

drum_beat:
    ld a,(drum_step)
    ld c,a
    inc a
    and 7
    ld (drum_step),a
    ld a,c
    and 3
    jp z,drum_kick
    cp 2
    jp z,drum_snare
    jp drum_hat

; Single bounded sample. Poll TIMER$ and BREAK between samples in caller.
; This is deliberately approximate synthesis, not a fixed-rate DAC ISR.
; 20 DJNZ iterations = roughly 0.13 ms at 2.027 MHz, plus overhead.
; Kick is a downward square-wave chirp, snare/hat use deterministic noise.
drum_slice:
    ld a,(drum_left)
    or a
    ret z
    ld a,(0x4288)
    ld b,a
    ld a,(drum_expire)
    ld c,a
    ld a,b
    sub c
    bit 7,a
    jp z,drum_stop_hit
    ld a,(drum_left)
    dec a
    ld (drum_left),a
    ld a,(drum_kind)
    cp 3
    jp z,drum_sample_kick
    cp 4
    jp nc,drum_sample_fx
    ; 8-bit maximal-length Galois-style LFSR, x^8+x^4+x^3+x^2+1.
    ld a,(drum_rng)
    ld l,a
    ld h,0
    add hl,hl
    ld a,l
    bit 0,h
    jp z,drum_rng_store
    xor 0x1d
drum_rng_store:
    ld (drum_rng),a
    and 1
    jp drum_sample_out
drum_sample_kick:
    ld a,(drum_hold)
    dec a
    ld (drum_hold),a
    jp nz,drum_sample_wave
    ld a,(drum_left)
    ld b,4
    cp 66
    jp nc,drum_hold_set
    ld b,7
    cp 33
    jp nc,drum_hold_set
    ld b,12
drum_hold_set:
    ld a,b
    ld (drum_hold),a
    ld a,(drum_wave)
    xor 1
    ld (drum_wave),a
drum_sample_wave:
    ld a,(drum_wave)
    jp drum_sample_out
; Extended synth: metallic square-wave tick, rising/falling chirps,
; and a warbling tone mixed with the existing pseudorandom noise source.
drum_sample_fx:
    ld a,(drum_hold)
    dec a
    ld (drum_hold),a
    jp nz,drum_fx_wave
    ld a,(drum_kind)
    cp 4
    jp z,drum_fx_metal
    cp 5
    jp z,drum_fx_rise
    cp 6
    jp z,drum_fx_fall
    ld a,(drum_left)
    and 16
    ld b,3
    jp z,drum_fx_hold
    ld b,9
    jp drum_fx_hold
drum_fx_metal:
    ld b,2
    jp drum_fx_hold
drum_fx_rise:
    ld a,(drum_left)
    ld b,2
    cp 45
    jp c,drum_fx_hold
    ld b,5
    cp 90
    jp c,drum_fx_hold
    ld b,11
    jp drum_fx_hold
drum_fx_fall:
    ld a,(drum_left)
    ld b,2
    cp 90
    jp nc,drum_fx_hold
    ld b,5
    cp 45
    jp nc,drum_fx_hold
    ld b,11
drum_fx_hold:
    ld a,b
    ld (drum_hold),a
    ld a,(drum_wave)
    xor 1
    ld (drum_wave),a
drum_fx_wave:
    ld a,(drum_kind)
    cp 7
    jp nz,drum_sample_wave
    ; On alternating envelope blocks use noise instead of the tone.
    ld a,(drum_left)
    bit 3,a
    jp z,drum_sample_wave
    ld a,(drum_rng)
    ld l,a
    ld h,0
    add hl,hl
    ld a,l
    bit 0,h
    jp z,drum_rng_store
    xor 0x1d
    jp drum_rng_store
drum_sample_out:
    out (0xff),a
    ld b,20
drum_sample_delay:
    djnz drum_sample_delay
    ld a,(drum_left)
    or a
    ret nz
drum_stop_hit:
    xor a
    ld (drum_left),a
    out (0xff),a
    ret

drum_mode: db 0
drum_left: db 0
drum_kind: db 0
drum_expire: db 0
drum_hold: db 0
drum_wave: db 0
drum_rng: db 0x5d
drum_step: db 0
drum_phase: dw 0,0
drum_period: dw 0

drum_midi_label: db "RAW MIDI + CASSETTE CH10        "
drum_auto_label: db "RAW MIDI + CASSETTE AUTO BEAT   "

