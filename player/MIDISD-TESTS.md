# MIDISD v0.1 validation

Binary under test: commit `c76f68bdfd8cf7846f07c95aaf995a376d0bd4d3`, `player/MIDISD.CMD` (8,643 bytes; load 6000–8136h). Original v0.9 CMD was independently reproduced byte-for-byte before the new build. New CMD load records and transfer address round-tripped successfully.

The following checks were executed against the compiled Z80 bytes using a restricted instruction simulator with mocked LDOS timer, ROM keyboard/console, UART and FreHD command/data/status ports. The mock did not execute DOS file calls, and each case checked restoration of the external I/O control value. This was not full-system or real-hardware emulation.

| Test | Result |
|---|---|
| Root MIDI file, four-byte open reply, expected MIDI output | PASS |
| Eight-byte TRSvid open reply; metadata drain; 255 + 47 byte reads across block boundary | PASS |
| Directory pagination, exclusion of .DSK, lowercase .mid extension | PASS |
| Nested directories and parent navigation | PASS |
| Buffered Nano transport START and natural END markers | PASS |
| FreHD read error and file close | PASS |
| Premature EOF and file close | PASS |
| Absent interface | PASS |
| Stalled BUSY status timeout | PASS |
| BREAK while playing, file close and cleanup | PASS |
| BREAK in browser without opening a file | PASS |

Real-machine verification still required: FreHD firmware variation, actual directory structure and path semantics, SD latency, keyboard release, screen control codes and LDOS interrupt timing. No firmware was changed. The ad hoc simulator was run during development; its source is not included in this branch.
