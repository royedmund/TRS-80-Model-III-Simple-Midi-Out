// Host simulation of the output-only MIDICLOCK v0.2 decoder.
// Replay actual assembled player wire fixtures paced at 9600 baud, without
// publishing third-party music. Mocked TX is not electrical/AVR timing.
#include <cassert>
#include <iostream>
#include <fstream>
#include <iterator>
#include <vector>
#include <algorithm>
#include "MIDICLOCK.ino"
void replay(const char* path){
 state=RAW;clearQueue();used=0;txStatus=txPos=0;panic=sx=terminateSx=false;clockStop=false;cancelClock();clockStop=false;clockProtocol=false;resetDecoder();for(auto &r:held)for(auto &v:r)v=0;Serial.tx.clear();Serial.trace.clear();Serial.ready=true;host.rx.clear();clockus=0;setup();
 std::ifstream f(path,std::ios::binary);std::vector<uint8_t> v{std::istreambuf_iterator<char>(f),{}};assert(v.size()>2&&v[0]==0xf6);
 unsigned rate=v[1],tick=0;uint32_t next=0;std::vector<std::pair<uint32_t,uint8_t>> in;std::vector<uint8_t> expect;
 auto add=[&](uint8_t b){in.push_back({next,b});next+=1042;};add(v[0]);add(v[1]);size_t i=2;
 while(i<v.size()){uint8_t tag=v[i++];add(tag);if(tag==0xf1){for(int n=0;n<6;n++)add(v[i++]);continue;}assert(tag==0xf2||tag==0xf3);uint8_t n=v[i++];add(n);while(n--){expect.push_back(v[i]);add(v[i++]);}if(tag==0xf2){++tick;next=std::max(next,uint32_t(uint64_t(tick)*1000000/rate));}}
 size_t k=0;unsigned peak=0;for(uint32_t t=0;t<next+800000;t+=100){clockus=t;while(k<in.size()&&in[k].first<=t){receive(in[k].second,t);++k;peak=std::max(peak,unsigned(count));}for(int j=0;j<8;j++)service(t);assert(state!=FAULT);}
 std::vector<uint8_t> music;for(auto b:Serial.tx)if(b<0xf8)music.push_back(b);assert(k==in.size()&&state==RAW&&!panic&&music.size()>=expect.size()&&std::equal(expect.begin(),expect.end(),music.begin()));assert(Serial.tx[0]==0xfa&&std::count(Serial.tx.begin(),Serial.tx.end(),0xfc)==1);auto clocks=std::count(Serial.tx.begin(),Serial.tx.end(),0xf8);assert(clocks>0);std::cout<<"PASS "<<path<<": "<<expect.size()<<" musical bytes, "<<clocks<<" clocks, FIFO peak "<<peak<<"/512\n";
}
int main(int argc,char**argv){for(int i=1;i<argc;++i)replay(argv[i]);}
