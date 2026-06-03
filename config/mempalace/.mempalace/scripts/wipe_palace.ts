#!/usr/bin/env bun
/**
 * wipe_palace.ts
 *
 * Wipes MemPalace memory databases while preserving configuration.
 * Deletes all indexed content (drawers, facts, entities) but keeps:
 *   - ~/.mempalace/config.json (linked to dotfiles)
 *   - ~/.mempalace/identity.txt (your AI identity)
 *   - ~/.mempalace/scripts (linked to dotfiles)
 *
 * Usage:
 *   bun run wipe_palace.ts
 *   bun run wipe_palace.ts --yes   (skip confirmation)
 *
 * Use this to start fresh before re-mining sessions with corrected settings.
 */

import { rmSync, existsSync } from "node:fs";
import { resolve } from "node:path";

// ── types ────────────────────────────────────────────────────────────────────

interface WipeConfig {
  palaceDir: string;
  mempalaceDir: string;
  skipConfirm: boolean;
}

interface WipeResult {
  deleted: string[];
  skipped: string[];
  errors: Array<{ path: string; error: string }>;
}

// ── helpers ──────────────────────────────────────────────────────────────────

const HOME = process.env.HOME ?? "~";

function expandHome(p: string): string {
  return p.replace(/^~/, HOME);
}

function parseArgs(): WipeConfig {
  const argv = Bun.argv.slice(2);
  return {
    palaceDir: expandHome("~/.mempalace/palace"),
    mempalaceDir: expandHome("~/.mempalace"),
    skipConfirm: argv.includes("--yes"),
  };
}

async function confirm(prompt: string): Promise<boolean> {
  process.stdout.write(`${prompt} [y/N] `);
  for await (const line of console) {
    return line.trim().toLowerCase() === "y" || line.trim().toLowerCase() === "yes";
  }
  return false;
}

function formatPath(p: string): string {
  return p.replace(HOME, "~");
}

// ── wipe logic ───────────────────────────────────────────────────────────────

/**
 * List of paths to delete relative to ~/.mempalace.
 * Config files (config.json, identity.txt, scripts) are NOT included.
 */
function getPaths(mempalaceDir: string): string[] {
  return [
    // ChromaDB vector store
    `${mempalaceDir}/palace/chroma.sqlite3`,
    `${mempalaceDir}/palace/palace.db`,
    `${mempalaceDir}/palace/.blob_seq_ids_migrated`,

    // ChromaDB segment data directory
    `${mempalaceDir}/palace/af0df5d6-9025-4e14-958c-8d0e6611cade`,

    // Palace metadata (corpus origin detection — auto-regenerated on next mine)
    `${mempalaceDir}/palace/.mempalace/origin.json`,

    // Knowledge graph
    `${mempalaceDir}/knowledge_graph.sqlite3`,
    `${mempalaceDir}/knowledge_graph.sqlite3-shm`,
    `${mempalaceDir}/knowledge_graph.sqlite3-wal`,

    // Lock files (entire directory)
    `${mempalaceDir}/locks`,

    // WAL files
    `${mempalaceDir}/wal`,

    // Entity cache
    `${mempalaceDir}/known_entities.json`,
  ];
}

function wipe(config: WipeConfig): WipeResult {
  const result: WipeResult = {
    deleted: [],
    skipped: [],
    errors: [],
  };

  const paths = getPaths(config.mempalaceDir);

  for (const path of paths) {
    try {
      if (existsSync(path)) {
        rmSync(path, { recursive: true, force: true });
        result.deleted.push(path);
      } else {
        result.skipped.push(path);
      }
    } catch (err) {
      result.errors.push({
        path,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  return result;
}

// ── main ─────────────────────────────────────────────────────────────────────

if (import.meta.main) {
  const config = parseArgs();

  console.log("");
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("  MemPalace Wipe — Delete all indexed memory");
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("");
  console.log("This will delete:");
  console.log("  • ChromaDB vector store (~/.mempalace/palace/chroma.sqlite3)");
  console.log("  • Knowledge graph (~/.mempalace/knowledge_graph.sqlite3)");
  console.log("  • Lock files (~/.mempalace/locks/)");
  console.log("  • WAL files (~/.mempalace/wal/)");
  console.log("  • Entity cache (~/.mempalace/known_entities.json)");
  console.log("");
  console.log("Preserved:");
  console.log("  ✓ config.json (symlink to dotfiles)");
  console.log("  ✓ identity.txt (symlink to dotfiles)");
  console.log("  ✓ scripts (symlink to dotfiles)");
  console.log("");

  const ok = config.skipConfirm || (await confirm("Proceed with wipe?"));
  if (!ok) {
    console.log("Aborted.");
    process.exit(0);
  }

  console.log("Wiping palace...\n");
  const result = wipe(config);

  if (result.deleted.length > 0) {
    console.log(`Deleted ${result.deleted.length} items:`);
    for (const path of result.deleted) {
      console.log(`  ✓ ${formatPath(path)}`);
    }
    console.log("");
  }

  if (result.skipped.length > 0) {
    console.log(`Skipped ${result.skipped.length} items (not found):`);
    for (const path of result.skipped) {
      console.log(`  - ${formatPath(path)}`);
    }
    console.log("");
  }

  if (result.errors.length > 0) {
    console.log(`Errors (${result.errors.length}):`);
    for (const { path, error } of result.errors) {
      console.log(`  ✗ ${formatPath(path)}: ${error}`);
    }
    console.log("");
    process.exit(1);
  }

  console.log("═══════════════════════════════════════════════════════════════");
  console.log("  Done. Palace wiped. You can now re-mine with:");
  console.log("  mempalace mine ~/.mempalace/scripts/<date>_export --mode convos");
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("");
}
