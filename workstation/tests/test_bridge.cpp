#include <cassert>
#include <iostream>
#include "../firmware/MIDIWORK/MIDIWORK.ino"
int main(){setup();for(auto b:{0x90,60,90,0xf8,64,91,60,0,0xc1,6,0xf0,1,2,0xf7,0xfa})inputByte(b);while(ic){clockus+=1050;inputService(clockus);}assert((host.tx==std::vector<uint8_t>{0x90,60,90,0x90,64,91,0x90,60,0,0xc1,6,0,0xfa,0,0}));std::cout<<"PASS input running status, realtime, SysEx filtering, program padding\n";
 host.tx.clear();for(int i=0;i<65;i++)frame(0x90,60,1);while(ic||lost){clockus+=1050;inputService(clockus);}assert(host.tx.size()==195);assert(host.tx[192]==0xf4);std::cout<<"PASS whole frame overflow and marker\n";
 for(auto b:{0x90,60,99,64,88})receive(b,clockus);while(count)service(clockus);assert((Serial.tx==std::vector<uint8_t>{0x90,60,99,64,88}));receive(0xfc,clockus);while(panic)service(clockus);assert(!held[0][7]&&!held[0][8]);std::cout<<"PASS raw output running status and panic\n";
 Serial.tx.clear();receive(0xfd,clockus);for(auto b:{0x90,67,90,0xf8,0x80,67,0,0xfa})receive(b,clockus);service(clockus);assert(Serial.tx.empty());clockus+=160000;for(int i=0;i<4;i++)service(clockus);assert((Serial.tx==std::vector<uint8_t>{0x90,67,90}));clockus+=40200;for(int i=0;i<50;i++)service(clockus);assert(state==RAW&&!panic);std::cout<<"PASS buffered lead, tick, drain\n";
}
