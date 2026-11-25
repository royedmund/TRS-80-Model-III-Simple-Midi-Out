#pragma once
#include <stdint.h>
#include <deque>
#include <vector>
#include <cassert>
#define SERIAL_8N1 0x06
#define LED_BUILTIN 13
#define HIGH 1
#define LOW 0
#define OUTPUT 1
extern uint32_t clock_us;
extern bool led;
inline uint32_t micros(){return clock_us;}
inline void pinMode(int,int){}
inline void digitalWrite(int,int value){led=value;}
struct MockSerial { std::vector<uint8_t> out; bool ready=true;
 void begin(unsigned long b,int cfg){assert(b==31250 && cfg==SERIAL_8N1);}
 int availableForWrite(){return ready?63:0;}
 void write(uint8_t b){out.push_back(b);}
};
extern MockSerial Serial;
struct SoftwareSerial { std::deque<int> input; bool over=false;
 SoftwareSerial(int rx,int tx){assert(rx==10 && tx==11);}
 void begin(unsigned long b){assert(b==9600);}
 bool overflow(){bool b=over;over=false;return b;}
 int available(){return int(input.size());}
 int read(){if(input.empty())return -1;int v=input.front();input.pop_front();return v;}
};
