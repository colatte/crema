# The repository on GitHub — branches, what blocks a merge, the robot

> The settings that are not in the tree. Everything below is applied through the
> API, and §5 reapplies all of it in one idempotent block — so a setting that
> drifts from this page is a bug in one of the two, never a mystery. The branch
> conventions this page enforces are written for contributors in
> [CONTRIBUTING.md](https://github.com/colatte/crema/blob/main/CONTRIBUTING.md);
> this page is what makes them true.

## 1. Where the repository lives, and why it matters

`colatte/crema`, public, GPL-3.0. Two things hang off the **default branch**,
`main`, and neither can be moved: GitHub Pages serves the landing page and the
Sparkle feed from `/docs` on `main` (docs/DECISIONS.md: the-feed-signs-itself),
and the issue forms, the pull-request template and the auto-close of issues
(`Fixes #n`) only work from the default branch. That is why a documentation-only
merge may reach `main` between releases (docs/DECISIONS.md:
main-takes-docs-outside-a-release) — and why nothing else may.

## 2. Branches

- **`main`** — every merge is a release, except the documentation-only case
  above. `release.sh` builds from it, the Release targets it, Pages serves it.
- **`dev`** — integration. Every pull request targets it; `main` takes it as a
  whole through one pull request per release (`dev` → `main`), and takes the
  appcast commit back from a short `release/X.Y.Z` branch right after (§3, and
  docs/RELEASE-GUIDE.md §5.4).
- **Work branches** — cut from `dev`, one per task, named as CONTRIBUTING.md
  "Branches" says, deleted at the merge (`delete_branch_on_merge`).

## 3. What blocks a merge — and what does not

Classic branch protection on **both** `main` and `dev`, identical except where
noted. There are no rulesets.

| Rule | `main` | `dev` | Why |
| --- | --- | --- | --- |
| Changes only through a pull request | yes | yes | The commits are written to tell the change, and a review — even one's own, a day later — needs the diff in one place. |
| Required status check `Build & test` | yes | yes | The one job in `ci.yml`: SwiftLint strict, SwiftFormat lint, the catalog self-test and checker, the full suite, a Release build and the rejection of ad-hoc plus hardened runtime. One job on purpose: splitting it into eight would multiply runners for a suite that takes four minutes whole. |
| Branch up to date before merging (`strict`) | yes | yes | Cheap here, so it stays on: what CI validated is what lands. |
| Conversation resolution | yes | yes | Costs nothing while there is no reviewer; the day there is one, an open comment cannot be merged past. |
| **Applies to administrators** (`enforce_admins`) | **yes** | **yes** | The rule that makes the others true for the owner too. Without it an admin `git push` bypasses every other rule with a "Bypassed rule violations" notice instead of a rejection (docs/DECISIONS.md: the-branch-rules-bind-the-admin-too). |
| Approving reviews required | 0 | 0 | A one-person project cannot require a second person. Raised the day there is one. |
| Force-push, deletion | no | no | |

**What does not block.** Nothing else: no CODEOWNERS, no signed-commit
requirement, no linear history (merges are merge commits by design — squash and
rebase are switched off at the repository level, so the buttons do not exist).

**What the rule costs the release.** With `enforce_admins` on, the appcast
commit can no longer be pushed straight to `main` — it travels on
`release/X.Y.Z`, through a pull request that `Build & test` gates, in the same
sitting as the Release; and `main` comes back into `dev` through a pull request
as well (`main` → `dev`), never a local merge pushed by hand. The whole
sequence is docs/RELEASE-GUIDE.md §5.4.

## 4. The robot

- **CI** — `.github/workflows/ci.yml`, on push and pull request to `main` and
  `dev`; a newer commit on the same ref supersedes the run in flight.
- **Dependabot** — `.github/dependabot.yml`: `github-actions` weekly (the
  `uses:` pins) and `swift` weekly (the Sparkle pin the project file carries),
  both targeting **`dev`** — a bot cannot land on `main` between releases, and
  the default target is the default branch. The `swift` entry is a declared bet:
  the manifest lives inside the Xcode project, which Dependabot learned to read
  behind a feature flag (dependabot-core #14332, merged 2026-03-05) the
  documentation does not yet mention; the first pull request it opens — or the
  first "no manifest found" on Insights → Dependency graph → Dependabot —
  decides whether the entry stays.
- **Pages** — environment `github-pages`, built from `/docs` on `main` by the
  push itself. There is no deploy workflow; there is nothing to deploy.
- **No secrets, no variables.** The signing identity and the EdDSA key live on
  the release machine (docs/RELEASE-GUIDE.md §1), never in Actions.

## 5. Reapplying everything (idempotent)

Run as an admin with `gh` logged in. Every call sets the full state, so a second
run changes nothing.

```bash
R=colatte/crema

# Merge buttons: merge commits only; delete the branch at the merge.
gh api -X PATCH repos/$R -f allow_merge_commit=true -f allow_squash_merge=false \
  -f allow_rebase_merge=false -f delete_branch_on_merge=true

# Both branches, the same protection (the JSON is the whole state).
for b in main dev; do
  gh api -X PUT repos/$R/branches/$b/protection --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["Build & test"] },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
done

# Read it back — this is what §3 claims.
for b in main dev; do
  gh api repos/$R/branches/$b/protection --jq \
    '{branch:"'$b'", checks:.required_status_checks.contexts, strict:.required_status_checks.strict,
      admins:.enforce_admins.enabled, conversation:.required_conversation_resolution.enabled,
      reviews:.required_pull_request_reviews.required_approving_review_count}'
done
```

## 6. What stays human

Publishing a release (docs/RELEASE-GUIDE.md), merging any pull request, labelling
issues, and the two decisions this page leaves open on purpose: requiring a
review the day there is a second maintainer, and reconsidering the single CI job
the day the suite outgrows one runner.
