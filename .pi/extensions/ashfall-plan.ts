import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import planMode from "../npm/node_modules/@narumitw/pi-plan-mode/dist/index.ts";

export default function ashfallPlan(pi: ExtensionAPI) {
  // Keep Plan preferences and /plan settings writes scoped to this project.
  planMode(pi, { settingsPath: fileURLToPath(new URL("../pi-plan-mode.json", import.meta.url)) });
}
