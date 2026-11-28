; MIDIIN v0.1 - Model III LDOS 5.3.1, raw UART receive monitor.
; Bridge sends explicit status + two 7-bit data bytes; Cn/Dn and
; FA/FB/FC padded. F4 00 00 reports dropped input frames.
; Direct VRAM, no ROM output in receive loop. No interrupt hooks.
org 6000h
start:
    ld hl,429Fh
    ld a,(hl)
    and 0FEh
    ld (hl),a
    xor a
    out (0E8h),a
    ld a,0EEh
    out (0E9h),a
    ld a,6Fh
    out (0EAh),a
    call reset
main:
    ; Receive has priority over keyboard and display. Check hardware errors.
    in a,(0EAh)
    bit 7,a
    jr z,keys
    ld b,a
    in a,(0EBh)
    ld c,a
    ld a,b
    and 38h
    jr z,good
    xor a
    ld (phase),a
    ld a,33
    ld (3C72h),a
    jr keys
good:
    ld a,c
    call parse
keys:
    ld a,(3840h)
    bit 2,a
    jp nz,exit
    ld a,(429Fh)
    bit 0,a
    jp nz,exit
    ld a,(3840h)
    bit 1,a
    jr z,clear_up
    ld a,(cleardown)
    or a
    jr nz,main
    ld a,1
    ld (cleardown),a
    call reset
    jr main
clear_up:
    xor a
    ld (cleardown),a
    jr main
exit:
    ld hl,429Fh
    ld a,(hl)
    and 0FEh
    ld (hl),a
    jp 402Dh
; Recover frame sync on any status byte. Fixed three-byte host messages.
parse:
    bit 7,a
    jr z,data
    ld (status),a
    ld a,1
    ld (phase),a
    ret
data:
    ld b,a
    ld a,(phase)
    or a
    ret z
    cp 1
    jr nz,complete
    ld a,b
    ld (data1),a
    ld a,2
    ld (phase),a
    ret
complete:
    ld a,b
    ld (data2),a
    xor a
    ld (phase),a
    jp render
; Display circular 12-event log. Only one 64-byte line per event.
render:
    ld hl,(lineptr)
    push hl
    ld b,64
    ld a,32
blank:
    ld (hl),a
    inc hl
    djnz blank
    pop hl
    ld a,(status)
    call hex
    inc hl
    ld a,(data1)
    call hex
    inc hl
    ld a,(data2)
    call hex
    inc hl
    inc hl
    ld a,(status)
    cp 0F4h
    jr z,loss
    cp 0FAh
    jr z,sttext
    cp 0FBh
    jr z,cttext
    cp 0FCh
    jr z,sptext
    and 0F0h
    cp 80h
    jr z,offtext
    cp 90h
    jr nz,other
    ld a,(data2)
    or a
    jr z,offtext
    ld de,onmsg
    jr label
other:
    cp 0B0h
    jr z,cctext
    cp 0C0h
    jr z,pgtext
    cp 0E0h
    jr z,pbtext
    ld de,othmsg
    jr label
loss:
    ld de,lossmsg
    jr label
sttext:
    ld de,startmsg
    jr label
cttext:
    ld de,contmsg
    jr label
sptext:
    ld de,stopmsg
    jr label
offtext:
    ld de,offmsg
    jr label
cctext:
    ld de,ccmsg
    jr label
pgtext:
    ld de,pgmsg
    jr label
pbtext:
    ld de,pbmsg
label:
    ld a,(de)
    or a
    jr z,advance
    ld (hl),a
    inc de
    inc hl
    jr label
advance:
    ld hl,(lineptr)
    ld de,64
    add hl,de
    ld a,h
    cp 40h
    jr c,saveptr
    ld hl,3D00h
saveptr:
    ld (lineptr),hl
    ret
hex:
    push af
    srl a
    srl a
    srl a
    srl a
    call nibble
    pop af
    and 15
nibble:
    add a,48
    cp 58
    jr c,digit
    add a,7
digit:
    ld (hl),a
    inc hl
    ret
reset:
    xor a
    ld (phase),a
    ld hl,3D00h
    ld (lineptr),hl
    ld hl,screen
    ld de,3C00h
    ld bc,1024
    ldir
    ret
phase: db 0
status: db 0
data1: db 0
data2: db 0
cleardown: db 0
lineptr: dw 3D00h
onmsg: db 78,79,84,69,32,79,78,0
offmsg: db 78,79,84,69,32,79,70,70,0
ccmsg: db 67,79,78,84,82,79,76,32,67,72,65,78,71,69,0
pgmsg: db 80,82,79,71,82,65,77,32,67,72,65,78,71,69,0
pbmsg: db 80,73,84,67,72,32,66,69,78,68,0
othmsg: db 67,72,65,78,78,69,76,32,77,69,83,83,65,71,69,0
lossmsg: db 73,78,80,85,84,32,79,86,69,82,70,76,79,87,32,45,32,82,69,76,69,65,83,69,32,75,69,89,83,0
startmsg: db 83,84,65,82,84,0
contmsg: db 67,79,78,84,73,78,85,69,0
stopmsg: db 83,84,79,80,0
screen:
    db 84,82,83,45,56,48,32,77,79,68,69,76,32,73,73,73,32,77,73,68,73,32,87,79,82,75,83,84,65,84,73,79,78,32,47,32,77,73,68,73,32,73,78,32,118,48,46,49,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 57,54,48,48,32,56,78,49,32,32,32,83,84,65,84,85,83,32,68,65,84,65,49,32,68,65,84,65,50,32,40,72,69,88,41,32,32,32,85,65,82,84,32,69,82,82,79,82,58,32,45,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 67,76,69,65,82,58,32,67,76,69,65,82,32,76,79,71,32,32,32,32,32,66,82,69,65,75,58,32,76,68,79,83,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 82,69,67,69,78,84,32,69,86,69,78,84,83,32,40,67,73,82,67,85,76,65,82,32,76,79,71,41,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
    db 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32
