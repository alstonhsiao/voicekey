# Agent Governance Refactor Report

- Generated: 2026-04-21 23:58:54
- Project: `voicekey`

## Phase 1

### A. Structure Diagnosis Summary
- Legacy AGENTS tended to mix governance rules, historical logs, and operational details in one file.
- This caused token growth and inconsistent entry behavior for new agents.
- Refactor splits high-frequency governance from detailed, high-growth content.

### B. Classification Table
| Original Section/Theme | Classification | New Location | Reason |
|---|---|---|---|
| Project background / purpose | KEEP_IN_AGENTS | `AGENTS.md` | Needed by every new agent session. |
| High-risk constraints / non-negotiables | KEEP_IN_AGENTS | `AGENTS.md + agent-operations.md` | Directly impacts safe execution. |
| Detailed architecture / stack / key paths | MOVE_TO_MODULE | `agent-context.md` | Useful but too detailed for hub. |
| Operational steps / validation details | MOVE_TO_MODULE | `agent-operations.md` | Frequent but better as focused playbook. |
| Recent progress / open issues | MOVE_TO_MODULE | `agent-progress.md` | High growth and time-sensitive. |
| Historical long-form AGENTS content | REPLACE_WITH_LINK | `agent-legacy-archive.md` | Preserved for audit, not daily reading. |
| Unclear or conflicting statements | NEED_REVIEW | `agent-progress.md` | Must be reviewed before destructive decisions. |

### C. Refactored AGENTS.md
- Final hub file: `AGENTS.md` (already applied).

### D. Module File Design
| File | Purpose |
|---|---|
| `agent-context.md` | Stable context, stack profile, and key paths. |
| `agent-operations.md` | Rules, execution order, and validation baseline. |
| `agent-progress.md` | Recent progress and unresolved issues. |
| `agent-refactor-report.md` | This migration report and metrics. |

### E. Module Drafts
- Implemented as concrete files listed above.

### F. Migration Summary
- Kept in hub: mission, always-on rules, execution flow, quick map.
- Moved out: detailed context, operations detail, progress/TODO, historical logs.
- Link-based: legacy AGENTS archive and spoke indexes.
- Archive recommendation: keep `agent-legacy-archive.md` until next major governance review.
- NEED_REVIEW items: ambiguous requirements or stale history are tracked in `agent-progress.md`.

## Phase 2

### Phase 1: Exploration (Read-only Findings)
- No high token-cost core directory met threshold; no new spoke index required.

### Phase 2: Spokes Created
- None (threshold not met).

### Phase 3: Hub Quick Map Update
- `AGENTS.md` quick map now includes all module files and spoke indexes.

### Phase 4: Validation
1. Spokes created: 0 index file(s) + module files in project root.
2. AGENTS.md changes: rewritten as governance hub with quick map and escalation rules.
3. Estimated reading load for common tasks: before ~22.0 KB, after ~1.4 KB.
   - Before assumption: hub + ~0 file reads across high-cost dirs.
   - After assumption: hub + relevant `INDEX.md` files first, then targeted deep reads only.
