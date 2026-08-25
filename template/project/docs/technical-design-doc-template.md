# [Document Title]

| **Approver** | **Role** | **Status** | **Date** |
|-------------|----------|------------|----------|
| | | Pending / Approved / Changes Requested | |

| **Team** | **Author(s)** | **Created** | **Last Updated** | **Status** |
|----------|--------------|-------------|-----------------|------------|
| | | | | Draft / In Review / Approved |

---

## What is changing

[One line summary of what is being changed and why.]

### Details

[More detailed description of what is changing, the problem being solved, and the impact.]

### Project Documents

[Add all documents relevant to this design here — PRDs, ADO epics, design decks, meeting recordings, reference docs, learning resources, external APIs, etc. Any document a reviewer might need to understand the context or decisions should be listed.]

| Document | Link | Description |
|----------|------|-------------|
| PRD | | Product requirements |
| Tracker item | | Work item tracking |
| Design Deck | | Architecture / overview slides |
| Meeting Recordings | | Key decision meetings |
| Reference Docs | | External documentation, learning resources |

### Contacts

| Name | Role | Area |
|------|------|------|
| | Tech Lead | |
| | Product Owner | |
| | Engineering Manager | |
| | Scrum Master | |
| | Subject Matter Expert | |

### Subject Matter Review

[Tag the relevant reviewer for each area that applies. Remove rows that are not applicable.]

| Subject Area | Reviewer | Status |
|-------------|----------|--------|
| Content Operations | | Pending |
| Product Testing | | Pending |
| API design | | Pending |
| Security | | Pending |
| Privacy | | Pending |
| Infrastructure / Deployment | | Pending |
| Data / Schema | | Pending |
| Monitoring / Observability | | Pending |

---

## Objective

[What is being built and why. What problem does this solve?]

### In Scope

[What this document covers and what will be built.]

### Out of Scope

[What is explicitly not being built — be specific.]

---

## Background

[Context a new reader needs to understand the design. No design decisions here. This section can include:]

- [Current state of the system and how it works today]
- [The problem being solved and why it matters]
- [Existing workflows or manual processes being replaced]
- [Relevant prior work, previous attempts, or related systems]
- [Key concepts or terminology a reader needs to know]

---

## Alternatives Considered

[Major system-level architectural decisions only. For module-level alternatives, see Detailed Design.]

### [Decision Name]

**Alternative 1 — [Name]**

[Description of what this option is and how it works.]

**Alternative 2 — [Name]**

[Description of what this option is and how it works.]

**Alternative 3 — [Name]**

[Description of what this option is and how it works.]

**Comparison:**

| | Alt 1 (Proposed Solution) | Alt 2 | Alt 3 |
|---|---|---|---|
| **[Criterion]** | 🟢 | 🔴 | 🟡 |
| **[Criterion]** | 🟡 | 🟢 | 🔴 |

**Reasoning:** [Why the proposed solution was chosen over the alternatives.]

---

## Overview

### Use Case Coverage

[Which use cases this design handles and which it does not.]

### High-Level Design

[System architecture diagram and high-level flow.]

### Limitation Summary

[High-level constraints and limitations of this design.]

### Design Extensibility

[How this design can be extended in future versions.]

---

## Detailed Design

### System Architecture

[Full system architecture diagram showing all layers and how they interact with each other and external systems.]

### [Layer / Module Name e.g. API Layer, Job Dispatcher, HTTP client]

**Owner:** [Name]

[Interaction diagram showing what messages are passed between this layer and others.]

[Description of this layer's responsibilities.]

#### Interface

[API contracts, Pydantic models, or method signatures this layer exposes to other layers.]

#### Design Decisions

**Alternative 1 — [Name]**

[Description.]

**Alternative 2 — [Name]**

[Description.]

**Comparison:**

| | Alt 1 (Proposed Solution) | Alt 2 |
|---|---|---|
| **[Criterion]** | 🟢 | 🔴 |
| **[Criterion]** | 🟡 | 🟢 |

**Reasoning:** [Why the proposed solution was chosen.]

---

## Testing

[Describe the testing strategy. Can include: unit tests, integration tests, end-to-end tests, test coverage requirements, test environments, and how to run tests.]

---

## Breaking Changes

[Any breaking changes to existing APIs, interfaces, or behaviour.]

---

## Dependencies

[External systems, teams, APIs, or permissions this design depends on.]

---

## Quota / API Limits

[Rate limits, quota constraints from external APIs or internal systems.]

---

## Compliance

[Regulatory or policy compliance requirements.]

### Privacy

[PII handling, data retention, user consent.]

### Security Considerations

[Authentication, authorization, data encryption, threat model.]

---

## Production

### Deployment

[How to build, run, and configure. Docker setup, environment variables, prerequisites.]

### Capacity

[Expected load, storage requirements, scaling considerations.]

### SLI / SLO / Error Handling

[Service level indicators, objectives, and how errors are handled.]

### Monitoring & Dashboards

[Describe observability for this system. Can include: metrics tracked, dashboards, logging strategy, log format, log access, alerting, and debugging approach.]

### Disaster Recovery

[Backup strategy, recovery playbooks, failover plan.]

### Regionalization

[Multi-region support, data residency requirements. N/A if not applicable.]

### Billing

[Cost implications, billing model changes. N/A if not applicable.]

### Customer Documentation

[Documentation to create or update for users. N/A if not applicable.]

### Customer Upgrades

[Migration path or upgrade steps for existing users. N/A if not applicable.]

---

## Open Questions

| Question | Owner | Due | Status |
|----------|-------|-----|--------|
| | | | Open / Resolved |
