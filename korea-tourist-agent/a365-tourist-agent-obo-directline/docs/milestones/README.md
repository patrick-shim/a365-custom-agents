# OBO Direct Line frontend milestones

The machine-readable current milestone is [milestones.json](milestones.json), validated by
[milestones.schema.json](milestones.schema.json). The backend protocol rules it follows are
documented in
[../../../a365-tourist-backend/docs/milestones/README.md](../../../a365-tourist-backend/docs/milestones/README.md);
where this summary and the JSON disagree, the JSON wins.

## Current milestone: M7

M7 preserves the standalone Direct Line client boundary and validates it against the one shared
backend without copying Teams, Agent 365 operational state, or backend deployment assets. The current
client passes 5/5 focused tests. See [M7-direct-line-alignment.md](M7-direct-line-alignment.md) for
the sanitized checkpoint.

## Recorded evidence

Backend revision `0000028` passed isolated Direct Line acceptance for one approved synthetic credit
card case, one passport case, and one South Korean resident-registration case. Each was blocked
before model access, and Azure OpenAI model requests remained zero across the covered interval.
Revision `0000027` remains the verified backend rollback boundary.

## Evidence standard

Isolated means one synthetic case per interval, with enough separation to attribute each host
policy-block record to exactly one turn — the recorded runs used three-minute spacing. Two rules
follow from that:

- Refusal wording alone is not proof. A blocked turn must be corroborated by sanitized host
  policy-block evidence **and** a zero model-request count for the interval.
- A 120-case run at a short interval is exploratory coverage, not isolated M7 evidence. It cannot be
  attributed per case.

Never use real personal, financial, passport, or resident-registration data. Never disable
fail-closed Purview enforcement to make an acceptance run pass.
