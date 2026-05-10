#!/usr/bin/env bash
set -euo pipefail

base_ref="${BASE_REF:-${GITHUB_BASE_REF:-main}}"
base="${BASE:-origin/${base_ref}}"

if [[ "${SKIP_FETCH:-0}" != "1" ]]; then
  git fetch origin "${base_ref}" --depth=1
fi

registry_file="galaxio-registry.yaml"

changed_files="$(git diff --name-only "${base}"...HEAD -- "${registry_file}" || true)"
if [[ -z "${changed_files}" ]]; then
  exit 0
fi

registry_version_for() {
  awk '$1 == "version:" { print $2; exit }' "$1"
}

semver_parts() {
  local version="$1"
  local major minor patch
  IFS=. read -r major minor patch <<< "${version}"
  echo "${major:-0} ${minor:-0} ${patch:-0}"
}

is_patch_bump() {
  local old="$1" new="$2"
  local old_major old_minor old_patch new_major new_minor new_patch
  read -r old_major old_minor old_patch <<< "$(semver_parts "${old}")"
  read -r new_major new_minor new_patch <<< "$(semver_parts "${new}")"
  [[ "${new_major}" == "${old_major}" && "${new_minor}" == "${old_minor}" && "${new_patch}" -gt "${old_patch}" ]]
}

is_minor_bump() {
  local old="$1" new="$2"
  local old_major old_minor old_patch new_major new_minor new_patch
  read -r old_major old_minor old_patch <<< "$(semver_parts "${old}")"
  read -r new_major new_minor new_patch <<< "$(semver_parts "${new}")"
  [[ "${new_major}" == "${old_major}" && "${new_minor}" -gt "${old_minor}" ]]
}

change_subject="$(git log -1 --pretty=%s)"
change_kind="other"
case "${change_subject}" in
  feat:* | feat\(*)
    change_kind="feat"
    ;;
  fix:* | fix\(*)
    change_kind="fix"
    ;;
esac

old_manifest="$(mktemp)"
git show "${base}:${registry_file}" > "${old_manifest}"

old_version="$(registry_version_for "${old_manifest}")"
new_version="$(registry_version_for "${registry_file}")"

if [[ -z "${new_version}" ]]; then
  echo "galaxio-registry.yaml is missing a top-level version field." >&2
  exit 1
fi

if [[ "${old_version}" == "${new_version}" ]]; then
  echo "galaxio-registry.yaml changed but version stayed ${new_version}." >&2
  echo "Bump version and use a feat/fix commit prefix." >&2
  exit 1
fi

if [[ "${change_kind}" == "feat" ]]; then
  if ! is_minor_bump "${old_version}" "${new_version}"; then
    echo "feat change requires a minor version bump: ${old_version} -> ${new_version}" >&2
    exit 1
  fi
fi

if [[ "${change_kind}" == "fix" ]]; then
  if ! is_patch_bump "${old_version}" "${new_version}"; then
    echo "fix change requires a patch version bump: ${old_version} -> ${new_version}" >&2
    exit 1
  fi
fi
