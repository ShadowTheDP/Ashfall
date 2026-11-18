import assert from 'node:assert/strict';
import director,{subagentBlockReason,toolBlockReason,planActive,workflowChildBlockReason,capacityBlockReason,MAX_CHILDREN} from '../.pi/extensions/ashfall-director.ts';
let checks=0;
const ok=(condition,message)=>{assert.ok(condition,message);checks++;};
const launch={agent:'ashfall-worker',task:'bounded task',async:true,options:{context:'fresh',timeoutMs:3600000}};
ok(subagentBlockReason(launch,false)===null,'ordinary async native worker remains usable');
for(const [field,value] of [['model','other'],['machine','remote'],['cwd','C:/'],['worktree',true],['workflow',true],['parallel',[]],['extensionBindings',{}]]) {
  ok(subagentBlockReason({...launch,[field]:value},false),`reject launch ${field}`);
  ok(subagentBlockReason({...launch,options:{[field]:value}},false),`reject nested launch ${field}`);
}
ok(subagentBlockReason({...launch,options:{timeoutMs:3600001}},false),'runtime ceiling');
ok(subagentBlockReason({...launch,timeoutMs:1,maxRuntimeMs:2},false),'conflicting timeout aliases');
for(const action of ['resume','steer']) {
  ok(subagentBlockReason({action,id:'owned',message:'follow up'},true),`Plan blocks ${action}`);
  ok(subagentBlockReason({action,id:'owned',options:{model:'other'}},false),`action cannot inject model`);
}
ok(subagentBlockReason({action:'create',config:{}},false),'no agent creation by main');
ok(subagentBlockReason({action:'status',options:{view:'transcript',lines:10}},false)===null,'readonly status options');
ok(subagentBlockReason({...launch,agent:'worker'},false),'global/builtin agent cannot launch');
for (const field of ['workflowScript','script','tasks','chain']) {
  for (const input of [{[field]:true},{options:{[field]:true}}]) {
    ok(subagentBlockReason(input,false),`${field} unsupported entry rejected`);
    ok(/Plan mode/.test(subagentBlockReason(input,true)),`Plan still blocks ${field}`);
  }
}
for(const name of ['write','edit','bash','powershell','codemode','subagent_supervisor','contact_supervisor','acp_delegate']) {
  ok(toolBlockReason(name,{},false),`main blocks ${name}`);
}
for(const name of ['compress','decompress','search_context','acp_status','acp_cache','acp_read_original_image','new_plugin_tool','mcp__godot__get_project_info']) {
  ok(toolBlockReason(name,{},false)===null,`default permits ${name}`);
}
for (const workflow of [true,'./project-workflow.js','parallel']) ok(subagentBlockReason({workflow,async:true},false)===null,'native workflow entry allowed');
ok(subagentBlockReason({workflow:'run-ci'},false),'host-command named resource blocked');
const child={workflowRunId:'fixture',key:'worker',agent:'ashfall-worker',task:'bounded task',cwd:process.cwd()};
ok(workflowChildBlockReason(child,false,process.cwd())===null,'native child approval allowed');
for(const extra of [{model:'other'},{async:true},{worktree:true},{resume:'old'},{commands:[{command:'echo bad'}]},{cwd:'C:/'},{output:'C:/outside.txt'}]) ok(workflowChildBlockReason({...child,...extra},false,process.cwd()),'workflow override blocked');
ok(workflowChildBlockReason(child,true,process.cwd()),'Plan blocks native child approval');
ok(capacityBlockReason([],[],true)===null,'idle workflow admission');
ok(capacityBlockReason([{}],[],true),'workflow waits for direct work');
ok(capacityBlockReason([{workflow:{}}],[],false),'direct waits for workflow after reload');
ok(capacityBlockReason([],[true],false),'workflow reservation excludes direct work');
ok(capacityBlockReason([],[],false)===null,'terminal releases workflow slot');
const branch=[{type:'custom',customType:'plan-mode-state',data:{enabled:false}}];
ok(!planActive({sessionManager:{getBranch:()=>branch,getEntries:()=>[...branch,{type:'custom',customType:'plan-mode-state',data:{enabled:true}}]}}),'Plan reads current branch, not abandoned branch');
const handlers={};
let activeTools=['read','compress','new_plugin_tool','write','bash'];
const pi={on:(name,handler)=>{handlers[name]=handler;},registerCommand:()=>{},getAllTools:()=>[],getActiveTools:()=>activeTools,setActiveTools:names=>{activeTools=names;}};
director(pi);
const ctx={sessionManager:{getBranch:()=>[],getSessionId:()=> 'pi-director-probe-unique-no-existing-runs',getSessionFile:()=>undefined},ui:{setStatus:()=>{}}};
await handlers.session_start({},ctx);
ok(JSON.stringify(activeTools)===JSON.stringify(['read','compress','new_plugin_tool']),'activation preserves plugins and removes only blacklist');
activeTools=['read'];
await handlers.before_agent_start({},ctx);
ok(JSON.stringify(activeTools)===JSON.stringify(['read']),'does not activate disabled or hidden plugins');
for(let i=0;i<MAX_CHILDREN;i++) ok(await handlers.tool_call({toolName:'subagent',toolCallId:`p${i}`,input:launch},ctx)===undefined,'in-flight launches fit configured capacity');
ok((await handlers.tool_call({toolName:'subagent',toolCallId:'overflow',input:launch},ctx))?.block,'overflow rejected before native index publishes');
await handlers.tool_execution_end({toolCallId:'p0'},ctx);
ok(await handlers.tool_call({toolName:'subagent',toolCallId:'replacement',input:launch},ctx)===undefined,'execution end releases aborted reservation');
await handlers.agent_settled({},ctx);
ok(await handlers.tool_call({toolName:'subagent',toolCallId:'after-settle',input:launch},ctx)===undefined,'settled clears stale in-flight reservations');
console.log(JSON.stringify({pass:true,checks}));
