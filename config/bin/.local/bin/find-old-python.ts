#!/usr/bin/env bun

import { spawn } from "bun";
import { accessSync, constants, lstatSync, statSync, unlinkSync } from "fs";
import * as readline from "readline";

// ── CLI parsing ───────────────────────────────────────────────────────────────

const args = process.argv.slice(2);

if (args.includes("--help") || args.includes("-h")) {
  console.log(`
find-old-python — scan the entire disk for Python installations below a version threshold

USAGE
  find-old-python [options]

OPTIONS
  --below <version>   Version threshold, exclusive (default: 3.13)
  --clean             Remove violations and broken symlinks (never touches non-executables)
  --yes               Skip confirmation prompts (use with --clean)
  --verbose           Also show non-executable matches (man pages, dylibs, etc.)
  --help              Show this help

EXAMPLES
  find-old-python                    # find all Python < 3.13
  find-old-python --below 3.12       # find all Python < 3.12
  find-old-python --clean            # find and interactively remove
  find-old-python --clean --yes      # find and remove all without prompts (CI)
  find-old-python --verbose          # also show non-executable matches

EXIT CODES
  0   Compliant — no violations found
  1   Violations found (or remaining after partial clean)
  2   Script error (fd not found, etc.)
`);
  process.exit(0);
}

const cleanFlag   = args.includes("--clean");
const yesFlag     = args.includes("--yes");
const verboseFlag = args.includes("--verbose");

let belowVersion = "3.13";
const belowIdx = args.indexOf("--below");
if (belowIdx !== -1 && args[belowIdx + 1]) {
  belowVersion = args[belowIdx + 1];
}

// ── Colors ────────────────────────────────────────────────────────────────────

const RESET  = "\x1b[0m";
const BOLD   = "\x1b[1m";
const RED    = "\x1b[31m";
const YELLOW = "\x1b[33m";
const GREEN  = "\x1b[32m";
const DIM    = "\x1b[2m";
const CYAN   = "\x1b[36m";

// ── Version utilities ─────────────────────────────────────────────────────────

function parseVersion(str: string): number[] | null {
  const match = str.match(/(\d+)\.(\d+)(?:\.(\d+))?/);
  if (!match) return null;
  return [parseInt(match[1]), parseInt(match[2]), parseInt(match[3] ?? "0")];
}

function compareVersions(a: number[], b: number[]): number {
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const diff = (a[i] ?? 0) - (b[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

const thresholdParts = parseVersion(belowVersion);
if (!thresholdParts) {
  console.error(`Invalid version threshold: ${belowVersion}`);
  process.exit(2);
}

function isBelowThreshold(version: number[]): boolean {
  const threshold: number[] = [thresholdParts![0], thresholdParts![1], thresholdParts![2] ?? 0];
  return compareVersions(version, threshold) < 0;
}

// ── Origin detection ──────────────────────────────────────────────────────────

function detectOrigin(p: string): string {
  if (p.includes("/Cellar/")) {
    const m = p.match(/\/Cellar\/([^/]+)\//);
    return m ? `homebrew:${m[1]}` : "homebrew";
  }
  if (p.startsWith("/opt/homebrew/")) return "homebrew";
  if (p.includes("/.cache/uv/"))     return "uv";
  if (p.includes("/.pyenv/"))        return "pyenv";
  if (p.includes("/.asdf/"))         return "asdf";
  if (p.includes("/.lmstudio/"))     return "lmstudio";
  if (p.includes("/Library/ManagedFrameworks/")) return "macos-managed";
  if (p.includes("/Library/Frameworks/"))        return "python.org";
  if (p.includes("/Library/Developer/"))         return "xcode-cli";
  if (p.startsWith("/usr/bin/"))    return "macos-system";
  if (p.startsWith("/usr/local/"))  return "manual";
  if (p.includes("/.venv/") || p.includes("/venv/")) return "virtualenv";
  return "unknown";
}

// ── Result types ──────────────────────────────────────────────────────────────

type Violation = { kind: "violation"; path: string; version: string; origin: string };
type Broken    = { kind: "broken";    path: string; origin: string };
type NonExec   = { kind: "non-executable"; path: string; origin: string };
type Result    = Violation | Broken | NonExec;

// ── Filesystem helpers ────────────────────────────────────────────────────────

function isBrokenSymlink(p: string): boolean {
  try {
    const lst = lstatSync(p);
    if (!lst.isSymbolicLink()) return false;
    statSync(p); // follows the symlink — throws if target missing
    return false;
  } catch {
    return true;
  }
}

function isExecutable(p: string): boolean {
  try {
    accessSync(p, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

// Async version check — spawns python binary and awaits output
async function getVersionString(p: string): Promise<string | null> {
  try {
    const proc = spawn([p, "--version"], { stdout: "pipe", stderr: "pipe" });
    const [stdout, stderr] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    await proc.exited;
    return stdout.trim() || stderr.trim() || null;
  } catch {
    return null;
  }
}

// ── Concurrency semaphore ─────────────────────────────────────────────────────

function makeSemaphore(limit: number) {
  let active = 0;
  const queue: Array<() => void> = [];

  return async function<T>(fn: () => Promise<T>): Promise<T> {
    if (active >= limit) {
      await new Promise<void>((resolve) => queue.push(resolve));
    }
    active++;
    try {
      return await fn();
    } finally {
      active--;
      queue.shift()?.();
    }
  };
}

// ── Progress spinner ──────────────────────────────────────────────────────────

function makeProgress() {
  const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  let frame = 0;
  let scanned = 0;
  let found = 0;
  let timer: ReturnType<typeof setInterval> | null = null;

  function render() {
    const spinner = frames[frame % frames.length];
    process.stderr.write(
      `\r${DIM}${spinner} scanned: ${scanned}   found: ${found}${RESET}  `
    );
    frame++;
  }

  return {
    start() {
      timer = setInterval(render, 80);
    },
    tick(didFind: boolean) {
      scanned++;
      if (didFind) found++;
    },
    stop() {
      if (timer) clearInterval(timer);
      process.stderr.write(`\r\x1b[2K`);
    },
    get scanned() {
      return scanned;
    },
  };
}

// ── Print report (buffered, grouped by section) ───────────────────────────────

const PATH_COL    = 120;
const VERSION_COL = 10;

function col(s: string, width: number): string {
  return s.length >= width ? s.slice(0, width - 1) + " " : s.padEnd(width);
}

function printReport(results: Result[]) {
  const violations = results
    .filter((r): r is Violation => r.kind === "violation")
    .sort((a, b) => a.version.localeCompare(b.version, undefined, { numeric: true }));
  const broken  = results.filter((r): r is Broken  => r.kind === "broken");
  const nonExec = results.filter((r): r is NonExec => r.kind === "non-executable");

  if (violations.length > 0) {
    console.log(`\n${BOLD}${RED}VIOLATIONS (${violations.length}) — NOT COMPLIANT${RESET}`);
    console.log(`${BOLD}${col("VERSION", VERSION_COL)}${col("PATH", PATH_COL)}ORIGIN${RESET}`);
    for (const v of violations) {
      console.log(`${RED}${col(v.version, VERSION_COL)}${RESET}${col(v.path, PATH_COL)}${DIM}${v.origin}${RESET}`);
    }
  }

  if (broken.length > 0) {
    console.log(`\n${BOLD}${YELLOW}BROKEN SYMLINKS (${broken.length})${RESET}`);
    console.log(`${BOLD}${col("PATH", PATH_COL)}ORIGIN${RESET}`);
    for (const b of broken) {
      console.log(`${YELLOW}${col(b.path, PATH_COL)}${RESET}${DIM}${b.origin}${RESET}`);
    }
  }

  if (verboseFlag && nonExec.length > 0) {
    console.log(`\n${BOLD}${DIM}NON-EXECUTABLE MATCHES (${nonExec.length}) — informational${RESET}`);
    console.log(`${BOLD}${col("PATH", PATH_COL)}ORIGIN${RESET}`);
    for (const n of nonExec) {
      console.log(`${DIM}${col(n.path, PATH_COL)}${n.origin}${RESET}`);
    }
  }
}

// ── Process a single path (async) ─────────────────────────────────────────────

async function processPath(p: string): Promise<Result | null> {
  const origin = detectOrigin(p);

  if (isBrokenSymlink(p)) {
    return { kind: "broken", path: p, origin };
  }

  if (!isExecutable(p)) {
    return { kind: "non-executable", path: p, origin };
  }

  const versionOutput = await getVersionString(p);
  if (!versionOutput) {
    return { kind: "non-executable", path: p, origin };
  }

  const parsed = parseVersion(versionOutput);
  if (!parsed) {
    return { kind: "non-executable", path: p, origin };
  }

  if (isBelowThreshold(parsed)) {
    const versionMatch = versionOutput.match(/\d+\.\d+(?:\.\d+)?/);
    return {
      kind: "violation",
      path: p,
      version: versionMatch ? versionMatch[0] : versionOutput,
      origin,
    };
  }

  // Compliant — not a violation
  return null;
}

// ── Cleanup ───────────────────────────────────────────────────────────────────

async function confirm(message: string): Promise<boolean> {
  if (yesFlag) return true;
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(`${message} [y/N] `, (answer) => {
      rl.close();
      resolve(answer.trim().toLowerCase() === "y");
    });
  });
}

async function cleanResults(
  violations: Violation[],
  broken: Broken[],
): Promise<{ removed: number; skipped: number }> {
  let removed = 0;
  let skipped = 0;

  console.log(`\n${BOLD}CLEANUP${RESET}`);

  const cleanable: Result[] = [...violations, ...broken];

  for (const r of cleanable) {
    const label =
      r.kind === "violation"
        ? `${RED}[violation ${(r as Violation).version}]${RESET}`
        : `${YELLOW}[broken symlink]${RESET}`;

    const ok = await confirm(`Remove ${label} ${CYAN}${r.path}${RESET}?`);
    if (ok) {
      try {
        unlinkSync(r.path);
        console.log(`  ${GREEN}Removed.${RESET}`);
        removed++;
      } catch (err: any) {
        console.log(`  ${RED}Failed: ${err.message}${RESET}`);
        skipped++;
      }
    } else {
      console.log(`  ${DIM}Skipped.${RESET}`);
      skipped++;
    }
  }

  return { removed, skipped };
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  // Check fd is available
  const fdCheck = spawn(["which", "fd"], { stdout: "pipe", stderr: "pipe" });
  await fdCheck.exited;
  if (fdCheck.exitCode !== 0) {
    console.error("Error: 'fd' is required but not found in PATH. Install with: brew install fd");
    process.exit(2);
  }

  console.log(`${BOLD}Scanning for Python installations below ${belowVersion}...${RESET}`);
  console.log(`${DIM}Scanning entire disk, results will appear when complete.${RESET}`);

  const progress  = makeProgress();
  const semaphore = makeSemaphore(32);
  const results: Result[] = [];
  const tasks: Promise<void>[] = [];

  // Start fd
  const fd = spawn([
    "fd",
    "--unrestricted",
    "--regex", "^python[0-9.]*$",
    "/",
    "--exclude", "/System",
    "--exclude", "/private",
    "--exclude", "*.app",
    "--type", "f",
    "--type", "l",
  ], { stdout: "pipe", stderr: "pipe" });

  progress.start();

  const decoder = new TextDecoder();
  let buffer = "";

  for await (const chunk of fd.stdout) {
    buffer += decoder.decode(chunk, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      const p = line.trim();
      if (!p) continue;

      const task = semaphore(async () => {
        const result = await processPath(p);
        progress.tick(result !== null);
        if (result) results.push(result);
      });
      tasks.push(task);
    }
  }

  if (buffer.trim()) {
    const p = buffer.trim();
    const task = semaphore(async () => {
      const result = await processPath(p);
      progress.tick(result !== null);
      if (result) results.push(result);
    });
    tasks.push(task);
  }

  await fd.exited;
  await Promise.all(tasks);
  progress.stop();

  printReport(results);

  const violations = results.filter((r): r is Violation => r.kind === "violation");
  const broken     = results.filter((r): r is Broken    => r.kind === "broken");
  const nonExec    = results.filter((r): r is NonExec   => r.kind === "non-executable");

  const summaryParts = [
    `scanned: ${progress.scanned}`,
    `violations: ${RED}${violations.length}${RESET}`,
    `broken: ${YELLOW}${broken.length}${RESET}`,
  ];
  if (verboseFlag) {
    summaryParts.push(`non-executable: ${DIM}${nonExec.length}${RESET}`);
  }
  console.log(`\n${BOLD}SUMMARY${RESET}  ${summaryParts.join("   ")}`);

  // Run cleanup if requested (violations + broken symlinks, regardless of count)
  if (cleanFlag && (violations.length > 0 || broken.length > 0)) {
    const { removed, skipped } = await cleanResults(violations, broken);
    console.log(`\n${BOLD}CLEANUP SUMMARY${RESET}  removed: ${GREEN}${removed}${RESET}   skipped: ${DIM}${skipped}${RESET}`);
  }

  // Compliance is determined solely by violations.
  // Re-stat each violation path to account for any removed during cleanup.
  const remainingViolations = violations.filter(v => {
    try { lstatSync(v.path); return true; } catch { return false; }
  });

  if (remainingViolations.length === 0) {
    console.log(`\n${GREEN}${BOLD}COMPLIANT — no Python installations below ${belowVersion} found.${RESET}`);
    process.exit(0);
  }

  if (!cleanFlag) {
    console.log(`\n${RED}${BOLD}NOT COMPLIANT${RESET}${DIM}  run with --clean to remove violations${RESET}`);
  } else {
    console.log(`\n${RED}${BOLD}NOT COMPLIANT — ${remainingViolations.length} violation(s) remain.${RESET}`);
  }
  process.exit(1);
}

main().catch((err) => {
  console.error(`${RED}Fatal error: ${err.message}${RESET}`);
  process.exit(2);
});
