#include <cassert>
#include <algorithm>
#include <iostream>
#include <vector>
#include <fstream>
#include <iterator>
#include "../firmware/MIDICLOCK/MIDICLOCK.ino"
void reset(){state=RAW;clearQueue();used=0;txStatus=txPos=0;panic=sx=terminateSx=false;clockStop=false;cancelClock();clockStop=false;clockProtocol=false;resetDecoder();for(auto &r:held)for(auto &v:r)v=0;Serial.tx.clear();Serial.trace.clear();Serial.ready=true;host.rx.clear();clockus=0;setup();}
void pump(uint32_t t){clockus=t;for(int i=0;i<32;i++)service(t);}
void send(std::initializer_list<uint8_t> bytes,uint32_t t=0){clockus=t;for(auto b:bytes)receive(b,t);}
void tempo(uint32_t us,uint32_t t=0){receive(0xf1,t);for(int i=20;i>=0;i-=4)receive((us>>i)&15,t);}
std::vector<uint32_t> pulses(){std::vector<uint32_t> x;for(auto p:Serial.trace)if(p.second==0xf8)x.push_back(p.first);return x;}
void run(uint32_t a,uint32_t b){for(uint32_t t=a;t<b;t+=100)pump(t);}
void frame(std::initializer_list<uint8_t> data,bool final=false,uint32_t t=0){receive(final?0xf3:0xf2,t);receive(data.size(),t);for(auto b:data)receive(b,t);}
void demoReplay(int rate){
 reset();std::ifstream f(std::string("tests/demo")+std::to_string(rate)+".wire",std::ios::binary);std::vector<uint8_t> v{std::istreambuf_iterator<char>(f),{}};assert(v.size()>2);std::vector<std::pair<uint32_t,uint8_t>> in;std::vector<uint8_t> expected;
 uint32_t next=0,tick=0;auto add=[&](uint8_t b){in.push_back({next,b});next+=1042;};add(v[0]);add(v[1]);size_t i=2;
 while(i<v.size()){
  uint8_t tag=v[i++];add(tag);if(tag==0xf1){for(int n=0;n<6;n++)add(v[i++]);continue;}
  assert(tag==0xf2||tag==0xf3);uint8_t n=v[i++];add(n);while(n--){expected.push_back(v[i]);add(v[i++]);}if(tag==0xf2){++tick;next=std::max(next,uint32_t(uint64_t(tick)*1000000/rate));}
 }
 size_t k=0;for(uint32_t t=0;t<next+700000;t+=100){clockus=t;while(k<in.size()&&in[k].first<=t){receive(in[k].second,t);++k;}for(int j=0;j<8;j++)service(t);assert(state!=FAULT);}
 std::vector<uint8_t> music;for(auto b:Serial.tx)if(b<0xf8)music.push_back(b);assert(k==in.size()&&state==RAW&&!panic&&music.size()>=expected.size()&&std::equal(expected.begin(),expected.end(),music.begin()));auto p=pulses();assert(p.size()==193&&Serial.tx[0]==0xfa&&std::count(Serial.tx.begin(),Serial.tx.end(),0xfc)==1);std::cout<<"PASS complete assembled CLOCKTST stream, "<<rate<<"Hz, "<<expected.size()<<" music bytes, "<<p.size()<<" clock pulses\n";
}
void framedTests(){
 for(int rate:{25,30}){
  reset();send({0xf6,uint8_t(rate)});tempo(500000);frame({0x90,60,100});for(int i=1;i<rate;i++)frame({});tempo(1000000);for(int i=0;i<rate;i++)frame({});frame({0x80,60,0},true);run(0,2400000);auto p=pulses();assert(state==RAW&&p.size()==73&&Serial.tx[0]==0xfa);for(size_t i=50;i<p.size();i++)assert(p[i]-p[i-1]>41000&&p[i]-p[i-1]<42500);std::vector<uint8_t> musical;for(auto b:Serial.tx)if(b<0xf8)musical.push_back(b);assert(musical.size()>=6&&std::equal(musical.begin(),musical.begin()+6,std::vector<uint8_t>{0x90,60,100,0x80,60,0}.begin()));assert(std::find(Serial.tx.begin(),Serial.tx.end(),0xf1)==Serial.tx.end());std::cout<<"PASS framed "<<rate<<"Hz tempo transition, 73 pulses and unchanged music\n";
  reset();std::ifstream f(std::string("tests/host")+std::to_string(rate)+".wire",std::ios::binary);std::vector<uint8_t> v{std::istreambuf_iterator<char>(f),{}};assert(!v.empty());uint32_t t=0;for(auto b:v){run(t,t+1000);t+=1042;clockus=t;receive(b,t);}run(t,600000);musical.clear();for(auto b:Serial.tx)if(b<0xf8)musical.push_back(b);std::vector<uint8_t> expect={0x90,60,100,0x90,64,90,0x80,60,0,0x80,64,0};assert(state==RAW&&musical.size()>=expect.size()&&std::equal(expect.begin(),expect.end(),musical.begin()));std::cout<<"PASS actual assembled Z80 wire fixture at 9600 baud, "<<rate<<"Hz\n";
 }
 reset();send({0xf6,25,0xf2,3,0x90,60});run(0,300000);assert(Serial.tx.empty()&&groups==0);send({100},300000);run(300000,360000);assert(Serial.tx.size()>=5&&Serial.tx[0]==0xfa&&Serial.tx[1]==0xf8);send({0xfc},360000);pump(360000);assert(state==RAW&&!panic);std::cout<<"PASS incomplete group withheld, then released; abort cleans up\n";
 reset();send({0xf6,25,0xf2,3,0x90,60,0xf8});assert(state==FAULT);pump(0);assert(pulses().empty());std::cout<<"PASS illegal payload/control collision rejected\n";
 reset();send({0xf6,25,0xf2,128});assert(state==FAULT);std::cout<<"PASS illegal length rejected\n";
 reset();send({0xf6,25,0xf1,0,7,0xf2});assert(state==FAULT);std::cout<<"PASS incomplete tempo rejected\n";
 reset();send({0xf6,25,0xf2,127});for(int i=0;i<127;i++)receive(1,0);assert(groups==1&&count==128);for(int k=0;k<3;k++){send({0xf2,127});for(int i=0;i<127;i++)receive(1,0);}assert(count==512&&groups==4);send({0xf2,0});assert(state==FAULT);std::cout<<"PASS max frame length and FIFO overflow fail closed\n";
 reset();send({0xf6,25,0xf2,3,0x90});clockus=2100000;loop();assert(state==FAULT);std::cout<<"PASS incomplete frame watchdog\n";
 reset();send({0xf6});clockus=2100000;loop();assert(state==FAULT);std::cout<<"PASS incomplete start watchdog\n";
 reset();send({0xf6,25,0xf2,3,0x90});send({0xfc});pump(0);assert(state==RAW&&pulses().empty());send({0xf6,30});frame({0x90,60,100});frame({0x80,60,0},true);run(0,400000);assert(state==RAW&&pulses().size()>0);std::cout<<"PASS partial frame abort and new session\n";
}
int main(){
 framedTests();demoReplay(25);demoReplay(30);
 reset();send({0x90,60,100,0x80,60,0});pump(0);assert((Serial.tx==std::vector<uint8_t>{0x90,60,100,0x80,60,0}));std::cout<<"PASS raw note stream unchanged\n";
 for(auto mode:{0xfd,0xf9}){reset();send({uint8_t(mode),0x90,60,100,0xf8,0x80,60,0,0xfa});run(0,400000);assert(Serial.tx[0]==0x90&&pulses().empty()&&state==RAW);}
 std::cout<<"PASS legacy buffered playback emits no clock\n";
 for(auto mode:{0xf5,0xf4}){reset();send({uint8_t(mode)});tempo(500000);send({0x90,60,100});for(int i=0;i<(mode==0xf5?25:30);i++)send({0xf8});send({0x80,60,0,0xfa});run(0,1400000);auto p=pulses();assert(Serial.tx[0]==0xfa&&Serial.tx[1]==0xf8&&p.size()==49&&state==RAW);assert(std::count(Serial.tx.begin(),Serial.tx.end(),0xfc)==1);for(size_t i=1;i<p.size();i++){auto dt=p[i]-p[i-1];assert(dt>20500&&dt<21200);}std::cout<<"PASS "<<(mode==0xf5?25:30)<<"Hz: 49 pulses including beat-zero; 48 intervals at 120 BPM\n";}
 reset();send({0xf5});tempo(500000);send({0x90,60,100});for(int i=0;i<25;i++)send({0xf8});tempo(1000000);for(int i=0;i<25;i++)send({0xf8});send({0x80,60,0,0xfa});run(0,2400000);auto p=pulses();assert(p.size()==73);for(size_t i=50;i<p.size();i++)assert(p[i]-p[i-1]>41000&&p[i]-p[i-1]<42500);assert(std::find(Serial.tx.begin(),Serial.tx.end(),0xf1)==Serial.tx.end());std::cout<<"PASS queued 120 to 60 BPM tempo change; private bytes not forwarded\n";
 reset();send({0xf5,0x90,60,100,0xf8});run(0,400000);assert(waiting);auto n=pulses().size();run(400000,700000);assert(pulses().size()==n);send({0xf8},700000);run(700000,750000);assert(pulses().size()>n);send({0xfc},750000);pump(750000);assert(state==RAW&&std::count(Serial.tx.begin(),Serial.tx.end(),0xfc)==1&&!panic);std::cout<<"PASS underrun holds phase; STOP and note cleanup\n";
 reset();send({0xf5,0xf1,0x01,0xf8});pump(1000);assert(state==FAULT&&pulses().empty());std::cout<<"PASS malformed tempo rejected\n";
 reset();send({0xf5,0x90,60,100,0xf8});Serial.ready=false;run(0,180000);assert(Serial.tx.empty());Serial.ready=true;pump(180000);run(180100,250000);assert(Serial.tx[0]==0xfa&&Serial.tx[1]==0xf8);std::cout<<"PASS blocked UART preserves start order\n";
 reset();send({0xf5,0x90,60,100,0xf8});run(0,300000);clockus=2100000;loop();pump(clockus);assert(state==FAULT&&std::count(Serial.tx.begin(),Serial.tx.end(),0xfc)==1);std::cout<<"PASS watchdog stops clock\n";
 reset();uint32_t base=0xffff0000;send({0xf4,0xf8,0xfa},base);for(uint32_t i=0;i<300000;i+=100)pump(base+i);assert(pulses().size()==2&&state==RAW);std::cout<<"PASS micros rollover\n";
#if BIDIRECTIONAL
 reset();inputByte(0x90);inputByte(60);inputByte(100);inputByte(0xf8);inputByte(64);inputByte(90);for(int i=0;i<6;i++)inputService(i*1050);assert((host.tx==std::vector<uint8_t>{0x90,60,100,0x90,64,90}));std::cout<<"PASS bidirectional input frames; incoming F8 filtered\n";
#endif
}
