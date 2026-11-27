// Restricted host Z80/FreHD simulation; no cycle/AVR/audio modeling.
const fs=require('fs'),path=require('path');
function verify(cmd,sym,demos){
function assert(v,m){if(!v)throw Error(m)}
function eq(a,b){return a.length===b.length&&a.every((v,i)=>v===b[i])}
function cpu(mid,mode,stopAt=-1){
 let m=new Uint8Array(65536),i=0;while(cmd[i]===1){let len=cmd[i+1]||256,addr=cmd[i+2]|cmd[i+3]<<8;m.set(cmd.slice(i+4,i+len+2),addr);i+=len+2}
 let pc=cmd[i+2]|cmd[i+3]<<8,sp=0xf000,r=new Uint8Array(8),z=false,c=false,keys=[49,0,mode.charCodeAt(0)],ki=0,output=[],timeline=[],consoleText="",pos=0,opened=false,port=0x20,size=0,st=0,resp=[],payload=[],status=0x58,dirDone=false,ticks=0,refreshes=0,closed=0;
 m[0x4288]=250;
 const word=a=>m[a]|m[(a+1)&65535]<<8,wr=(a,v)=>{m[a]=v;m[(a+1)&65535]=v>>8},pair=i=>i===3?sp:r[i*2]*256+r[i*2+1],setpair=(i,v)=>{v&=65535;if(i===3)sp=v;else{r[2*i]=v>>8;r[2*i+1]=v}},get=i=>i===6?m[pair(2)]:r[i],set=(i,v)=>{if(i===6)m[pair(2)]=v;else r[i]=v},f=()=>{let a=m[pc];pc=(pc+1)&65535;return a},fw=()=>f()|f()<<8,push=v=>{sp=(sp-2)&65535;wr(sp,v)},pop=()=>{let v=word(sp);sp=(sp+2)&65535;return v},cond=i=>[!z,z,!c,c,false,false,false,false][i];
 function alu(i,v){let a=r[7],x;if(i===0){x=a+v;c=x>255}else if(i===2||i===7){x=a-v;c=x<0}else if(i===4){x=a&v;c=false}else if(i===5){x=a^v;c=false}else if(i===6){x=a|v;c=false}else throw Error("alu "+i);z=(x&255)===0;if(i!==7)r[7]=x}
 function read(p){if(p===0xea)return 64;if(p===0xff)return port;if(p===0xcf)return status;if(p===0xc3)return resp.length&255;if(p===0xc2){assert(resp.length,"empty response");return resp.shift()}throw Error("read "+p)}
 function write(p,v){if(p===0xec){port=v;return}if([0xe8,0xe9,0xea].includes(p))return;if(p===0xeb){output.push(v);timeline.push(ticks);return}if(p===0xc3){size=v||256;return}if(p===0xc4){payload=[];resp=[];status=0x58;st=v;if(v===0)resp=[1,2,3,4,5,6];else if(v===3||v===8){}else if(v===9){if(dirDone)status=0x50;else{dirDone=true;resp=[mid.length&255,mid.length>>8&255,mid.length>>16&255,mid.length>>24,0,0,0,0,32,...Array.from("TEST.MID",x=>x.charCodeAt(0)),0,0,0,0,0]}}else if(v===4){assert(opened,"read unopened");resp=mid.slice(pos,pos+size);pos+=resp.length;if(!resp.length)status=0x50}else if(v===6){opened=false;closed++;status=0x50}else throw Error("FreHD cmd "+v);return}if(p===0xc2){payload.push(v);if(payload.length===size){if(st===3){assert(payload[0]===1&&String.fromCharCode(...payload.slice(1,-1))==="/TEST.MID","open");opened=true;pos=0;resp=[mid.length&255,mid.length>>8&255,mid.length>>16&255,mid.length>>24]}else if(st===8){dirDone=false;status=0x50}else throw Error("payload "+st)}return}throw Error("unexpected output port "+p)}
 for(let steps=0;steps<30000000;steps++){
  let p=pc;if(p===0x402d)return {output,timeline,ticks,refreshes,closed,port,consoleText,opened};
  if(p===0x002b){r[7]=keys[ki++]||0;pc=pop();continue}if(p===0x0033){consoleText+=String.fromCharCode(r[7]);pc=pop();continue}
  if(p===sym.wait_loop){m[0x4288]++;ticks++;if(ticks===stopAt)m[0x3840]=4}
  if(p===sym.render_parts)refreshes++;
  let op=f();
  if(op>=0x40&&op<=0x7f)set(op>>3&7,get(op&7));
  else if((op&0xc7)===6)set(op>>3&7,f());
  else if((op&0xcf)===1)setpair(op>>4&3,fw());
  else if((op&0xcf)===3||(op&0xcf)===11){let i=op>>4&3;setpair(i,pair(i)+((op&15)===3?1:-1))}
  else if((op&0xc7)===4||(op&0xc7)===5){let i=op>>3&7,v=(get(i)+((op&7)===4?1:-1))&255;set(i,v);z=v===0}
  else if((op&0xcf)===9){let x=pair(2)+pair(op>>4&3);setpair(2,x);c=x>65535}
  else if(op===0){}else if(op===0x1a)r[7]=m[pair(1)];else if(op===0x12)m[pair(1)]=r[7];else if(op===0x37)c=true;
  else if(op===0x3a)r[7]=m[fw()];else if(op===0x32)m[fw()]=r[7];else if(op===0x2a)setpair(2,word(fw()));else if(op===0x22)wr(fw(),pair(2));
  else if(op>=0x80&&op<=0xbf)alu(op>>3&7,get(op&7));else if([0xc6,0xd6,0xe6,0xee,0xf6,0xfe].includes(op))alu(op>>3&7,f());
  else if(op===0xed){let x=f(),i=x>>4&3;if(x===0xb2){let b=r[0]||256,h=pair(2);while(b--){m[h]=read(r[1]);h=(h+1)&65535}setpair(2,h);r[0]=0}else if((x&0xcf)===0x43)wr(fw(),pair(i));else if((x&0xcf)===0x4b)setpair(i,word(fw()));else if((x&0xcf)===0x42){let v=pair(2)-pair(i)-Number(c);c=v<0;z=(v&65535)===0;setpair(2,v)}else if((x&0xcf)===0x4a){let v=pair(2)+pair(i)+Number(c);c=v>65535;z=(v&65535)===0;setpair(2,v)}else throw Error("ED "+x)}
  else if(op===0xcb){let x=f(),i=x&7,mask=1<<(x>>3&7);if(x>=0x40&&x<=0x7f)z=!(get(i)&mask);else if(x>=0x80&&x<=0xbf)set(i,get(i)&~mask);else if(x>=0x38&&x<=0x3f){let v=get(i);c=!!(v&1);set(i,v>>1);z=(v>>1)===0}else throw Error("CB "+x)}
  else if(op===0xc3)pc=fw();else if((op&0xc7)===0xc2){let a=fw();if(cond(op>>3&7))pc=a}
  else if(op===0xcd){let a=fw();push(pc);pc=a}else if(op===0xc9)pc=pop();else if((op&0xc7)===0xc0){if(cond(op>>3&7))pc=pop()}
  else if((op&0xcf)===0xc5){let i=op>>4&3;push(i!==3?pair(i):r[7]<<8|(z?64:0)|Number(c))}
  else if((op&0xcf)===0xc1){let i=op>>4&3,v=pop();if(i===3){r[7]=v>>8;z=!!(v&64);c=!!(v&1)}else setpair(i,v)}
  else if(op===0x10){let d=f();r[0]--;if(r[0])pc=(pc+(d<128?d:d-256))&65535}
  else if(op===0xd3)write(f(),r[7]);else if(op===0xdb)r[7]=read(f());else throw Error("unsupported "+p.toString(16)+" "+op.toString(16));
 }throw Error("step limit "+pc.toString(16));
}
function reference(mid){let p=22,run=0,tx=0,out=[],msgs=0,sx=0,ch=new Set;function vlq(){let n=0,b;do{b=mid[p++];n=n*128+(b&127)}while(b&128);return n}
while(p<mid.length){vlq();let b=mid[p++];if(b===255){let k=mid[p++],l=vlq();p+=l;run=0;if(k===47)break}else if(b===240||b===247){let l=vlq(),a=mid.slice(p,p+l);p+=l;run=0;if(b===240&&l>=5&&l<=128&&a.at(-1)===247&&a.slice(0,-1).every(x=>x<128)&&((l===5&&a[0]===126&&a[2]===9&&a[3]===1)||(l>=10&&a[0]===65&&a[1]<32&&a[2]===66&&a[3]===18&&[64,65].includes(a[4])&&(a.slice(4,-1).reduce((a,b)=>a+b,0)&127)===0))){out.push(240,...a);tx=0;sx++}}
else{if(b&128)run=b;else p--;assert(run,"reference running");if(tx!==run){out.push(run);tx=run}let l=(run&224)===192?1:2;out.push(...mid.slice(p,p+l));p+=l;msgs++;ch.add(run&15)}}return {out,msgs,sx,channels:ch.size}}
let results=[],wires={};
for(let [name,mid] of demos){let ref=reference(mid);for(let mode of ["2","4","5"]){let q=cpu(mid,mode);assert(q.consoleText.includes("End of MIDI file."),"EOT "+name+" "+mode+" "+q.consoleText.slice(-100));assert(q.closed===1&&!q.opened&&q.port===0x20,"close");let music;if(mode==="2"){music=q.output.slice(0,-240);assert(q.output.length===ref.out.length+240,"raw cleanup length");assert(eq(q.output.slice(-3),[191,120,0]),"raw CC120")}else{assert(q.output[0]===(mode==="4"?253:249)&&q.output.at(-1)===250,"markers");music=q.output.slice(1,-1).filter(x=>x!==248);assert(q.output.filter(x=>x===248).length===q.ticks,"ticks");wires[name+"-"+mode]=q.output}
assert(eq(music,ref.out),"music mismatch "+name+" "+mode+" "+music.length+" "+ref.out.length);
results.push({name,mode,music:music.length,messages:ref.msgs,sysex:ref.sx,channels:ref.channels,ticks:q.ticks,refreshes:q.refreshes,wire:q.output.length});}
let q=cpu(mid,"4",10);assert(q.output.at(-1)===252&&q.closed===1&&q.consoleText.includes("Playback stopped."),"BREAK "+name)}
return {results,wires};
}
const dir=__dirname,cmd=Array.from(fs.readFileSync(path.join(dir,'SC55PLAY.CMD'))),sym=Object.fromEntries(fs.readFileSync(path.join(dir,'SC55PLAY.MAP'),'utf8').trim().split('\n').map(l=>{const [v,k]=l.split(' ');return [k,parseInt(v,16)]}));
const demos=['SC55DEMO','VELVET'].map(n=>[n,Array.from(fs.readFileSync(path.join(dir,n+'.MID')))]);const q=verify(cmd,sym,demos);for(const r of q.results)console.log(JSON.stringify(r));for(const [name,wire] of Object.entries(q.wires))fs.writeFileSync(path.join(dir,name+'.wire'),Buffer.from(wire));console.log('PASS buffered BREAK and file closure');
