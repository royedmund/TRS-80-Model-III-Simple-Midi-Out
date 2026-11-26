# MIDISD v0.1 — FreHD native SD-card player (experimental)

A separate Model III LDOS 5.3.1 CMD based on MIDIPlay v0.9. The original MIDIPLAY and Nano firmware are unchanged. Read-only: no SD writes, mounting commands, or firmware updates.

## Hardware test
1. Copy one or more known-good Format 0 MIDI files (e.g. player/VOICES.MID and player/ROCKJAZZ.MID) to the FreHD SD card's FAT root or a MIDI folder. Use 8.3 names, e.g. VOICES.MID. No DOS disk-image import of songs.
2. Put MIDISD.CMD into your LDOS disk image once (DOS name MIDISD/CMD). Boot LDOS 5.3.1 on the Model III.
3. With your existing 9600-baud RS-232-to-MIDI bridge and EMT-10 connected, run MIDISD.
4. Choose a numbered file or folder; N next page, R restart current directory, U parent, BREAK exit. No sorting; entries are shown in FAT order. Up to nine entries per page, no total directory limit. Only .MID and visible folders shown.
5. Select existing timing/transport: 2 raw 25 Hz, 3 raw 30 Hz, 4 buffered 25 Hz, 5 buffered 30 Hz. Use the buffered modes only with the project's buffered Nano firmware.
6. End of song or BREAK closes the file and returns to LDOS. Run MIDISD again for another song.

Use a backup SD card for initial hardware tests. No FreHD firmware flashing should be necessary if GETVER/OPENFILE/READFILE/CLOSEFILE/OPENDIR/READDIR are supported. Both 4-byte stock and 8-byte TRSvid-style open responses are accepted. Hardware compatibility is not yet verified.

## Implementation
- C2 data, C3 count, C4 command, C5 error, CF status. Enable external I/O with EC bit 4 and restore the previous control value at exit.
- Probe GETVER (0, 6 bytes); OPENDIR (8) and READDIR (9) for native FAT directory enumeration; OPENFILE (3, FA_READ=1), READFILE (4), CLOSEFILE (6).
- 255-byte RAM reads into the existing 256-byte sector buffer; no sector streaming, no direct FAT parsing, no DOS file access during playback.
- Native short names only; 63-character path limit, conservative path-join guard. Nested folders and parent navigation. Hidden/system/volume entries skipped.
- Bounded BUSY polling, error checking and complete reply draining. BREAK checked between transactions to avoid aborting half a transfer. Existing MIDI panic and timer logic retained.
- MIDI restrictions inherited unchanged: standard MIDI format 0, PPQN, track <=65535 bytes, 16-bit delta/length handling, EMT-10 SysEx whitelist. Format 1 needs existing convert_midi.py or other format-0 conversion, not disk import. The FreHD directory can hold larger files but this engine cannot play arbitrary large SMFs.
- LDOS interrupts remain enabled; actual SD latency/timing, I/O port control, ROM keyboard release behavior and firmware compatibility need real-machine verification. A hung hardware I/O bus itself is not recoverable by a software polling timeout.

## Build
Run `python3 build_midisd.py` in this directory. No third-party dependencies. Outputs MIDISD.CMD and MIDISD.MAP. The original v0.9 assembly was independently assembled and compared byte-for-byte against its committed CMD before this build. The new CMD has been assembled and load-record checked, not executed on real hardware.

## Credits
George Phillips, TRSvid (https://48k.ca/trsvid.html) and GIF/CMD: supplied archives, TRSvid directory browser and FreHD protocol usage, GIF development-mode buffered input. Frederic Vecoven, FreHD firmware (https://www.vecoven.com/trs80/trs80.html): documented file and directory command behavior. New browser/reader independently implemented for this project; no firmware or George's source files redistributed.
