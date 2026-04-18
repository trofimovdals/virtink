#!/usr/bin/env bash

set -euo pipefail

context="."
dockerfile=""
tag=""
platforms="linux/amd64,linux/arm64"
metadata_file=""
build_args=()

while (($# > 0)); do
  case "$1" in
    --context)
      context="$2"
      shift 2
      ;;
    --file)
      dockerfile="$2"
      shift 2
      ;;
    --tag)
      tag="$2"
      shift 2
      ;;
    --platforms)
      platforms="$2"
      shift 2
      ;;
    --metadata-file)
      metadata_file="$2"
      shift 2
      ;;
    --build-arg)
      build_args+=("--build-arg" "$2")
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${dockerfile}" || -z "${tag}" ]]; then
  echo "--file and --tag are required" >&2
  exit 1
fi

cmd=(
  docker buildx build
  --progress=plain
  --platform "${platforms}"
  --file "${dockerfile}"
  --tag "${tag}"
  --push
  --provenance=false
)

if [[ -n "${metadata_file}" ]]; then
  cmd+=(--metadata-file "${metadata_file}")
fi

cmd+=("${build_args[@]}")
cmd+=("${context}")

echo "building and pushing ${tag}"
"${cmd[@]}"
