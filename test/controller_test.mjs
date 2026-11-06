import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('../assets/controller.html', import.meta.url), 'utf8');
function controller(startRacing=true) {
  const elements = new Map();
  for (const [,id] of source.matchAll(/id="([^"]+)"/g)) elements.set(id, {
    value: id === 'sensitivity' ? '.75' : id === 'name' ? 'Ana' : '',
    style: {}, dataset: {}, classList: {add(){},remove(){},toggle(){}},
    clientWidth: 200, clientHeight: 250, textContent: '',
    setAttribute(){}, setPointerCapture(){},
  });
  const messages = [], listeners = {};
  let socket, clock = 0;
  const context = {
    document: {getElementById: id => elements.get(id), documentElement:{style:{setProperty(){}}}, addEventListener(name, handler){listeners[name]=handler;}},
    location: {pathname:'/TESTROOM', host:'localhost', protocol:'http:'},
    localStorage:{getItem:()=>null,setItem(){}},sessionStorage:{getItem:()=>null,setItem(){},removeItem(){}},
    performance: {now:()=>clock+=50}, setInterval(){},setTimeout(){},clearTimeout(){},
    addEventListener(name, handler){listeners[name]=handler;},
    WebSocket: class {constructor(){socket=this;this.readyState=1;}send(value){messages.push(JSON.parse(value));}close(){}},
  };
  context.window = context;
  vm.runInNewContext(source.split('<script>')[1].split('</script>')[0], context);
  const element=id=>elements.get(id);
  element('name').value='Ana';
  element('join').onsubmit({preventDefault(){}});
  socket.onopen();
  socket.onmessage({data:JSON.stringify({type:'state',status:startRacing?'racing':'lobby',ready:false,playerCount:1,readyCount:0})});
  const last=()=>messages.filter(m=>m.type==='input').at(-1);
  const pointer=(pointerId,clientX,clientY)=>({pointerId,clientX,clientY,preventDefault(){}});
  return {element,last,pointer,listeners,messages,receive:data=>socket.onmessage({data:JSON.stringify(data)})};
}

test('relative steering starts neutral, filters tiny touches and keeps direction signs',()=>{
  const {element,last,pointer}=controller(), wheel=element('steering');
  wheel.onpointerdown(pointer(1,20,100));
  assert.equal(last().steer,0);
  wheel.onpointermove(pointer(1,24,100));
  assert.equal(last().steer,0);
  wheel.onpointermove(pointer(1,80,100));
  assert.ok(last().steer>0 && last().steer<.75);
  wheel.onpointermove(pointer(1,-40,100));
  assert.ok(last().steer<0);
});

test('two thumbs steer and slide acceleration to boost to reverse without lifting',()=>{
  const {element,last,pointer}=controller(), wheel=element('steering'), pedal=element('power');
  wheel.onpointerdown(pointer(1,100,100));
  wheel.onpointermove(pointer(1,50,100));
  pedal.onpointerdown(pointer(2,300,150));
  assert.equal(last().accelerate,true);
  assert.ok(last().steer<0);
  pedal.onpointermove(pointer(2,300,90));
  assert.equal(last().boost,true);
  assert.equal(last().accelerate,true);
  wheel.onpointerup(pointer(1,50,100));
  assert.equal(last().boost,true);
  assert.equal(last().steer,0);
  pedal.onpointermove(pointer(2,300,150));
  assert.equal(last().accelerate,true);
  assert.equal(last().boost,false);
  pedal.onpointermove(pointer(2,300,210));
  assert.equal(last().reverse,true);
  assert.equal(last().accelerate,false);
  pedal.onpointercancel(pointer(2,300,210));
  assert.equal(last().reverse,false);
});

test('leaving the page neutralizes every input and HTTP does not request sensors',async()=>{
  const {element,last,pointer,listeners}=controller();
  element('power').onpointerdown(pointer(2,300,150));
  listeners.blur();
  assert.equal(last().accelerate,false);
  assert.equal(last().steer,0);
  await element('tilt').onclick();
  assert.match(element('sensorStatus').textContent,/HTTPS/);
});

test('ready, countdown, timers and a two-step pause are reflected in the controller',()=>{
 const {element,last,messages,receive}=controller(false);
 element('ready').onclick();
 assert.deepEqual(messages.at(-1),{type:'ready',ready:true});
 receive({type:'state',status:'lobby',ready:true,readyCount:1,playerCount:1});
 assert.equal(element('ready').textContent,'Cancelar pronto');
 receive({type:'state',status:'countdown',countdown:3});
 assert.equal(element('power').disabled,true);
 assert.equal(element('countdown').textContent,3);
 receive({type:'state',status:'racing'});
 element('pause').onclick();assert.equal(messages.at(-1).type,'pause');
 receive({type:'pauseRequest',armed:true});
 assert.equal(element('pause').textContent,'Confirmar pausa');
 assert.equal(element('power').disabled,false);
 element('pause').onclick();assert.equal(messages.at(-1).type,'pause');
 receive({type:'state',status:'racing',paused:true});
 assert.equal(element('power').disabled,true);
 assert.equal(last().accelerate,false);
 receive({type:'telemetry',speed:100,lap:1,rank:1,charge:1,raceTime:65.12,lapTime:10.5});
 assert.equal(element('raceTime').textContent,'1:05.12');
 assert.equal(element('lapTime').textContent,'0:10.50');
});
