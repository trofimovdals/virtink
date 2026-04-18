#!/usr/bin/env bash

set -euo pipefail

skaffold_bin="${SKAFFOLD:-skaffold}"
default_repo="${DEFAULT_REPO:-}"
digest_source="${DIGEST_SOURCE:-tag}"

images=()
if [[ -n "${CONTROLLER_IMAGE:-}" ]]; then
  images+=("virt-controller=${CONTROLLER_IMAGE}")
fi
if [[ -n "${DAEMON_IMAGE:-}" ]]; then
  images+=("virt-daemon=${DAEMON_IMAGE}")
fi
if [[ -n "${PRERUNNER_IMAGE:-}" ]]; then
  images+=("virt-prerunner=${PRERUNNER_IMAGE}")
fi

render_args=(
  render
  "--offline=true"
  "--digest-source=${digest_source}"
)

if [[ -n "${default_repo}" ]]; then
  render_args+=("--default-repo=${default_repo}")
else
  render_args+=("--default-repo=")
fi

if ((${#images[@]} > 0)); then
  render_args+=("--images" "$(IFS=,; echo "${images[*]}")")
fi

manifest="$("${skaffold_bin}" "${render_args[@]}")"

if [[ -n "${CONTROLLER_IMAGE:-}" ]]; then
  escaped_controller_image="$(printf '%s\n' "${CONTROLLER_IMAGE}" | sed 's/[&|]/\\&/g')"
  manifest="$(printf '%s' "${manifest}" | sed "s|image: virt-controller|image: ${escaped_controller_image}|g")"
fi

if [[ -n "${DAEMON_IMAGE:-}" ]]; then
  escaped_daemon_image="$(printf '%s\n' "${DAEMON_IMAGE}" | sed 's/[&|]/\\&/g')"
  manifest="$(printf '%s' "${manifest}" | sed "s|image: virt-daemon|image: ${escaped_daemon_image}|g")"
fi

if [[ -n "${PRERUNNER_IMAGE:-}" ]]; then
  escaped_prerunner_image="$(printf '%s\n' "${PRERUNNER_IMAGE}" | sed 's/[&|]/\\&/g')"
  manifest="$(printf '%s' "${manifest}" | sed "s|value: virt-prerunner|value: ${escaped_prerunner_image}|g")"
fi

printf '%s\n' "${manifest}"
