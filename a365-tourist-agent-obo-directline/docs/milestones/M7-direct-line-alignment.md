# M7 OBO Direct Line end-to-end alignment

Workspace paths in this document are written from the Direct Line project root.

This frontend stays limited to the Direct Line client, its focused tests, the synthetic prompt list,
and a non-secret contract pin. Shared behavior and deployment remain owned by
`../a365-tourist-backend`.

## Current checkpoint

- Contract version `1.0.0` pins `/api/messages/obo`,
  `TokenValidation__Audiences__OnBehalfOf`, and `configured-obo-child-agent-identity`.
- The Release-focused suite passes 5/5.
- Shared host revision `0000028` runs digest
  `sha256:161f9b8fa401012d5d87ccef1c215c23515709850496f585e0aca66f93b1f771`;
  revision `0000027` and digest
  `sha256:9dd1e4d22f824504c375cd112da36b8b25ace68aa4b8e23af12dd0de2a09004c`
  are the verified host rollback boundary.
- Exactly three approved synthetic cases were sent with three-minute isolation gaps: one credit card,
  one South Korean passport, and one South Korean resident-registration number. All three returned
  the organization DLP block, revision logs recorded the block before model access, and model
  requests stayed at zero for every covered minute. Prompt values were not echoed, and no background
  closed-channel warning appeared during observation.

This evidence is sanitized and does not contain prompts, matched values, identities, tokens, or
responses beyond the policy outcome. A broad 120-case/five-second run is exploratory coverage, not
substitute evidence for an isolated pre-model acceptance interval.
