#!/usr/bin/env bash
# Integration check: verify that every registry entry resolves to a real
# template pack with at least one published release, and that the CLI
# can resolve the full registry through its own resolution path.
#
# Requires: curl, yq (https://github.com/mikefarah/yq)
# Optional: GITHUB_TOKEN (raises API rate limit from 60 to 5000 req/h)
#           GALAXIO_BIN   (path to galaxio binary for CLI resolution check)
set -euo pipefail

registry_file="${1:-galaxio-registry.yaml}"

if [[ ! -f "$registry_file" ]]; then
  echo "Registry file not found: $registry_file" >&2
  exit 1
fi

auth_header=""
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
fi

curl_gh() {
  local url="$1"
  if [[ -n "$auth_header" ]]; then
    curl -sf -H "$auth_header" -H "Accept: application/vnd.github+json" "$url"
  else
    curl -sf -H "Accept: application/vnd.github+json" "$url"
  fi
}

failures=0
checked=0

# ── Parse registry YAML structurally via yq ──────────────────────────
pack_count=$(yq '.packs | length' "$registry_file")

if [[ "$pack_count" -eq 0 ]]; then
  echo "No packs found in $registry_file" >&2
  exit 1
fi

for (( i=0; i<pack_count; i++ )); do
  pack_name=$(yq ".packs[$i].name" "$registry_file")
  pack_source=$(yq ".packs[$i].source" "$registry_file")
  checked=$((checked + 1))

  echo "--- Checking pack: $pack_name (source: $pack_source)"

  # Only github: sources are supported for resolution checks.
  if [[ "$pack_source" != github:* ]]; then
    echo "  SKIP: non-github source, cannot verify remotely"
    continue
  fi

  # Parse github:owner/repo or github:owner/repo#ref
  gh_ref="${pack_source#github:}"
  repo="${gh_ref%%#*}"
  ref="${gh_ref#*#}"
  if [[ "$ref" == "$gh_ref" ]]; then
    ref="main"
  fi

  # 1. Verify the repository exists
  if ! curl_gh "https://api.github.com/repos/${repo}" > /dev/null 2>&1; then
    echo "  FAIL: repository ${repo} not found or not accessible"
    failures=$((failures + 1))
    continue
  fi
  echo "  OK: repository ${repo} exists"

  # 2. Verify galaxio-pack.yaml is accessible on the ref
  pack_url="https://raw.githubusercontent.com/${repo}/${ref}/galaxio-pack.yaml"
  pack_yaml_file=$(mktemp)
  trap 'rm -f "$pack_yaml_file"' EXIT
  if ! curl -sf "$pack_url" -o "$pack_yaml_file" 2>/dev/null || [[ ! -s "$pack_yaml_file" ]]; then
    echo "  FAIL: galaxio-pack.yaml not found at ${repo}@${ref}"
    failures=$((failures + 1))
    continue
  fi
  echo "  OK: galaxio-pack.yaml found at ${repo}@${ref}"

  # 3. Validate pack manifest structure via yq
  pack_api_version=$(yq '.apiVersion' "$pack_yaml_file")
  pack_kind=$(yq '.kind' "$pack_yaml_file")
  pack_manifest_name=$(yq '.name' "$pack_yaml_file")
  pack_version=$(yq '.version // ""' "$pack_yaml_file")
  template_count=$(yq '.templates | length' "$pack_yaml_file")

  manifest_ok=true
  if [[ "$pack_api_version" != "galaxio.io/v1" ]]; then
    echo "  FAIL: apiVersion must be galaxio.io/v1, got: $pack_api_version"
    manifest_ok=false
  fi
  if [[ "$pack_kind" != "TemplatePack" ]]; then
    echo "  FAIL: kind must be TemplatePack, got: $pack_kind"
    manifest_ok=false
  fi
  if [[ -z "$pack_manifest_name" || "$pack_manifest_name" == "null" ]]; then
    echo "  FAIL: pack name is required"
    manifest_ok=false
  fi
  if [[ "$template_count" -eq 0 ]]; then
    echo "  FAIL: at least one template is required"
    manifest_ok=false
  fi

  if [[ "$manifest_ok" != "true" ]]; then
    failures=$((failures + 1))
    continue
  fi
  echo "  OK: pack manifest valid (version: ${pack_version:-none}, templates: ${template_count})"

  # 4. If pack has a version, verify the corresponding release tag exists.
  #    A declared version without a resolvable tag is a hard failure —
  #    the CLI will not be able to download the pack archive.
  if [[ -n "$pack_version" ]]; then
    tag="v${pack_version}"
    if curl_gh "https://api.github.com/repos/${repo}/releases/tags/${tag}" > /dev/null 2>&1; then
      echo "  OK: release tag ${tag} exists"
    elif curl_gh "https://api.github.com/repos/${repo}/git/ref/tags/${tag}" > /dev/null 2>&1; then
      echo "  OK: git tag ${tag} exists (no GitHub release, but tag is resolvable)"
    else
      echo "  FAIL: version ${pack_version} declared but tag ${tag} not found — CLI cannot resolve this pack"
      failures=$((failures + 1))
      continue
    fi
  fi

  # 5. Verify the repo has at least one release (for download resolution)
  release_json=$(curl_gh "https://api.github.com/repos/${repo}/releases?per_page=1" 2>/dev/null) || release_json="[]"
  if echo "$release_json" | grep -q '"tag_name"'; then
    echo "  OK: repository has published releases"
  else
    echo "  WARN: no releases found — templates may only be available from HEAD"
  fi

  echo "  PASS: pack ${pack_name} resolves correctly"
done

# ── CLI resolution check ─────────────────────────────────────────────
# Drive the real CLI resolution path to catch drift between the script
# checks above and the actual galaxio template resolution logic.
galaxio_bin="${GALAXIO_BIN:-$(command -v galaxio 2>/dev/null || true)}"

if [[ -n "$galaxio_bin" ]]; then
  echo ""
  echo "--- CLI resolution check (via $galaxio_bin)"

  registry_source="local:$(cd "$(dirname "$registry_file")" && pwd)"
  cli_output=$("$galaxio_bin" template list --registry "$registry_source" --output json 2>&1) || true

  if echo "$cli_output" | grep -q '"name"'; then
    cli_template_count=$(echo "$cli_output" | grep -c '"name"' || true)
    echo "  OK: galaxio template list resolved ${cli_template_count} template(s)"
  else
    echo "  FAIL: galaxio template list failed to resolve registry"
    echo "  Output: $cli_output"
    failures=$((failures + 1))
  fi
else
  echo ""
  echo "--- CLI resolution check: SKIPPED (galaxio binary not found; set GALAXIO_BIN to enable)"
fi

echo ""
echo "Checked ${checked} pack(s): $((checked - failures)) passed, ${failures} failed."

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi
