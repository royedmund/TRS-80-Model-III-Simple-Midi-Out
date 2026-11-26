# MIDIDRUM v0.2 — FreHD MIDI and cassette percussion

**Experimental:** [MIDIDRUM v0.3 performance build](experimental-v03/README.md). The v0.2 files below remain unchanged.

TRS-80 Model III (48 KB), LDOS 5.3.1, FreHD native FAT files, Yamaha EMT-10, existing 9600-baud RS-232/MIDI interface. Based on [MIDISD v0.1](../README-MIDISD.md); the original player is untouched.

## Install and play

1. Transfer [MIDIDRUM.CMD](MIDIDRUM.CMD) in binary mode into your LDOS disk image as MIDIDRUM/CMD. Requires free RAM 6000h–84E9h.
2. Copy [GHSTWIRE.MID](GHSTWIRE.MID) and [NIGHTFAL.MID](NIGHTFAL.MID) directly onto the FreHD SD card (FAT, short 8.3 names). Do not import the songs into a DOS disk image.
3. Connect the existing RS-232/Nano/MIDI bridge to the EMT-10 (receive channel 1 or OMNI).
4. Connect the cassette audio OUTPUT (normally MIC/tape recorder input lead, not EAR playback input) to a separate amplified speaker or mixer input. Verify the cable pinout, use appropriate attenuation and start with low volume. Never connect the two outputs directly together. No cassette motor is needed.
5. Run MIDIDRUM, browse for a MIDI file, and select 6 or 7 for the actual LDOS timer frequency. BREAK stops playback.

| Keys | Mode | Clock |
|---|---|---|
| 2 / 3 | Original raw MIDI | 25 / 30 Hz |
| 4 / 5 | Original Nano buffered MIDI (matching firmware only) | 25 / 30 Hz |
| 6 / 7 | MIDI channel 10 to cassette, other channels to RS-232 | 25 / 30 Hz |
| 8 / 9 | Automatic 4/4 cassette beat; ignore incoming channel 10 | 25 / 30 Hz |

## Original compositions

| File | Character | Tempo | Duration | Melodic notes | Drum hits | Peak held melodic notes |
|---|---|---|---|---:|---:|---:|
| GHSTWIRE.MID | GHOSTWIRE: driving piano riffs, rock rhythm, eerie choir | 156–180 BPM | 57.16 s | 716 | 322 | 5 |
| NIGHTFAL.MID | NIGHTFALL: layered piano, atmospheric choir, heartbeat and metallic effects | 128–148 BPM | 87.34 s | 508 | 303 | 6 |

| SUNSPARK.MID | SUNSPARK: modern jazz piano, playful cassette percussion and 10-second solo | 144 BPM | 80.42 s | 860 | 382 | 6 |

SUNSPARK is an original D-major format-0 MIDI file at 96 PPQN. Piano 1 on channel 1, cassette percussion on channel 10. From 30 to 40 seconds all piano notes are released; both audio paths resume at 40 seconds. Choose hybrid mode 6/7. The GHOSTWIRE and NIGHTFALL demos are original E-minor format-0 MIDI files at 96 PPQN, using native Yamaha program 0 (Piano 1) and 8 (Choir) on channel 1, alternating because a single EMT-10 does not independently layer two non-bass voices. Notes are released before program changes. Channel 10 is exclusively local percussion in hybrid mode. These files are not GM arrangements.

## Cassette percussion routing

| Note | Sound |
|---|---|
| 35/36 | Descending square-wave kick |
| 37–40 | Pseudorandom noise snare |
| 41/43/45/47/48/50 | Low tom approximation |
| 42/44/46 | Short noise hi-hat |
| 75 | Metallic tick |
| 76 | Rising chirp |
| 77 | Falling chirp |
| 78/79 | Ghost warble |

Other notes 35–81 use simple approximations; outside that range ignored. Channel 10 Note On with nonzero velocity triggers the sound, all other channel-10 messages are consumed. No velocity-to-amplitude mapping yet. Hybrid panic skips channel 10. Other channels, running status, the EMT-10 SysEx whitelist and existing display are retained.

## Implementation and limits

The Z80 generates cassette waveforms in bounded idle slices of the existing timer wait, prioritising MIDI playback. Interrupts remain enabled, with no hooks or port EC changes by the percussion engine. One software voice, priority FX > kick > snare > hat; hits expire after two timer ticks or the sample budget. Port FFh returns low between waits and on exit. Busy UART/SD processing can clip percussion. Actual frequency, sound quality and timing depend on CPU load and hardware. Hybrid uses raw MIDI to avoid the Nano's 160 ms buffering latency. No FreHD or Nano firmware changes required by design. Format 0, PPQN, 16-bit track length and delta/length handling remain inherited limits.

## Build

Python 3 standard library only. From this directory run:

```sh
python build.py
```

The two-pass assembler emits MIDIDRUM.CMD and MIDIDRUM.MAP, verifies all load records and the transfer address. [MIDIDRUM.ASM](MIDIDRUM.ASM) is the complete generated source with the commented [cassette extension](drums.asm); see the original [MIDISD.ASM](../MIDISD.ASM) for detailed comments on the inherited code. No external assembler or network access required.

## Validation

See [TESTS.txt](TESTS.txt) and [SHA256SUMS.txt](SHA256SUMS.txt). Original base CMD reproduced byte-for-byte; the new binary and both demo files were rebuilt and the targeted opcode harness passed. These tests stub file input, display, UART and timer; they are not full machine emulation or real-time playback. Physical hardware audio, timing and FreHD operation of the hybrid build remain to be tested.

Credits: George Phillips ([TRSvid](https://48k.ca/trsvid.html), GIF/CMD) and Frédéric Vecoven ([FreHD](https://www.vecoven.com/trs80/trs80.html)), as documented in the original MIDISD notes. Project and original compositions under the repository [MIT license](../../LICENSE).
