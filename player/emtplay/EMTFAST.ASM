; EMTPLAY v0.8: transport-first hot paths in unused former dashboard RAM.
; All serial calls retain full MIDI status bytes and existing Nano protocol.
ORG 6CA3H
uart_slow:
    ; AF already saved by fast sender. Preserve BC only on busy path.
    PUSH BC
    LD B,0
uart_retry:
    IN A,(0EAH)
    AND 40H
    JR NZ,uart_ready
    DJNZ uart_retry
    ; Existing error handling restores original SP, including saved AF/BC.
    XOR A
    LD (7C3EH),A
    LD HL,6A8AH
    JP 6626H
uart_ready:
    POP BC
    POP AF
    OUT (0EBH),A
    RET

; Get one byte of track payload. Combine the existing bounds check and
; RAM cache read in one HL save/restore. Preserve BC and DE, and continue
; polling CLEAR/BREAK on every cached byte. For SD, use original reader.
fast_get:
    PUSH HL
    LD HL,(7C40H)
    LD A,H
    OR L
    JP Z,6623H
    DEC HL
    LD (7C40H),HL
    LD A,(cache_on_addr)
    OR A
    JR Z,fast_get_sd
    CALL 63CAH
    LD HL,(cache_ptr_addr)
    LD A,(HL)
    INC HL
    LD (cache_ptr_addr),HL
    POP HL
    RET
fast_get_sd:
    POP HL
    JP 805AH
