/** Project model-tool policy; human slash commands and the OS remain trusted. */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import path from "node:path";
import { listAsyncRuns } from "../npm/node_modules/pi-subagents/src/runs/background/async-status.js";
import { ASYNC_DIR } from "../npm/node_modules/pi-subagents/src/shared/types.js";
import { registerSubagentCapabilityCeiling } from "../npm/node_modules/pi-subagents/bundle/capability-ceiling.js";

export const ROLES = ["ashfall-scout", "ashfall-worker", "ashfall-reviewer", "ashfall-validator"];
export const MAX_RUNTIME_MS = 3_600_000;
export const MAX_CHILDREN = 6;
export const BLOCKED_TOOLS = new Set([
  "write", "edit", "bash", "powershell", "codemode",
  "subagent_supervisor", "contact_supervisor", "acp_delegate",
]);
const LAUNCH_FIELDS = ["agent", "task", "async", "timeoutMs", "maxRuntimeMs", "context", "options"];
const LAUNCH_OPTIONS = ["timeoutMs", "maxRuntimeMs", "context"];
const WORKFLOW_FIELDS = ["workflow", "args", "async", "timeoutMs", "maxRuntimeMs", "context", "options"];
const ACTION_FIELDS: Record<string, string[]> = {
  status: ["id", "view", "lines", "index"],
  list: ["search", "capabilities"],
  "children.list": [],
  guide: ["topic"],
  stop: ["id"],
  steer: ["id", "message", "mode"],
  resume: ["id", "message"],
};

export function planActive(ctx: Pick<ExtensionContext, "sessionManager">): boolean {
  const entries = ctx.sessionManager.getBranch();
  for (let i = entries.length - 1; i >= 0; i--) {
    const entry = entries[i];
    if (entry.type === "custom" && entry.customType === "plan-mode-state") return entry.data?.enabled === true;
  }
  return false;
}

function unknownField(input: Record<string, unknown>, allowed: string[]): string | undefined {
  return Object.keys(input).find(key => !allowed.includes(key));
}

export function subagentBlockReason(input: Record<string, unknown>, inPlan: boolean): string | null {
  const options = input.options;
  if (options !== undefined && (!options || typeof options !== "object" || Array.isArray(options))) return "options must be an object";
  const nested = (options ?? {}) as Record<string, unknown>;
  if (input.action !== undefined) {
    const action = String(input.action);
    const fields = ACTION_FIELDS[action];
    if (!fields) return `Director does not permit action '${action}'`;
    const extra = unknownField(input, ["action", "options", ...fields]) ?? unknownField(nested, fields);
    if (extra) return `Director does not permit '${extra}' on ${action}`;
    if (inPlan && ["resume", "steer"].includes(action)) return "Plan mode cannot resume or steer implementation";
    for (const key of Object.keys(nested)) if (input[key] !== undefined && input[key] !== nested[key]) return `Conflicting '${key}'`;
    if (["stop", "steer", "resume"].includes(action) && typeof (input.id ?? nested.id) !== "string") return "An exact owned run id is required";
    return null;
  }
  if (inPlan) return "Plan mode cannot launch children";
  const workflow = input.workflow !== undefined;
  const extra = unknownField(input, workflow ? WORKFLOW_FIELDS : LAUNCH_FIELDS) ?? unknownField(nested, LAUNCH_OPTIONS);
  if (extra) return `Director does not permit launch field '${extra}'`;
  if (workflow) {
    // Raw native workflows have no runs.host; named resources can execute host commands.
    if (input.workflow !== true && input.workflow !== "parallel" && !(typeof input.workflow === "string" && /[\\/]/.test(input.workflow))) return "Use native workflow:true, parallel, or a workflow script path; named host-command resources require separate review";
  } else {
    if (!ROLES.includes(String(input.agent))) return "Use one of the four project ashfall roles";
    if (typeof input.task !== "string" || !input.task.trim()) return "A non-empty task is required";
  }
  if (input.async !== undefined && typeof input.async !== "boolean") return "async must be boolean";
  const durations = [input.timeoutMs, input.maxRuntimeMs, nested.timeoutMs, nested.maxRuntimeMs].filter(x => x !== undefined);
  if (durations.some(x => typeof x !== "number" || !Number.isSafeInteger(x) || x <= 0 || x > MAX_RUNTIME_MS)) return "Runtime must be 1..3600000 milliseconds";
  if (durations.some(x => x !== durations[0])) return "Conflicting runtime aliases";
  if ([input.context, nested.context].some(x => x !== undefined && x !== "fresh")) return "New children require fresh context";
  return null;
}

export function toolBlockReason(name: string, input: Record<string, unknown>, inPlan: boolean): string | null {
  if (BLOCKED_TOOLS.has(name)) return `The primary agent cannot call '${name}'; use project roles for implementation and delegation`;
  if (name === "subagents_enable") return inPlan ? "Plan mode cannot enable delegation" : null;
  if (name === "subagent") return subagentBlockReason(input, inPlan);
  if (name === "subagent_launch") return workflowChildBlockReason(input, inPlan);
  return null;
}

export function workflowChildBlockReason(input: Record<string, unknown>, inPlan: boolean, cwd?: string): string | null {
  if (inPlan) return "Plan mode cannot launch workflow children";
  if (!ROLES.includes(String(input.agent))) return "Workflow children must use one of the four project ashfall roles";
  if (typeof input.task !== "string" || !input.task.trim()) return "A non-empty workflow child task is required";
  if (input.model !== undefined) return "Use the project's role model defaults, without workflow model overrides";
  if (input.async === true) return "Await workflow children inside the native workflow; do not detach async children";
  if (input.worktree === true || input.resume !== undefined) return "Workflow children use fresh project-local runs; dispatch retained resume separately";
  if (Array.isArray(input.commands) && input.commands.length) return "Delegate checks to ashfall-validator instead of workflow host commands";
  if (cwd && (typeof input.cwd !== "string" || path.resolve(input.cwd).toLowerCase() !== path.resolve(cwd).toLowerCase())) return "Workflow children must stay in the project root";
  if (cwd && input.output !== undefined) {
    const relative = path.relative(path.resolve(cwd), path.resolve(String(input.output)));
    if (relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) return "Workflow output must stay inside the project";
  }
  return null;
}

export function capacityBlockReason(runs: Array<{workflow?: unknown}>, pending: Iterable<boolean>, workflow: boolean): string | null {
  const reservations = [...pending];
  if (workflow && (runs.length || reservations.length)) return "Wait for existing project runs before starting a workflow";
  if (runs.some(run => run.workflow) || reservations.some(Boolean)) return "A native workflow owns the six child slots; wait for it to finish";
  if (runs.length + reservations.length >= MAX_CHILDREN) return "Six owned children are active; wait or stop one before launching";
  return null;
}

export default function director(pi: ExtensionAPI): void {
  const pending = new Map<string, boolean>();
  let restriction: ReturnType<typeof registerSubagentCapabilityCeiling> | undefined;
  const bindRoles = (ctx: ExtensionContext) => {
    restriction?.dispose();
    restriction = registerSubagentCapabilityCeiling({sessionId: ctx.sessionManager.getSessionId(), source: "ashfall-director", ceiling: {allowedAgents: ROLES}});
  };
  const ownedRuns = (ctx: ExtensionContext, activeOnly: boolean) => listAsyncRuns(ASYNC_DIR, {
    sessionId: ctx.sessionManager.getSessionFile() ?? ctx.sessionManager.getSessionId(),
    ...(activeOnly ? {states: ["queued", "running", "paused"] as Array<"queued" | "running" | "paused">} : {}),
    reconcile: false, includeNested: false,
  });
  const activate = (ctx: ExtensionContext) => {
    const inPlan = planActive(ctx);
    // Preserve plugin exposure and lazy activation; never enable hidden tools or reset Plan's selection.
    if (!inPlan) {
      const active = pi.getActiveTools();
      const permitted = active.filter(name => !BLOCKED_TOOLS.has(name));
      if (permitted.length !== active.length) pi.setActiveTools(permitted);
    }
  };
  pi.on("session_start", async (_event, ctx) => { pending.clear(); bindRoles(ctx); activate(ctx); });
  pi.on("session_switch", async (_event, ctx) => { pending.clear(); bindRoles(ctx); activate(ctx); });
  pi.on("session_shutdown", async () => { restriction?.dispose(); });
  pi.on("before_agent_start", async (_event, ctx) => activate(ctx));
  pi.on("tool_call", async (event, ctx) => {
    const input = event.input as Record<string, unknown>;
    let reason = toolBlockReason(event.toolName, input, planActive(ctx));
    if (!reason && event.toolName === "subagent_launch") reason = workflowChildBlockReason(input, planActive(ctx), ctx.cwd);
    if (!reason && event.toolName === "subagent") {
      const action = input.action;
      try {
        if (action === undefined || action === "resume") {
          const workflow = input.workflow !== undefined;
          if (workflow && !pi.getAllTools().some(tool => tool.name === "subagent_launch")) reason = "Native workflow approval tool is unavailable; reopen Pi with pi-subagents loaded";
          if (!reason) reason = capacityBlockReason(ownedRuns(ctx, true), pending.values(), workflow);
          if (!reason) pending.set(event.toolCallId, workflow);
        }
        if (!reason && ["resume", "steer"].includes(String(action))) {
          const id = String(input.id ?? (input.options as Record<string, unknown> | undefined)?.id);
          const run = ownedRuns(ctx, false).find(run => run.id === id);
          if (!run || run.steps.length !== 1 || !ROLES.includes(run.steps[0].agent)) reason = "Only an exact owned single ashfall-role run may be resumed or steered";
        }
      } catch { reason = "Cannot verify owned child state; refusing to launch or steer"; }
      if (reason) pending.delete(event.toolCallId);
    }
    if (reason) return {block: true, reason};
  });
  pi.on("tool_result", async (event) => { pending.delete(event.toolCallId); });
  pi.on("tool_execution_end", async (event) => { pending.delete(event.toolCallId); });
  pi.on("agent_settled", async () => { pending.clear(); });
  pi.registerCommand("director", {
    description: "Show this project's director limits",
    handler: async (_args, ctx) => {
      ctx.ui.notify("director 採黑名單：禁直接寫檔／shell／codemode 與替代派工入口，其餘插件預設放行；不覆寫插件啟用狀態。主代理協調、派工與驗收。獨立實作預設3個 DeepSeek worker，可獨立拆分時用4至5個；小事或耦合工作用1個。四角色可重複派工，共用6槽、不向下派工；workflow 與直接派工輪流用槽。同檔單一 writer，完成檔案可先審查，整合凍結後集中驗證。Plan 禁派工／追問／恢復。角色預設最長1小時；workflow 審批摘要不含全部覆寫，這是協作政策，並非作業系統沙箱。", "info");
    },
  });
}
