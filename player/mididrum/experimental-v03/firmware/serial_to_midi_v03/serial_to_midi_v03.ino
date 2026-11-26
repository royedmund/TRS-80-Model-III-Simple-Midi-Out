/* TRS-80 MIDI bridge v0.3 hybrid performance build (based on v0.8 timed bridge).
 * Classic Nano ATmega328P 16 MHz. MAX3232 -> D10, D1 -> MIDI out.
 * Raw MIDIDRUM modes 2/3/6/7/8/9: direct fast path, no artificial delay.
 * Timed modes 4/5: original F9/FD START, F8 TICK, FA END, FC STOP protocol.
 * No rewiring. Not a general-purpose MIDI realtime bridge; tokens reserved.
 * Disconnect MIDI during upload/reset. Keep original firmware as fallback.
 */
#include <SoftwareSerial.h>
SoftwareSerial trs(10,11);
constexpr uint32_t LEAD_US=160000UL, WATCHDOG_US=2000000UL;
constexpr uint8_t CAP=192, OUTPUT_BUDGET=8, INPUT_BUDGET=16;
uint32_t deadlines[CAP];
uint8_t data[CAP],head=0,tail=0,count=0;
uint32_t deadline=0,period=40000,lastInput=0;
enum State:uint8_t {RAW,STREAM,DRAIN,FAULT};
State state=RAW;
uint8_t panicIndex=192;
bool inSysex=false,terminateSysex=false;
// Saturating diagnostic counters (inspect via debugger; no serial logging on MIDI).
uint16_t rxOverflows=0,queueOverflows=0;
uint8_t peakQueue=0;
bool due(uint32_t now,uint32_t then){return (int32_t)(now-then)>=0;}
uint8_t advance(uint8_t n){return n+1==CAP?0:n+1;}
void clearQueue(){head=tail=count=0;}
void requestPanic(){clearQueue();terminateSysex=inSysex;panicIndex=0;}
void fail(){requestPanic();state=FAULT;digitalWrite(LED_BUILTIN,HIGH);}
void beginStream(uint8_t token,uint32_t now){
  if(state!=RAW||count||inSysex)requestPanic();
  clearQueue();state=STREAM;period=token==0xfd?40000UL:33333UL;
  deadline=now+LEAD_US;lastInput=now;digitalWrite(LED_BUILTIN,LOW);
}
void put(uint8_t b,uint32_t when){
  if(count==CAP){if(queueOverflows!=65535)++queueOverflows;fail();return;}
  data[head]=b;deadlines[head]=when;head=advance(head);++count;
  if(count>peakQueue)peakQueue=count;
}
void sendByte(uint8_t b){
  Serial.write(b);
  if(b==0xf0)inSysex=true;
  else if(b==0xf7||(b>=0x80&&b<0xf0))inSysex=false;
}
// In ordinary raw playback, no queueing, no timestamp calculation. Preserve
// ordering by taking the direct path only when all deferred output is empty.
bool tryRaw(uint8_t b){
  if(state!=RAW||count||panicIndex<192||terminateSysex||b==0xfd||b==0xf9||b==0xfc)return false;
  if(b==0xf8||b==0xfa)return true; // original reserved-token behavior
  if(Serial.availableForWrite()<56)return false;
  sendByte(b);return true;
}
void receiveByte(uint8_t b,uint32_t now){
  if(b==0xfd||b==0xf9){beginStream(b,now);return;}
  if(b==0xfc){requestPanic();state=RAW;return;}
  if(state==FAULT)return;
  if(state==STREAM){
    lastInput=now;
    if(b==0xf8){
      deadline+=period;
      int32_t error=(int32_t)((now+LEAD_US)-deadline);
      if(error>100)error=100;
      if(error< -100)error=-100;
      deadline+=error;return;
    }
    if(b==0xfa){state=DRAIN;return;}
    put(b,deadline);return;
  }
  if(state==DRAIN)return;
  if(b==0xf8||b==0xfa)return;
  put(b,now);
}
bool pending(){return terminateSysex||panicIndex<192||count||state==DRAIN;}
// Batch only bytes already due. Preserve the original small TX backlog
// (8 bytes in the 64-byte hardware ring) for responsive STOP handling.
void serviceOutput(uint32_t now){
  for(uint8_t budget=OUTPUT_BUDGET;budget;--budget){
    if(Serial.availableForWrite()<56)return;
    if(terminateSysex){sendByte(0xf7);terminateSysex=false;continue;}
    if(panicIndex<192){
      static const uint8_t cc[]={64,66,67,123};
      uint8_t i=panicIndex++,k=i%12;
      sendByte(k%3==0?0xb0+i/12:k%3==1?cc[k/3]:0);continue;
    }
    if(count&&due(now,deadlines[tail])){sendByte(data[tail]);tail=advance(tail);--count;continue;}
    if(!count&&state==DRAIN){requestPanic();state=RAW;continue;}
    return;
  }
}
void setup(){pinMode(LED_BUILTIN,OUTPUT);digitalWrite(LED_BUILTIN,LOW);Serial.begin(31250,SERIAL_8N1);trs.begin(9600);}
void loop(){
  if(trs.overflow()){if(rxOverflows!=65535)++rxOverflows;fail();}
  for(uint8_t budget=INPUT_BUDGET;budget&&trs.available();--budget){
    int v=trs.read();if(v<0)break;
    if(tryRaw((uint8_t)v))continue;
    uint32_t now=micros();receiveByte((uint8_t)v,now);
    if(pending())serviceOutput(now);
  }
  // Do not call micros() at all on the usual idle raw path.
  if(state==STREAM||pending()){
    uint32_t now=micros();
    if(state==STREAM&&due(now,lastInput+WATCHDOG_US))fail();
    if(pending())serviceOutput(now);
  }
}
