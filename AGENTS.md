# AGENTS.md

## Build/Lint/Test Commands

This is a dotfiles repository - no traditional build commands exist.

**Formatting:**
- Lua: `stylua` (2 spaces indentation)
- JS/TS/HTML/CSS/JSON/YAML/Markdown: `prettier`
- Python: `ruff_format` + `ruff_fix`
- Go: `gofmt`
- Fish: `fish_indent`
- OCaml: `ocamlformat`

**Linting:**
- JS/TS: ESLint (auto-fix enabled)
- Python: Ruff

**Testing:**
- No test commands (configuration repository)

## Code Style Guidelines

- **Formatting**: Auto-formatted on save via Neovim conform.nvim
- **Indentation**: 2 spaces for Lua, language defaults otherwise
- **Imports**: Follow language conventions
- **Naming**: Standard conventions (camelCase for JS/TS, snake_case for Python, etc.)
- **Types**: TypeScript preferred, type annotations encouraged
- **Error Handling**: Language-appropriate patterns
- **Comments**: Minimal, only when necessary for clarity

## Repository Conventions

- **Git**: main branch default, rebase on pull, rerere enabled
- **Editor**: Neovim with lazy.nvim plugin manager
- **Theme**: Tokyo Night
- **Shell**: Fish with custom functions