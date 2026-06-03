# scripts

## export_from_opencode.ts

Exports OpenCode session history from the local SQLite database (`opencode.db`)
to Markdown transcripts that MemPalace can mine as conversations.

Reads directly from the SQLite DB — covers all projects, no subprocess calls,
no redaction.

### Requirements

- Bun on PATH
- `opencode.db` at its default location (`~/.local/share/opencode/opencode.db`)

### Run

```sh
bun run ~/.mempalace/scripts/export_from_opencode.ts --since <date> [options]
```

### Options

| Flag               | Description                                       | Default                                                                                  |
| ------------------ | ------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `--since`          | Only export sessions from this date on (required) | —                                                                                        |
| `--out`            | Output directory for Markdown files               | `~/.mempalace/scripts/<date>_opencode_sessions_export`                                   |
| `--db`             | Path to `opencode.db`                             | `~/.local/share/opencode/opencode.db`                                                    |
| `--exclude-dirs`   | Comma-separated directory prefixes to skip        | `~/.aws`, `~/.duckdb`, `~/.local/share/opencode/log`, `~/Downloads`, `~/Documents/notes` |
| `--exclude-agents` | Comma-separated agent names to skip               | `translate`, `chrome`, `browser`                                                         |
| `--dry-run`        | List sessions without writing files               | off                                                                                      |

`--exclude-dirs` matches exact paths and their subdirectories. Passing `--exclude-dirs`
overrides the defaults entirely — include everything you want to skip.
`--exclude-agents` skips sessions where **every** message belongs to one of the listed agents.
`~` in `--exclude-dirs` values is expanded to `$HOME`.

Before starting, the script shows the active configuration and asks for confirmation.

### Example

```sh
# Export all sessions from April 2026 onwards (with confirmation prompt)
bun run ~/.mempalace/scripts/export_from_opencode.ts --since 2026-04-01

# Dry-run first to preview what would be exported
bun run ~/.mempalace/scripts/export_from_opencode.ts --since 2026-04-01 --dry-run

# Export to a custom directory, skipping additional dirs
bun run ~/.mempalace/scripts/export_from_opencode.ts \
  --since 2026-04-01 \
  --out ~/opencode-export \
  --exclude-dirs ~/.aws,~/.duckdb,~/Downloads,~/Documents/notes,~/Documents

# Exclude additional noisy agents
bun run ~/.mempalace/scripts/export_from_opencode.ts \
  --since 2026-04-01 \
  --exclude-agents translate,chrome,browser
```

### Mine into MemPalace

[MemPalace](https://mempalaceofficial.com) is a local AI memory system backed by a ChromaDB vector database.
It lets your AI recall past decisions, conversations, and context across sessions via semantic search.
Once mined, memories are available through the `mempalace_search` MCP tool and the other 28 MCP tools
exposed by the MemPalace MCP server.

**IMPORTANT: Correct mine command**

```sh
# Mine the Markdown transcripts as conversations into the palace.
# --mode convos : treats each file as a conversation export (human + assistant turns)
# The default --extract exchange uses topic keywords (technical, architecture, planning, decisions, problems)
# Do NOT use --extract general — it applies emotion/sentiment heuristics designed for personal journals,
# which misclassifies technical content as "emotional".
mempalace mine ~/.mempalace/scripts/<date>_opencode_sessions_export/ --mode convos
```

### Wipe palace (start from scratch)

To delete all indexed memory and start fresh (while preserving config), use `wipe_palace.ts`:

```sh
bun run ~/.mempalace/scripts/wipe_palace.ts
bun run ~/.mempalace/scripts/wipe_palace.ts --yes   # skip confirmation
```

This deletes:
- ChromaDB vector store (`~/.mempalace/palace/`)
- Knowledge graph (`~/.mempalace/knowledge_graph.sqlite3`)
- Lock files and WAL entries
- Entity cache

It preserves:
- `config.json` (symlink to dotfiles)
- `identity.txt` (symlink to dotfiles)
- `scripts` (symlink to dotfiles)

**Use case:** After wiping, re-mine sessions with corrected settings without duplicate drawers.

### Stow

This package is managed with GNU Stow. To symlink `~/.mempalace/scripts/` to this repo:

```sh
stow -d ~/repos/arielschiavoni/dotfiles/config -t ~ mempalace
```

### Test

```sh
bun test ~/.mempalace/scripts/export_from_opencode.test.ts
```
