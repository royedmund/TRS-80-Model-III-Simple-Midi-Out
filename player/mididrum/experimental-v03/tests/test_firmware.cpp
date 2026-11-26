#include <cassert>
#include <iostream>
#include <initializer_list>
#include "../firmware/serial_to_midi_v03/serial_to_midi_v03.ino"
void reset(){clearQueue();state=RAW;panicIndex=192;inSysex=terminateSysex=false;fakeClock=0;microsCalls=0;Serial.bytes.clear();Serial.freeSlots=63;trs.input.clear();trs.over=false;rxOverflows=queueOverflows=0;peakQueue=0;led=false;}
void input(std::initializer_list<uint8_t> bytes){for(auto b:bytes)trs.input.push_back(b);loop();}
void flush(){for(int i=0;i<40;i++){Serial.freeSlots=63;loop();}}
int main(){
 setup();reset();input({0x90,60,100,64,90,60,0});assert(Serial.bytes==std::vector<uint8_t>({0x90,60,100,64,90,60,0}));assert(!count&&!microsCalls);loop();assert(!microsCalls);
 // Backpressure: queued bytes must be sent before subsequent raw data.
 reset();Serial.freeSlots=55;input({0x90,60,100});assert(count==3&&Serial.bytes.empty());Serial.freeSlots=63;input({64,90});flush();assert(Serial.bytes==std::vector<uint8_t>({0x90,60,100,64,90}));assert(!count);
 // 25 Hz timed protocol with lead and ordered byte deadlines.
 reset();input({0xfd,0x90,60,100});assert(state==STREAM&&count==3&&Serial.bytes.empty());fakeClock=159999;loop();assert(Serial.bytes.empty());fakeClock=160000;loop();assert(Serial.bytes==std::vector<uint8_t>({0x90,60,100}));fakeClock=40000;input({0xf8,64,90});assert(count==2);fakeClock=200000;Serial.freeSlots=63;loop();assert(Serial.bytes==std::vector<uint8_t>({0x90,60,100,64,90}));
 // Natural end drains before panic; STOP clears outstanding music.
 reset();input({0xf9,0x90,60,100,0xfa});assert(state==DRAIN);fakeClock=160000;flush();assert(state==RAW&&Serial.bytes.size()==195&&Serial.bytes[0]==0x90&&Serial.bytes[3]==0xb0);
 reset();input({0xfd,0x90,60,100,0xfc});flush();assert(state==RAW&&Serial.bytes.size()==192&&Serial.bytes[0]==0xb0);
 // STOP during SysEx terminates it before panic.
 reset();input({0xf0,0x43,0xfc});flush();assert(Serial.bytes[0]==0xf0&&Serial.bytes[1]==0x43&&Serial.bytes[2]==0xf7&&Serial.bytes[3]==0xb0);
 // Clock rollover and timeout preserve original behavior.
 reset();fakeClock=0xffff0000u;input({0xfd,0x90,60,100});fakeClock+=159999;loop();assert(Serial.bytes.empty());++fakeClock;loop();assert(Serial.bytes.size()==3);fakeClock=lastInput+WATCHDOG_US;loop();assert(state==FAULT&&led);
 reset();Serial.freeSlots=0;for(int i=0;i<193;i++)receiveByte(0x40,0);assert(state==FAULT&&queueOverflows==1&&peakQueue==192);
 reset();trs.over=true;loop();assert(rxOverflows==1&&state==FAULT&&led);
 std::cout<<"PASS: raw fast path (zero micros calls), FIFO backpressure, running status, timed lead/ticks, END/STOP/SysEx cleanup, rollover, watchdog and overflow diagnostics\n";
}
