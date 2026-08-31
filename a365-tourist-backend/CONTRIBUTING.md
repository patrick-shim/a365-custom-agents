# Contributing

Read `AGENTS.md` and `docs/milestones/milestones.json` before changing code. Work only in the active
milestone and preserve the repository boundaries.

Required local checks:

```powershell
dotnet build KoreaExpertAgent.slnx
dotnet test KoreaExpertAgent.slnx
./tools/Invoke-Validation.ps1
./tools/Invoke-LocalCi.ps1
./tools/tests/Invoke-ToolsSelfTest.ps1
```

Use synthetic data. Never commit secrets, generated user state, tenant/user identifiers, prompt or
tool content, or cloud mutation scripts. New failure behavior needs a focused regression test and a
stable safe error contract. Tenant reads and mutations follow the milestone approval gates.
