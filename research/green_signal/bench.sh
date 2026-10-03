#!/usr/bin/env bash
# EXPERIMENTAL -- research spike, Phase 12.
#
#   research/green_signal/bench.sh APP_DIR OUT_DIR RUNS [ORDER] -- [rspec args...]
#
# Runs baseline and instrumented back to back, RUNS times, and prints RSpec's
# own "Finished in", wall time and peak RSS for each. ORDER is "baseline-first"
# (default) or "instrumented-first": on a machine that slows down over time the
# second run of every pair is penalised, so measure both orders. Nothing in
# APP_DIR is modified.
set -euo pipefail

app=$1 out=$2 runs=$3 order=baseline-first
shift 3
if [[ "${1:-}" == *-first ]]; then order=$1; shift; fi
[[ "${1:-}" == "--" ]] && shift
observer="$(cd "$(dirname "$0")" && pwd)/observer.rb"
mkdir -p "$out"

run() { # label extra-args...
  local label=$1 n=$2
  shift 2
  local log="$out/$label-$n.log" time="$out/$label-$n.time"
  (cd "$app" && /usr/bin/time -v env GREEN_SIGNAL_OUT="$out/$label-$n.jsonl" "$@" >"$log" 2>"$time") || true
  local finished wall rss
  finished=$(grep -oE "Finished in [0-9.]+ (seconds|minutes [0-9.]+ seconds)" "$log" | head -1)
  wall=$(grep -E "Elapsed \(wall clock\)" "$time" | awk '{print $NF}')
  rss=$(grep -E "Maximum resident set size" "$time" | awk '{print $NF}')
  echo "$label run=$n | $finished | wall=$wall | max_rss_kb=$rss | $(grep -E "examples, " "$log" | tail -1)"
}

for n in $(seq 1 "$runs"); do
  if [[ "$order" == instrumented-first ]]; then
    run instrumented "$n" bundle exec rspec -r "$observer" "$@"
    run baseline "$n" bundle exec rspec "$@"
  else
    run baseline "$n" bundle exec rspec "$@"
    run instrumented "$n" bundle exec rspec -r "$observer" "$@"
  fi
done
