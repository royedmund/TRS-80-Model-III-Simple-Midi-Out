# Framed RS-232 music transport — version 0.2 (experimental)

One-way, binary, 9600 baud 8N1, no flow control. TRS-80 is master; Nano is playback scheduler and MIDI Clock generator. DIN OUT is standard MIDI at 31250 baud. No extra clock pin. All hex bytes below are binary, not ASCII.

## Wire records

| Tag | Fields | Meaning |
|---|---|---|
| F6 | 19 or 1E | Begin new 25 or 30 Hz framed session (hex rate byte). Default tempo 500000 us/quarter. |
| F1 | six 0..0F nibbles, most significant first | Set 24-bit tempo, queued with next frame. E.g. F1 00 07 0A 01 02 00 = 500000 us/quarter. |
| F2 | length 00..7F; that many MIDI bytes | Complete one group of simultaneous (quantised) MIDI events, then advance one LDOS tick. Length 00 is a silent tick. |
| F3 | length 00..7F; that many MIDI bytes | Final group: drain, send MIDI Stop, release pedals and held notes. No following tick. |
| FC | none | Immediate abort/discard; send Stop if armed, clean up. Recognised even within an incomplete record. |

MIDI payload contains complete channel messages and supported complete SysEx (F0..F7 with 7-bit data). F1..F6 and F8..FF are forbidden in framed payloads; F6 starts a new session and FC aborts. No raw MIDI Clock bytes are needed from the TRS-80. F1 tempo records may occur before each F2/F3; multiple tempo changes at the same quantised boundary use the last one for the following interval. No checksums/ACK/retransmission; malformed tag/length/range, FIFO overflow and two-second active-stream timeout fail closed and clean up. Byte loss or corruption that still forms legal records is not reliably detectable. The decoder validates reserved bytes and length, not every possible MIDI message structure. A new F6 plus valid rate can recover from a fault.

## Example

```
F6 19                         ; start 25Hz session
F1 00 07 0A 01 02 00          ; 120 BPM
F2 03 90 3C 64                ; Note On middle C, then one 40ms tick
F2 00                         ; no new notes, advance 40ms
...                           ; further empty/event frames
F3 03 80 3C 00                ; last note-off, then stop and cleanup
```

Nano output begins FA F8 90 3C 64 ... and emits additional F8 at the clock rate. Private F6/F1/F2/F3 and their framing fields never appear as MIDI messages on DIN. At 120 BPM: 24 clocks/quarter, 48/s, 20833.33us interval. At 60 BPM: 24/s, 41666.67us. Notes and clock share the same scheduler deadline; clock phase is maintained across tempo changes. Phase pauses if the stream underruns rather than free-running away from the notes. Start is emitted ahead of first note/clock; first F8 at beat zero. Stop on EOF/abort/fault. No idle clock, Continue, SPP, external clock slave or MIDI IN.

## In-memory structures

Z80: one 127-byte group buffer + length. At a scheduled wait, flush the group before waiting for the next tick (better lookahead). Tempo record is transmitted immediately but committed with the next group. Raw mode bypasses the buffer. More than 127 music bytes in a single tick causes explicit native error/abort, not silent truncation.

Nano: 512-byte circular queue, 16x16-byte held-note bitmap, indices and complete-group count. Decoder strips wire headers/length and appends internal tempo token + nibbles, musical bytes, and a private internal end-of-tick/end-of-song token. Group count increments only after all declared payload bytes arrive. Scheduler only releases complete groups and generates actual MIDI Clock independently. No additional full-frame copy on Nano. Nominal initial lead 160ms. 25/30Hz note resolution is unchanged; clock pulses are interpolated within the existing tick schedule, with minor occupancy-based timing slew. Heavy bursts and UART stalls may affect physical timing. This is not a high-resolution per-event timestamp protocol.

At 9600 8N1 the serial line carries at most 960 bytes/s. Two-byte frame header costs 50 or 60 bytes/s; tempo updates cost 7 bytes each. At 120 BPM, the 48 clocks/s are generated locally, not sent over RS-232. MIDI OUT also carries musical bytes, transport messages and cleanup. Legacy FD/F9 starts remain clock-free. Historical F4/F5 clock v0.1 supported; older checked F4/F5 protocol is NOT supported. New F6 start reserves MIDI Tune Request in all modes: raw mode is compatible with existing supported player messages, not a fully transparent MIDI link. Never run framed MIDICLK with an older bridge.
