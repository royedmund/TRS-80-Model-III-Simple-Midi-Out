; EMTPLAY v0.2: CLEAR cancels and reopens the FreHD picker; BREAK exits.
; Native Model III matrix 3840h: CLEAR bit 1, BREAK bit 2.
; LDOS KFLAG$ 429Fh bit 0 is latched BREAK. Preserve BC/DE/HL on poll.
; Existing MIDISD finish resets SP, stops transport, closes SD file and
; restores external I/O before dispatching here. No recursive browser calls.
ORG 6425H
key_poll:
    ; Fast idle path: read matrix only once, check latched BREAK.
    LD A,(3840H)
    AND 6
    JR NZ,key_pressed
    LD A,(429FH)
    AND 1
    JP NZ,63D8H
    RET
key_pressed:
    AND 4
    JP NZ,63D8H
    LD A,(429FH)
    AND 1
    JP NZ,63D8H
    LD A,(7C3DH)
    OR A
    RET Z
    LD A,1
    LD (return_menu),A
    LD HL,6A29H
    JP 6626H

; Finish has already reset stack and closed file. Pop the saved message.
finish_dispatch:
    POP HL
    LD A,(return_menu)
    OR A
    JR NZ,menu_restart
    LD A,(7C3AH) ; normal end: retain score, await CLEAR/BREAK
    OR A
    JR NZ,end_wait
    CALL 66A7H ; original status output for errors / BREAK
    JP exit_dos
end_wait:
    LD A,(3840H)
    AND 4
    JR NZ,end_exit
    LD A,(429FH)
    AND 1
    JR NZ,end_exit
    LD A,(3840H)
    AND 2
    JR Z,end_wait
    CALL end_abort
    JR menu_restart
end_exit:
    CALL end_abort
    JR exit_dos
end_abort:
    ; If user acts before Nano completes its natural drain, cancel it.
    ; Clear EOF before send so UART error cannot reenter end_wait.
    XOR A
    LD (7C3AH),A
    LD A,(7C39H)
    OR A
    RET Z
    LD A,0FCH
    JP 65FBH
menu_restart:
    XOR A
    LD (return_menu),A
    LD (7C3AH),A
    ; Give BREAK priority while waiting for release of CLEAR.
release_wait:
    LD A,(3840H)
    AND 4
    JR NZ,exit_dos
    LD A,(429FH)
    AND 1
    JR NZ,exit_dos
    LD A,(3840H)
    AND 2
    JR NZ,release_wait
    CALL 63DEH
    ; Return through the original start: new saved SP, reset parser and
    ; transport, reprobe FreHD and start at the root directory.
    JP 6000H
exit_dos:
    CALL 63DEH
    JP 402DH
return_menu: DB 0

; File picker keyboard wrapper. Only ASCII lowercase letters are folded.
; Digits, BREAK (01h), zero/no key, and all other codes pass unchanged.
menu_scan:
    CALL 002BH
    CP 61H
    RET C
    CP 7BH
    RET NC
    AND 0DFH
    RET
