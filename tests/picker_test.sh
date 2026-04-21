#!/usr/bin/env bash
# Regression tests for the TUI pickers (pick_one_tui / pick_many_tui).
#
# Drives the picker subprocess in an isolated tmux server, injects keys via
# `send-keys`, captures the printed result. No new dependencies — tmux is
# already required by orca itself.
#
# Usage: ./tests/picker_test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../_lib.sh"
SOCK="picker-test-$$"
SCRATCH="$(mktemp -d)"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$SCRATCH"' EXIT

# Sanity: lib must be sourceable.
# shellcheck source=../_lib.sh
source "$LIB"

PASS=0
FAIL=0

# Run a one-shot picker harness in tmux; inject keys; echo the captured output.
# Args: <harness_body> [keys...]
run_picker() {
  local body="$1"; shift
  local outfile="$SCRATCH/out"
  local script="$SCRATCH/harness.sh"

  cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$LIB"
$body
EOF
  chmod +x "$script"
  rm -f "$outfile"

  tmux -L "$SOCK" new-session -d -s t -x 100 -y 20 "$script > '$outfile' 2>&1; sleep 5"
  sleep 0.4
  while [ "$#" -gt 0 ]; do
    tmux -L "$SOCK" send-keys -t t "$1"
    shift
    sleep 0.1
  done
  sleep 0.4
  tmux -L "$SOCK" kill-session -t t 2>/dev/null || true
  cat "$outfile" 2>/dev/null || true
}

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n        want: %s\n        got:  %s\n' "$label" "$want" "$got"
  fi
}

ONE_HARNESS='r=$(pick_one_tui "Pick:" "" "new" "row 1" "row 2" "row 3") || { echo "CANCELLED"; exit 0; }
echo "RESULT: $r"'

MANY_HARNESS='r=$(pick_many_tui "Pick many:" "" "row A" "row B" "row C") || { echo "CANCELLED"; exit 0; }
echo "PICKED: $(echo "$r" | tr "\n" "," | sed "s/,$//")"'

echo "pick_one_tui:"
assert_eq "$(run_picker "$ONE_HARNESS" Down Enter)"           "RESULT: 2"   "Down + Enter -> row 2"
assert_eq "$(run_picker "$ONE_HARNESS" Down Down Down Enter)" "RESULT: NEW" "Down x3 + Enter -> NEW (last entry)"
assert_eq "$(run_picker "$ONE_HARNESS" j Enter)"              "RESULT: 2"   "j (vim down) + Enter"
assert_eq "$(run_picker "$ONE_HARNESS" k Enter)"              "RESULT: NEW" "k (vim up) wraps to last"
assert_eq "$(run_picker "$ONE_HARNESS" Up Enter)"             "RESULT: NEW" "Up wraps to last"
assert_eq "$(run_picker "$ONE_HARNESS" q)"                    "CANCELLED"   "q cancels"

echo
echo "pick_many_tui:"
assert_eq "$(run_picker "$MANY_HARNESS" Space Down Down Space Enter)" "PICKED: 1,3" "Space + nav + Space + Enter"
assert_eq "$(run_picker "$MANY_HARNESS" Down Space Up Space Enter)"   "PICKED: 1,2" "nav around, multi-toggle"
assert_eq "$(run_picker "$MANY_HARNESS" Enter)"                       "PICKED: "    "Enter with no selection -> empty"
assert_eq "$(run_picker "$MANY_HARNESS" q)"                           "CANCELLED"   "q cancels"

echo
echo "Total: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
