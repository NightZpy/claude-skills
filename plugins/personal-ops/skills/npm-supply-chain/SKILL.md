---
name: npm-supply-chain
description: Use when I ask to "set up npm supply-chain protection on this machine" (or equivalent). 4-step recipe - npmrc/bunfig release-age delays, pin all deps to exact versions, commit the lockfile, then report what changed.
---

# NPM Supply-Chain Protection — 4-Step Recipe

When I ask "set up npm supply-chain protection on this machine" (or equivalent), execute these four steps in order, then report files changed, deps pinned, and anything unexpected.

1. **Edit `~/.npmrc`** — keep every existing line (auth tokens, registry config, etc.), append:
   ```
   min-release-age=7
   minimum-release-age=10080
   save-exact=true
   ```

2. **Edit `~/.bunfig.toml`** (create if missing) — keep existing content, append:
   ```toml
   [install]
   minimumReleaseAge = 604800
   ```

3. **Pin every dependency** in the current project's `package.json` — strip `^` and `~` from every version under `dependencies`, `devDependencies`, and `peerDependencies`. Exact versions only.

4. **Commit the lockfile** (`bun.lock` / `package-lock.json` / `pnpm-lock.yaml`) so the resolved tree is locked in git.

**Report after running:** files changed, deps pinned (count + names if non-trivial), anything unexpected (mismatches, conflicts, lockfile drift, etc.). In a monorepo, apply step 3 to every workspace `package.json` that declares real deps — skip the root if it only carries workspace metadata.

**Why:** caret/tilde + npm's default zero-second release window means a single compromised publish lands in your tree on the next `install`. Pinning + a 7-day release-age delay closes both holes; lockfile commit makes the resolved tree auditable.
