# M7 OBO Teams end-to-end alignment

> Historical Seoul Tourist record. M8 owns the Japan Expert package and registration migration.

Workspace paths in this document are written from the OBO Teams project root.

The OBO Teams frontend retains only its Teams package, OBO contract pin, and protected OBO operational
state. The Direct Line client, focused tests, synthetic prompt list, and .NET metadata are owned only
by `../a365-tourist-agent-obo-directline`. All shared backend source and deployment residue was
removed; `../a365-tourist-backend` is the only backend source and Azure deployment owner.

M7 preserved that completed separation while validating and, through approved CLI-owned workflows,
aligning the OBO Teams package with `/api/messages/obo`, its OBO audience and child identity, Purview
enforcement, and the same deployed backend revision used by Direct Line. Its remaining acceptance
work was superseded by M8, which requires fresh Japan Expert registration and evidence.

## Latest recorded checkpoint

- The contract pin remains version `1.0.0` and matches `/api/messages/obo`,
  `TokenValidation__Audiences__OnBehalfOf`, and the configured OBO child identity binding.
- The committed Teams manifest and contract source validate structurally. Protected CLI state and
  generated build output remain outside Git and are not current deployment authority.
- The last documented live OBO Teams pass used shared host revision `0000025`. The latest
  repository-recorded host checkpoint is revision `0000028`, so a sanitized normal-turn, MCP,
  Purview, and observability replay against `0000028` remains the final OBO Teams same-revision gate.
