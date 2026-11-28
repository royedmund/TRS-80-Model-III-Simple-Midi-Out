; EMTPLAY v0.7: static information header; only native patch changes redraw row 2.
; Source aliases resolved by build.py against assembled GM symbols.
ORG 75A9H
    JP header_init
    JP header_patch
header_init:
    LD HL,8243H ; FreHD full path, maximum 63 characters
    LD DE,3C00H
    LD B,64
    CALL copy_z
    LD DE,3C40H
    LD A,(gm_mode_addr)
    CP 2
    LD HL,native_text
    JR NZ,mode_ready
    LD HL,gm_text
mode_ready:
    LD B,16
    CALL copy_z
    LD DE,3C50H
    LD A,(cache_on_addr)
    OR A
    LD HL,sd_text
    JR Z,cache_ready
    LD HL,ram_text
cache_ready:
    LD B,16
    CALL copy_z
    LD DE,3C60H
    LD A,(7C39H)
    OR A
    LD HL,raw_text
    JR Z,transport_ready
    LD HL,buffer_text
transport_ready:
    LD B,32
    CALL copy_z
    LD DE,3C80H
    LD HL,voice_text
    LD B,8
    CALL copy_z
    LD DE,3CC0H
    LD HL,upper_text
    LD B,64
    CALL copy_z
    LD DE,3E40H
    LD HL,bass_text
    LD B,64
    CALL copy_z
    LD DE,3FC0H
    LD HL,key_text
    LD B,64
    CALL copy_z
    LD A,(gm_mode_addr)
    CP 2
    JR NZ,panel_default
    LD A,(selected_patch_addr)
    JP header_patch
panel_default:
    LD HL,6CE9H ; original panel/unknown voice string
    JR patch_copy
header_patch:
    ; A = native Yamaha program (0..127), use baseline native alias table.
    AND 7FH
    LD L,A
    LD H,0
    ADD HL,HL
    LD DE,7329H
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    EX DE,HL
patch_copy:
    LD DE,3C88H
    LD B,40
patch_loop:
    LD A,(HL)
    LD (DE),A
    INC HL
    INC DE
    DJNZ patch_loop
    RET
copy_z:
    LD A,(HL)
    OR A
    RET Z
    LD (DE),A
    INC HL
    INC DE
    DJNZ copy_z
    RET
native_text: DB 78,65,84,73,86,69,32,69,77,84,45,49,48,0
gm_text: DB 71,77,32,65,85,84,79,32,65,82,82,65,78,71,69,0
sd_text: DB 83,68,32,83,84,82,69,65,77,0
ram_text: DB 82,65,77,32,67,65,67,72,69,0
raw_text: DB 82,65,87,32,77,73,68,73,0
buffer_text: DB 78,65,78,79,32,67,76,79,67,75,0
voice_text: DB 86,79,73,67,69,58,0
upper_text: DB 85,80,80,69,82,32,78,79,84,69,83,32,40,71,51,32,65,78,68,32,65,66,79,86,69,41,0
bass_text: DB 66,65,83,83,32,78,79,84,69,83,32,40,66,69,76,79,87,32,71,51,41,0
key_text: DB 67,76,69,65,82,58,32,77,69,78,85,32,32,32,66,82,69,65,75,58,32,69,88,73,84,0
