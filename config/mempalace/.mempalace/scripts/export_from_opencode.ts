#!/usr/bin/env bun
/**
 * export_to_mempalace.ts
 *
 * Exports OpenCode session history from opencode.db to Markdown transcripts
 * that MemPalace can mine as conversations.
 *
 * Usage:
 *   bun run export_to_mempalace.ts --since 2026-04-01 [options]
 *
 * See README.md for full option reference.
 */

import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { join, resolve } from "node:path";

// ── types ────────────────────────────────────────────────────────────────────

export type SessionRow = {
  id: string;
  directory: string;
  title: string;
  time_created: number;
};

type MessageRow = {
  id: string;
  data: string;
};

type PartTextRow = {
  text: string;
};

export type MessageData = {
  role: "user" | "assistant" | string;
  agent?: string;
};

export type SessionMessage = {
  role: string;
  agent?: string;
  textParts: string[];
};

// ── pure helpers ─────────────────────────────────────────────────────────────

/**
 * Derive a filesystem-safe project label from a directory path.
 * Takes the last 2 path segments joined by "__".
 */
export function projectLabel(directory: string): string {
  const parts = directory.replace(/\\/g, "/").split("/").filter(Boolean);
  const label =
    parts.length >= 2
      ? `${parts[parts.length - 2]}__${parts[parts.length - 1]}`
      : (parts[parts.length - 1] ?? "unknown");
  return label.replace(/[^\w\-.]/g, "_").slice(0, 80).replace(/^_+|_+$/g, "");
}

/**
 * Format epoch milliseconds to "YYYY-MM-DD HH:MM UTC".
 */
export function formatDate(epochMs: number): string {
  return new Date(epochMs).toISOString().slice(0, 16).replace("T", " ") + " UTC";
}

/**
 * Returns true if the directory should be excluded based on the given prefix list.
 * Each pattern is matched as an exact path or a path prefix (slash-boundary safe).
 */
export function isDirectoryExcluded(directory: string, excludeDirs: string[]): boolean {
  return excludeDirs.some(
    (pattern) => directory === pattern || directory.startsWith(pattern + "/")
  );
}

/**
 * Returns true if all messages in the session belong to excluded agents.
 * A session with no messages is not excluded.
 */
export function isAgentExcluded(messages: SessionMessage[], excludeAgents: string[]): boolean {
  if (messages.length === 0 || excludeAgents.length === 0) return false;
  return messages.every((m) => m.agent !== undefined && excludeAgents.includes(m.agent));
}

/**
 * Convert a session and its messages into a Markdown conversation transcript.
 */
export function sessionToMarkdown(
  session: SessionRow,
  messages: SessionMessage[]
): string {
  const lines: string[] = [
    `# ${session.title}`,
    "",
    `- **project:** ${session.directory}`,
    `- **date:** ${formatDate(session.time_created)}`,
    `- **session:** ${session.id}`,
    "",
  ];

  for (const msg of messages) {
    const heading = msg.role === "user" ? "## User" : "## Assistant";
    lines.push(heading, "");
    if (msg.textParts.length > 0) {
      lines.push(msg.textParts.join("\n\n"));
    } else {
      lines.push("*(no text content)*");
    }
    lines.push("");
  }

  return lines.join("\n");
}

// ── db queries ───────────────────────────────────────────────────────────────

/**
 * Return all sessions with time_created >= sinceMs, ordered by date ascending.
 */
export function querySessions(db: Database, sinceMs: number): SessionRow[] {
  return db
    .query<SessionRow, [number]>(
      `SELECT id, directory, title, time_created
       FROM session
       WHERE time_created >= ?
       ORDER BY time_created ASC`
    )
    .all(sinceMs);
}

/**
 * Return all messages for a session, each with their text parts.
 * Only includes parts of type "text" with non-empty content.
 */
export function querySessionMessages(
  db: Database,
  sessionId: string
): SessionMessage[] {
  const messages = db
    .query<MessageRow, [string]>(
      `SELECT id, data
       FROM message
       WHERE session_id = ?
       ORDER BY time_created ASC`
    )
    .all(sessionId);

  return messages.map((msg) => {
    const data = JSON.parse(msg.data) as MessageData;
    const textParts = db
      .query<PartTextRow, [string]>(
        `SELECT json_extract(data, '$.text') AS text
         FROM part
         WHERE message_id = ?
           AND json_extract(data, '$.type') = 'text'
           AND json_extract(data, '$.text') IS NOT NULL
           AND trim(json_extract(data, '$.text')) != ''
         ORDER BY time_created ASC`
      )
      .all(msg.id)
      .map((p) => p.text);

    return { role: data.role, agent: data.agent, textParts };
  });
}

// ── arg parsing ──────────────────────────────────────────────────────────────

const HOME = process.env.HOME ?? "~";

const DEFAULT_EXCLUDE_DIRS = [
  `${HOME}/.aws`,
  `${HOME}/.duckdb`,
  `${HOME}/.local/share/opencode/log`,
  `${HOME}/Downloads`,
  `${HOME}/Documents/notes`,
];

function expandHome(p: string): string {
  return p.replace(/^~/, HOME).replace(/\/$/, "");
}

function parseArgs() {
  const argv = Bun.argv.slice(2);

  const date = new Date().toISOString().slice(0, 10);
  const result = {
    since: null as string | null,
    out: `${HOME}/.mempalace/scripts/${date}_opencode_sessions_export`,
    db: `${HOME}/.local/share/opencode/opencode.db`,
    dryRun: false,
    excludeDirs: [...DEFAULT_EXCLUDE_DIRS],
    excludeAgents: ["translate", "chrome", "browser"] as string[],
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--dry-run") {
      result.dryRun = true;
    } else if (arg === "--since" && argv[i + 1]) {
      result.since = argv[++i];
    } else if (arg === "--out" && argv[i + 1]) {
      result.out = argv[++i];
    } else if (arg === "--db" && argv[i + 1]) {
      result.db = argv[++i];
    } else if (arg === "--exclude-dirs" && argv[i + 1]) {
      result.excludeDirs = argv[++i].split(",").map((s) => expandHome(s.trim()));
    } else if (arg === "--exclude-agents" && argv[i + 1]) {
      result.excludeAgents = argv[++i].split(",").map((s) => s.trim());
    } else if (arg === "--help" || arg === "-h") {
      console.log(
        [
          "Usage: bun run export_to_mempalace.ts --since <date> [options]",
          "",
          "Options:",
          "  --since            YYYY-MM-DD or epoch-ms       (required)",
          "  --out              output directory              (default: ~/.mempalace/scripts/<date>_opencode_sessions_export)",
          "  --db               path to opencode.db          (default: ~/.local/share/opencode/opencode.db)",
          "  --exclude-dirs     comma-separated dir prefixes to skip",
          `                     (default: ${DEFAULT_EXCLUDE_DIRS.map((d) => d.replace(HOME, "~")).join(", ")})`,
          "  --exclude-agents   comma-separated agent names to skip (default: translate,chrome,browser)",
          "  --dry-run          list sessions without writing files",
        ].join("\n")
      );
      process.exit(0);
    }
  }

  return result;
}

function parseSince(value: string): number {
  const asInt = parseInt(value, 10);
  if (!isNaN(asInt) && String(asInt) === value) return asInt;
  const ms = Date.parse(value);
  if (isNaN(ms)) throw new Error(`Invalid --since value: ${value}`);
  return ms;
}

async function confirm(prompt: string): Promise<boolean> {
  process.stdout.write(`${prompt} [y/N] `);
  for await (const line of console) {
    return line.trim().toLowerCase() === "y" || line.trim().toLowerCase() === "yes";
  }
  return false;
}

// ── main ─────────────────────────────────────────────────────────────────────

if (import.meta.main) {
  const args = parseArgs();

  if (!args.since) {
    console.error("Error: --since is required. Example: --since 2026-04-01");
    process.exit(1);
  }

  const sinceMs = parseSince(args.since);
  const outRoot = resolve(expandHome(args.out));
  const sinceStr = new Date(sinceMs).toISOString().slice(0, 10);

  const displayDirs = args.excludeDirs.map((d) => d.replace(HOME, "~"));

  console.log("");
  console.log("Export configuration:");
  console.log(`  since:          ${sinceStr}`);
  console.log(`  output:         ${outRoot.replace(HOME, "~")}`);
  console.log(`  db:             ${args.db.replace(HOME, "~")}`);
  console.log(`  exclude dirs:   ${displayDirs.join(", ")}`);
  console.log(`  exclude agents: ${args.excludeAgents.join(", ")}`);
  if (args.dryRun) console.log(`  mode:           dry-run`);
  console.log("");

  const ok = await confirm("Proceed?");
  if (!ok) {
    console.log("Aborted.");
    process.exit(0);
  }

  console.log(`\nOpening DB: ${args.db.replace(HOME, "~")}`);
  const db = new Database(args.db, { readonly: true });

  console.log(`Listing sessions (created >= ${sinceStr}) ...`);
  const sessions = querySessions(db, sinceMs);
  console.log(`Found ${sessions.length} sessions on/after ${sinceStr}.`);

  if (sessions.length === 0) {
    console.log("Nothing to export.");
    process.exit(0);
  }

  if (args.dryRun) {
    console.log("\n[dry-run] Sessions that would be exported:");
    for (const s of sessions) {
      if (isDirectoryExcluded(s.directory, args.excludeDirs)) continue;
      const messages = querySessionMessages(db, s.id);
      if (isAgentExcluded(messages, args.excludeAgents)) continue;
      const date = new Date(s.time_created).toISOString().slice(0, 10);
      console.log(`  ${date}  ${s.id}  ${s.directory}  ${s.title.slice(0, 60)}`);
    }
    db.close();
    process.exit(0);
  }

  let exported = 0;
  let skipped = 0;
  let errors = 0;

  for (const session of sessions) {
    if (isDirectoryExcluded(session.directory, args.excludeDirs)) {
      console.log(`  skip    ${session.id} (excluded directory: ${session.directory})`);
      skipped++;
      continue;
    }

    const label = projectLabel(session.directory);
    const outDir = join(outRoot, label);
    const outFile = join(outDir, `${session.id}.md`);

    if (await Bun.file(outFile).exists()) {
      console.log(`  skip    ${session.id} (already exported)`);
      skipped++;
      continue;
    }

    const date = new Date(session.time_created).toISOString().slice(0, 10);
    process.stdout.write(`  export  ${date}  ${session.id}  ${session.title.slice(0, 50)}`);

    try {
      const messages = querySessionMessages(db, session.id);

      if (isAgentExcluded(messages, args.excludeAgents)) {
        console.log(`  (excluded agent, skipped)`);
        skipped++;
        continue;
      }

      const hasText = messages.some((m) => m.textParts.length > 0);
      if (!hasText) {
        console.log("  (no text content, skipped)");
        skipped++;
        continue;
      }

      const md = sessionToMarkdown(session, messages);
      mkdirSync(outDir, { recursive: true });
      await Bun.write(outFile, md);
      console.log(`  -> ${label}/${session.id}.md`);
      exported++;
    } catch (err) {
      console.log(`  ERROR: ${err}`);
      errors++;
    }
  }

  db.close();
  console.log(`\nDone. Exported: ${exported}, Skipped: ${skipped}, Errors: ${errors}`);
  if (errors > 0) process.exit(1);
}
