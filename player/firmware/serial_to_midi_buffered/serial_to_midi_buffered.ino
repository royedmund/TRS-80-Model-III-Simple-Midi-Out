/* TRS-80 MIDI bridge v0.8 - optional timed playback.
 * Classic Nano 5V ATmega328P, D10 RX at 9600; D1 TX at 31250.
 * D11 unused. Disconnect MIDI during upload/reset. No wiring changes.
 * Raw MIDIPLAY 2/3 works for channel data and complete EMT-10 SysEx.
 * Buffered MIDIPLAY 4/5 reserves F8, F9, FA, FC, FD as transport tokens.
 * This is NOT a general purpose raw MIDI real-time bridge.
 */
#include <SoftwareSerial.h>
SoftwareSerial trs(10, 11);
constexpr uint32_t LEAD_US=160000UL, WATCHDOG_US=2000000UL;
constexpr uint8_t CAP=192;
// Parallel arrays avoid padding; exactly 960 bytes of static queue storage.
uint32_t deadlines[CAP];
uint8_t data[CAP], head=0, tail=0, count=0;
uint32_t deadline=0, period=40000, lastInput=0;
enum State : uint8_t { RAW, STREAM, DRAIN, FAULT };
State state=RAW;
uint8_t panicIndex=192;
bool inSysex=false, terminateSysex=false;

bool due(uint32_t now,uint32_t then) { return (int32_t)(now-then)>=0; }
uint8_t advance(uint8_t n) { return n+1==CAP?0:n+1; }
void clearQueue() { head=tail=count=0; }
void requestPanic() {
  clearQueue();
  terminateSysex=inSysex;
  panicIndex=0;
}
void fail() { requestPanic(); state=FAULT; digitalWrite(LED_BUILTIN,HIGH); }
void beginStream(uint8_t token,uint32_t now) {
  if(state!=RAW || count || inSysex) requestPanic();
  clearQueue();
  state=STREAM; period=token==0xfd?40000UL:33333UL;
  deadline=now+LEAD_US; lastInput=now;
  digitalWrite(LED_BUILTIN,LOW);
}
void put(uint8_t b,uint32_t when) {
  if(count==CAP) { fail(); return; }
  data[head]=b; deadlines[head]=when; head=advance(head); ++count;
}
void receiveByte(uint8_t b,uint32_t now) {
  if(b==0xfd || b==0xf9) { beginStream(b,now); return; }
  if(b==0xfc) { requestPanic(); state=RAW; return; }
  if(state==FAULT) return; // resynchronise only on next START
  if(state==STREAM) {
    lastInput=now;
    if(b==0xf8) {
      deadline+=period;
      // Gentle clock discipline: max 100 us per tick, not per-byte
      // rescheduling. An occasional late tick is absorbed by the lead.
      int32_t error=(int32_t)((now+LEAD_US)-deadline);
      if(error>100) error=100;
      if(error< -100) error=-100;
      deadline+=error;
      return;
    }
    if(b==0xfa) { state=DRAIN; return; }
    put(b,deadline); return;
  }
  if(state==DRAIN) return; // only new START or STOP can interrupt drain
  // Unbuffered compatibility: immediate FIFO, no artificial delay.
  if(b==0xf8 || b==0xfa) return;
  put(b,now);
}
void sendByte(uint8_t b) {
  Serial.write(b);
  if(b==0xf0) inSysex=true;
  else if(b==0xf7 || (b>=0x80 && b<0xf0)) inSysex=false;
}
void serviceOutput(uint32_t now) {
  // Keep hardware backlog small so STOP is responsive. AVR TX ring
  // has 63 usable slots; at most 8 bytes are queued here.
  if(Serial.availableForWrite()<56) return;
  if(terminateSysex) { sendByte(0xf7); terminateSysex=false; return; }
  if(panicIndex<192) {
    static const uint8_t cc[]={64,66,67,123};
    uint8_t i=panicIndex++;
    uint8_t k=i%12;
    sendByte(k%3==0?0xb0+i/12:k%3==1?cc[k/3]:0);
    return;
  }
  if(count && due(now,deadlines[tail])) {
    sendByte(data[tail]); tail=advance(tail); --count;
  } else if(!count && state==DRAIN) {
    requestPanic(); state=RAW;
  }
}
void setup() {
  pinMode(LED_BUILTIN,OUTPUT); digitalWrite(LED_BUILTIN,LOW);
  Serial.begin(31250,SERIAL_8N1); trs.begin(9600);
}
void loop() {
  if(trs.overflow()) fail();
  while(trs.available()) {
    int v=trs.read(); if(v>=0) receiveByte((uint8_t)v,micros());
    serviceOutput(micros());
  }
  uint32_t now=micros();
  if(state==STREAM && due(now,lastInput+WATCHDOG_US)) fail();
  serviceOutput(now);
}
