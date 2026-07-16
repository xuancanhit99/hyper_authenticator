# Contributing

This repository treats documentation, security behavior, and data contracts as part of the product.

## Before starting

1. Read AGENTS.md.
2. Run scripts/agent/context.sh.
3. Read docs/PROJECT_STATUS.md and the canonical document for the area being changed.
4. Inspect git status and preserve unrelated user changes.
5. For non-trivial work, copy docs/tasks/TEMPLATE.md to a dated task note and record scope, risks, and validation.

## Change workflow

1. Define observable acceptance criteria.
2. Add or update tests before changing a security-critical or data-loss-sensitive path.
3. Keep Presentation, Domain, and Data responsibilities separate.
4. Never log TOTP secrets, otpauth URIs, passwords, session tokens, encryption keys, salts, or recovery material.
5. Update generated Injectable output when dependency annotations change.
6. Update documentation in the same change when behavior, configuration, data contracts, or operational steps change.
7. Run the smallest relevant quality gate, then the full gate when feasible.

## Quality gates

Documentation-only:

    scripts/agent/check.sh docs

Dart or Flutter code:

    scripts/agent/check.sh quick

Behavior, storage, authentication, sync, routing, or platform integration:

    scripts/agent/check.sh full

Platform-specific changes also require a build or test on the affected platform. Record commands and results in the handoff.

## Architecture decisions

Add an ADR when a change affects:

- persisted or remote data shape;
- authentication or authorization boundaries;
- encryption or key management;
- state-management or dependency-injection ownership;
- supported platforms;
- destructive sync or deletion semantics;
- a dependency that establishes a long-lived project constraint.

Use docs/adr/0000-template.md and add the new record to docs/ARCHITECTURAL_DECISIONS.md.

## Pull request checklist

- Scope and acceptance criteria are explicit.
- No unrelated user changes were overwritten.
- Tests cover the changed behavior or the missing coverage is explained.
- No secret or personal data is present in code, fixtures, logs, screenshots, or documentation.
- Data migration and rollback implications are documented.
- Relevant canonical docs are updated.
- Analyzer, tests, and platform checks are reported with exact outcomes.
