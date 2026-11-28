; EMTPLAY v1.0 - two-pass GM adaptation and framed clock output.
; State: 0 native, 1 scan, 2 GM playback. Scan reuses validated SMF parser.
; Histogram: 16 channels x 16 mapped voices, 16-bit count per cell.
; Ignore channel 10. Pick most active upper and bass channel/voice pairs.
; If same channel wins both roles, retain upper only. Bass-only is single voice.
; Fixed patch for entire performance, no arbitrary GM SysEx/controller output.
; Source-to-output table: accepted source note maps to output pitch + 1.
; Mix pitched channels into two native voices; preserve source note identity.
; Reserve two upper slots for the primary channel; merge unisons by refcount.
ORG 8301H
new_browser:
    XOR A
    LD (gm_mode),A
    LD (cache_on),A
    LD (force_piano),A
    JP 7D80H
header_ready:
    LD A,(gm_mode)
    CP 2
    JP Z,clock_prompt
    CALL cache_load
    LD HL,gm_prompt
    CALL 66A7H
choose_mode:
    CALL 63CAH
    CALL 002BH
    AND 0DFH
    CP 47H
    JR Z,begin_scan
    CP 50H
    JR NZ,not_piano
    LD A,1
    LD (force_piano),A
    JR begin_scan
not_piano:
    CP 4EH
    JR NZ,choose_mode
clock_prompt:
    LD HL,6993H
    JP 607DH
begin_scan:
    LD HL,scan_msg
    CALL 66A7H
    LD HL,gm_programs
    LD DE,gm_programs+1
    LD BC,527
    LD (HL),0
    LDIR
    LD A,1
    LD (gm_mode),A
    XOR A
    LD (7C3FH),A
    JP 6118H
; Do not wait or emit transport ticks during scan.
gm_delay:
    LD A,(gm_mode)
    CP 1
    RET Z
    JP 6316H
gm_tempo:
    LD A,(gm_mode)
    CP 1
    RET Z
    JP 62ACH
; Native SysEx remains whitelisted; suppress all in scan and GM mode.
gm_sysex:
    LD A,(gm_mode)
    OR A
    JP NZ,6118H
    CALL 6AD0H ; reset wire status before native SysEx
    JP 624BH
; Intercept full parsed messages, never modify parser running status.
gm_three:
    LD A,(gm_mode)
    OR A
    JP Z,native_three
    CP 1
    JP NZ,play_three
    LD A,(7C3FH)
    AND 0F0H
    CP 90H
    JP NZ,6118H
    LD A,(7C5EH)
    OR A
    JP Z,6118H
    CALL channel_index
    CP 9
    JP Z,6118H
    LD C,A
    LD B,0
    LD HL,gm_programs
    ADD HL,BC
    LD E,(HL)
    ; channel * 32 + mapped voice * 2
    LD L,C
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD D,0
    ADD HL,DE
    ADD HL,DE
    LD DE,histogram
    ADD HL,DE
    INC (HL)
    JP NZ,6118H
    INC HL
    INC (HL)
    JP 6118H
gm_two:
    LD A,(gm_mode)
    OR A
    JP Z,native_two
    CP 1
    JP NZ,6118H
    LD A,(7C3FH)
    AND 0F0H
    CP 0C0H
    JP NZ,6118H
    LD A,(7C5DH)
    LD C,A
    LD B,0
    LD HL,gm_map
    ADD HL,BC
    LD D,(HL)
    CALL channel_index
    LD C,A
    LD B,0
    LD HL,gm_programs
    ADD HL,BC
    LD (HL),D
    JP 6118H
channel_index:
    LD A,(7C3FH)
    AND 0FH
    RET
; EOT is the only rewind point; no UART initialized yet.
gm_end:
    LD A,H
    OR L
    JP NZ,6623H
    LD A,(gm_mode)
    CP 1
    JP NZ,61E8H
    CALL choose_voices
    CALL show_choice
    LD A,2
    LD (gm_mode),A
    LD A,(cache_on)
    OR A
    JR Z,stream_rewind
    LD HL,cache_base
    LD (cache_ptr),HL
    LD HL,(cache_size)
    LD (7C40H),HL
    XOR A
    LD (7C3FH),A
    JP clock_prompt
stream_rewind:
    ; CLOSEFILE without disabling external I/O, then reopen same path.
    LD A,6
    OUT (0C4H),A
    CALL 80A1H
    JP C,80D1H
    XOR A
    LD (7C3DH),A
    LD A,2
    LD (gm_mode),A
    CALL 8001H
    JP 602BH
choose_voices:
    LD HL,0
    LD (upper_count),HL
    LD (bass_count),HL
    LD (upper_total),HL
    LD A,0FFH
    LD (upper_ch),A
    LD (bass_ch),A
    LD HL,histogram
    LD B,0 ; 256 entries, DJNZ wraps
    LD C,0 ; packed channel/voice index
choose_loop:
    PUSH HL
    PUSH BC
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD A,D
    OR E
    JR Z,choose_next
    LD A,C
    AND 0FH
    CP 9
    JR NC,bass_candidate
    PUSH AF
    LD HL,(upper_total)
    ADD HL,DE
    JR NC,total_ok
    LD HL,0FFFFH
total_ok:
    LD (upper_total),HL
    POP AF
    LD HL,(upper_count)
    OR A
    SBC HL,DE
    JR NC,choose_next
    LD (upper_count),DE
    LD (upper_voice),A
    CALL packed_channel
    LD (upper_ch),A
    JR choose_next
bass_candidate:
    LD HL,(bass_count)
    OR A
    SBC HL,DE
    JR NC,choose_next
    LD (bass_count),DE
    LD (bass_voice),A
    CALL packed_channel
    LD (bass_ch),A
choose_next:
    POP BC
    POP HL
    INC HL
    INC HL
    INC C
    DJNZ choose_loop
    XOR A
    LD (split_mode),A
    LD A,(upper_ch)
    CP 0FFH
    JR NZ,upper_found
    LD A,(bass_ch)
    CP 0FFH
    JP Z,6623H ; no pitched notes
    LD (upper_ch),A
    LD A,(bass_voice)
    LD (upper_voice),A
    JR single_voice
upper_found:
    ; A mixed score benefits from a neutral piano reduction when the sum
    ; of the other pitched parts is at least the primary part's activity.
    LD A,(force_piano)
    OR A
    JR NZ,neutral_voice
    LD HL,(upper_count)
    ADD HL,HL
    JR C,retain_voice
    EX DE,HL
    LD HL,(upper_total)
    OR A
    SBC HL,DE
    JR C,retain_voice
neutral_voice:
    XOR A
    LD (upper_voice),A
retain_voice:
    LD A,(upper_ch)
    LD C,A
    LD A,(bass_ch)
    CP 0FFH
    JR Z,single_voice
    CP C
    JR Z,single_voice
    LD A,1
    LD (split_mode),A
    LD A,(bass_voice)
    SUB 9
    ADD A,A
    ADD A,A
    ADD A,A
    ADD A,A
    ADD A,48
    LD C,A
    LD A,(upper_voice)
    ADD A,C
    LD (selected_patch),A
    RET
single_voice:
    LD A,0FFH
    LD (bass_ch),A
    LD A,(upper_voice)
    LD (selected_patch),A
    RET
packed_channel:
    LD A,C
    SRL A
    SRL A
    SRL A
    SRL A
    RET
show_choice:
    LD HL,upper_msg
    CALL 66A7H
    LD A,(upper_voice)
    CALL print_voice
    LD A,(upper_ch)
    CALL print_channel
    LD A,(split_mode)
    OR A
    RET Z
    LD HL,bass_msg
    CALL 66A7H
    LD A,(bass_voice)
    CALL print_voice
    LD A,(bass_ch)
    JP print_channel
print_voice:
    LD L,A
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD DE,voice_names
    ADD HL,DE
    JP 66A7H
print_channel:
    LD L,A
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD DE,channel_names
    ADD HL,DE
    JP 66A7H
; Start original transport, then initialise mapping tables and send patch.
gm_start:
    CALL 63F7H
    LD A,(gm_mode)
    CP 2
    RET NZ
    LD HL,source_notes
    LD DE,source_notes+1
    LD BC,2049
    LD (HL),0
    LDIR
    LD A,0C0H
    CALL 65FBH
    LD A,(selected_patch)
    JP 65FBH
; Only notes are forwarded in GM mode. Maintain output voice budget.
play_three:
    LD A,(7C3FH)
    AND 0F0H
    CP 80H
    JR Z,play_note
    CP 90H
    JP NZ,6118H
play_note:
    CALL channel_index
    CP 9
    JP Z,6118H
    LD C,A
    LD A,(bass_ch)
    CP C
    LD A,0
    JR NZ,role_ready
    INC A
role_ready:
    LD (role),A
    ; Track each of the 16 input channels independently. Channel*128 + pitch.
    LD L,C
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD A,(7C5DH)
    LD E,A
    LD D,0
    ADD HL,DE
    LD DE,source_notes
    ADD HL,DE
    LD (source_ptr),HL
    LD A,(7C3FH)
    AND 0F0H
    CP 80H
    JP Z,release_note
    LD A,(7C5EH)
    OR A
    JP Z,release_note
    LD A,(HL)
    OR A
    JP NZ,6118H ; repeated held source pitch ignored
    CALL fold_pitch
    LD (out_pitch),A
    LD C,A
    LD B,0
    LD HL,7831H
    ADD HL,BC
    LD A,(HL)
    OR A
    JR NZ,merge_unison
    ; Reserve two upper keys for primary melody; count unique sounding pitches.
    CALL count_ptr
    LD C,8
    LD A,(split_mode)
    OR A
    JR Z,cap_upper
    LD C,6
    LD A,(role)
    OR A
    JR Z,cap_upper
    LD C,2
    JR cap_ready
cap_upper:
    CALL channel_index
    LD B,A
    LD A,(upper_ch)
    CP B
    JR Z,cap_ready
    DEC C
    DEC C
cap_ready:
    LD A,(HL)
    CP C
    JP NC,6118H
    INC (HL)
    LD A,(out_pitch)
    LD C,A
    LD B,0
    LD HL,7831H
    ADD HL,BC
    LD (HL),1
    CALL remember_source
    LD A,90H
    CALL 6AA3H ; explicit status via selected transport
    LD A,(out_pitch)
    CALL 65FBH
    LD A,(7C5EH)
    CALL 65FBH
    LD A,(out_pitch)
    CALL score_draw
    JP 6118H
merge_unison:
    ; Multiple source keys may map to the same physical note. Hold until the
    ; last corresponding note-off. No additional MIDI note-on is sent.
    CP 0FFH
    JP Z,6118H
    INC (HL)
    CALL remember_source
    JP 6118H
remember_source:
    LD HL,(source_ptr)
    LD A,(out_pitch)
    INC A
    LD (HL),A
    RET
release_note:
    LD A,(HL)
    OR A
    JP Z,6118H
    LD (HL),0
    DEC A
    LD (out_pitch),A
    LD C,A
    LD B,0
    LD HL,7831H
    ADD HL,BC
    DEC (HL)
    JP NZ,6118H
    CALL count_ptr
    DEC (HL)
    LD A,80H
    CALL 6AA3H ; explicit status via selected transport
    LD A,(out_pitch)
    CALL 65FBH
    XOR A
    CALL 65FBH
    JP 6118H
count_ptr:
    LD HL,upper_held
    LD A,(role)
    OR A
    RET Z
    INC HL
    RET
; Fold by octaves, preserving pitch class. Practical ranges chosen for
; split bass 28..54, upper 55..108; single 21..108.
fold_pitch:
    LD A,(split_mode)
    OR A
    JR Z,single_range
    LD A,(role)
    OR A
    JR Z,upper_range
    LD B,28
    LD C,55
    JR range_ready
upper_range:
    LD B,55
    LD C,109
    JR range_ready
single_range:
    LD B,21
    LD C,109
range_ready:
    LD A,(7C5DH)
fold_low:
    CP B
    JR NC,fold_high
    ADD A,12
    JR fold_low
fold_high:
    CP C
    RET C
    SUB 12
    JR fold_high
; Cache SMF track payload after MTrk header. HIGH$ is inclusive top
; of available LDOS memory, NOT physical RAM size. No HIGH$ changes.
; Reserve 512 bytes below saved entry stack if it lives in high RAM.
; The file stays logically open for CLEAR and normal cleanup.
cache_load:
    XOR A
    LD (cache_on),A
    LD HL,(7C40H)
    LD A,H
    OR L
    RET Z
    LD (cache_size),HL
    DEC HL
    LD DE,cache_base
    ADD HL,DE
    RET C ; last byte would exceed FFFFh
    LD (cache_last),HL
    EX DE,HL
    LD HL,(4411H)
    OR A
    SBC HL,DE
    RET C ; track does not fit below resident modules
    LD HL,(7C3BH)
    LD DE,cache_base
    OR A
    SBC HL,DE
    JR C,cache_fit ; stack below cache
    LD HL,(7C3BH)
    LD DE,512
    OR A
    SBC HL,DE
    RET C
    LD DE,(cache_last)
    OR A
    SBC HL,DE
    RET C ; stack guard
cache_fit:
    LD HL,cache_msg
    CALL 66A7H
    LD HL,cache_base
    LD BC,(cache_size)
cache_copy:
    CALL 805AH ; original SD reader preserves BC/DE/HL and checks keys
    LD (HL),A
    INC HL
    DEC BC
    LD A,B
    OR C
    JR NZ,cache_copy
    LD HL,cache_base
    LD (cache_ptr),HL
    LD A,1
    LD (cache_on),A
    RET
; Fast cached rawget: preserve BC/DE/HL, poll keyboard exactly as old reader.
; Caller get enforces remaining bytes. Header reads always use original SD.
cache_rawget:
    LD A,(cache_on)
    OR A
    JP Z,805AH
    CALL 63CAH
    PUSH HL
    LD HL,(cache_ptr)
    LD A,(HL)
    INC HL
    LD (cache_ptr),HL
    POP HL
    RET
; Tables appended by build.py as DB rows.
