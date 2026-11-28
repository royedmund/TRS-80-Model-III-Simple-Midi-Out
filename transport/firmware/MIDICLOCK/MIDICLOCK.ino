/* MIDICLOCK v0.2 -- output-only structured serial transport.
 * Classic 5V Nano: D10 receives 9600 8N1 from MAX3232; D1 MIDI OUT 31250.
 * F6 + 19/1E starts 25/30Hz framed playback. F1 + 6 nibbles = tempo.
 * F2 + count + MIDI payload = one timing interval; F3 = last frame.
 * FC immediate abort. Legacy v0.3 FD/F9 playback remains clock-free.
 * No MIDI IN or external clock slave support. See PROTOCOL.md.
 */
#include <SoftwareSerial.h>
SoftwareSerial host(10,11);
constexpr uint16_t CAP=512, MASK=CAP-1;
uint8_t q[CAP], held[16][16];
uint16_t head=0,tail=0,count=0,groups=0,used=0;
uint32_t deadline=0,lastInput=0,period=40000;
uint8_t frac=0,txStatus=0,txFirst=0,txPos=0;
bool sx=false,terminateSx=false,waiting=false,panic=false;
enum State:uint8_t {RAW,STREAM,DRAIN,FAULT}; State state=RAW;
uint8_t panicCh=0,panicCC=0,panicByte=0,panicData=0;
uint16_t panicNote=0;
static bool due(uint32_t a,uint32_t b){return int32_t(a-b)>=0;}
// Clock phase is measured in units of 1/24 microsecond modulo the tempo.
// Each LDOS interval advances nominal time but is stretched to the actual
// scheduler deadline (including slew). No clock pulses during rebuffering.
static bool clockProtocol=false;
static bool clockMode=false, clockArmed=false, clockRunning=false, clockStop=false;
static uint8_t tempoBytes=0;
// Framed wire decoder: a group is not eligible for playback until every
// advertised data byte is received. FIFO retains the existing compact
// internal token representation; wire tags never reach the DIN output.
static bool framed=false, startPending=false, lengthPending=false, finalFrame=false;
static uint8_t frameRemaining=0;
static void resetDecoder(){framed=startPending=lengthPending=finalFrame=false;frameRemaining=0;tempoBytes=0;}
static uint32_t clockTempo=500000, clockPhase=0, pulseNumerator=0;
static uint32_t intervalStart=0, intervalLength=0, intervalNominal=0, pulseAt=0;
static void cancelClock(){
 if(clockArmed)clockStop=true;
 clockMode=clockArmed=clockRunning=false;intervalNominal=0;tempoBytes=0;
}
static void setTempo(uint32_t t){
 // Outside a practical 10–600 BPM range, disable clock only, keep music.
 if(t<100000UL||t>6000000UL){cancelClock();return;}
 clockPhase=uint32_t(uint64_t(clockPhase)*t/clockTempo);
 clockTempo=t;
}
static void schedulePulse(){
 // 24-unit phase -> microseconds, then map onto actual slewed interval.
 uint32_t u=(pulseNumerator+23)/24;
 pulseAt=intervalStart+(u*intervalLength+intervalNominal-1)/intervalNominal;
}
static void clockInterval(uint32_t begin,uint32_t end,uint32_t nominal){
 if(!clockRunning)return;
 intervalStart=begin;intervalLength=end-begin;intervalNominal=nominal;
 pulseNumerator=clockTempo-clockPhase;
 clockPhase=(clockPhase+nominal*24UL)%clockTempo;
 if(pulseNumerator<=nominal*24UL)schedulePulse();
}
static bool serviceClock(uint32_t now){
 if(clockStop){Serial.write(0xfc);clockStop=false;return true;}
 if(!clockRunning||!intervalNominal||pulseNumerator>intervalNominal*24UL)return false;
 if(!due(now,pulseAt))return false;
 Serial.write(0xf8);pulseNumerator+=clockTempo;
 if(pulseNumerator<=intervalNominal*24UL)schedulePulse();
 return true;
}
static void clearQueue(){head=tail=count=groups=0;waiting=false;}
static void requestPanic(){resetDecoder();cancelClock();clearQueue();terminateSx|=sx;txStatus=txPos=0;panic=true;panicCh=panicCC=panicByte=0;panicNote=0;}
static void fail(){requestPanic();state=FAULT;}
static void start(uint8_t b,uint32_t now){
 if(state!=RAW||count||used||sx||panic)requestPanic();else clearQueue();
 resetDecoder();
 clockMode=clockProtocol=(b==0xf5||b==0xf4);clockArmed=clockRunning=false;clockPhase=0;clockTempo=500000;intervalNominal=0;tempoBytes=0;
 period=(b==0xfd||b==0xf5)?40000UL:33333UL;frac=0;deadline=now+160000UL;lastInput=now;state=STREAM;
}
static void put(uint8_t b){if(count==CAP){fail();return;}q[head]=b;head=(head+1)&MASK;++count;}
static void commitFrame(){
 put(finalFrame?0xfa:0xf8);if(state==FAULT)return;
 ++groups;if(finalFrame)state=DRAIN;
}
static void receive(uint8_t b,uint32_t now){
 // Explicit abort works even in the middle of a record. Reserved F6
 // cannot occur in supported MIDI payloads or tempo/length fields.
 if(b==0xfc){requestPanic();state=RAW;return;}
 if(b==0xf6){startPending=true;lastInput=now;return;}
 if(startPending){
  startPending=false;if(b!=25&&b!=30){fail();return;}
  start(b==25?0xf5:0xf4,now);framed=true;return;
 }
 if(framed){
  if(state==FAULT||state==DRAIN)return;
  lastInput=now;
  if(tempoBytes){if(b>15){fail();return;}put(b);if(state!=FAULT)--tempoBytes;return;}
  if(lengthPending){
   lengthPending=false;if(b>127){fail();return;}
   frameRemaining=b;if(!b)commitFrame();return;
  }
  if(frameRemaining){
   if(b>=0xf1&&b!=0xf7){fail();return;}
   put(b);if(state!=FAULT&&!--frameRemaining)commitFrame();return;
  }
  if(b==0xf1){tempoBytes=6;put(b);return;}
  if(b==0xf2||b==0xf3){finalFrame=b==0xf3;lengthPending=true;return;}
  fail();return;
 }
 // Legacy raw and v0.3 tick-delimited playback, plus v0.1 clock mode.
 if(b==0xfd||b==0xf9||b==0xf5||b==0xf4){start(b,now);return;}
 if(state==FAULT||state==DRAIN)return;
 if(state==STREAM){
  lastInput=now;
  if(clockProtocol){
   if(tempoBytes){if(b>15){fail();return;}--tempoBytes;}
   else if(b==0xf1)tempoBytes=6;
  }
  put(b);if(state==FAULT)return;
  if(b==0xf8||b==0xfa)++groups;if(b==0xfa)state=DRAIN;
 }
 else if(b!=0xf8&&b!=0xfa)put(b);
}
static void sendMusic(uint8_t b){
 Serial.write(b);if(b>=0xf8)return;
 if(b&128){if(b==0xf0){sx=true;txStatus=txPos=0;return;}sx=false;txPos=0;if(b>=0xf0){txStatus=0;return;}txStatus=b;used|=uint16_t(1)<<(b&15);return;}
 if(!txStatus||sx||(txStatus&0xe0)==0xc0)return;
 if(!txPos){txFirst=b;txPos=1;return;}txPos=0;
 uint8_t type=txStatus&0xf0;if(type!=0x80&&type!=0x90)return;
 uint8_t &v=held[txStatus&15][txFirst>>3],mask=uint8_t(1<<(txFirst&7));if(type==0x90&&b)v|=mask;else v&=uint8_t(~mask);
}
static void servicePanic(){
 if(terminateSx){Serial.write(0xf7);sx=terminateSx=false;return;}
 if(panicByte){Serial.write(panicByte==1?panicData:0);if(++panicByte==3)panicByte=0;return;}
 while(panicCh<16&&!((used|1)&(uint16_t(1)<<panicCh)))++panicCh;
 if(panicCh==16){panic=false;used=0;txStatus=txPos=0;return;}
 uint8_t s;
 if(panicCC<3){static const uint8_t cc[]={64,66,67};s=0xb0+panicCh;panicData=cc[panicCC++];}
 else if(panicCC==3){while(panicNote<128&&!(held[panicCh][panicNote>>3]&(1<<(panicNote&7))))++panicNote;if(panicNote==128){++panicCC;return;}s=0x80+panicCh;panicData=panicNote++;}
 else if(panicCC==4){s=0xb0+panicCh;panicData=123;++panicCC;}
 else{for(uint8_t i=0;i<16;++i)held[panicCh][i]=0;++panicCh;panicCC=0;panicNote=0;return;}
 Serial.write(s);panicByte=1;
}
static void service(uint32_t now){
 if(Serial.availableForWrite()<56)return;
 if(serviceClock(now))return;
 if(panic||terminateSx){servicePanic();return;}
 if(state==FAULT)return;
 if(state!=RAW){
  if(clockMode&&!clockArmed&&groups&&due(now,deadline-2000UL)){
   if(due(now,deadline-1000UL))deadline=now+2000UL;
   clockArmed=true;waiting=false;Serial.write(0xfa);return;
  }
  if(!due(now,deadline))return;
  if(!groups){waiting=true;return;}
  if(waiting){deadline=now;waiting=false;}
  if(clockMode&&!clockRunning){clockRunning=true;Serial.write(0xf8);return;}
 }
 if(!count)return;
 uint8_t b=q[tail];tail=(tail+1)&MASK;--count;
 if(state!=RAW&&clockProtocol&&b==0xf1){
  if(count<6){fail();return;}
  uint32_t t=0;for(uint8_t i=0;i<6;++i){uint8_t n=q[tail];tail=(tail+1)&MASK;--count;if(n>15){fail();return;}t=(t<<4)|n;}
  if(clockMode)setTempo(t);return;
 }
 if(state!=RAW&&b==0xf8){
  --groups;uint32_t begin=deadline, nominal=period;
  if(period==33333UL&&++frac==3){++nominal;frac=0;}
  deadline+=nominal;uint8_t high=period==40000UL?5:6;
  if(groups>high)deadline-=200;else if(groups<2)deadline+=200;
  clockInterval(begin,deadline,nominal);return;
 }
 if(state!=RAW&&b==0xfa){--groups;requestPanic();state=RAW;return;}sendMusic(b);
}
void setup(){pinMode(LED_BUILTIN,OUTPUT);Serial.begin(31250);host.begin(9600);}
void loop(){
 if(host.overflow())fail();
 for(uint8_t i=0;i<16&&host.available();++i){int b=host.read();if(b>=0)receive(uint8_t(b),micros());service(micros());}
 uint32_t now=micros();if((state==STREAM||startPending)&&due(now,lastInput+2000000UL))fail();
 for(uint8_t i=0;i<8;++i)service(now);
 digitalWrite(LED_BUILTIN,state==FAULT?HIGH:((state==STREAM||state==DRAIN)?((now>>18)&1):LOW));
}
