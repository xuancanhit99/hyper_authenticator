# AI Agent Playbook

AGENTS.md is the repository-wide operating contract. This document explains how to apply it to long-running work.

## Harness components

- AGENTS.md: invariant rules and validation matrix.
- docs/PROJECT_STATUS.md: verified baseline and known failures.
- docs/README.md: canonical documentation map.
- docs/tasks: durable task context across sessions.
- docs/adr: durable architectural decisions.
- scripts/agent/context.sh: safe repository orientation.
- scripts/agent/doctor.sh: environment and configuration checks.
- scripts/agent/check.sh: documentation, quick, and full gates.

## Session startup

Run:

    git status --short --branch
    scripts/agent/context.sh
    scripts/agent/doctor.sh

Then read:

1. AGENTS.md.
2. PROJECT_STATUS.md.
3. The canonical document for the subsystem.
4. The nearest source, tests, and generated boundaries.

Do not begin from README claims alone.

## Task record

For non-trivial work, create:

    docs/tasks/YYYY-MM-DD-short-name.md

from docs/tasks/TEMPLATE.md.

Keep it concise and update it with:

- objective and non-goals;
- acceptance criteria;
- evidence and assumptions;
- affected contracts;
- implementation checkpoints;
- commands and outcomes;
- follow-ups.

Task records are not a substitute for canonical docs. On completion, migrate durable facts to canonical documents and close or archive the task note.

## Work loop

### 1. Frame

- Restate the user-visible outcome.
- Identify security and data-loss impact.
- List evidence needed.
- Choose a validation gate.

### 2. Inspect

- Search with rg and rg --files.
- Trace from UI to BLoC, use case, repository, and data source.
- Inspect registration lifecycle when instances cross features.
- Check platform and backend configuration.
- Distinguish current behavior from comments and planned docs.

### 3. Plan

- Use small reversible steps.
- Put tests before security-critical fixes.
- Identify migration and rollback for persisted data.
- Request owner direction only for decisions that materially change product behavior.

### 4. Implement

- Preserve unrelated changes.
- Avoid broad refactors during a bug fix.
- Never hand-edit generated DI output.
- Do not log credentials while adding diagnostics.
- Update docs as contracts change.

### 5. Verify

- Run the narrowest test during iteration.
- Run the required harness gate at completion.
- Run platform or Supabase integration checks for boundary changes.
- Compare git diff to task scope.

### 6. Handoff

Report:

- outcome first;
- files and behavior changed;
- migration or compatibility impact;
- exact validation results;
- remaining known risks;
- unrelated changes preserved.

## Evidence standard

Strong evidence:

- passing deterministic test;
- reproduced runtime output;
- direct source trace;
- generated manifest or compiled artifact inspection;
- isolated backend integration test.

Weak evidence:

- old comments;
- README feature lists;
- planned design documents;
- runner directories;
- package presence without an active call path.

Label inference as inference.

## Security-sensitive task protocol

For auth, TOTP, secure storage, sync, crypto, recovery, or RLS:

1. Identify assets and attackers.
2. Define trust boundaries.
3. Write failure and abuse cases.
4. Add negative tests.
5. Define migration, rollback, and key/data recovery.
6. Confirm logs and fixtures are redacted.
7. Update SECURITY.md.
8. Add an ADR when a long-lived decision changes.

Do not ship a partial crypto design behind a normal user toggle.

## Context management

When a task spans sessions:

- keep durable facts in the task record;
- reference file paths and symbols, not copied source;
- record the last command and result;
- record unresolved decisions separately from implementation TODOs;
- avoid storing secrets or transient tokens;
- keep PROJECT_STATUS.md reserved for repository-wide verified facts.

## Review prompts

Before declaring completion, ask:

- Can this change lose local or cloud accounts?
- Can any secret reach a log, backend field, test output, or screenshot?
- Does retry duplicate or delete data?
- Do old records still load?
- Are UI and background components using the same state owner?
- Does a configured lock fail closed?
- Are server policies version-controlled and negatively tested?
- Did behavior and canonical docs change together?

## Stop conditions

Pause and request owner direction when:

- offline versus mandatory account behavior must be chosen;
- logout data ownership changes;
- E2EE recovery policy is undecided;
- a migration can irreversibly delete plaintext or ciphertext;
- supported platform claims change;
- legal, store, or external production configuration must be approved.

Continue independently for read-only investigation, tests, safe refactors, and changes within an already accepted contract.
