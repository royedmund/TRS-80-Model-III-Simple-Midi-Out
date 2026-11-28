; EMTPLAY v1.0: two independent compact note streams, no staves.
; Upper: rows 4..8. Bass: rows 10..14. Header rows 0..3, bass label row 9.
; MIDI note >=55 goes to upper, below 55 to bass (EMT-10 split at G3).
; Native non-split mode uses the same visual pitch division, not two voices.
; Note onsets only, no repeated held-note drawing. Each token is explicit
; pitch and octave, e.g. C#4 or Bb represented canonically as A#3.
; No padding between tokens. Wrap each band independently; clear one row
; only when reused. Never split a note token across rows.
ORG 66B3H
score_init:
    XOR A
    LD (6AE0H),A ; reset outgoing running status at every playback start
    LD A,4
    LD (upper_row),A
    XOR A
    LD (upper_col),A
    LD (bass_col),A
    LD A,10
    LD (bass_row),A
    CALL clear_keys
    LD HL,3C00H
    LD DE,3C01H
    LD BC,1023
    LD (HL),32
    LDIR
    CALL 75A9H ; initialise MIDI information header
    LD A,1
    LD (7829H),A
    RET

; Nothing to redraw on timing ticks. Keep the existing timing hook.
score_step:
    RET

; A = accepted MIDI pitch. Four-byte, zero-padded note-token table.
; Notes at 0..11 can use all four bytes (e.g. C#-1).
draw_pitch:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD DE,upper_row
    CP 55
    JR NC,stream_ready
    LD DE,bass_row
stream_ready:
    LD (stream_ptr),DE
    ; Precomputed lengths and page-aligned pitch tokens.
    LD L,A
    LD H,7BH
    LD C,(HL)
    LD H,0
    ADD HL,HL
    ADD HL,HL
    LD A,H
    ADD A,79H
    LD H,A
    LD (token_ptr),HL
    LD A,C
    LD (token_len),A
    LD HL,(stream_ptr)
    INC HL
    ADD A,(HL)
    CP 65
    JR C,write_token
    ; Advance row and wrap within the selected five-row band.
    LD (HL),0
    DEC HL
    LD A,(HL)
    INC A
    CP 9
    JR NZ,check_bass_wrap
    LD A,4
    JR row_ready
check_bass_wrap:
    CP 15
    JR NZ,row_ready
    LD A,10
row_ready:
    LD (HL),A
    CALL row_address
    ; LDIR fills only the recycled row, never the header.
    LD D,H
    LD E,L
    INC DE
    LD (HL),32
    LD BC,63
    LDIR
write_token:
    LD HL,(stream_ptr)
    LD A,(HL)
    CALL row_address
    EX DE,HL
    LD HL,(stream_ptr)
    INC HL
    LD C,(HL)
    LD A,(token_len)
    ADD A,C
    LD (HL),A
    EX DE,HL
    LD B,0
    ADD HL,BC
    EX DE,HL
    LD HL,(token_ptr)
    LD A,(token_len)
    LD B,A
copy_token:
    LD A,(HL)
    LD (DE),A
    INC DE
    INC HL
    DJNZ copy_token
    POP HL
    POP DE
    POP BC
    POP AF
    RET

; A=character row, HL=video RAM row start, preserve other registers.
row_address:
    ; 16 precomputed row addresses, page aligned at 7B80h.
    ADD A,A
    ADD A,80H
    LD L,A
    LD H,7BH
    LD A,(HL)
    INC L
    LD H,(HL)
    LD L,A
    RET

; These hooks are entered by JP after full SMF message parsing.
; Filter other channels, never split messages or forward GM percussion.
; Channel 1 status/program/controllers unchanged. Yamaha SysEx follows
; the unmodified baseline whitelist independently of these hooks.
send_three:
    LD A,(7C3FH)
    AND 0FH
    JP NZ,6118H
    LD A,(7C3FH)
    CALL 6AA3H ; status byte through full-message transport
    LD A,(7C5DH)
    CALL 65FBH
    LD A,(7C5EH)
    CALL 65FBH
    CALL observe_score
    JP 6118H
send_two:
    LD A,(7C3FH)
    AND 0FH
    JP NZ,6118H
    LD A,(7C3FH)
    CALL 6AA3H ; status byte through full-message transport
    LD A,(7C5DH)
    CALL 65FBH
    LD A,(7C3FH)
    CP 0C0H
    JR NZ,native_two_done
    LD A,(7C5DH)
    CALL 75ACH ; update native voice name only on program change
native_two_done:
    JP 6118H
observe_score:
    LD A,(7C3FH)
    CP 90H
    JR Z,note_on
    CP 80H
    JR Z,note_off
    CP 0B0H
    RET NZ
    LD A,(7C5DH)
    CP 120
    JP Z,clear_keys
    CP 123
    JP Z,clear_keys
    RET
note_on:
    LD A,(7C5EH)
    OR A
    JR Z,note_off
    LD A,(7C5DH)
    LD C,A
    LD B,0
    LD HL,7831H
    ADD HL,BC
    LD (HL),1
    LD A,C
    JP draw_pitch
note_off:
    LD A,(7C5DH)
    LD C,A
    LD B,0
    LD HL,7831H
    ADD HL,BC
    LD (HL),0
    RET
clear_keys:
    LD HL,7831H
    LD DE,7832H
    LD BC,127
    LD (HL),0
    LDIR
    RET

; Raw transport cleanup: release pedal, explicit off for tracked notes,
; then All Notes Off on channel 1. Buffered mode still uses Nano FA/FC.
raw_cleanup:
    LD A,0B0H
    CALL 65FBH
    LD A,64
    CALL 65FBH
    XOR A
    CALL 65FBH
    LD A,0B0H
    CALL 65FBH
    LD A,66
    CALL 65FBH
    XOR A
    CALL 65FBH
    LD A,0B0H
    CALL 65FBH
    LD A,67
    CALL 65FBH
    XOR A
    CALL 65FBH
    LD HL,7831H
    LD B,128
    LD C,0
panic_scan:
    LD A,(HL)
    OR A
    JR Z,panic_next
    LD A,80H
    CALL 65FBH
    LD A,C
    CALL 65FBH
    XOR A
    CALL 65FBH
panic_next:
    INC HL
    INC C
    DJNZ panic_scan
    LD A,0B0H
    CALL 65FBH
    LD A,123
    CALL 65FBH
    XOR A
    CALL 65FBH
    CALL clear_keys
    JP 6694H

; End of playback: return to original DOS status output, not dashboard.
score_finish:
    LD A,(7829H)
    OR A
    RET Z
    XOR A
    LD (7829H),A
    LD HL,3FC0H
    LD (4020H),HL
    RET
upper_row: DB 0
upper_col: DB 0
bass_row: DB 0
bass_col: DB 0
stream_ptr: DW 0
token_ptr: DW 0
token_len: DB 0
