import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {listAsyncRuns} from '../.pi/npm/node_modules/pi-subagents/src/runs/background/async-status.js';
import {updateActiveRunIndex} from '../.pi/npm/node_modules/pi-subagents/src/runs/background/active-run-index.js';
import {MAX_CHILDREN} from '../.pi/extensions/ashfall-director.ts';
const base=path.resolve('output/pi-director-six-slot-index-fixture');
fs.mkdirSync(base,{recursive:true});
const sample={mode:'single',currentStep:0,chainStepCount:1,startedAt:Date.now(),lastUpdate:Date.now(),steps:[{agent:'ashfall-worker',status:'running'}]};
for(let i=0;i<MAX_CHILDREN+1;i++){
 const id=`fixture-owned-${i}`;const dir=path.join(base,id);fs.mkdirSync(dir,{recursive:true});
 fs.writeFileSync(path.join(dir,'status.json'),JSON.stringify({...sample,runId:id,sessionId:i<MAX_CHILDREN?'fixture-owner':'foreign-owner',state:'running',pid:process.pid}));
 updateActiveRunIndex(dir,'running');
}
const options={sessionId:'fixture-owner',states:['queued','running'],reconcile:false,includeNested:false};
const initial=listAsyncRuns(base,options);
assert.equal(initial.length,MAX_CHILDREN);assert.ok(initial.every(x=>x.id.startsWith('fixture-owned-')));
const reloaded=listAsyncRuns(base,options);assert.equal(reloaded.length,MAX_CHILDREN);
assert.ok(reloaded.length>=MAX_CHILDREN,'overflow admission must be denied by director native-index count');
const queuedPath=path.join(base,'fixture-owned-0','status.json');
const queued=JSON.parse(fs.readFileSync(queuedPath));queued.state='queued';fs.writeFileSync(queuedPath,JSON.stringify(queued));
assert.equal(listAsyncRuns(base,options).length,MAX_CHILDREN,'queued occupies a slot');
queued.state='complete';fs.writeFileSync(queuedPath,JSON.stringify(queued));updateActiveRunIndex(path.dirname(queuedPath),'complete');
assert.equal(listAsyncRuns(base,options).length,MAX_CHILDREN-1,'terminal releases slot');
fs.writeFileSync(path.join(base,'summary.json'),JSON.stringify({pass:true,checks:6,owned:initial.length,foreignExcluded:true,reloadCount:reloaded.length,reconcile:false,limitation:'Synthetic native-index entries, not paid concurrent model runs. Director in-flight rejection separately tested.'},null,2));
console.log(JSON.stringify({pass:true,checks:6,owned:initial.length}));
