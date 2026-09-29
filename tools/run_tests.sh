#!/usr/bin/env bash
# run_tests.sh — the single documented runner for the Grand Exhibit suite.
#
# Exit code is 0 only when every selected test passes. Any failure, crash,
# timeout, or missing binary exits nonzero, so CI can gate on this one command.
#
#   tools/run_tests.sh                 # every test under tests/
#   tools/run_tests.sh venue           # only tests whose path matches "venue"
#   tools/run_tests.sh test_save       # a single test
#   GODOT=/path/to/godot tools/run_tests.sh
#   TEST_TIMEOUT=300 tools/run_tests.sh
#
# Two things this runner does that a bare `godot -s tests/foo.gd` does not, and
# which are the difference between "green on my machine" and "green from a clean
# checkout":
#
#   1. It runs an import pass first. `.godot/` is gitignored, and it holds
#      global_script_class_cache.cfg — the ONLY registry of `class_name
#      BigNumber`. Without it every script that types a BigNumber fails to
#      parse, so a fresh clone fails ~everything for a reason that looks
#      nothing like the real cause.
#   2. It isolates user://. The suite writes and DELETES
#      user://grand_exhibit_save.json, which on a developer box is the live
#      player save. The runner points the app at a throwaway user data dir so a
#      test run can never eat real progress. See GRAND_EXHIBIT_TEST_RUN below.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

GODOT="${GODOT:-$HOME/bin/godot441}"
TEST_TIMEOUT="${TEST_TIMEOUT:-180}"
FILTER="${1:-}"

if [[ ! -x "$GODOT" ]]; then
	echo "run_tests: godot binary not found or not executable: $GODOT" >&2
	echo "run_tests: set GODOT=/path/to/godot and retry" >&2
	exit 2
fi

# --- user:// isolation ---------------------------------------------------
# Godot derives the user data dir from application/config/name, so there is no
# CLI flag to redirect it. Instead the suite honours this env var: save_system
# and every test that touches persistence route through
# TestPaths.save_path(), which appends a per-run suffix when it is set. Belt and
# braces, we also point HOME's XDG data root at a scratch dir so even a stray
# hardcoded user:// write lands outside the real profile.
export GRAND_EXHIBIT_TEST_RUN="1"
SCRATCH="$(mktemp -d -t grand-exhibit-tests-XXXXXX)"
export XDG_DATA_HOME="$SCRATCH/xdg-data"
mkdir -p "$XDG_DATA_HOME"
# Preserve failing logs outside the scratch dir (which is removed on exit) so
# a red run leaves evidence instead of deleting it. Successful runs still
# clean up fully.
FAILED_LOG_DIR=""
cleanup() {
	if [[ -n "$FAILED_LOG_DIR" && -d "$FAILED_LOG_DIR" ]]; then
		: # failing logs already copied out; drop the scratch dir
	fi
	rm -rf "$SCRATCH";
}
trap cleanup EXIT

# --- import pass ---------------------------------------------------------
echo "==> import pass ($PROJECT)"
if ! timeout 900 "$GODOT" --headless --import --path "$PROJECT" >"$SCRATCH/import.log" 2>&1; then
	echo "run_tests: import pass failed; see below" >&2
	tail -40 "$SCRATCH/import.log" >&2
	exit 2
fi

if [[ ! -f "$PROJECT/.godot/global_script_class_cache.cfg" ]]; then
	echo "run_tests: import pass did not produce .godot/global_script_class_cache.cfg" >&2
	exit 2
fi

# --- collect tests -------------------------------------------------------
mapfile -t TESTS < <(find "$PROJECT/tests" -type f -name 'test_*.gd' | sort)
if [[ -n "$FILTER" ]]; then
	mapfile -t TESTS < <(printf '%s\n' "${TESTS[@]}" | grep -- "$FILTER" || true)
fi

if [[ ${#TESTS[@]} -eq 0 ]]; then
	echo "run_tests: no tests matched filter '${FILTER}'" >&2
	exit 2
fi

echo "==> running ${#TESTS[@]} test(s), timeout ${TEST_TIMEOUT}s each"
echo

PASSED=(); FAILED=(); TIMEDOUT=()
START_ALL=$SECONDS

for abs in "${TESTS[@]}"; do
	rel="${abs#"$PROJECT"/}"
	log="$SCRATCH/$(echo "$rel" | tr '/' '_').log"
	t0=$SECONDS
	timeout --signal=KILL "$TEST_TIMEOUT" \
		"$GODOT" --headless --path "$PROJECT" --editor-pid 0 -s "res://$rel" \
		>"$log" 2>&1
	rc=$?
	dt=$((SECONDS - t0))

	# A test can exit 0 while still having printed failures — for example if it
	# reports through a path that forgets to feed the quit() code. Treat any
	# FAIL line as authoritative regardless of exit status.
	if grep -qE '^\s*(FAIL|FAILED)\b' "$log"; then
		rc=1
	fi

	# ...and a test can exit 0 having asserted NOTHING. A script that fails to
	# compile leaves its preloaded helpers as dead GDScript objects; every call
	# against them errors, no check() ever runs, the failure counter stays at
	# zero and quit(0) reports a pass. That false green is worse than a red,
	# because it looks like coverage. A compile or load error is a failure no
	# matter what the exit code says.
	if grep -qE 'SCRIPT ERROR|Compile Error|Parse Error|Failed to load script' "$log"; then
		rc=1
	fi

	# Engine runtime errors (e.g. "ERROR: Error calling deferred method")
	# must also fail the gate: the rapid-popup-disposal probe exited 0 with
	# 21 such errors before UI-01 was fixed. Only narrow, explicitly expected
	# faults are excused:
	#  · tests that deliberately feed a truncated save exercise JSON recovery
	#    and intentionally emit one "Parse JSON failed" engine error;
	#  · a test may declare an additional expected substring by printing
	#    "EXPECTED_ERROR: <substring>" — but only when that same substring
	#    also appears literally in the test's own source file. A test can only
	#    excuse errors it anticipated in code, never arbitrary runtime errors.
	#    Excused lines are still echoed to the failure report for review.
	if grep -qE '(^|[^A-Z])ERROR:' "$log"; then
		err_tmp="$log.errlines"
		grep -E '(^|[^A-Z])ERROR:' "$log" >"$err_tmp" || true
		# Collect declared expectations from the log itself.
		expect_tmp="$log.expect"
		grep -E 'EXPECTED_ERROR:' "$log" | sed -E 's/.*EXPECTED_ERROR:[[:space:]]*//' >"$expect_tmp" || true
		: >"$err_tmp.filtered"
		: >"$err_tmp.excused"
		while IFS= read -r line || [[ -n "$line" ]]; do
			# Narrow standing exception for intentional corruption fixtures.
			if echo "$line" | grep -qF 'Parse JSON failed'; then
				case "$rel" in
					tests/core/test_save.gd|tests/qa/test_interrupted_transitions.gd|tests/qa/test_save_migration.gd|tests/monetization/test_purchase_durability.gd)
						echo "$line" >>"$err_tmp.excused"
						continue
						;;
				esac
			fi
			# Declared per-test expectations (substring match + source-scoped).
			excused=0
			if [[ -s "$expect_tmp" ]]; then
				while IFS= read -r pat || [[ -n "$pat" ]]; do
					[[ -z "$pat" ]] && continue
					if echo "$line" | grep -qF "$pat" && grep -qF "$pat" "$PROJECT/$rel"; then excused=1; break; fi
				done <"$expect_tmp"
			fi
			if [[ $excused -eq 0 ]]; then echo "$line" >>"$err_tmp.filtered"; else echo "$line" >>"$err_tmp.excused"; fi
		done <"$err_tmp"
		if [[ -s "$err_tmp.filtered" ]]; then
			rc=1
		fi
		if [[ -s "$err_tmp.excused" ]]; then
			echo "  (excused ${rel}: $(wc -l <"$err_tmp.excused") expected ERROR line(s))" >>"$log"
		fi
	fi

	if [[ $rc -eq 137 || $rc -eq 124 ]]; then
		TIMEDOUT+=("$rel"); printf 'TIMEOUT  %-52s %3ds\n' "$rel" "$dt"
	elif [[ $rc -eq 0 ]]; then
		PASSED+=("$rel");   printf 'pass     %-52s %3ds\n' "$rel" "$dt"
	else
		FAILED+=("$rel:$rc"); printf 'FAIL     %-52s %3ds (rc=%d)\n' "$rel" "$dt" "$rc"
	fi
	cp "$log" "$SCRATCH/keep_$(basename "$log")" 2>/dev/null || true
done

TOTAL_T=$((SECONDS - START_ALL))
echo
echo "================================================================"
printf 'passed %d   failed %d   timeout %d   of %d   in %ds\n' \
	"${#PASSED[@]}" "${#FAILED[@]}" "${#TIMEDOUT[@]}" "${#TESTS[@]}" "$TOTAL_T"

if [[ ${#FAILED[@]} -gt 0 || ${#TIMEDOUT[@]} -gt 0 ]]; then
	echo "----------------------------------------------------------------"
	for f in "${FAILED[@]}"; do
		rel="${f%:*}"
		echo
		echo "### FAILED $rel"
		log="$SCRATCH/$(echo "$rel" | tr '/' '_').log"
		grep -E '^\s*(FAIL|FAILED)\b|SCRIPT ERROR|Parse Error|Compile Error|(^|[^A-Z])ERROR:' "$log" | head -25
	done
	for t in "${TIMEDOUT[@]}"; do
		echo
		echo "### TIMEOUT $t (killed after ${TEST_TIMEOUT}s)"
		tail -15 "$SCRATCH/$(echo "$t" | tr '/' '_').log"
	done
	# Keep evidence: copy every failed/timed-out log out of the scratch dir
	# before the EXIT trap removes it. Path is printed so CI artifacts can
	# collect it; successful runs leave nothing behind.
	FAILED_LOG_DIR="$(mktemp -d -t grand-exhibit-tests-failed-XXXXXX)"
	for f in "${FAILED[@]}"; do
		rel="${f%:*}"
		cp "$SCRATCH/$(echo "$rel" | tr '/' '_').log" "$FAILED_LOG_DIR/" 2>/dev/null || true
	done
	for t in "${TIMEDOUT[@]}"; do
		cp "$SCRATCH/$(echo "$t" | tr '/' '_').log" "$FAILED_LOG_DIR/" 2>/dev/null || true
	done
	echo
	echo "failing logs preserved in: $FAILED_LOG_DIR"
	echo
	echo "FAILURE"
	exit 1
fi

echo "ALL GREEN"
exit 0
