# Public release checklist

Do not publish this working directory directly.

- [ ] Establish Git provenance and release from a clean clone or `git archive`.
- [ ] Select and add an explicit open-source `LICENSE`; no license is chosen implicitly.
- [ ] Add repository owner/contact values to `SECURITY.md`, `SUPPORT.md`, and `CODEOWNERS`.
- [ ] Confirm generated Agent 365, Teams build, `.env.*.user`, `.azure`, and local state are absent.
- [ ] Scan current files and complete Git history for credentials and tenant/user identifiers.
- [ ] Replace environment-specific deployment evidence with sanitized examples where appropriate.
- [ ] Run NuGet vulnerability/license, container, and Bicep drift checks; run npm checks only in a
	frontend that contains npm-managed artifacts.
- [ ] Generate an SBOM and third-party notices for release artifacts.
- [ ] Pin CI actions and build images to reviewed immutable revisions.
- [ ] Run Release build, full tests, strict validation, Local CI, and tools self-tests.
- [ ] Verify one backend passes both protected route/audience modes through all three frontend paths:
	OBO Teams, OBO Direct Line, and AI Teammate.
- [ ] Document the current process-local storage limitation or replace it before scale-out.

The workspace now has a source-safe initial Git baseline that excludes local credentials, generated
Agent 365 state, package output, and protected deployment evidence. That establishes reviewable
provenance but does not make the workspace public-release ready: complete every unchecked item above
from a clean clone before publishing.
