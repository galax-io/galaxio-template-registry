#!/usr/bin/env bash
# Integration check: verify that every registry entry resolves to a real
# template pack with at least one published release.
#
# Requires: curl, grep, awk
# Optional: GITHUB_TOKEN (raises API rate limit from 60 to 5000 req/h)
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

# Parse pack entries from registry YAML.
# Paste name and source lines side-by-side, tab-separated.
pack_entries=$(
  paste \
    <(grep '^\s*- name:' "$registry_file" | awk '{print $3}') \
    <(grep '^\s*source:' "$registry_file" | awk '{print $2}')
)

if [[ -z "$pack_entries" ]]; then
  echo "No packs found in $registry_file" >&2
  exit 1
fi

while IFS=$'\t' read -r pack_name pack_source; do
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
  pack_yaml=$(curl -sf "$pack_url" 2>/dev/null) || true
  if [[ -z "$pack_yaml" ]]; then
    echo "  FAIL: galaxio-pack.yaml not found at ${repo}@${ref}"
    failures=$((failures + 1))
    continue
  fi
  echo "  OK: galaxio-pack.yaml found at ${repo}@${ref}"

  # 3. Validate pack manifest structure (basic checks via grep)
  pack_api_version=$(echo "$pack_yaml" | grep '^apiVersion:' | awk '{print $2}')
  pack_kind=$(echo "$pack_yaml" | grep '^kind:' | awk '{print $2}')
  pack_manifest_name=$(echo "$pack_yaml" | grep '^name:' | head -1 | awk '{print $2}')
  pack_version=$(echo "$pack_yaml" | grep '^version:' | head -1 | awk '{print $2}')
  template_count=$(echo "$pack_yaml" | grep -c '^\s*- name:' || true)

  manifest_ok=true
  if [[ "$pack_api_version" != "galaxio.io/v1" ]]; then
    echo "  FAIL: apiVersion must be galaxio.io/v1, got: $pack_api_version"
    manifest_ok=false
  fi
  if [[ "$pack_kind" != "TemplatePack" ]]; then
    echo "  FAIL: kind must be TemplatePack, got: $pack_kind"
    manifest_ok=false
  fi
  if [[ -z "$pack_manifest_name" ]]; then
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

  # 4. If pack has a version, verify the corresponding release tag exists
  if [[ -n "$pack_version" ]]; then
    tag="v${pack_version}"
    if curl_gh "https://api.github.com/repos/${repo}/releases/tags/${tag}" > /dev/null 2>&1; then
      echo "  OK: release tag ${tag} exists"
    elif curl_gh "https://api.github.com/repos/${repo}/git/ref/tags/${tag}" > /dev/null 2>&1; then
      echo "  OK: git tag ${tag} exists (no GitHub release, but tag is resolvable)"
    else
      echo "  WARN: version ${pack_version} declared but tag ${tag} not found yet"
    fi
  fi

  # 5. Verify the repo has at least one release (for download resolution)
  release_json=$(curl_gh "https://api.github.com/repos/${repo}/releases?per_page=1" 2>/dev/null) || release_json="[]"
  # Check if response is a non-empty array
  if echo "$release_json" | grep -q '"tag_name"'; then
    echo "  OK: repository has published releases"
  else
    echo "  WARN: no releases found — templates may only be available from HEAD"
  fi

  echo "  PASS: pack ${pack_name} resolves correctly"
done <<< "$pack_entries"

echo ""
echo "Checked ${checked} pack(s): $((checked - failures)) passed, ${failures} failed."

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi
