## Fina RAG Knowledge Base

**Graph-first (Fina).** Before substantive claims about this project, query the Fina graph: `mcp_fina_query_project_context` for concepts/decisions/issues, `mcp_fina_query_knowledge` for notes. Cite what you find. Fall back to training only after exhausting Fina or to enhance what's already there — rework costs more than the query.

**Roadmap — use it.** `_fina_tasks` per partition is canonical planned work, durable across sessions.
- Orient: `mcp_fina_list_tasks` at start of substantive work; cross-reference user requests before filing new tasks.
- **Never execute `needs_refinement` tasks.** They need user clarification. Use `mcp_fina_add_task_question` (asked_by=llm) to raise blockers; `mcp_fina_resolve_task_question` + `mcp_fina_update_task` to clear them.
- File discovered bugs/features via `mcp_fina_create_task` (kind fix/feature). Don't only chat them.
- On ship: `mcp_fina_complete_task` with `milestone_id` + `ship_version`. No silent status flips.
- `_fina_tasks` beats in-memory todos — in-memory is session-local, `_fina_tasks` is durable and shared.

### Session Workflow

**Start of every task:** Call `mcp_fina_query_project_context` with a description of what you're about to do. Read the `suggested_reads` before opening files. This avoids re-reading files the project already knows about.

**During work:** Record knowledge *as you work*, not at the end:
- Fixed a bug → immediately call `mcp_fina_record_milestone` with files and concepts
- Made a design decision → immediately call `mcp_fina_record_decision` with rationale
- Found a gotcha → immediately call `mcp_fina_remember` with tags: "gotcha"
- Learned how files relate → immediately call `mcp_fina_record_milestone`
- User told you something important → immediately call `mcp_fina_remember`

**End of task:** Call `mcp_fina_record_milestone` summarizing what was done, which files were involved, and why. Link to concepts.

This is not optional. Every session should leave the graph richer than it found it.

### Reading

1. **Start with the graph** — call `mcp_fina_query_project_context` before reading files.
2. **Then check partitions** — call `mcp_fina_query_knowledge` on the project partition, then `global`.
3. **Only then read files** — and only the ones suggested by the graph or not covered by existing knowledge.

### Writing

Write prolifically to the partition you're working in. **Never write to `global` unless the user explicitly asks.**

- Working in a project → project partition
- Working with a skill → skill partition
- Working with an agent → agent partition

Do NOT record: raw code, git history, trivial facts derivable from the code.
