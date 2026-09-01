# OBO Direct Line frontend configuration

The client binds to `/api/messages/obo` through `backend-contract.lock.json`. The committed pin names
`TokenValidation__Audiences__OnBehalfOf` and `configured-obo-child-agent-identity`; actual tenant,
channel, child, and secret values remain outside source.

Set the Direct Line site secret only for the current process:

```powershell
$env:KOREA_EXPERT_DIRECT_LINE_SECRET = '<retrieve-through-approved-secret-workflow>'
dotnet run --project direct/KoreaExpert.Direct
Remove-Item Env:KOREA_EXPERT_DIRECT_LINE_SECRET
```

Do not place the value in source, command arguments, shell history, logs, appsettings, `.env` files,
or key files. `KOREA_EXPERT_DIRECT_LINE_ENDPOINT` may override the regional Direct Line base URL;
the default is the standard Direct Line v3 service.

The OBO Teams package and protected OBO state belong only in `../a365-tourist-agent-obo`; AI Teammate
package state belongs only in `../a365-tourist-agent-teammate`. Shared route, identity, Purview, or
deployment changes belong only in `../a365-tourist-backend`.
