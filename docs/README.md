# Documentation Map

This directory is the canonical engineering documentation for Hyper Authenticator.

## Reading order

1. [Project Status](PROJECT_STATUS.md) — what is implemented, what is broken, and which checks currently pass.
2. [System Design](SYSTEM_DESIGN.md) — runtime architecture and data flows.
3. [Security](SECURITY.md) — assets, trust boundaries, threats, and release blockers.
4. [Data Models](DATA_MODELS.md) — current local and remote serialization contracts.
5. [Development](DEVELOPMENT.md) — setup and day-to-day commands.
6. [Testing Strategy](TESTING_STRATEGY.md) — quality gates and required coverage.
7. [Supabase Integration](SUPABASE_INTEGRATION.md) — authentication, database contract, and RLS.
8. [Deployment](DEPLOYMENT.md) — release readiness and platform checklists.

## Canonical documents

| Document | Purpose | Truth type |
|---|---|---|
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | Verified current baseline and known gaps | Current |
| [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md) | Runtime components and flows | Current |
| [DATA_MODELS.md](DATA_MODELS.md) | Implemented model and serialization shapes | Current |
| [SECURITY.md](SECURITY.md) | Current security posture and mandatory controls | Current + requirements |
| [SUPABASE_INTEGRATION.md](SUPABASE_INTEGRATION.md) | Observed client contract and required server setup | Current + requirements |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Reproducible local workflow | Procedure |
| [TESTING_STRATEGY.md](TESTING_STRATEGY.md) | Test layers and quality gates | Procedure + target |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Release gates by platform | Procedure |
| [NON_FUNCTIONAL_REQUIREMENTS.md](NON_FUNCTIONAL_REQUIREMENTS.md) | Measurable quality targets | Requirements |
| [E2EE_DESIGN.md](E2EE_DESIGN.md) | Proposed end-to-end encryption design | Planned |
| [ROADMAP.md](ROADMAP.md) | Prioritized remediation sequence | Planned |
| [ARCHITECTURAL_DECISIONS.md](ARCHITECTURAL_DECISIONS.md) | Decision index and status | Decisions |
| [AI_AGENT_PLAYBOOK.md](AI_AGENT_PLAYBOOK.md) | Long-running AI workflow | Procedure |

Component documentation:

- [Password-recovery web page](../reset-password-web/README.md)

Localized architecture summaries:

- [SYSTEM_DESIGN.vi.md](SYSTEM_DESIGN.vi.md) — Vietnamese.

The English documents above remain canonical when translations disagree.

## Status vocabulary

- Implemented: present in source and traceable to a runtime path.
- Verified: reproduced by a documented command or test.
- Planned: proposed but not implemented.
- Known gap: implemented behavior is incomplete, unsafe, misleading, or unverified.
- Release blocker: must be resolved before real production secrets are accepted.

## Documentation rules

- Describe the current system before the desired system.
- Put future design in an explicitly Planned section.
- Link claims to source paths where practical.
- Do not include real URLs, keys, tokens, passwords, TOTP secrets, otpauth URIs, or user identifiers.
- Update PROJECT_STATUS.md after verification changes.
- Update DATA_MODELS.md and SUPABASE_INTEGRATION.md in the same change as a serialization or schema change.
- Add an ADR for long-lived architectural, security, or data-contract decisions.
- Keep translations short enough to maintain; do not duplicate the entire canonical corpus.

## Task and decision records

- [Task template](tasks/TEMPLATE.md) — working note for non-trivial changes.
- [ADR template](adr/0000-template.md) — architecture decision record template.
- [Architectural Decisions](ARCHITECTURAL_DECISIONS.md) — index of accepted and proposed decisions.
