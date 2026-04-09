#!/bin/bash
# hooks/_lib.sh — Zero-overhead JSON extraction for hooks
# Source this after: INPUT=$(cat)
# ~0.01ms vs python3's ~80ms cold start

_json() {
  local _tmp="${INPUT#*\"$1\":\"}"
  [[ "$_tmp" != "$INPUT" ]] && printf '%s' "${_tmp%%\"*}"
}
