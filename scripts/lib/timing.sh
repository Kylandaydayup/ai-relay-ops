#!/usr/bin/env bash

start_script_timer() {
  if [ -n "${EDREAM_TIMING_STARTED:-}" ]; then
    return 0
  fi
  EDREAM_TIMING_STARTED=1
  EDREAM_SCRIPT_NAME="${1:-${0##*/}}"
  EDREAM_SCRIPT_START_EPOCH="$(date +%s)"
  trap 'status=$?; end_epoch="$(date +%s)"; elapsed=$((end_epoch - EDREAM_SCRIPT_START_EPOCH)); echo "[timing] script=${EDREAM_SCRIPT_NAME} status=${status} elapsed=${elapsed}s"; exit "$status"' EXIT
}
