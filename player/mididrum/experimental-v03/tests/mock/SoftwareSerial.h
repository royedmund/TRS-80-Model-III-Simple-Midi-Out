#pragma once
#include <cstdint>
#include <cstddef>
using std::size_t;
#include <deque>
#include <vector>
using std::uint8_t;using std::uint16_t;using std::uint32_t;using std::int32_t;
constexpr int LED_BUILTIN=13,OUTPUT=1,HIGH=1,LOW=0,SERIAL_8N1=6;
inline uint32_t fakeClock=0,microsCalls=0;inline bool led=false;
inline uint32_t micros(){++microsCalls;return fakeClock;}
inline void pinMode(int,int){} inline void digitalWrite(int,int v){led=v;}
struct HardwareSerialMock{
    int freeSlots=63;std::vector<uint8_t> bytes;
    void begin(unsigned long,int){} int availableForWrite(){return freeSlots;}
    size_t write(uint8_t b){bytes.push_back(b);--freeSlots;return 1;}
} inline Serial;
class SoftwareSerial{
 public:std::deque<uint8_t> input;bool over=false;
 SoftwareSerial(int,int){}void begin(unsigned long){}int available(){return input.size();}
 int read(){if(input.empty())return -1;int a=input.front();input.pop_front();return a;}
 bool overflow(){bool b=over;over=false;return b;}
};
