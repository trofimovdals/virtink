if [[ -n "${VIRTINK_TIMESTAMP_LOGGING:-}" ]]; then
  return 0
fi

export VIRTINK_TIMESTAMP_LOGGING=1

_virtink_ts_dir="${RUNNER_TEMP:-/tmp}"
_virtink_ts_fifo="$(mktemp -u "${_virtink_ts_dir%/}/virtink-ts.XXXXXX")"
mkfifo "${_virtink_ts_fifo}"

while IFS= read -r line || [[ -n "$line" ]]; do
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$line"
done <"${_virtink_ts_fifo}" &
_virtink_ts_pid=$!

exec >"${_virtink_ts_fifo}" 2>&1

trap '
  exec 1>&- 2>&-
  wait "${_virtink_ts_pid}" 2>/dev/null || true
  rm -f "${_virtink_ts_fifo}"
' EXIT
