---
name: npm-supply-chain-security
description: Audit and harden Node.js projects against npm supply chain attacks — compromised maintainer accounts, malicious package versions, and install-script payloads. Use when reviewing or setting up package.json, lockfiles, .npmrc, Dockerfile, or CI workflows for security; when the user mentions npm security, supply chain attacks, `npm audit`, lockfile policy, install scripts, or min-release-age; also when the user wants to check whether their dependencies are safe, or recover from a suspected compromise.
---

# npm Supply Chain Security

> Adapted from [NPM Security Best Practices for Supply Chain Attacks](https://www.localcan.com/blog/npm-security-best-practices-supply-chain-attacks) by Localcan.

Defends against three concrete attack patterns: zero-day malicious publishes (a compromised maintainer pushes a backdoored version), install-script payloads (lifecycle scripts run arbitrary code on install), and resolution drift (`npm install` picks up a newer-than-locked version). Controls operate at three layers — **resolution** (versions entering the lockfile), **installation** (lifecycle scripts), and **execution environment** (what the build can reach).

npm-primary; pnpm and bun equivalents are noted inline. Full per-PM detail in [REFERENCE.md](REFERENCE.md).

## Quick start

Apply the **30-minute baseline**:

1. Commit the lockfile (`package-lock.json` / `pnpm-lock.yaml` / `bun.lock`).
2. Add an install cooldown — `min-release-age=1` in `.npmrc` (npm 11+), or `minimumReleaseAge: 1` in `pnpm-workspace.yaml` (pnpm 10.16+). Bun has no native equivalent — this is a real gap, since `bun install` re-resolves locally and bypasses any PR-layer cooldown. Configure Dependabot or Renovate cooldown as a partial mitigation for the update-PR path.
3. In CI/Dockerfile, install with frozen lockfile **and** `--ignore-scripts`:
   - `npm ci --ignore-scripts`
   - `pnpm install --frozen-lockfile --ignore-scripts`
   - `bun install --frozen-lockfile --ignore-scripts`

   Allow-list required native modules with a follow-up `npm rebuild <pkg>` (e.g. `sharp`, `better-sqlite3`).
4. Digest-pin base images: `FROM node:24-alpine@sha256:...`, not `FROM node:24-alpine`.
5. Add an audit step to CI: `npm audit --audit-level=high` (or `pnpm audit` / `bun audit`).
6. Put `package.json`, the lockfile, `.npmrc`, and `Dockerfile` under CODEOWNERS with required review.

## Workflows

### Audit an existing project

Run the audit script (lives at `scripts/audit.sh` in this skill directory) from the target project's root:

```bash
bash <path-to-this-skill>/scripts/audit.sh
```

It detects the package manager, checks each baseline item, and prints PASS/FAIL/WARN. Treat each FAIL as a TODO; WARN items need human judgment.

### Harden a project from scratch

Walk the user through the 30-minute checklist in order. Two recurring gotchas:

- `--ignore-scripts` belongs in **CI commands**, not project-level `.npmrc`. Local dev often needs install scripts to compile native modules.
- Electron apps and projects with many native modules may need a per-package allow-list rather than a blanket block. Ask before applying `--ignore-scripts` globally.

### Respond to a suspected compromise

If a malicious version may have been installed:

1. **Enumerate reachable credentials.** For every affected machine or runner, list every credential that was loaded — env vars, dotfiles, keychains, agent forwards, cloud metadata. Assume each one is exfiltrated.
2. **Rotate everything reachable.** Don't try to assess which were actually stolen. Rotate npm tokens, GitHub PATs, SSH keys, cloud credentials, CI secrets, SaaS API keys.
3. **Pin to last-known-good.** Find the commit predating the bad version, revert the lockfile, `npm ci` from there.
4. **Trace the blast radius.** `npm ls <bad-pkg>` shows every dependency path. For multi-repo orgs, search across all lockfiles.
5. **Rebuild artifacts.** Any image, deploy, or published package produced while the bad version was installed should be considered tainted. Rebuild from clean inputs.

## What this does NOT prevent

- Malicious commits directly to the lockfile (the cooldown only filters registry metadata; CODEOWNERS + required review is the answer).
- Attacks that evade detection beyond the cooldown window.
- Projects where install scripts are an architectural requirement (mitigate with allow-listing, not blocking).

## Out of scope: publishing-side hardening

This skill covers the **install side** — protecting your project from compromised upstream packages. If the user is also publishing packages to npm, point them at the publishing-side controls (separate concern, not audited here):

- 2FA enforced on the npm account and on any maintainer accounts.
- Scoped, short-lived automation tokens — never long-lived publish tokens checked into CI secrets.
- OIDC-based trusted publishing (GitHub Actions → npm) instead of static tokens where possible.
- Provenance attestations (`npm publish --provenance`) so consumers can verify the build origin.

See [REFERENCE.md](REFERENCE.md) for per-control rationale, per-PM syntax, and incident background.
