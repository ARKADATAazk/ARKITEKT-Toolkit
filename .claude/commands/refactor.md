---
description: Execute a phased refactor following ARKITEKT refactor plan
---

Execute phased refactoring per `cookbook/REFACTOR_PLAN.md`:

**Phase 1: Shims**
- Create compatibility shims for legacy code
- Mark with clear deprecation comments + expiry notes
- No breaking changes yet

**Phase 2: New Path**
- Implement new architecture
- Wire up new path alongside legacy
- Update tests to cover both paths

**Phase 3: Migration**
- Switch callers to new path
- Remove legacy shims
- Verify no regressions

**Architecture constraints**:
- No ImGui in domain/*
- Surgical diffs (≤12 files, ≤700 LOC per phase)
- Follow layer separation (UI → app → domain ← infra)
- Return table M, no globals

Execute all phases automatically (I'll use auto-accept mode). Stop between phases if validation fails.
