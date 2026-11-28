#pragma once
#include <stdint.h>
#include <deque>
#include <vector>
#define LOW 0
#define HIGH 1
#define INPUT_PULLUP 2
#define OUTPUT 1
#define LED_BUILTIN 13
inline uint32_t clockus=0;inline int gate=LOW;
inline uint32_t micros(){return clockus;}inline int digitalRead(int){return gate;}inline void digitalWrite(int,int){}inline void pinMode(int,int){}
struct Port{std::deque<uint8_t> rx;std::vector<uint8_t> tx;void begin(int){}int available(){return rx.size();}int read(){if(rx.empty())return -1;int b=rx.front();rx.pop_front();return b;}int availableForWrite(){return 64;}void write(uint8_t b){tx.push_back(b);}};
inline Port Serial;using AltSoftSerial=Port;
