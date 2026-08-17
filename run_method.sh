#!/bin/bash

METHOD=$1
BENCHMARK_DIR=$(realpath "$2")

REPO_DIR=$(pwd)
RESULTS_DIR="$REPO_DIR/results"
RESULTS_FILE="$RESULTS_DIR/${METHOD}.json"
LOGS_DIR="$RESULTS_DIR/logs/$METHOD"

CIRCUIT_TIMEOUT="5m"
CIRCUIT_MEMORY_MAX="1000M"
GLOBAL_TIMEOUT_SECONDS=$((3 * 60 * 60))

mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

mapfile -d '' QASM_FILES < <(
    find "$BENCHMARK_DIR" -type f -name '*.qasm' -print0 | sort -z
)

if [ ${#QASM_FILES[@]} -eq 0 ]; then
    echo "No QASM files found under $BENCHMARK_DIR" >&2
    exit 1
fi

START_TIME=$(date +%s)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse HEAD)

{
echo "{"
echo "  \"method\": \"$METHOD\","
echo "  \"benchmark_set\": \"$BENCHMARK_DIR\","
echo "  \"started_at\": \"$STARTED_AT\","
echo "  \"git_commit\": \"$GIT_COMMIT\","
echo "  \"runs\": ["
} > "$RESULTS_FILE"

FIRST=true

for BENCHMARK_FILE in "${QASM_FILES[@]}"; do
    NOW=$(date +%s)

    if (( NOW - START_TIME >= GLOBAL_TIMEOUT_SECONDS )); then
        echo "Global benchmark timeout reached."
        break
    fi

    BENCHMARK_NAME=$(basename "$BENCHMARK_FILE")
    BENCHMARK_RELATIVE="${BENCHMARK_FILE#"$BENCHMARK_DIR"/}"
    BENCHMARK_STEM="${BENCHMARK_RELATIVE%.qasm}"
    BENCHMARK_STEM="${BENCHMARK_STEM//\//__}"

    TIME_FILE="$LOGS_DIR/${BENCHMARK_STEM}.time.log"
    STDOUT_FILE="$LOGS_DIR/${BENCHMARK_STEM}.stdout.log"
    STDERR_FILE="$LOGS_DIR/${BENCHMARK_STEM}.stderr.log"

    # systemd unit names have a restricted character set.
    SAFE_METHOD=$(printf '%s' "$METHOD" | tr -c 'A-Za-z0-9_.@-' '-')
    SAFE_BENCHMARK=$(printf '%s' "$BENCHMARK_STEM" | tr -c 'A-Za-z0-9_.@-' '-')
    UNIT_NAME="abstracts-${SAFE_METHOD}-${SAFE_BENCHMARK}-$$"

    : > "$TIME_FILE"
    : > "$STDOUT_FILE"
    : > "$STDERR_FILE"

    echo "Running $METHOD on $BENCHMARK_FILE"

    # A transient service gets its own cgroup. If this circuit exceeds
    # MemoryMax, systemd kills this service rather than the benchmark driver.
    if systemd-run --user \
        --unit="$UNIT_NAME" \
        --wait \
        --pipe \
        --quiet \
        --service-type=exec \
        --working-directory="$REPO_DIR" \
        -p MemoryMax="$CIRCUIT_MEMORY_MAX" \
        -p MemorySwapMax=0 \
        -p OOMPolicy=stop \
        /usr/bin/time -v -o "$TIME_FILE" \
        timeout --kill-after=10s "$CIRCUIT_TIMEOUT" \
        "$REPO_DIR/methods/$METHOD/run.sh" "$BENCHMARK_FILE" \
        > "$STDOUT_FILE" 2> "$STDERR_FILE"
    then
        RUNNER_EXIT_STATUS=0
    else
        RUNNER_EXIT_STATUS=$?
    fi

    # Query the transient unit before clearing it. Result=oom-kill is a more
    # reliable OOM indicator than treating every exit 137 as memory-related.
    SERVICE_RESULT=$(systemctl --user show "$UNIT_NAME.service" \
        --property=Result --value 2>/dev/null || true)
    EXEC_MAIN_STATUS=$(systemctl --user show "$UNIT_NAME.service" \
        --property=ExecMainStatus --value 2>/dev/null || true)

    # Prefer the service process's actual status where available.
    EXIT_STATUS=${EXEC_MAIN_STATUS:-$RUNNER_EXIT_STATUS}

    if [ "$SERVICE_RESULT" = "oom-kill" ]; then
        STATUS="failed"
        ERROR_TYPE='"out of memory"'
    elif [ "$EXIT_STATUS" -eq 0 ] 2>/dev/null; then
        STATUS="success"
        ERROR_TYPE="null"
    elif [ "$EXIT_STATUS" -eq 124 ] 2>/dev/null; then
        STATUS="timed out"
        ERROR_TYPE='"timeout"'
    elif [ "$EXIT_STATUS" -eq 137 ] 2>/dev/null; then
        STATUS="failed"
        ERROR_TYPE='"process killed (SIGKILL)"'
    else
        STATUS="failed"
        ERROR_TYPE='"process error"'
    fi

    # Clear failed transient units after collecting their result.
    systemctl --user reset-failed "$UNIT_NAME.service" >/dev/null 2>&1 || true

    # A process killed early may leave some /usr/bin/time fields absent.
    USER_TIME=$(grep "User time" "$TIME_FILE" | awk '{print $4}' || true)
    SYSTEM_TIME=$(grep "System time" "$TIME_FILE" | awk '{print $4}' || true)
    PEAK_MEMORY_KB=$(grep "Maximum resident set size" "$TIME_FILE" | awk '{print $6}' || true)
    WALL_TIME=$(grep "Elapsed (wall clock) time" "$TIME_FILE" | awk '{print $8}' || true)

    USER_TIME=${USER_TIME:-0}
    SYSTEM_TIME=${SYSTEM_TIME:-0}
    PEAK_MEMORY_KB=${PEAK_MEMORY_KB:-0}
    WALL_TIME=${WALL_TIME:-""}

    if [ "$STATUS" = "success" ]; then
        RESULT=$(tail -n 1 "$STDOUT_FILE")
    else
        RESULT=""
        if [ -s "$STDERR_FILE" ]; then
            echo "Failure details for $BENCHMARK_NAME:"
            tail -n 20 "$STDERR_FILE"
        fi
    fi

    CPU_TIME=$(python3 - <<EOF_PY
print(float("$USER_TIME") + float("$SYSTEM_TIME"))
EOF_PY
)

    if [ "$FIRST" = false ]; then
        echo "," >> "$RESULTS_FILE"
    fi

    FIRST=false

    cat >> "$RESULTS_FILE" <<EOF_JSON
    {
      "benchmark": "$BENCHMARK_RELATIVE",
      "benchmark_file": "$BENCHMARK_FILE",
      "status": "$STATUS",
      "exit_status": $EXIT_STATUS,
      "service_result": "$SERVICE_RESULT",
      "error": $ERROR_TYPE,
      "result": "$RESULT",
      "wall_time": "$WALL_TIME",
      "user_time_seconds": $USER_TIME,
      "system_time_seconds": $SYSTEM_TIME,
      "cpu_time_seconds": $CPU_TIME,
      "peak_memory_kb": $PEAK_MEMORY_KB
    }
EOF_JSON

done

END_TIME=$(date +%s)
FINISHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TOTAL_WALL_TIME_SECONDS=$((END_TIME - START_TIME))

cat >> "$RESULTS_FILE" <<EOF_JSON

  ],
  "finished_at": "$FINISHED_AT",
  "total_wall_time_seconds": $TOTAL_WALL_TIME_SECONDS
}
EOF_JSON

echo "Wrote results to $RESULTS_FILE"
