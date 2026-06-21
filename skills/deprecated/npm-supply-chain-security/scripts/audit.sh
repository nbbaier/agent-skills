#!/usr/bin/env bash
# Audit the current directory against the npm supply-chain-security baseline.
# Detects npm/pnpm/yarn/bun and runs PM-appropriate checks.
# Prints PASS / FAIL / WARN per check and exits non-zero if any FAIL.

set -uo pipefail

if [[ -t 1 ]]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  GREEN=""; RED=""; YELLOW=""; DIM=""; RESET=""
fi

FAILS=0
WARNS=0
pass() { echo "${GREEN}PASS${RESET}  $1"; }
fail() { echo "${RED}FAIL${RESET}  $1"; FAILS=$((FAILS+1)); }
warn() { echo "${YELLOW}WARN${RESET}  $1"; WARNS=$((WARNS+1)); }
info() { echo "${DIM}      $1${RESET}"; }

if [[ ! -f package.json ]]; then
  echo "No package.json in current directory — run from project root."
  exit 1
fi

# --- Detect package manager ---
PM=""
LOCKFILE=""
if [[ -f bun.lock ]]; then
  PM="bun"; LOCKFILE="bun.lock"
elif [[ -f bun.lockb ]]; then
  PM="bun"; LOCKFILE="bun.lockb"
elif [[ -f pnpm-lock.yaml ]]; then
  PM="pnpm"; LOCKFILE="pnpm-lock.yaml"
elif [[ -f yarn.lock ]]; then
  PM="yarn"; LOCKFILE="yarn.lock"
elif [[ -f package-lock.json ]]; then
  PM="npm"; LOCKFILE="package-lock.json"
else
  PM="npm"; LOCKFILE="package-lock.json"
  warn "No lockfile present; assuming npm — install once and commit the lockfile"
fi

echo "Package manager: ${PM}"
echo "Expected lockfile: ${LOCKFILE}"
echo

# --- Check 1: lockfile committed ---
if [[ -f "$LOCKFILE" ]]; then
  pass "Lockfile present: $LOCKFILE"
  if git ls-files --error-unmatch "$LOCKFILE" >/dev/null 2>&1; then
    pass "Lockfile is tracked by git"
  else
    fail "Lockfile is NOT tracked by git — commit it"
  fi
  if [[ -f .gitignore ]] && grep -qE "^/?${LOCKFILE}$" .gitignore 2>/dev/null; then
    fail "Lockfile appears in .gitignore — remove that line and commit it"
  fi
else
  fail "No lockfile found ($LOCKFILE) — install once and commit it"
fi

# --- Check 2: install cooldown ---
case "$PM" in
  npm)
    if [[ -f .npmrc ]] && grep -qE '^min-release-age' .npmrc; then
      pass "min-release-age set in .npmrc"
    else
      fail "min-release-age not set in .npmrc (add 'min-release-age=1', requires npm 11+)"
    fi
    ;;
  pnpm)
    if [[ -f pnpm-workspace.yaml ]] && grep -qE '^[[:space:]]*minimumReleaseAge' pnpm-workspace.yaml; then
      pass "minimumReleaseAge set in pnpm-workspace.yaml"
    elif [[ -f .npmrc ]] && grep -qE '^minimum-release-age' .npmrc; then
      pass "minimum-release-age set in .npmrc"
    else
      fail "No install cooldown configured (add 'minimumReleaseAge: 1' to pnpm-workspace.yaml, requires pnpm 10.16+)"
    fi
    ;;
  bun)
    fail "Bun has no native install cooldown — local 'bun install' will re-resolve to fresh publishes"
    info "Partial mitigation: configure Dependabot or Renovate cooldown for update PRs (covers the PR path only)"
    ;;
  yarn)
    fail "Yarn has no native install cooldown — 'yarn install' will re-resolve to fresh publishes"
    info "Partial mitigation: configure Dependabot or Renovate cooldown for update PRs (covers the PR path only)"
    ;;
esac

# Bonus: Dependabot / Renovate cooldown
DEPENDABOT=""
for f in .github/dependabot.yml .github/dependabot.yaml; do
  [[ -f "$f" ]] && DEPENDABOT="$f" && break
done
if [[ -n "$DEPENDABOT" ]]; then
  if grep -qE 'cooldown|default-days' "$DEPENDABOT" 2>/dev/null; then
    pass "Dependabot cooldown configured ($DEPENDABOT)"
  else
    info "Dependabot present but no cooldown block found in $DEPENDABOT"
  fi
fi

RENOVATE=""
for f in renovate.json .github/renovate.json .renovaterc .renovaterc.json; do
  [[ -f "$f" ]] && RENOVATE="$f" && break
done
if [[ -n "$RENOVATE" ]]; then
  if grep -qE 'minimumReleaseAge' "$RENOVATE" 2>/dev/null; then
    pass "Renovate minimumReleaseAge configured ($RENOVATE)"
  else
    info "Renovate present but no minimumReleaseAge in $RENOVATE"
  fi
fi

# --- Collect CI files ---
CI_FILES=()
if [[ -d .github/workflows ]]; then
  while IFS= read -r f; do CI_FILES+=("$f"); done < <(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
fi
while IFS= read -r f; do CI_FILES+=("$f"); done < <(find . -maxdepth 3 -type f -name 'Dockerfile*' ! -path './node_modules/*' ! -path './.git/*' 2>/dev/null)

# --- Check 3: frozen-lockfile + ignore-scripts in CI ---
case "$PM" in
  npm)   FROZEN_RE='npm[[:space:]]+ci' ;;
  pnpm)  FROZEN_RE='pnpm[[:space:]]+(install|i)[^|&;]*--frozen-lockfile' ;;
  bun)   FROZEN_RE='bun[[:space:]]+(install|i)[^|&;]*--frozen-lockfile' ;;
  yarn)  FROZEN_RE='yarn[[:space:]]+install[^|&;]*(--frozen-lockfile|--immutable)' ;;
esac
IGNORE_RE='--ignore-scripts'

if [[ ${#CI_FILES[@]} -eq 0 ]]; then
  warn "No CI workflows or Dockerfiles found — skipping CI checks"
else
  FROZEN_OK=0
  IGNORE_OK=0
  for f in "${CI_FILES[@]}"; do
    grep -qE -- "$FROZEN_RE" "$f" 2>/dev/null && FROZEN_OK=1
    grep -qF -- "$IGNORE_RE" "$f" 2>/dev/null && IGNORE_OK=1
  done
  if [[ $FROZEN_OK -eq 1 ]]; then
    pass "Frozen-lockfile install command found in CI/Dockerfile"
  else
    fail "No frozen-lockfile install command in CI/Dockerfile"
  fi
  if [[ $IGNORE_OK -eq 1 ]]; then
    pass "--ignore-scripts found in CI/Dockerfile"
  else
    fail "--ignore-scripts not used in any CI install — lifecycle scripts will execute"
  fi
fi

# --- Check 4: Dockerfile base image digest-pinned ---
if [[ -f Dockerfile ]]; then
  FROM_LINES=$(grep -E '^[[:space:]]*FROM[[:space:]]' Dockerfile || true)
  if [[ -z "$FROM_LINES" ]]; then
    info "Dockerfile present but no FROM lines parsed"
  elif echo "$FROM_LINES" | grep -vqE '@sha256:[a-f0-9]{64}'; then
    fail "Dockerfile FROM line(s) not digest-pinned (tag-only pins are mutable)"
    info "$(echo "$FROM_LINES" | sed 's/^/      /')"
  else
    pass "Dockerfile FROM uses digest pin (@sha256:...)"
  fi
else
  info "No Dockerfile in repo root — skipping image-pin check"
fi

# --- Check 5: audit step in CI ---
if [[ ${#CI_FILES[@]} -gt 0 ]]; then
  AUDIT_FOUND=0
  for f in "${CI_FILES[@]}"; do
    if grep -qE "(${PM}|npm)[[:space:]]+audit" "$f" 2>/dev/null; then
      AUDIT_FOUND=1; break
    fi
  done
  if [[ $AUDIT_FOUND -eq 1 ]]; then
    pass "audit step found in CI"
  else
    fail "No '${PM} audit' step in CI"
  fi
fi

# --- Check 6: CODEOWNERS on dep files ---
CODEOWNERS=""
for c in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
  [[ -f "$c" ]] && CODEOWNERS="$c" && break
done

if [[ -z "$CODEOWNERS" ]]; then
  fail "No CODEOWNERS file found — dependency files have no required review"
else
  pass "CODEOWNERS file present: $CODEOWNERS"
  HITS=0
  for pattern in 'package\.json' "${LOCKFILE//./\\.}" '\.npmrc' 'Dockerfile'; do
    grep -qE "$pattern" "$CODEOWNERS" 2>/dev/null && HITS=$((HITS+1))
  done
  if [[ $HITS -ge 2 ]]; then
    pass "Dependency files appear under CODEOWNERS ($HITS/4 matched)"
  else
    warn "CODEOWNERS exists but may not cover package.json / lockfile / .npmrc / Dockerfile"
  fi
fi

echo
echo "──────────────────────────────────────"
echo "Summary: ${FAILS} fail, ${WARNS} warn"
[[ $FAILS -gt 0 ]] && exit 1 || exit 0
