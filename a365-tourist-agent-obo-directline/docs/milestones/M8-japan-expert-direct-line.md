# M8 Japan Expert Direct Line migration

This frontend owns only the renamed Japan Expert Direct Line client, focused tests, synthetic
acceptance inputs, and `/api/messages/obo` contract pin. The client will use a newly approved Japan
Expert Direct Line site and OAuth boundary; no Seoul secret, identifier, or tenant-bound evidence may
be reused or committed.

Live channel and policy validation is complete for the functional path: the Japan Expert Direct Line
site and OBO registration exist, and governed turns return model answers with fail-closed Purview
evaluation and all four MCP services healthy. The reserved three-case synthetic policy run remains a
separate operation requiring its own reviewed approval.

The Direct Line site belongs to the new Japan Expert Azure Bot in `rg-a365-custom-agents`. Its site
secret is retrieved only after channel creation, held only in the current client process, and never
written to source, arguments, logs, or configuration files.
