# TRS-80 Model III – Simple MIDI OUT

A minimal, external, one-way MIDI interface for the TRS-80 Model III and Yamaha EMT-10 AWM Sound Expander. No modification to the TRS-80 is required.

**Status:** Rev 0.2 prototype design, 24 November 2026. Firmware and circuit have not yet been tested on physical hardware.

## How it works

The Model III sends raw MIDI bytes over its existing RS-232 port at 9600 baud (8N1). A MAX3232 module converts the RS-232 voltage levels to 5 V logic; a classic Arduino Nano receives the bytes and retransmits them at the MIDI rate of 31,250 baud.

```text
TRS-80 DB-25 TXD -> MAX3232 -> Nano D10 (RX)
                                  Nano D1 (TX) -> MIDI OUT -> EMT-10 MIDI IN
```

The stock Model III baud-rate generator does not support 31,250 baud. RS-232 and MIDI also use different electrical signalling. **Never wire RS-232 directly to MIDI IN.**

## Circuit schematic

![Minimal one-way RS-232 to MIDI OUT schematic](hardware/minimal-midi-out.svg)

[View schematic](hardware/minimal-midi-out.svg) · [Arduino firmware](firmware/serial_to_midi/serial_to_midi.ino)

## Parts list

| Qty | Part |
| --- | --- |
| 1 | Classic Arduino Nano, ATmega328P, 5 V / 16 MHz |
| 1 | MAX3232 RS-232-to-logic module, rated for 5 V operation, with onboard charge-pump capacitors |
| 2 | 220 ohm resistors, 1/4 W |
| 1 | 180-degree 5-pin DIN female socket |
| 1 | Mating DB-25 connector or breakout for the TRS-80 |
| 1 | Regulated 5 V supply, at least 200 mA (USB power is convenient) |
| As required | Wire, board and standard MIDI cable |

## Wiring

| From | To |
| --- | --- |
| TRS-80 DB-25 pin 2 (TXD) | MAX3232 R1IN (RS-232 input) |
| TRS-80 DB-25 pin 7 (signal ground) | Common GND |
| MAX3232 R1OUT (logic output) | Nano D10 |
| Nano 5V | MAX3232 VCC |
| Nano GND | MAX3232 GND and MIDI OUT DIN pin 2 |
| Nano 5V | R1 (220 ohm) -> MIDI OUT DIN pin 4 |
| Nano D1 / TX | R2 (220 ohm) -> MIDI OUT DIN pin 5 |

DIN pins 1 and 3 and Nano D11 remain unconnected. The DIN pin numbers identify terminals, not physical positions; verify against the socket's datasheet. MAX3232 breakout labels vary: verify the direction of the receiver rather than relying on TX/RX labels alone.

Power the Nano via USB, or use a suitable regulated 5 V supply at its 5V pin (not VIN); avoid simultaneously driving the 5V rail from separate supplies. The MAX3232 and MIDI output share that regulated rail. No power is taken from the TRS-80 serial port.

The direct Nano TX driver is a deliberately minimal prototype. A buffered output following the MIDI Association electrical specification is preferable for a formally compliant or production interface. The Yamaha's MIDI IN provides its own receiver isolation; no MIDI IN or return-data circuit is provided here.

## Firmware

Open `firmware/serial_to_midi/serial_to_midi.ino` in the Arduino IDE. Select the classic Arduino Nano (ATmega328P), the appropriate bootloader option and serial port. Disconnect the Yamaha while uploading or resetting the Nano, since bootloader traffic on D1 is not valid MIDI. No extra libraries beyond the AVR core's SoftwareSerial are needed.

The bridge does not interpret the data or add line endings. Do not send debugging text over the MIDI UART.

## First hardware test

1. With the Yamaha disconnected, check the 5 V supply and verify that D1 idles high after boot.
2. Set the Model III serial software to 9600 baud, 8 data bits, no parity, one stop bit. Disable hardware/software flow control and any text translation.
3. Verify raw transmission at the MAX3232 output and 31,250-baud output on D1 with a logic analyser or oscilloscope if available.
4. Connect MIDI OUT to the Yamaha EMT-10 MIDI IN, set the receiver to channel 1 (or OMNI), and connect its audio output to an amplifier.
5. Send these raw bytes from the TRS-80, waiting about half a second between note-on and note-off:

| Action | Hex bytes | Decimal bytes |
| --- | --- | --- |
| Middle C on | 90 3C 64 | 144, 60, 100 |
| Middle C off | 90 3C 00 | 144, 60, 0 |
| E on | 90 40 64 | 144, 64, 100 |
| E off | 90 40 00 | 144, 64, 0 |
| G on | 90 43 64 | 144, 67, 100 |
| G off | 90 43 00 | 144, 67, 0 |

Send binary byte values, not ASCII hex strings. If a note sticks, explicitly send note-off for each active note or use the Yamaha's reset procedure. CC 123 (B0 7B 00) may be used if supported by the receiver.

## Model III MIDI player (v0.2)

The native Z80 player streams compatible format-0 SMF files from disk. LDOS 5.3.1 is the initial target; TRSDOS and physical hardware are not yet verified.

- [MIDIPLAY.CMD](player/MIDIPLAY.CMD) — 1,374-byte native executable
- [MIDIPLAY.ASM](player/MIDIPLAY.ASM) — Z80 source
- [NYPLAY.BAS](player/NYPLAY.BAS) — BASIC player for converted data
- [VOICES.MID](player/VOICES.MID) — original 12-voice EMT-10 demo
- [PIANOBRS.MID](player/PIANOBRS.MID) — original 38.4-second Piano 1 / Brass test, with [generator](player/make_piano_brass.py)
- [convert_midi.py](player/convert_midi.py) — desktop conversion utility
- [Player documentation](player/README.md)

Transfer CMD and MID files in binary mode; preserve the CR-delimited BASIC source. At LDOS Ready, enter:

```text
MIDIPLAY VOICES/MID:0
```

Select the actual LDOS tick frequency (2 = 25 Hz, 3 = 30 Hz); BREAK stops native playback. The EMT-10's voice assignments are not General MIDI patch numbers. Use converted files for this single-voice module.

The player supports running status, tempo changes, note and controller messages, skips SysEx, and sends pedal/all-notes-off cleanup. Format 1 requires desktop conversion. The adapted song was mock-tested locally but is not distributed here.

To audition Piano 1 and Brass in an alternating original piece, run `MIDIPLAY PIANOBRS/MID:0`. See the [player documentation](player/README.md#original-piano-and-brass-test-piece) for details and test results.

## License

Original project code, documentation, schematic and original MIDI demonstrations are provided under the [MIT License](LICENSE). Third-party manuals, songs and recordings are not included or licensed by this project.

## References

- [TRS-80 Model III service manual](https://manualzz.com/doc/63456250/radio-shack-26-1062--trs-80-service-manual)
- [TRS-80 port and I/O reference](https://www.trs-80.com/main-internal-ports-and-i-o.htm)
- [MIDI Association – 5-pin DIN electrical specifications](https://midi.org/5-pin-din-electrical-specs)
