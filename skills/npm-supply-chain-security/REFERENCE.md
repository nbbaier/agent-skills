# npm Supply Chain Security — Reference

## Recent incidents (why this matters)

- **TanStack (May 2026)** — a compromised CI pipeline published 42 malicious packages across 84 versions in roughly 6 minutes.
- **Shai-Hulud worm** — automated self-propagating attack that spread through hundreds of packages via stolen npm tokens.
- **chalk / debug (Sept 2024)** — maintainer phishing led to crypto-clipper malware being distributed via widely-installed packages.

Common thread: the attacker is upstream of you, and the malicious version arrives in your install with the same name as a package you already trust.

## Three-layer model

| Layer | When it happens | Controls |
|---|---|---|
| Resolution | `install` / `update` writes new versions into the lockfile | Commit the lockfile, install with frozen lockfile in CI, apply cooldowns to fresh publishes |
| Installation | `preinstall` / `install` / `postinstall` lifecycle scripts run | `--ignore-scripts` with selective `npm rebuild <pkg>` for required native modules |
| Execution environment | What the running build can read or send | Digest-pin base images, scope CI credentials minimally, avoid `pull_request_target` with secrets |

## Control reference

### 1. Lockfile + frozen-lockfile installs everywhere

**Why:** `npm install` resolves versions afresh — it can pick up a brand-new release between two runs. `npm ci` installs exactly what the lockfile says, with integrity verification.

```bash
# CI / Docker
npm ci
pnpm install --frozen-lockfile
bun install --frozen-lockfile
yarn install --frozen-lockfile     # Classic
yarn install --immutable           # Berry
```

The lockfile MUST be committed for any of this to work.

### 2. Install cooldown

**Why:** Most malicious publishes are detected within hours-to-days. Refusing to install packages younger than N days dramatically reduces zero-day exposure.

**npm 11+** — `.npmrc`:

```ini
min-release-age=1
```

Filters registry metadata to exclude packages published within `min-release-age` days. Affects `npm install`/`update`, NOT `npm ci`.

**pnpm 10.16+** — `pnpm-workspace.yaml`:

```yaml
minimumReleaseAge: 1
minimumReleaseAgeExclude:
  - package-you-need-fresh
```

**Dependabot** — `.github/dependabot.yml`:

```yaml
updates:
  - package-ecosystem: npm
    directory: /
    schedule: { interval: weekly }
    cooldown:
      default-days: 1
```

**Renovate** — `renovate.json`:

```json
{ "minimumReleaseAge": "1 day" }
```

**Bun**: no native equivalent at this writing. Mitigations: rely on Dependabot/Renovate for update PRs (so version bumps still pass through a cooldown), or wrap installs in a script that defers to npm/pnpm for cooldown enforcement.

### 3. Disable install scripts in CI

**Why:** Every dependency in the tree can run arbitrary code at install via lifecycle scripts. A typical Node project has thousands of transitive deps. `--ignore-scripts` defeats this entire attack class.

```bash
# CI
npm ci --ignore-scripts
pnpm install --frozen-lockfile --ignore-scripts
bun install --frozen-lockfile --ignore-scripts
```

For packages that legitimately need install scripts, allow-list after install:

```bash
npm ci --ignore-scripts && npm rebuild sharp better-sqlite3
```

**Do not** put `ignore-scripts=true` in project-level `.npmrc` — that breaks local dev. Apply it only in CI/Dockerfile invocations, or in a user-level `.npmrc`.

**Exceptions:** Electron apps and projects with heavy native-module dependencies may need a custom allow-list rather than a global block.

### 4. Digest-pin base images

**Why:** `FROM node:24-alpine` re-resolves on every build; the same tag can point at different image bytes tomorrow. A digest pin locks the exact image.

```dockerfile
FROM node:24-alpine@sha256:abc123...
```

Get the digest with:

```bash
docker pull node:24-alpine
docker inspect --format='{{index .RepoDigests 0}}' node:24-alpine
```

### 5. CI audit step

```bash
npm audit --audit-level=high   # exits non-zero on high/critical
pnpm audit --audit-level high
bun audit                       # check current flags
yarn npm audit                  # Berry
```

This catches known-bad versions; combined with the cooldown, it covers most of the gap between "malicious publish" and "registry takedown."

### 6. CODEOWNERS on dependency files

```
# .github/CODEOWNERS
package.json        @your-team
package-lock.json   @your-team
.npmrc              @your-team
Dockerfile          @your-team
```

Required reviews on these files mean an attacker who lands a write token still cannot quietly modify the resolution surface.

## Per-PM cheat sheet

| Capability | npm 11+ | pnpm 10.16+ | bun | yarn |
|---|---|---|---|---|
| Lockfile | `package-lock.json` | `pnpm-lock.yaml` | `bun.lock` / `bun.lockb` | `yarn.lock` |
| Reproducible install | `npm ci` | `pnpm install --frozen-lockfile` | `bun install --frozen-lockfile` | `--frozen-lockfile` (Classic) / `--immutable` (Berry) |
| Disable scripts | `--ignore-scripts` | `--ignore-scripts` | `--ignore-scripts` | `--ignore-scripts` |
| Cooldown | `min-release-age` in `.npmrc` | `minimumReleaseAge` in `pnpm-workspace.yaml` | not yet | not yet |
| Audit | `npm audit` | `pnpm audit` | `bun audit` | `yarn npm audit` (Berry) |

## What these controls do NOT prevent

- Direct malicious commits to your lockfile — the cooldown only filters the registry. A PR that hand-edits `package-lock.json` bypasses everything; CODEOWNERS + required review is the answer.
- Long-tail attacks that go undetected beyond the cooldown window.
- Projects where install scripts are an architectural hard requirement (mitigate with allow-listing, not blocking).
- Compromise of your own publishing flow (separate concern: 2FA on npm accounts, scoped automation tokens, OIDC publishing instead of long-lived tokens).

## Incident response playbook

1. **Identify affected machines.** Local dev boxes, CI runners, build hosts — all of them.
2. **Enumerate reachable credentials.** For each machine/runner, list every credential loaded in env vars, files, keychains, agent forwards, or cloud metadata. Treat each as exfiltrated.
3. **Rotate.** Don't triage what was actually stolen — rotate everything reachable. npm tokens, GitHub PATs, SSH keys, cloud creds, CI secrets, SaaS API keys.
4. **Pin to last-known-good.** Revert the lockfile to a commit predating the bad version. `npm ci` from there.
5. **Find every install of the bad version.** `npm ls <pkg>` shows the dependency paths. For multi-repo orgs, search across all lockfiles (`grep -l "<pkg>" **/package-lock.json`).
6. **Rebuild artifacts.** Any container image, deploy, or published package built while the bad version was present is suspect. Rebuild from clean inputs.
7. **Pre-document this list before you need it.** The 3am version of this checklist is much worse than the calm version.
