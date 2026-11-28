; EMTPLAY v1.0 structured output-only transport. Uses old unused workspace.
; Private F6 rate starts framed mode; F2 count data = tick frame;
; F3 count data = final frame; F1 + six nibbles = queued tempo.
; FC aborts immediately. MIDI bytes never share the command namespace.
ORG 6AF0H
FRAME_START:
    LD A,(7C39H)
    OR A
    RET Z
    XOR A
    LD (FRAME_LEN),A
    LD A,0F6H
    CALL 65FBH
    LD A,(7C39H)
    CP 0FDH
    LD A,25
    JP Z,65FBH
    LD A,30
    JP 65FBH
; Same tick's tempo record precedes the frame. Original scaler remains.
CLOCK_TEMPO:
    LD A,(7C39H)
    OR A
    JP Z,62ACH
    LD A,0F1H
    CALL 65FBH
    LD HL,7C4EH
    LD B,3
TEMPO_LOOP:
    LD A,(HL)
    SRL A
    SRL A
    SRL A
    SRL A
    CALL 65FBH
    LD A,(HL)
    AND 0FH
    CALL 65FBH
    DEC HL
    DJNZ TEMPO_LOOP
    JP 62ACH
; Preserve BC, HL and input A, raw mode goes to original UART.
FRAME_MIDI:
    PUSH AF
    LD A,(7C39H)
    OR A
    JP Z,RAW_MIDI
    POP AF
    PUSH HL
    PUSH BC
    PUSH AF
    LD A,(FRAME_LEN)
    CP 127
    JP NC,6623H ; dense tick exceeds supported capacity: native abort
    LD C,A
    LD B,0
    LD HL,FRAME_DATA
    ADD HL,BC
    INC A
    LD (FRAME_LEN),A
    POP AF
    LD (HL),A
    POP BC
    POP HL
    RET
RAW_MIDI:
    POP AF
    JP 65FBH
; Flush before waiting for the next LDOS tick, giving Nano maximum lead.
WAIT_START:
    CALL FRAME_TICK
    LD A,(7C5CH)
    INC A
    LD (7C5CH),A
    RET
FRAME_TICK:
    LD A,(7C39H)
    OR A
    RET Z
    LD A,0F2H
    JP FRAME_FLUSH
FRAME_FINISH:
    CP 0FCH
    JP Z,65FBH
    LD A,0F3H
FRAME_FLUSH:
    PUSH BC
    PUSH HL
    CALL 65FBH
    LD A,(FRAME_LEN)
    CALL 65FBH
    OR A
    JP Z,FRAME_DONE
    LD B,A
    LD HL,FRAME_DATA
FRAME_LOOP:
    LD A,(HL)
    CALL 65FBH
    INC HL
    DJNZ FRAME_LOOP
FRAME_DONE:
    XOR A
    LD (FRAME_LEN),A
    POP HL
    POP BC
    RET
FRAME_LEN: DB 0
FRAME_DATA:
    DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
