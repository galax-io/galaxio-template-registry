<!--
Sync Impact Report
- Version change: (template) -> 1.0.0
- Bump rationale: MAJOR, the first ratified constitution of galaxio-template-registry.
- Sections: Precedence; Core Principles (I. Pointers, not templates; II. The manifest
  is a public contract of galaxio-cli; III. Every listed pack resolves; IV. The
  manifest carries its own version; V. Releases come only from the release workflow;
  VI. The shared kit and process are not edited here; VII. Least privilege, no secrets);
  Public Contracts and Dependencies; Development Workflow and Quality Gates; Governance.
- Templates checked: .specify/templates/plan-template.md (Constitution Check reads the
  principles below as gates; no change needed), .specify/templates/spec-template.md,
  .specify/templates/tasks-template.md (no change needed; the kit is not edited here).
- Follow-up TODOs: none.
-->

# galaxio-template-registry Constitution

## Precedence

When rules disagree, the higher level wins:

1. The maintainer's direct instruction.
2. The ecosystem constitution (`galax-io/galaxio-sdlc-backlog`, `.specify/memory/constitution.md`).
3. This constitution.
4. This repository's `AGENTS.md`.

This constitution MAY tighten the ecosystem principles and add its own; it MUST NOT
contradict them. A spec or plan that touches this repository is checked against both.

## Core Principles

### I. Pointers, not templates

- The repository MUST NOT contain template content. `galaxio-registry.yaml` maps a pack
  name to the repository that holds the pack; templates live and are versioned in that
  repository (today `galax-io/templates-gatling`).
- `galaxio-registry.yaml` at the repository root MUST stay the single registry manifest.
  A second manifest, a per-pack copy of `galaxio-pack.yaml`, or a pack version pinned in
  the registry is a violation: pack versions are pinned in the pack's own
  `galaxio-pack.yaml` (`README.md`, "Pinning and inspecting versions").

Rationale: the registry is an index. Duplicating pack data here creates a second source
of truth that drifts from the pack repositories the CLI actually downloads from.

### II. The manifest is a public contract of galaxio-cli

- `galaxio-cli` reads this repository by default, from `main`. The shape of
  `galaxio-registry.yaml` — `apiVersion: galaxio.io/v1`, `kind: TemplateRegistry`, a
  top-level `version`, and `packs[]` entries with `name`, `source` and `description` —
  MUST NOT change without a change to `galaxio-cli` that reads the new shape, planned in
  the same feature.
- A `source` MUST use a form the CLI resolves: `github:owner/repo`, optionally
  `#ref` (default `main`), as parsed by `.github/scripts/check-registry-resolution.sh`.
- Removing or renaming an existing pack `name` is a breaking change for users who run
  `galaxio template` commands against it; it MUST be a deliberate, stated decision in
  the feature's spec, never a side effect.
- `main` MUST always hold a manifest the CLI can resolve: there is no release branch
  between a merge and the users.

Rationale: every merge to `main` reaches every CLI user that has not overridden
`--registry`. Compatibility is deliberate (ecosystem principle).

### III. Every listed pack resolves

- Every entry in `packs` MUST point to an accessible GitHub repository whose
  `galaxio-pack.yaml` on the referenced branch has `apiVersion: galaxio.io/v1`,
  `kind: TemplatePack`, a `name` and at least one template; a declared pack `version`
  MUST have a resolvable tag `v<version>`. These are the checks of
  `check-registry-resolution.sh`.
- The `integration resolution check` job in `.github/workflows/ci.yml` (real
  `galaxio-cli`, real GitHub) MUST stay part of CI and MUST NOT be replaced by
  stubs or fixtures. A manifest change is accepted on that job's result, not on reading.

Rationale: the registry's only value is that its entries work end to end; the real CLI
resolution path catches drift that a static check would miss.

### IV. The manifest carries its own version

- A pull request that changes `galaxio-registry.yaml` MUST change its top-level
  `version`: a minor bump when the change is a `feat`, a patch bump when it is a `fix`
  (`.github/scripts/check-registry-version-bump.sh`, run by the `versioning` job; its
  rule is what `check-registry-version-bump_test.sh` asserts).
- `version` MUST stay semantic `X.Y.Z` and MUST NOT go backwards.

Rationale: the version is how consumers tell registry states apart; the bump rule ties it
to the nature of the change.

### V. Releases come only from the release workflow

- A release MUST be made by `.github/workflows/release.yml` (`workflow_dispatch`, input
  `version`): it validates `X.Y.Z`, refuses an existing tag, bumps `version`, writes
  `CHANGELOG.md` with git-cliff (`cliff.toml`), and creates the tag `v<version>` and the
  GitHub Release.
- Tags and `CHANGELOG.md` releases MUST NOT be made by hand; `release/*` branches MUST NOT
  be created.
- A release tag MUST NOT be deleted and a version number MUST NOT be reused (`AGENTS.md`,
  "Release Process").
- Commit subjects MUST follow Conventional Commits: `cliff.toml` builds the release notes
  from them and the version-bump check reads the `feat`/`fix` prefix.

Rationale: one release path keeps the tag, the manifest `version` and the changelog in
step; moving or reusing a tag breaks anyone who resolved against it.

### VI. The shared kit and process are not edited here

- `.claude/skills/speckit-*`, `.agents/skills/speckit-*` and the Spec Kit directories
  under `.specify/` MUST match `.specify/speckit-kit.sha256` byte for byte
  (`scripts/check-speckit.sh`, the `speckit` workflow). Changes arrive from
  `spec-kit-galaxio-bootstrap` by `copier update`; only `.specify/memory/` is this
  repository's own.
- The `specify` CLI's `extension`, `preset` and `integration` commands MUST NOT be run
  here.
- The linkage gate (`scripts/check-linkage.sh`, `.claude/hooks/linkage-guard.sh`,
  `.githooks/pre-push`, `.github/workflows/linkage.yml`) MUST NOT be weakened locally.

Rationale: the kit and the process are shared by every repository of the organization;
a local edit forks them silently.

### VII. Least privilege, no secrets

- Workflows MUST keep their declared permissions: `ci` and `speckit` read-only,
  `linkage` read-only plus issues and pull requests read, and only `release` with
  `contents: write`.
- `BACKLOG_READ_TOKEN` MUST be used only by the `linkage` workflow, which checks out with
  `persist-credentials: false` and runs no third-party build code.
- Tokens, keys and credentials MUST NOT be committed; the resolution check takes
  `GITHUB_TOKEN` from the environment only.

Rationale: the release job can push to `main` and tags, and the backlog is private; any
widening of either is a security change.

## Public Contracts and Dependencies

- Consumer: `galaxio-cli` (default registry; `README.md`, "How resolution works").
  The contract is Principle II plus the resolution chain registry -> `galaxio-pack.yaml`
  -> release tag `v<version>` in the pack repository.
- Dependencies, declared in `catalog-info.yaml` `spec.dependsOn` with
  `galaxio.io/uses.*` annotations: `templates-gatling` (the `gatling` pack) and
  `spec-kit-galaxio-bootstrap` (process and kit via `copier update`).
- Adding or removing a pack MUST update `catalog-info.yaml` (`dependsOn` and the
  `galaxio.io/uses.<repo>` annotation) and the "Packs" table of `README.md` in the same
  change.

## Development Workflow and Quality Gates

- Work enters through the backlog: every pull request is in a milestone of this
  repository and links a feature with `Part of galax-io/galaxio-sdlc-backlog#N`
  (`linkage` workflow).
- Gates on a pull request: `ci` (`lint`: shellcheck on `.github/scripts/*.sh`,
  actionlint, YAML syntax of every `*.yaml`/`*.yml`; `versioning`; `integration
  resolution check`), `linkage`, `speckit`. A failing gate is fixed, not skipped.
- A change to a script under `.github/scripts/` that has a `_test.sh` suite MUST come
  with a case in that suite that fails before and passes after.
- Merge is the maintainer's decision; history on pull request branches is rebased, never
  merged, and `main` is never force-pushed.

## Governance

- This constitution is amended only by a pull request to this repository, approved
  explicitly by the maintainer, that updates the Sync Impact Report at the top of this
  file.
- Versioning of this document: MAJOR for removing or redefining a principle, MINOR for
  adding a principle or section or materially widening one, PATCH for wording that does
  not change meaning.
- An exception to a principle MUST be recorded in the plan's Complexity Tracking with an
  owner and a removal date; an exception without both is a violation.
- Specs and plans that touch this repository MUST pass the Constitution Check of
  `.specify/templates/plan-template.md` against these principles; reviewers answer each
  principle with yes or no.

**Version**: 1.0.0 | **Ratified**: 2026-10-20 | **Last Amended**: 2026-10-20
