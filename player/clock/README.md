# MIDISD v0.4 — framed MIDI Clock (experimental)

Clock-enabled successor to the hardware-tested MIDISD v0.3. The original executable and source are unchanged in the parent directory. Install the output-only [MIDICLOCK v0.2 Nano firmware](../../transport/firmware/MIDICLOCK/MIDICLOCK.ino) before using modes 4/5. No hardware change. See the [protocol](../../transport/PROTOCOL.md) and [corrected schematic](../../transport/hardware/MIDI-CLOCK-OUT.svg).

Import MIDISD.CMD as MIDISD/CMD under LDOS 5.3.1. Copy CLOCKTST.MID to the FreHD SD card. Modes 2/3: raw 25/30 Hz (no clock); modes 4/5: framed clock 25/30 Hz (new firmware required). BREAK exits; original picker and dashboard retained. The EMT-10 ignores MIDI Clock itself; use a clock-following device or monitor to verify pulses.

## Source and build

MIDISD-base.CMD is the exact MIT-licensed v0.3 baseline (Git blob 6afd5600e2207c987aeea06d9755708356a42067). [MIDISD.ASM](../MIDISD.ASM) documents the original parser. [CLOCKHOOK.ASM](CLOCKHOOK.ASM) adds the framed sender, tempo encoding, timing and final/abort hooks; build.py checks the original instructions at every hook and verifies the CMD load records. Run python build.py and python test_hook.py in this directory. The 9,109-byte CMD is an experimental executable. See TESTS.txt and the central transport tests.

F6 rate starts a session, F1 sets tempo, F2/F3 carry complete event groups, FC aborts. Buffer 127 musical bytes per tick in unused memory; flush before the LDOS tick wait. Original 25/30 Hz note scheduling and raw fallback unchanged. Nominal Nano lead 160 ms; 512-byte FIFO; no CRC or ACK. Oversized frames abort instead of truncating. Instruction-level and host simulation passed; AVR compilation and physical audio/electrical timing remain unverified.
