# OBO Frontend Milestones

The machine-readable current milestone is [milestones.json](milestones.json), validated by
[milestones.schema.json](milestones.schema.json). Read it before changing package, channel, or tenant
state. The backend protocol rules it follows are documented in
[../../../a365-tourist-backend/docs/milestones/README.md](../../../a365-tourist-backend/docs/milestones/README.md);
where this summary and the JSON disagree, the JSON wins.

## Current milestone: M7

M7 preserves the completed backend-residue removal and Direct Line separation. This tree retains
only the Teams package source, committed non-secret OBO contract pin, and protected local OBO state,
and owns approved CLI-driven package/channel operations. M7 never copies backend source or
hand-edits operational state.

The sanitized channel record is [M7-obo-alignment.md](M7-obo-alignment.md).

## Open acceptance

The last documented Teams live pass used backend revision `0000025`; the current backend is
`0000028`, so same-revision acceptance remains open. Closing it requires a sanitized Teams replay on
`0000028` covering endpoint, audience, authentication, installed package, governed response, Purview
behavior, and observability with no raw prompts, tool data, or credentials.

Do not claim same-revision alignment from the Direct Line evidence. Direct Line has isolated
pre-model DLP evidence on `0000028`, but it exercises a different channel and token path.

## Mutation rules

Every package publication, consent change, channel configuration change, or tenant mutation requires
the active M7 permission, a reviewed dry run where the CLI supports one, an explicit rollback
boundary, and explicit approval after the dry-run output has been shown. Validation never signs in on
the operator's behalf. Never run `a365 cleanup blueprint` while any child identity or sibling
frontend exists.
