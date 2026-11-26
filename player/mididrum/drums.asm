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
