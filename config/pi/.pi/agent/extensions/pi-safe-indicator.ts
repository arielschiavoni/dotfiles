// Shows a badge in the footer's status line when pi runs inside pi-safe
// (which sets PI_SAFE=1).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  if (process.env.PI_SAFE !== "1") return;

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setStatus("pi-safe", ctx.ui.theme.fg("success", "🔒 pi-safe"));
  });
}
