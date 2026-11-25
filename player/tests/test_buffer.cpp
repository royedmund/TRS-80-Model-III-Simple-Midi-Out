// Host-compiled execution of the actual Arduino sketch, using UART/time stubs.
// Not an AVR build or a cycle-accurate UART simulation.
#include "mock/SoftwareSerial.h"
#include "../firmware/serial_to_midi_buffered/serial_to_midi_buffered.ino"
#include <iostream>
uint32_t clock_us=0; bool led=false; MockSerial Serial;
void input(uint8_t b,uint32_t at){clock_us=at;trs.input.push_back(b);loop();}
void drain(uint32_t at,int loops=500){clock_us=at;while(loops--)loop();}
void reset(){Serial.out.clear();Serial.ready=true;state=RAW;clearQueue();panicIndex=192;inSysex=terminateSysex=false;clock_us=0;trs.over=false;trs.input.clear();setup();}
std::vector<uint8_t> panic(){std::vector<uint8_t> v;for(int ch=0;ch<16;ch++)for(int c:{64,66,67,123}){v.push_back(0xb0+ch);v.push_back(c);v.push_back(0);}return v;}
int main(){
 reset();for(uint8_t b:{0x90,60,100,0x80,60,0})input(b,0);assert((Serial.out==std::vector<uint8_t>{0x90,60,100,0x80,60,0}));std::cout<<"PASS raw bridge bytes unchanged\n";
 for(uint8_t start:{0xfd,0xf9}){
  reset();input(start,1000);input(0x90,2000);input(60,3000);input(100,4000);
  drain(160999);assert(Serial.out.empty());drain(161000);assert((Serial.out==std::vector<uint8_t>{0x90,60,100}));
  uint32_t p=start==0xfd?40000:33333;input(0xf8,1000+p+80000); // late tick still before queued due
  input(0x80,1000+p+81000);input(60,1000+p+82000);input(0,1000+p+83000);
  auto t=161000+p+100;drain(t-1);assert(Serial.out.size()==3);drain(t);assert(Serial.out.size()==6);
  input(0xfa,t+1000);drain(t+1000);auto want=std::vector<uint8_t>{0x90,60,100,0x80,60,0};auto pp=panic();want.insert(want.end(),pp.begin(),pp.end());assert(Serial.out==want && state==RAW);
  std::cout<<"PASS timed due, 80ms delayed tick absorbed, END drain + panic "<<int(start)<<"\n";
 }
 reset();input(0xfd,0);input(0x90,1000);input(60,2000);input(100,3000);input(0xfc,4000);drain(5000);assert(Serial.out==panic() && count==0);std::cout<<"PASS BREAK discards pending music and sends panic\n";
 reset();input(0xfd,0);input(0xf0,1000);input(0x43,2000);drain(160000);input(0xfc,170000);drain(171000);assert(Serial.out[2]==0xf7);std::cout<<"PASS STOP terminates partial SysEx before panic\n";
 reset();input(0xfd,0);for(int i=0;i<193;i++)input(1,1+i);drain(1000);assert(state==FAULT && Serial.out==panic() && led);input(0xfd,2000);assert(state==STREAM && !led);std::cout<<"PASS overflow fails safely and new START recovers\n";
 reset();input(0xfd,0);drain(2000000);assert(state==FAULT && Serial.out==panic());std::cout<<"PASS silent link watchdog panic\n";
 reset();input(0xfd,0xffff0000UL);input(0x90,0xffff1000UL);drain(uint32_t(0xffff0000UL+160000UL-1));assert(Serial.out.empty());drain(uint32_t(0xffff0000UL+160000UL));assert(Serial.out.size()==1);std::cout<<"PASS micros() rollover\n";
 reset();input(0xfd,0);Serial.ready=false;input(0x90,1000);drain(200000);assert(count==1 && Serial.out.empty());Serial.ready=true;drain(200001);assert(count==0 && Serial.out.size()==1);std::cout<<"PASS nonblocking transmit under UART backpressure\n";
}
