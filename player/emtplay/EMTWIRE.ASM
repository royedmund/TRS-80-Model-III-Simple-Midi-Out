; Explicit status dispatch. In v1.0 the build links this jump to FRAME_MIDI.
; No running-status compression. Raw fallback sends the original bytes.
ORG 6AA3H
wire_send:
    JP 65FBH
