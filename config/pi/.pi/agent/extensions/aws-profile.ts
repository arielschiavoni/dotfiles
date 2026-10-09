// The AWS profile for the agent's `aws` commands inside pi-safe. pi-safe lists
// the profiles cred-broker serves in PI_SAFE_AWS_PROFILES (read-only roles,
// `[aws] profiles` in ~/.config/cred-broker/config.toml). The agent's first
// `aws` command asks the user which one to use and sets AWS_PROFILE for the
// rest of the session. /aws-profile switches it.
//
// A convenience: the sandbox may use every listed profile, and the broker
// enforces that list. The extension loads inside pi-safe.
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";

// `aws` in command position: at a line start or after `;&|(`, `$(` or a
// backtick, maybe behind VAR=x assignments or a path: `aws s3 ls`,
// `cd x && aws ...`, `$(aws ...)`, `AWS_PAGER= /usr/bin/aws ...`.
const AWS_COMMAND = /(^|[;&|(`]|\$\()\s*(\w+=\S*\s+)*(\S*\/)?aws(\s|$)/m;
const PROFILE_FLAG = /--profile[=\s]+["']?([\w.-]+)/;

export default function (pi: ExtensionAPI) {
  const profiles = (process.env.PI_SAFE_AWS_PROFILES ?? "")
    .split(",")
    .filter(Boolean);
  if (process.env.PI_SAFE !== "1" || profiles.length === 0) return;

  // parallel tool calls share one question
  let asking: Promise<string | undefined> | undefined;

  const showStatus = (ctx: ExtensionContext) => {
    const p = process.env.AWS_PROFILE;
    ctx.ui.setStatus(
      "aws",
      p ? ctx.ui.theme.fg("accent", `aws: ${p}`) : undefined,
    );
  };

  const choose = (ctx: ExtensionContext): Promise<string | undefined> => {
    asking ??= (async () => {
      const choice = await ctx.ui.select(
        "AWS profile for this session",
        profiles,
      );
      if (choice) {
        // the bash tool passes process.env to every command it runs
        process.env.AWS_PROFILE = choice;
        showStatus(ctx);
      }
      return choice;
    })().finally(() => {
      asking = undefined;
    });
    return asking;
  };

  pi.on("session_start", async (_event, ctx) => showStatus(ctx));

  pi.on("before_agent_start", async (event) => {
    const guideline =
      `AWS: run \`aws\` without --profile; the user picks the profile (${profiles.join(", ")}) ` +
      "on first use, then AWS_PROFILE is set. Credentials are read-only. Pass --region when needed.";
    const guidelines = event.systemPromptOptions.promptGuidelines;
    if (!guidelines.includes(guideline)) guidelines.push(guideline);
  });

  pi.on("tool_call", async (event, ctx) => {
    if (
      !isToolCallEventType("bash", event) ||
      !AWS_COMMAND.test(event.input.command)
    )
      return;

    if (!process.env.AWS_PROFILE) {
      if (!ctx.hasUI) {
        return {
          block: true,
          reason: "No AWS profile chosen, and no UI to ask the user for one.",
        };
      }
      if (!(await choose(ctx))) {
        return {
          block: true,
          reason:
            "The user chose no AWS profile. Ask them before using AWS again.",
        };
      }
    }

    const flag = event.input.command.match(PROFILE_FLAG)?.[1];
    if (flag && flag !== process.env.AWS_PROFILE) {
      return {
        block: true,
        reason:
          `The user chose the AWS profile ${process.env.AWS_PROFILE}: run aws without --profile. ` +
          "To use another one, ask the user to switch with /aws-profile.",
      };
    }
  });

  pi.registerCommand("aws-profile", {
    description: "Choose the AWS profile for the agent's aws commands",
    handler: async (_args, ctx) => {
      const choice = await choose(ctx);
      if (choice) ctx.ui.notify(`AWS_PROFILE=${choice}`, "info");
    },
  });
}
