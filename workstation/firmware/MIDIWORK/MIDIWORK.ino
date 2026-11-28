/* TRS-80 MIDIWORK v0.1 experimental bidirectional bridge.
 * Classic 5V ATmega328P Nano. AltSoftSerial RX D8, TX D9 at 9600.
 * Hardware UART D0/D1 at 31250. Isolate USB-UART TX from D0 in use.
 * Host output protocol compatible with fast v0.3: FD/F9 start, F8 tick,
 * FA drain, FC abort. In RAW, ordinary MIDI bytes pass through.
 * Host input: explicit status + two data bytes (zero padding for Cn/Dn
 * and FA/FB/FC). F4 00 00 means input queue overflow / discontinuity.
 * No MIDI THRU: host decides what to do with input. D4 low at reset enables input.
 */
#include <AltSoftSerial.h>
AltSoftSerial host;
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
static void clearQueue(){head=tail=count=groups=0;waiting=false;}
static void requestPanic(){clearQueue();terminateSx|=sx;txStatus=txPos=0;panic=true;panicCh=panicCC=panicByte=0;panicNote=0;}
static void fail(){requestPanic();state=FAULT;}
static void start(uint8_t b,uint32_t now){
 if(state!=RAW||count||used||sx||panic)requestPanic();else clearQueue();
 period=b==0xfd?40000UL:33333UL;frac=0;deadline=now+160000UL;lastInput=now;state=STREAM;
}
static void put(uint8_t b){if(count==CAP){fail();return;}q[head]=b;head=(head+1)&MASK;++count;}
static void receive(uint8_t b,uint32_t now){
 if(b==0xfd||b==0xf9){start(b,now);return;}
 if(b==0xfc){requestPanic();state=RAW;return;}
 if(state==FAULT||state==DRAIN)return;
 if(b==0xf4||b==0xf5){fail();return;}
 if(state==STREAM){lastInput=now;put(b);if(state==FAULT)return;if(b==0xf8||b==0xfa)++groups;if(b==0xfa)state=DRAIN;}
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
 if(panic||terminateSx){servicePanic();return;}
 if(state==FAULT)return;
 if(state!=RAW){if(!due(now,deadline))return;if(!groups){waiting=true;return;}if(waiting){deadline=now;waiting=false;}}
 if(!count)return;
 uint8_t b=q[tail];tail=(tail+1)&MASK;--count;
 if(state!=RAW&&b==0xf8){--groups;deadline+=period;if(period==33333UL&&++frac==3){++deadline;frac=0;}uint8_t high=period==40000UL?5:6;if(groups>high)deadline-=200;else if(groups<2)deadline+=200;return;}
 if(state!=RAW&&b==0xfa){--groups;requestPanic();state=RAW;return;}sendMusic(b);
}
// MIDI IN is normalized into fixed frames, with status always explicit.
// Whole-frame drops only. Real-time clock and active sensing are filtered.
constexpr uint8_t ICAP=192;
uint8_t iq[ICAP],ih=0,it=0,ic=0,rxStatus=0,rxFirst=0,rxPos=0;
bool rxSx=false,lost=false,inputEnabled=false;uint32_t nextHost=0;
static void enqueue(uint8_t b){iq[ih]=b;if(++ih==ICAP)ih=0;++ic;}
static void frame(uint8_t s,uint8_t a,uint8_t b){
 if(lost||ic>ICAP-3){lost=true;return;}enqueue(s);enqueue(a);enqueue(b);
}
static void inputByte(uint8_t b){
 if(b>=0xf8){if(b==0xfa||b==0xfb||b==0xfc)frame(b,0,0);return;}
 if(b&128){rxPos=0;if(b>=0xf0){rxStatus=0;rxSx=b==0xf0;return;}rxSx=false;rxStatus=b;return;}
 if(rxSx||!rxStatus)return;
 if((rxStatus&0xe0)==0xc0){frame(rxStatus,b,0);return;}
 if(!rxPos){rxFirst=b;rxPos=1;return;}rxPos=0;frame(rxStatus,rxFirst,b);
}
static void inputService(uint32_t now){
 // When disabled, consume MIDI so the hardware UART never fills. Reset parser.
 if(!inputEnabled){while(Serial.available())Serial.read();rxStatus=rxPos=0;rxSx=false;return;}
 for(uint8_t i=0;i<16&&Serial.available();++i){int b=Serial.read();if(b>=0)inputByte(uint8_t(b));}
 if(lost&&ic==0){enqueue(0xf4);enqueue(0);enqueue(0);lost=false;}
 // One byte per 1.05 ms prevents AltSoftSerial TX queue from blocking.
 if(ic&&due(now,nextHost)){host.write(iq[it]);if(++it==ICAP)it=0;--ic;nextHost=now+1050UL;}
}
void setup(){pinMode(4,INPUT_PULLUP);inputEnabled=digitalRead(4)==LOW;pinMode(LED_BUILTIN,OUTPUT);Serial.begin(31250);host.begin(9600);nextHost=micros();}
void loop(){
 for(uint8_t i=0;i<16&&host.available();++i){int b=host.read();if(b>=0)receive(uint8_t(b),micros());service(micros());}
 uint32_t now=micros();if(state==STREAM&&due(now,lastInput+2000000UL))fail();
 for(uint8_t i=0;i<8;++i)service(now);
 inputService(micros());digitalWrite(LED_BUILTIN,state==FAULT?HIGH:((state==STREAM||state==DRAIN)?((now>>18)&1):LOW));
}
