import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {registerHooks} from 'node:module';
import director from '../.pi/extensions/ashfall-director.ts';
const host='C:/Users/user/AppData/Roaming/npm/node_modules/@earendil-works/pi-coding-agent';
registerHooks({resolve(specifier,context,nextResolve){
  try{return nextResolve(specifier,context);}catch(error){
    if(error.code!=='ERR_MODULE_NOT_FOUND'||specifier.startsWith('.')||specifier.startsWith('/')||specifier.includes(':')) throw error;
    return nextResolve(specifier,{...context,parentURL:pathToFileURL(`${host}/dist/index.js`).href});
  }
}});
const {resolveDisabledFeatureSurface}=await import('../.pi/npm/node_modules/pi-subagents/src/shared/disabled-features.js');
const {createSubagentParamsSchema}=await import('../.pi/npm/node_modules/pi-subagents/src/extension/schemas.js');
const {buildSubagentToolDescription}=await import('../.pi/npm/node_modules/pi-subagents/src/extension/tool-description.js');
const {registerSubagentLaunchTool,approveWorkflowChildLaunch}=await import('../.pi/npm/node_modules/pi-subagents/src/extension/subagent-launch-tool.js');
const {runWorkflowScript}=await import('../.pi/npm/node_modules/pi-subagents/src/workflows/scripted-workflow.js');
const {resolveCurrentSubagentCapabilityCeiling}=await import('../.pi/npm/node_modules/pi-subagents/bundle/capability-ceiling.js');
const root=path.resolve(import.meta.dirname,'..');
const settings=JSON.parse(fs.readFileSync(path.join(root,'.pi/settings.json')));
const parameters=createSubagentParamsSchema(resolveDisabledFeatureSurface(settings.subagents));
const description=buildSubagentToolDescription(settings.subagents,{cwd:root});
let checks=0,executions=0,childExecutions=0,peak=0,active=0,approvalCalls=0,hookVisible=false;
const check=(name,value)=>{assert.ok(value,name);checks++;};
check('native schema exposes workflow and args',parameters.properties.workflow&&parameters.properties.args);
check('native description supports workflow and all four roles',description.includes('workflow:true')&&['scout','worker','reviewer','validator'].every(role=>description.includes(`ashfall-${role}`)));
check('declarations refresh and native concurrency is six',settings.subagents.pinToolDeclarations===false&&settings.subagents.globalConcurrencyLimit===6);
check('automatic unhooked starts disabled',settings.subagents.autoResume===false&&settings.subagents.authorityPolicy.scheduleCreate==='forbid');
check('project MCP has no orphan memory override',!JSON.parse(fs.readFileSync(path.join(root,'.pi/mcp.json'))).mcpServers['magpie-memory']);
const sdk=await import(pathToFileURL(`${host}/dist/index.js`));
const {runToolCall}=await import(pathToFileURL(`${host}/node_modules/@earendil-works/pi-agent-core/dist/index.js`));
const settingsManager=sdk.SettingsManager.inMemory({...settings,packages:[]},{projectTrusted:true});
// Exercise the real workflow sandbox/scheduler and nested native approval through Pi.
// Only the final child model execution is replaced; no provider or user process runs.
const loader=new sdk.DefaultResourceLoader({cwd:root,agentDir:path.join(root,'output/pi-six-slot-workflow-2026-11-16/isolated-agent'),settingsManager,
 noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,
 additionalExtensionPaths:[path.join(root,'.pi/extensions/ashfall-plan.ts')],
 extensionFactories:[{name:'native-workflow-offline-fixture',factory:pi=>{
  registerSubagentLaunchTool(pi);
  for (const name of ['web_enable','web_search','source_check','fetch_content','get_search_content','tool_search','compress','decompress','search_context','acp_status','acp_cache','acp_read_original_image','future_plugin_tool']) {
   pi.registerTool({name,label:name,description:'Offline web policy fixture',parameters:{type:'object',properties:{}},
    async execute(){return {content:[{type:'text',text:'MOCK web result'}]};}});
  }
  pi.on('tool_call',async event=>{if(event.toolName==='subagent_launch')approvalCalls++;});
  pi.registerTool({name:'subagent',label:'Subagent',description,parameters,
   async execute(_id,params,signal,_update,ctx){
    executions++;
    if(params.workflow===undefined)return {content:[{type:'text',text:'MOCK direct child'}]};
    hookVisible=ctx.tools.some(tool=>tool.name==='subagent_launch');
    const result=await runWorkflowScript({script:params.args.script,processCwd:root,signal,globalConcurrencyLimit:settings.subagents.globalConcurrencyLimit,
     status:async()=>{throw new Error('Unexpected status');},
     launch:async(key,child,childSignal)=>{
      const approval=await approveWorkflowChildLaunch(ctx,()=>({workflowRunId:'offline-workflow',key,cwd:root,...child}),childSignal);
      if(approval.refusal)return {key,ok:false,error:approval.refusal,output:approval.refusal,artifactPaths:[]};
      active++;peak=Math.max(peak,active);childExecutions++;
      try {await new Promise(resolve=>setTimeout(resolve,8));return {key,ok:true,output:`completed:${key}`,artifactPaths:[]};}
      finally {active--;}
     }});
    return {content:[{type:'text',text:JSON.stringify(result.value)}],details:result};
   }});
 }},{name:'project-director',factory:director}]});
await loader.reload();assert.deepEqual(loader.getExtensions().errors,[]);
const agentDir='C:/Users/user/.pi/agent';
const modelRuntime=await sdk.ModelRuntime.create({authPath:`${agentDir}/auth.json`,modelsPath:`${agentDir}/models.json`,allowModelNetwork:false});
const model=new sdk.ModelRegistry(modelRuntime).find('magpie',settings.defaultModel);
assert.ok(model,'configured model exists locally');
const {session}=await sdk.createAgentSession({cwd:root,agentDir,modelRuntime,model,settingsManager,resourceLoader:loader,sessionManager:sdk.SessionManager.inMemory(root)});
await session.bindExtensions({mode:'print',onError:error=>{throw error;}});
async function invoke(args,name='subagent'){
 const call={type:'toolCall',id:crypto.randomUUID(),name,arguments:args};
 const assistantMessage={role:'assistant',api:model.api,provider:model.provider,model:model.id,content:[call],stopReason:'toolUse',timestamp:Date.now(),usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}};
 session.agent.state.messages.push(assistantMessage);
 return runToolCall(call,{tools:session.agent.state.tools,assistantMessage,context:{messages:[],tools:session.agent.state.tools},beforeToolCall:session.agent.beforeToolCall,afterToolCall:session.agent.afterToolCall,signal:AbortSignal.timeout(20000)});
}
const workflow=script=>({workflow:true,args:{script},async:true});
try {
 const direct={agent:'ashfall-worker',task:'Bounded mock task',async:true};
 for (const name of ['compress','decompress','search_context','acp_status','acp_cache','acp_read_original_image','future_plugin_tool']) {
  check(`blacklist preserves active ${name}`,session.getActiveToolNames().includes(name));
  check(`real pipeline permits ${name}`,!(await invoke({},name)).isError);
 }
 session.setActiveToolsByName([...session.getActiveToolNames(),'bash']);
 check('director rejects reactivated shell',(await invoke({command:'echo forbidden'},'bash')).isError);
 check('direct role call usable',!(await invoke(direct)).isError);
 check('model override rejected',(await invoke({...direct,model:'other'})).isError);
 check('native role ceiling bound to current session',resolveCurrentSubagentCapabilityCeiling(session.sessionManager.getSessionId()).allowedAgents.length===4);
 const sequential=await invoke(workflow('const a = await runs.run("implement", {agent:"ashfall-worker",task:"bounded implementation"}); if (!a.ok) throw new Error(a.error); return runs.run("review", {agent:"ashfall-reviewer",task:a.output});'));
 assert.ok(!sequential.isError,JSON.stringify(sequential));
 check('native dependent workflow completes',sequential.result.details.value.ok);
 check('nested approval visible without advertising it to model',hookVisible&&!session.getActiveToolNames().includes('subagent_launch'));
 const jobs=Array.from({length:8},(_,i)=>({key:`worker${i}`,agent:'ashfall-worker',task:`exclusive mock file set ${i}`}));
 const parallel=await invoke(workflow(`return runs.all(${JSON.stringify(jobs)});`));
 check('native eight-worker workflow queues within six slots',!parallel.isError&&parallel.result.details.value.length===8&&peak===6);
 const before=childExecutions;
 const denied=await invoke(workflow('return runs.run("bad", {agent:"ashfall-worker",task:"bounded",model:"other"});'));
 check('native child override refused before child runner',denied.isError&&JSON.stringify(denied.result).includes('model overrides')&&childExecutions===before);
 check('every attempted child passed native approval',approvalCalls===11);
 await session.prompt('/plan start');
 for (const name of ['web_enable','web_search','source_check','fetch_content','get_search_content','tool_search','compress','decompress','search_context','acp_status','acp_cache','acp_read_original_image']) {
  check(`real Plan permits ${name}`,!(await invoke({},name)).isError);
 }
 session.setActiveToolsByName([...session.getActiveToolNames(),'write']);
 check('real Plan still blocks writes',(await invoke({path:'output/plan-must-not-write.txt',content:'blocked'},'write')).isError);
 session.setActiveToolsByName([...session.getActiveToolNames(),'subagent']);
 check('real Plan blocks workflow',(await invoke(workflow('return 1;'))).isError);
 check('real Plan blocks direct',(await invoke(direct)).isError);
 await session.prompt('/plan exit');
 session.setActiveToolsByName([...session.getActiveToolNames(),'subagent']);
 check('direct usable after Plan exits',!(await invoke(direct)).isError);
 check('terminal workflow releases reservation',!(await invoke(workflow('return 42;'))).isError);
}finally{session.dispose();}
const evidence={pass:true,checks,executions,childExecutions,approvalCalls,peak,paidCalls:0,liveProcessesTouched:false,limitations:'Actual native workflow sandbox/scheduler and nested approval through real Pi SDK and project Plan; child execution and web responses mocked. Live web providers, full subagent executor/recovery and interactive /plan implement not exercised.'};
const evidenceDir=path.join(root,'output/pi-director-blacklist-2026-11-17');fs.mkdirSync(evidenceDir,{recursive:true});fs.writeFileSync(path.join(evidenceDir,'workflow-probe.json'),JSON.stringify(evidence,null,2));console.log(JSON.stringify(evidence));
