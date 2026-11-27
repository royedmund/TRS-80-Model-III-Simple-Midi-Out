#include "mock/SoftwareSerial.h"
#include "../firmware/serial_to_midi_fast/serial_to_midi_fast.ino"
#include <iostream>
#include <algorithm>
#include <fstream>
#include <iterator>
#include <string>
uint32_t clock_us=0;bool led=false;MockSerial Serial;
void reset(){state=RAW;clearQueue();used=0;status=pos=0;panic=sysex=terminateSysex=false;for(auto &r:held)for(auto &v:r)v=0;Serial.out.clear();Serial.ready=true;trs.input.clear();trs.over=false;clock_us=0;setup();}
void pump(uint32_t t,int n=300){clock_us=t;while(n--)loop();}
void byte(uint8_t b,uint32_t t){clock_us=t;trs.input.push_back(b);loop();}
void input(std::initializer_list<uint8_t> a,uint32_t t){for(auto b:a)byte(b,t);}
bool has(std::initializer_list<uint8_t> a){return std::search(Serial.out.begin(),Serial.out.end(),a.begin(),a.end())!=Serial.out.end();}
void units(){
 reset();input({0x90,60,100,0x80,60,0},0);assert((Serial.out==std::vector<uint8_t>{0x90,60,100,0x80,60,0}));std::cout<<"PASS raw MIDI unchanged\n";
 for(auto startByte:{0xfd,0xf9}){reset();byte(startByte,1000);input({0x90,60,100},2000);pump(161000);assert(Serial.out.empty()&&waiting);byte(0xf8,181000);pump(181000);assert((Serial.out==std::vector<uint8_t>{0x90,60,100}));input({0x80,60,0,0xfa},190000);pump(deadline);assert(state==RAW&&!panic&&has({0x80,60,0}));std::cout<<"PASS complete groups, late-start recovery and END "<<(startByte==0xfd?25:30)<<"Hz\n";}
 reset();byte(0xfd,0);input({0x90,60,100,0xf8},40000);pump(160000);assert(held[0][7]&16);pump(800000);assert(state==STREAM&&waiting);input({0x80,60,0,0xf8},850000);pump(850000);assert(state==STREAM&&!waiting&&!held[0][7]);std::cout<<"PASS 600ms temporary input stall resumes without dropping notes\n";
 reset();byte(0xfd,0);input({0x90,60,100,0xf8},40000);pump(160000);byte(0xfc,170000);pump(170000);assert(state==RAW&&has({0x80,60,0})&&!panic);std::cout<<"PASS BREAK explicitly releases held notes and pedals\n";
 reset();byte(0xfd,0);input({0xf0,0x43,0xf8},40000);pump(160000);byte(0xfc,170000);pump(170000);assert(Serial.out[2]==0xf7);std::cout<<"PASS abort closes partial SysEx\n";
 reset();byte(0xfd,0);for(int i=0;i<512;i++)byte(1,1000);assert(count==512);byte(1,1000);pump(1000);assert(state==FAULT&&faultCode==1&&led);byte(0xfd,2000);assert(state==STREAM);std::cout<<"PASS full FIFO overflow and restart\n";
 reset();byte(0xfd,0);trs.over=true;loop();assert(state==FAULT&&faultCode==2);pump(0);byte(0xfd,1000);assert(state==STREAM);pump(2001000);assert(state==FAULT&&faultCode==3);std::cout<<"PASS RX overflow and link watchdog\n";
 reset();byte(0xf4,0);assert(state==FAULT&&faultCode==4);std::cout<<"PASS incompatible checked v0.2 START visibly rejected\n";
 reset();byte(0xf9,0xffff0000);input({0x90,60,100,0xf8},0xffff0000+33333);pump(uint32_t(0xffff0000UL+160000UL-1));assert(Serial.out.empty());pump(uint32_t(0xffff0000UL+160000UL));assert(Serial.out.size()==3);std::cout<<"PASS micros rollover\n";
 reset();byte(0xfd,0);input({0x90,60,100,0xf8},40000);Serial.ready=false;pump(160000);assert(count==4&&Serial.out.empty());Serial.ready=true;pump(160001);assert(Serial.out.size()==3);std::cout<<"PASS output backpressure no dequeue\n";
}
// Actual assembled Z80 output. Pace byte arrivals at 9600 8N1 and tick
// boundaries at selected clock. Allow slow UART output service and a 100ms
// input stall. Host simulation only, not an ISR or electrical model.
void replay(const char* path){
 reset();std::ifstream f(path,std::ios::binary);std::vector<uint8_t> wire{std::istreambuf_iterator<char>(f),{}};assert(!wire.empty());uint32_t per=wire[0]==0xfd?40000:33333;
 std::vector<uint8_t> expect;uint32_t next=0,tick=0;std::vector<uint32_t> arrivals;
 for(size_t i=0;i<wire.size();++i){uint8_t b=wire[i];if(b==0xf8){++tick;next=std::max(next,tick*per);}if(i==wire.size()/2)next+=100000;arrivals.push_back(next);next+=1042;if(i&&b!=0xf8&&b!=0xfa)expect.push_back(b);}
 size_t n=0;uint32_t end=next+1000000;
 for(uint32_t t=0;t<end;t+=320){clock_us=t;while(n<wire.size()&&arrivals[n]<=t)trs.input.push_back(wire[n++]); // one byte per ~1ms
  // Artificial UART pressure: block several loop passes every 8ms.
  Serial.ready=(t%8000)<6400;loop();assert(state!=FAULT);}
 assert(n==wire.size()&&state==RAW&&!panic&&Serial.out.size()>=expect.size());assert(std::equal(expect.begin(),expect.end(),Serial.out.begin()));
 std::cout<<"PASS "<<path<<" "<<expect.size()<<" music bytes, peak "<<peak<<"/512, underruns "<<underruns<<"\n";
}
int main(int argc,char**argv){units();for(int i=1;i<argc;i++)replay(argv[i]);}
