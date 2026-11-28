# GM zero-based programs, mapped to native EMT-10 patch numbers.
# Deliberately approximate organs/reeds/leads/FX with suitable sustained voices.
MAP = [
 0,1,0,1,2,3,4,4, # pianos
 4,2,2,2,4,4,4,4, # chromatic percussion
 6,6,6,6,8,8,5,5, # organs
 5,5,5,5,5,5,5,5, # guitars
 9,10,10,10,11,11,10,10, # basses
 6,6,6,6,6,5,4,4, # strings
 6,6,6,6,8,8,8,7, # ensemble
 7,7,7,7,7,7,7,7, # brass
 7,7,7,7,7,7,7,7, # reeds
 6,6,6,6,6,6,6,6, # pipes
 7,7,6,6,7,8,6,7, # synth leads
 8,6,6,8,6,8,8,6, # pads
 6,8,6,6,6,8,6,6, # FX
 5,5,5,5,5,4,4,5, # ethnic
 4,4,4,4,4,4,4,4, # percussive
 4,4,8,6,8,8,8,7, # sound effects
]
VOICES=['PIANO 1','PIANO 2','ELEC PIANO 1','ELEC PIANO 2','HARPSICHORD','GUITAR','STRINGS','BRASS','CHOIR','UPRIGHT BASS','ELECTRIC BASS','SLAP BASS']
def db(label,data):
 return label+':\n'+'\n'.join(' DB '+','.join(map(str,data[i:i+16])) for i in range(0,len(data),16))+'\n'
def tables():
 s=''
 for label,data in [('gm_prompt',b'\rG = GENERAL MIDI AUTO ARRANGE\rP = PIANO REDUCTION + BASS\rN = NATIVE EMT-10\rCLEAR: MENU  BREAK: EXIT\r\0'),('scan_msg',b'\rScanning MIDI...\r\0'),('upper_msg',b'\rMain: \0'),('bass_msg',b'Bass: \0'),('voice_names',b''.join(x.encode().ljust(15)+b'\0' for x in VOICES)),('channel_names',b''.join(f' CH{i:02d}\r'.encode()+b'\0\0' for i in range(1,17))),('gm_map',bytes(MAP)),('cache_msg',b'\rLoading track into RAM...\r\0'),('cache_on',b'\0'),('cache_size',bytes(2)),('cache_ptr',bytes(2)),('cache_last',bytes(2)),('gm_mode',b'\0'),('upper_count',bytes(2)),('upper_total',bytes(2)),('force_piano',b'\0'),('bass_count',bytes(2)),('upper_voice',b'\0'),('bass_voice',b'\0'),('upper_ch',b'\0'),('bass_ch',b'\0'),('split_mode',b'\0'),('selected_patch',b'\0'),('role',b'\0'),('out_pitch',b'\0'),('source_ptr',bytes(2)),('gm_programs',bytes(16)),('histogram',bytes(512)),('source_notes',bytes(2048)),('upper_held',b'\0'),('bass_held',b'\0')]:s+=db(label,data)
 return s+"cache_base:\n"
