# OpenCode Instructions

## Search Tool Preferences

**IMPORTANT**: Always prefer ck-search MCP tools over standard search tools when available:

- **Semantic/Conceptual searches**: Use `ck-search_semantic_search` to find code by meaning
- **Complex code queries**: Use `ck-search_hybrid_search` for best results combining semantic + regex
- **Text pattern searches**: Use `ck-search_regex_search` instead of `grep` tool
- **Keyword/term searches**: Use `ck-search_lexical_search` for BM25-ranked results

Only fall back to standard `grep` tool if:
- ck-search is unavailable/unhealthy
- Search is outside an indexed codebase
- Simple file name patterns (use `glob` instead)

**Examples:**
- "Find error handling code" → `ck-search_semantic_search`
- "Search for TODO comments" → `ck-search_regex_search`
- "Find authentication logic" → `ck-search_hybrid_search`
