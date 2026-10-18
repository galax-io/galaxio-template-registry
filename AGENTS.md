# galaxio-template-registry — Agent Guide

Template registry for Galaxio CLI — versioned project templates and metadata

> The sections above the `---` are **project-specific** — fill them in for each new
> project. Everything below the `---` is the **stack-agnostic development process**
> and is meant to be reused verbatim across all projects.

## Role

Maintainer of the default template registry for `galaxio-cli`: a versioned manifest that points the CLI to public template packs. It holds no templates. Keep the manifest, its version bump and the resolution check in step.

## Stack

YAML manifest (`galaxio-registry.yaml`), bash scripts under `.github/scripts/` checked with shellcheck and actionlint, GitHub Actions (`ci`, `release`); changelog by git-cliff (`cliff.toml`). No build, no runtime.

## Commands

```bash
# lint    shellcheck .github/scripts/*.sh
# test    bash .github/scripts/check-registry-version-bump_test.sh
# check   bash .github/scripts/check-registry-version-bump.sh      # needs the base ref, as in CI
# resolve bash .github/scripts/check-registry-resolution.sh        # installs nothing; CI runs it with galaxio-cli
```

## Structure

<!-- A LIGHT search index, not a full tree. List only the entry points an agent needs
     to FIND code fast — one terse line per area (`dir/ -> what lives there`). Omit
     anything discoverable by looking; an exhaustive tree is noise and rots fast. -->
`galaxio-registry.yaml` -> the manifest (packs and their sources, own semantic `version`); `.github/scripts/` -> version-bump checker with its test, resolution check; `.github/workflows/ci.yml` -> lint, versioning, integration resolution check; `.github/workflows/release.yml` -> manual release; `CHANGELOG.md`, `cliff.toml` -> release notes.

## Architecture

The manifest maps a pack name to a GitHub repository (`source: github:owner/repo`); the CLI then reads `galaxio-pack.yaml` from that repository and resolves a pack version to the release tagged `v<version>`. A change to the manifest must bump its `version` itself (minor for `feat`, patch for `fix`); the release workflow bumps it again on release. See `README.md` for the resolution chain.

## Test Model

Tests are bash and run in CI: `check-registry-version-bump_test.sh` covers the bump rule with fixtures; the `integration resolution check` job installs `galaxio-cli` and resolves every pack in the manifest end to end. A manifest change is checked by that job, not by reading it.

---

<!-- ===================================================================== -->
<!-- STACK-AGNOSTIC DEVELOPMENT PROCESS — reuse verbatim across projects.   -->
<!-- ===================================================================== -->

## Boundaries

**Always:** format before commit, branch from `main`, keep commits semantic and green, preserve backward compat for published public APIs and any downstream consumers. `galaxio-registry.yaml` = the registry's truth, `.github/workflows/` = CI/release truth.

**Ask first:** new deps or upgrades, changing public API signatures / observable behavior / serialized formats, editing another repo, release/publish workflow changes.

**Never:** force-push or commit to `main`, merge commits in PR branches (rebase only), commit broken code, opportunistic refactors outside scope, mock external systems where a real integration path exists.

## Milestones (ALWAYS)

Every piece of work is tied to a milestone. No exceptions unless explicitly told otherwise.

- **Every PR** must be assigned to the active milestone before merging. No milestone = do not merge.
- **Issues are for important tasks**, not technical ones. A PR that completes one writes `Closes owner/repo#N` (the issue closes when the PR lands on `main`); one PR of several writes `Part of owner/repo#N`. A linked issue carries the PR's milestone. A technical PR (sync, pins, docs, CI) needs no issue: its commit already records it.
- **Spec work** (`specs/NNN-*/`) belongs to the milestone that owns the spec. Link the spec PR to the milestone immediately when creating it.
- **Active milestone** = the lowest-numbered open milestone that matches the current spec/plan. Check `gh api repos/galax-io/galaxio-template-registry/milestones` if unsure.

## Feature milestones (ALWAYS)

A feature is an issue in `galax-io/galaxio-sdlc-backlog`. It belongs to exactly one backlog milestone whose description has the line `Release: business`. Backlog milestones without that line (the backlog's own tooling and documents) are not releases and follow "Milestones" above.

- **Feature issue.** Lists the work in every repository it touches as a checklist, one line per issue or PR: `- [ ] galax-io/<repo>#<N> → <repo milestone>`. A line is checked when that work is merged and the repository milestone it names has been released, so its tag exists.
- **Repository work.** Every issue and PR of a feature carries the version milestone of its own repository and writes `Part of galax-io/galaxio-sdlc-backlog#<feature>`. A repository ships its own version when its milestone is complete, as under "Release Process". `scripts/check-linkage.sh` skips the same-milestone rule for a link to a feature; the PR still needs its own milestone.
- **Every PR links a feature.** No PR of a product repository merges without `Part of galax-io/galaxio-sdlc-backlog#<feature>` (or a closing link to a feature); `scripts/check-linkage.sh --pr` fails it. A bot's PR (a bot author, or a `dependabot/` or `update/` branch) and the backlog's own PRs are exempt. The backlog is private, so the CI job reads it with `BACKLOG_READ_TOKEN`, a read-only token for that repository (Issues and Metadata) set as an organisation secret; without it the gate fails and says it cannot read the backlog. Maintenance and technical PRs with no feature of their own link the standing feature of the active business milestone (the issue with the label `standing`); every business milestone has one.
- **Work enters through the backlog.** A bug, an audit finding or a request is not worked on until it belongs to a feature: grouped into one or given one. An issue from outside stays in its repository, which is public, and carries the label `needs-feature` until it is linked to a feature in the backlog.
- **Feature done.** A feature issue is closed only when every line of its checklist is checked.
- **Release.** When every feature of a business milestone is closed, close the milestone and publish a GitHub Release in `galax-io/galaxio-sdlc-backlog` that lists each feature with the repository versions that carry it. Name the release and its tag by the milestone's id, the title up to its first em dash, lowercased (`M1 — first run` → `m1`).
- **Published releases are not edited.** A revert after the release is a new feature in the next business milestone.
- **Never** close a business milestone with an open feature, release a feature whose repository version is not tagged, or leave a repository version out of the release text.

## Commits & PRs

- **Spec-first.** `specs/NNN-*/` artifacts → `docs(speckit): add NNN-<feature> spec/plan/tasks` commit BEFORE any `feat`/`fix`. Never folded into implementation.
- **1 issue = 1 commit.** Each tracked GitHub issue maps to one semantic commit (`feat(scope): … (#NNN)`), green on its own (`shellcheck .github/scripts/*.sh` and the test above). Docs, tweaks, and out-of-scope improvements go in separate PRs — never mixed with issue commits.
- **Intent, not path.** No add-then-remove within a PR. Squash churn before review.
- **1 concern per PR.** Feature ≠ docs/README. Stack dependent PRs; update with `--force-with-lease`.
- **Idiomatic code.** Follow the language's idioms and the conventions already in the codebase; no control-flow-by-exception, no dead/duplicated code.

## Agents & Models (ALWAYS)

Route work by the reasoning it needs, not by habit; parallelize only where agents would not rebuild the same context. Every model is the newest of its class that the accounts can run; an older one is never used.

| Tier | Claude (effort) | Codex (effort) | Work |
|---|---|---|---|
| deep | `claude-opus-5-5` (xhigh) | `gpt-6.1-sol` (xhigh) | complex code, review and verification (every critic), research, root-cause analysis, specs/plans, architecture |
| light | `claude-sonnet-5-5` (high) | `gpt-6.1-sol` (high) | simpler work a plan already spells out: task/issue generation, mechanical infra (CI config, version pins, renames, doc fixes) |
| trivial | `claude-haiku-5-5` (medium) | `gpt-6-luna` (medium) | very simple edits, gathering context, finding files, bookkeeping |
| exceptional | — | `gpt-6-astra` (xhigh) | only when the maintainer names it for a task; no agent and not the engine chooses it |

- **Newest only.**
  - When a newer model of a class appears, this table and every pin of it move to it in the same change: `.claude/settings.json`, `.claude/agents/`, `setup-speckit.sh`, and any code that routes models.
  - Luna and Astra stay at 6 because Codex refuses `gpt-6.1-luna` and `gpt-6.1-astra` to a ChatGPT account.
  - `gpt-6.1-sol` needs Codex CLI 0.162 or later.
  - Claude Code's own aliases and its background model are pinned to the table in `.claude/settings.json` (`env`: `ANTHROPIC_DEFAULT_OPUS_MODEL`, `…_SONNET_MODEL`, `…_HAIKU_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`). Without that pin its `haiku` alias means an older Haiku.
- **Codex has no middle model.** Light work runs Sol on high effort, one less than deep; Luna is for trivial work only.
- **Reviews are deep.** Every critic and reviewer runs at the deep tier, on the other vendor than the work it judges.
- **Research is adversarial.** Deep research gets a second opinion from the other vendor (`deep-researcher` does this via `codex exec --sandbox read-only`). A claim only one model supports is unverified, not a fact.
- **Every task carries its tier.** `tasks.md` lines add `[tier:deep]`, `[tier:light]` or `[tier:trivial]` next to `[P]`, and issues carry the matching `tier:*` label where the project labels them. When unsure, it is deep.
- **Parallelize by context, not by file.**
  - Every sub-agent builds its own context from scratch. Agents that must read the same code, spec, or repository repeat that cost and leave integration work behind.
  - `[tier:deep]` work that shares a context runs in one agent, task after task: the main session or a single deep sub-agent. This holds even when `[P]` marks the tasks as parallelizable.
  - Fan deep work out only where each agent's context differs: separate repositories, or subsystems an agent can learn without the others.
  - `[tier:light]` mechanical work (`infra-worker`) and `[tier:trivial]` work (`trivial-worker`) may fan out freely.
  - Dependent tasks stay sequential.
- **Pinned, not remembered.**
  - `setup-speckit.sh` pins spec-kit skills to their tier; override with `SPECKIT_DEEP_MODEL` / `SPECKIT_LIGHT_MODEL`.
  - `.claude/agents/` defines the tiered sub-agents, each with its tier's model and `effort`.
  - Where a project routes models in code, it routes by this table: a task or stage names its tier, and each harness runs its own vendor's model of that tier. A model outside the table is an error.

## Release Process (MANDATORY)

A release is the manual `release` workflow (`workflow_dispatch`, input `version`, for example `1.1.0`). It validates the version, checks the tag does not exist, bumps `version` in `galaxio-registry.yaml`, updates `CHANGELOG.md` with git-cliff, creates and pushes the tag `v<version>` and creates the GitHub Release. Do not tag or bump by hand, and do not create `release/*` branches: the registry is consumed from `main` by `galaxio-cli`.

### Rules

- **Never delete a release tag** and **never reuse a version number**: packs and the CLI resolve against them.
- **Before releasing**: every PR merged since the previous tag is assigned to the milestone and every issue in it whose fix is on `main` is closed (`scripts/check-linkage.sh --for-tag vX.Y.Z`).

<!-- The issue↔PR↔milestone contract above is enforced mechanically by         -->
<!-- scripts/check-linkage.sh, run from two places:                             -->
<!--   .claude/hooks/linkage-guard.sh  in-session, before the command runs      -->
<!--     (LINKAGE_OFF=1 bypasses it for a deliberate release)                   -->
<!--   .githooks/pre-push               on any push, from any client            -->
<!--     enable once per clone: git config core.hooksPath .githooks             -->
<!-- Both are fast local failures and both can be skipped. Nothing checks       -->
<!-- server-side unless the release workflow runs check-linkage.sh --for-tag.   -->
