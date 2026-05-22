# galaxio-template-registry

Default template registry for `galaxio-cli`.

The registry points the CLI to public template packs. It does not contain the
templates themselves.

## Registry

The root manifest is [`galaxio-registry.yaml`](galaxio-registry.yaml).

```yaml
apiVersion: galaxio.io/v1
kind: TemplateRegistry
packs:
  - name: gatling
    source: github:galax-io/templates-gatling
    description: Gatling performance testing templates
```

## Packs

| Name | Source | Description |
| --- | --- | --- |
| `gatling` | `github:galax-io/templates-gatling` | Gatling performance testing templates |

## How resolution works

The registry, pack manifests, and GitHub releases form a three-level chain:

1. **Registry source** (`galaxio-registry.yaml`) maps each pack name to a
   GitHub repository via `source: github:owner/repo`.
2. The CLI fetches `galaxio-pack.yaml` from that repository's default branch
   (`main`). Each template entry in the pack can declare a `version` field.
3. When a pack declares `version: 0.3.0`, the CLI resolves it to the GitHub
   release tagged `v0.3.0` and downloads the ZIP archive from that release.
   If no version is set, the CLI uses the repository's default branch HEAD.

```
galaxio-registry.yaml          galaxio-pack.yaml (in source repo)
┌────────────────────┐         ┌──────────────────────┐
│ packs:             │         │ version: 0.3.0       │
│   - name: gatling  │ ──────▶│ templates:           │ ──▶ GitHub release v0.3.0
│     source: github │         │   - name: scala-sbt  │
│     :galax-io/...  │         │     path: scala-sbt  │
└────────────────────┘         └──────────────────────┘
```

## Overriding the default registry

The CLI uses this repository by default. To point at a different registry:

```sh
# Persist a custom registry
galaxio template configure --registry github:my-org/my-registry

# Check current configuration
galaxio template configure --show

# One-off override on any template command
galaxio template list --registry github:my-org/my-registry

# Use a local directory during development
galaxio template list --registry local:./path/to/registry
```

## Pinning and inspecting versions

- **Pin a version**: set the `version` field in `galaxio-pack.yaml` inside the
  template source repo. The CLI will download exactly that release tag.
- **Inspect current versions**: run `galaxio template list` to see each
  template's pack version and individual version.
- **Update a pack**: publish a new GitHub release tag in the source repo, then
  bump the `version` in its `galaxio-pack.yaml`. The next `galaxio template
  list` or `galaxio template init` call will pick up the new version.
- **Clear cached downloads**: run `galaxio template clear-cache` to force
  re-fetching on the next command.
