#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script_path="${repo_root}/.github/scripts/check-registry-version-bump.sh"

failures=0

base_registry() {
  cat <<'EOF'
apiVersion: galaxio.io/v1
kind: TemplateRegistry
version: 1.0.0
packs:
  - name: gatling
    source: github:galax-io/templates-gatling
    description: Gatling performance testing templates
EOF
}

create_repo() {
  local repo_dir="$1"

  git init -b main "$repo_dir" >/dev/null
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.com"

  base_registry > "${repo_dir}/galaxio-registry.yaml"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -m "feat: bootstrap registry" >/dev/null
  git -C "$repo_dir" checkout -b feature >/dev/null
}

# run_check <repo_dir> [env VAR=VAL ...]
# Always invokes the script via bash to avoid needing the exec bit.
run_check() {
  local repo_dir="$1"
  shift
  (
    cd "$repo_dir"
    "$@" bash "${script_path}"
  )
}

assert_success() {
  local name="$1"
  shift
  if "$@"; then
    printf 'PASS %s\n' "$name"
    return
  fi
  printf 'FAIL %s\n' "$name"
  failures=$((failures + 1))
}

assert_failure_contains() {
  local name="$1"
  local expected="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)"; then
    printf 'FAIL %s\nexpected failure containing: %s\n' "$name" "$expected"
    failures=$((failures + 1))
    return
  fi
  if [[ "$output" == *"$expected"* ]]; then
    printf 'PASS %s\n' "$name"
    return
  fi
  printf 'FAIL %s\nexpected output to contain: %s\nactual output:\n%s\n' "$name" "$expected" "$output"
  failures=$((failures + 1))
}

test_non_registry_change_passes() {
  local repo_dir
  repo_dir="$(mktemp -d)"
  trap 'rm -rf "$repo_dir"' RETURN
  create_repo "$repo_dir"

  printf '# docs\n' > "${repo_dir}/README.md"
  git -C "$repo_dir" add README.md
  git -C "$repo_dir" commit -m "docs: update readme" >/dev/null

  assert_success \
    "non-registry change does not require bump" \
    run_check "$repo_dir" env SKIP_FETCH=1 BASE=main
}

test_registry_change_without_bump_fails() {
  local repo_dir
  repo_dir="$(mktemp -d)"
  trap 'rm -rf "$repo_dir"' RETURN
  create_repo "$repo_dir"

  cat > "${repo_dir}/galaxio-registry.yaml" <<'EOF'
apiVersion: galaxio.io/v1
kind: TemplateRegistry
version: 1.0.0
packs:
  - name: gatling
    source: github:galax-io/templates-gatling
    description: Gatling performance testing templates
  - name: spring
    source: github:galax-io/templates-spring
    description: Spring Boot templates
EOF

  git -C "$repo_dir" add galaxio-registry.yaml
  git -C "$repo_dir" commit -m "feat(spring): add spring pack" >/dev/null

  assert_failure_contains \
    "registry change without version bump fails" \
    "galaxio-registry.yaml changed but version stayed 1.0.0" \
    run_check "$repo_dir" env SKIP_FETCH=1 BASE=main
}

test_feat_change_requires_minor_bump() {
  local repo_dir
  repo_dir="$(mktemp -d)"
  trap 'rm -rf "$repo_dir"' RETURN
  create_repo "$repo_dir"

  cat > "${repo_dir}/galaxio-registry.yaml" <<'EOF'
apiVersion: galaxio.io/v1
kind: TemplateRegistry
version: 1.1.0
packs:
  - name: gatling
    source: github:galax-io/templates-gatling
    description: Gatling performance testing templates
  - name: spring
    source: github:galax-io/templates-spring
    description: Spring Boot templates
EOF

  git -C "$repo_dir" add galaxio-registry.yaml
  git -C "$repo_dir" commit -m "feat(spring): add spring pack" >/dev/null

  assert_success \
    "feat change with minor bump passes" \
    run_check "$repo_dir" env SKIP_FETCH=1 BASE=main
}

test_feat_change_with_patch_bump_fails() {
  local repo_dir
  repo_dir="$(mktemp -d)"
  trap 'rm -rf "$repo_dir"' RETURN
  create_repo "$repo_dir"

  cat > "${repo_dir}/galaxio-registry.yaml" <<'EOF'
apiVersion: galaxio.io/v1
kind: TemplateRegistry
version: 1.0.1
packs:
  - name: gatling
    source: github:galax-io/templates-gatling
    description: Gatling performance testing templates
  - name: spring
    source: github:galax-io/templates-spring
    description: Spring Boot templates
EOF

  git -C "$repo_dir" add galaxio-registry.yaml
  git -C "$repo_dir" commit -m "feat(spring): add spring pack" >/dev/null

  assert_failure_contains \
    "feat change with patch bump fails" \
    "feat change requires a minor version bump" \
    run_check "$repo_dir" env SKIP_FETCH=1 BASE=main
}

test_fix_change_requires_patch_bump() {
  local repo_dir
  repo_dir="$(mktemp -d)"
  trap 'rm -rf "$repo_dir"' RETURN
  create_repo "$repo_dir"

  cat > "${repo_dir}/galaxio-registry.yaml" <<'EOF'
apiVersion: galaxio.io/v1
kind: TemplateRegistry
version: 1.0.1
packs:
  - name: gatling
    source: github:galax-io/templates-gatling
    description: Gatling performance testing templates (fixed url)
EOF

  git -C "$repo_dir" add galaxio-registry.yaml
  git -C "$repo_dir" commit -m "fix(gatling): correct source description" >/dev/null

  assert_success \
    "fix change with patch bump passes" \
    run_check "$repo_dir" env SKIP_FETCH=1 BASE=main
}

test_fix_change_with_minor_bump_fails() {
  local repo_dir
  repo_dir="$(mktemp -d)"
  trap 'rm -rf "$repo_dir"' RETURN
  create_repo "$repo_dir"

  cat > "${repo_dir}/galaxio-registry.yaml" <<'EOF'
apiVersion: galaxio.io/v1
kind: TemplateRegistry
version: 1.1.0
packs:
  - name: gatling
    source: github:galax-io/templates-gatling
    description: Gatling performance testing templates (fixed url)
EOF

  git -C "$repo_dir" add galaxio-registry.yaml
  git -C "$repo_dir" commit -m "fix(gatling): correct source description" >/dev/null

  assert_failure_contains \
    "fix change with minor bump fails" \
    "fix change requires a patch version bump" \
    run_check "$repo_dir" env SKIP_FETCH=1 BASE=main
}

test_missing_version_field_fails() {
  local repo_dir
  repo_dir="$(mktemp -d)"
  trap 'rm -rf "$repo_dir"' RETURN
  create_repo "$repo_dir"

  cat > "${repo_dir}/galaxio-registry.yaml" <<'EOF'
apiVersion: galaxio.io/v1
kind: TemplateRegistry
packs:
  - name: gatling
    source: github:galax-io/templates-gatling
    description: Gatling performance testing templates
  - name: spring
    source: github:galax-io/templates-spring
    description: Spring Boot templates
EOF

  git -C "$repo_dir" add galaxio-registry.yaml
  git -C "$repo_dir" commit -m "feat(spring): add spring pack" >/dev/null

  assert_failure_contains \
    "missing version field fails" \
    "galaxio-registry.yaml is missing a top-level version field" \
    run_check "$repo_dir" env SKIP_FETCH=1 BASE=main
}

test_non_registry_change_passes
test_registry_change_without_bump_fails
test_feat_change_requires_minor_bump
test_feat_change_with_patch_bump_fails
test_fix_change_requires_patch_bump
test_fix_change_with_minor_bump_fails
test_missing_version_field_fails

if [[ "$failures" -ne 0 ]]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi

printf '\nAll tests passed\n'
