/**
 * German translator/tutor mode for pi.
 *
 * Not auto-discovered (lives outside ~/.pi/agent/extensions). Load explicitly:
 *   pi -ne -ns -nc -e ~/.pi/agent/translator/translate.ts
 * (see the `pi_translate` fish function)
 */
import { readFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PROVIDER = "anthropic";
const MODEL = "claude-haiku-5-5";
const PROMPT_URL = new URL("./translate.md", import.meta.url);

export default function (pi: ExtensionAPI) {
  let systemPrompt = "";

  pi.on("session_start", async (_event, ctx) => {
    systemPrompt = readFileSync(PROMPT_URL, "utf8");
    const model = ctx.modelRegistry.find(PROVIDER, MODEL);
    if (!model || !(await pi.setModel(model))) {
      ctx.ui.notify(`translate: cannot use ${PROVIDER}/${MODEL}`, "error");
    }
    pi.setThinkingLevel("low");
    pi.setActiveTools([]);
    ctx.ui.setStatus("translate", ctx.ui.theme.fg("accent", "DE translate"));
  });

  pi.on("before_agent_start", async () => ({ systemPrompt }));
}
