#!/usr/bin/env node
// Opens an AWS console URL in an agent-browser session, signed in as
// AWS_PROFILE: its role credentials become a console sign-in token
// (federation endpoint), and the browser follows the login URL to the page.
// Credentials, the token and the login URL stay out of the output.
//
// It starts the agent-browser dashboard first (PI_SAFE_DASHBOARD_PORT, the
// port pi-safe publishes to the Mac), so the user can watch the session, and
// prints its URL, the identity signed in and the page reached.
//
// The browser uses a Chromium profile per AWS profile, so the cookie banner
// and the console's tours and "what's new" popups, once dismissed, stay
// dismissed in later sessions. The consent cookie is preset.
//
// Usage: aws-console.ts <console-url> [--session <name>]
// Exit: 0 page opened, 1 not signed in (login page), 2 failure.
import { execFileSync, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const FEDERATION = "https://signin.aws.amazon.com/federation";

function fail(message: string, code = 2): never {
  console.error(`aws-console: ${message}`);
  process.exit(code);
}

function parseArgs(argv: string[]) {
  let url: string | undefined;
  let session = process.env.AGENT_BROWSER_SESSION;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--session") session = argv[++i];
    else if (arg.startsWith("--session=")) session = arg.slice(10);
    else if (arg === "-h" || arg === "--help") {
      console.log("Usage: aws-console.ts <console-url> [--session <name>]");
      process.exit(0);
    } else if (!url) url = arg;
    else fail(`unexpected argument: ${arg}`);
  }
  if (!url) fail("Usage: aws-console.ts <console-url> [--session <name>]");
  let destination: URL;
  try {
    destination = new URL(url);
  } catch {
    fail(`not a URL: ${url}`);
  }
  if (
    destination.protocol !== "https:" ||
    !/(^|\.)console\.aws\.amazon\.com$/.test(destination.hostname)
  )
    fail(`not an AWS console URL: ${destination.host}`);
  return { destination, session: session || "default" };
}

function credentials() {
  try {
    const out = execFileSync(
      "aws",
      ["configure", "export-credentials", "--format", "process"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: 360_000 },
    );
    const c = JSON.parse(out);
    if (!c.SessionToken) fail("the profile has no session credentials");
    return {
      sessionId: c.AccessKeyId,
      sessionKey: c.SecretAccessKey,
      sessionToken: c.SessionToken,
    };
  } catch (error) {
    const stderr = String((error as { stderr?: string }).stderr ?? "").trim();
    // aws prints no secrets on failure; the last line says what went wrong
    fail(
      `no credentials for ${process.env.AWS_PROFILE}: ${stderr.split("\n").pop() || error}`,
    );
  }
}

async function signinToken(session: object): Promise<string> {
  const query = new URLSearchParams({
    Action: "getSigninToken",
    Session: JSON.stringify(session),
  });
  const res = await fetch(`${FEDERATION}?${query}`, {
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) fail(`federation endpoint returned HTTP ${res.status}`);
  const token = ((await res.json()) as { SigninToken?: string }).SigninToken;
  if (!token) fail("federation endpoint returned no sign-in token");
  return token;
}

function browser(session: string, args: string[], quiet = false): string {
  const res = spawnSync("agent-browser", ["--session", session, ...args], {
    encoding: "utf8",
    timeout: 120_000,
  });
  if (res.status !== 0) {
    // the login URL carries the token: never echo output of that command
    const detail = quiet ? "" : `: ${(res.stderr || res.stdout).trim()}`;
    fail(`agent-browser ${args[0]} failed${detail}`);
  }
  return res.stdout.trim();
}

function running(session: string): boolean {
  const res = spawnSync("agent-browser", ["session", "list", "--json"], {
    encoding: "utf8",
  });
  return res.status === 0 && res.stdout.includes(JSON.stringify(session));
}

function identity(): string {
  try {
    const out = execFileSync(
      "aws",
      ["sts", "get-caller-identity", "--output", "json"],
      {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
        timeout: 60_000,
      },
    );
    const id = JSON.parse(out) as { Account: string; Arn: string };
    return `${id.Arn} (account ${id.Account})`;
  } catch {
    return "unknown identity";
  }
}

// the dashboard is optional: a failure is a warning
function dashboard(): string {
  const port = process.env.PI_SAFE_DASHBOARD_PORT || "4848";
  const res = spawnSync(
    "agent-browser",
    ["dashboard", "start", "--port", port],
    {
      encoding: "utf8",
      timeout: 30_000,
    },
  );
  const out = `${res.stdout}\n${res.stderr}`;
  const url = out.match(/https?:\/\/localhost:\d+/)?.[0];
  if (res.status === 0 && url) return url;
  const running = out.match(/already running with port (\d+)/)?.[1];
  if (running) return `http://localhost:${running}`;
  return `not started (${out.trim().split("\n").pop()})`;
}

const { destination, session } = parseArgs(process.argv.slice(2));
const profile = process.env.AWS_PROFILE;
if (!profile)
  fail(
    "AWS_PROFILE is not set. Run `aws sts get-caller-identity` first: " +
      "the user picks the profile.",
  );

const watch = dashboard();
const token = await signinToken(credentials());
const login = new URL(FEDERATION);
login.search = new URLSearchParams({
  Action: "login",
  Issuer: destination.origin,
  Destination: destination.href,
  SigninToken: token,
}).toString();

if (running(session)) {
  // the Chromium profile is chosen at launch
  console.error(
    `aws-console: session ${session} is already running; using it as is ` +
      "(close it first for the AWS browser profile).",
  );
} else {
  const dir = join(homedir(), ".cache", "agent-browser", "aws", profile);
  mkdirSync(dir, { recursive: true });
  browser(session, ["--profile", dir, "open", "about:blank"]);
}

// cookie banner: "accept all", as the console stores it
const consent = Buffer.from(
  JSON.stringify({ e: 1, p: 1, f: 1, a: 1, i: randomUUID(), v: "1" }),
).toString("base64");
const expires = String(Math.floor(Date.now() / 1000) + 365 * 24 * 3600);
browser(session, [
  "cookies",
  "set",
  "awsccc",
  consent,
  "--domain",
  ".aws.amazon.com",
  "--path",
  "/",
  "--secure",
  "--expires",
  expires,
]);

browser(session, ["open", login.href], true);
const url = new URL(browser(session, ["get", "url"]));
console.log(`Dashboard: ${watch} (session ${session})`);
if (url.hostname.startsWith("signin.") || url.pathname.includes("/signin")) {
  fail(`not signed in, the browser is at ${url.origin}${url.pathname}`, 1);
}
console.log(`Signed in: ${identity()}, profile ${profile}`);
console.log(`Opened: ${url.href}`);
