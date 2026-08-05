#!/bin/bash

METHOD=$1
BENCHMARK_DIR=$2

RESULTS_DIR="results"
RESULTS_FILE="$RESULTS_DIR/${METHOD}.json"

CIRCUIT_TIMEOUT="5m"
CIRCUIT_MEMORY_MAX="700M"
GLOBAL_TIMEOUT_SECONDS=$((3 * 60 * 60))

mkdir -p "$RESULTS_DIR"

shopt -s nullglob
QASM_FILES=("$BENCHMARK_DIR"/*.qasm)

if [ ${#QASM_FILES[@]} -eq 0 ]; then
    echo "No QASM files found in $BENCHMARK_DIR" >&2
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
    TIME_FILE=$(mktemp)
    STDOUT_FILE=$(mktemp)
    STDERR_FILE=$(mktemp)

    echo "Running $METHOD on $BENCHMARK_FILE"

    # Run each circuit in its own memory-limited systemd scope.  The limit is
    # below the VM's total RAM so that Ubuntu and sshd retain enough memory.
    if systemd-run --user --scope --quiet \
        -p MemoryMax="$CIRCUIT_MEMORY_MAX" \
        -p MemorySwapMax=0 \
        /usr/bin/time -v -o "$TIME_FILE" \
        timeout "$CIRCUIT_TIMEOUT" \
        ./methods/"$METHOD"/run.sh "$BENCHMARK_FILE" \
        > "$STDOUT_FILE" 2> "$STDERR_FILE"
    then
        EXIT_STATUS=0
    else
        EXIT_STATUS=$?
    fi

    if [ "$EXIT_STATUS" -eq 0 ]; then
        STATUS="success"
        ERROR_TYPE="null"
    elif [ "$EXIT_STATUS" -eq 124 ]; then
        STATUS="timed out"
        ERROR_TYPE='"timeout"'
    elif [ "$EXIT_STATUS" -eq 137 ]; then
        STATUS="failed"
        ERROR_TYPE='"memory limit exceeded or process killed"'
    else
        STATUS="failed"
        ERROR_TYPE='"process error"'
    fi

    # A process killed early may leave some /usr/bin/time fields absent.
    USER_TIME=$(grep "User time" "$TIME_FILE" | awk '{print $4}' || true)
    SYSTEM_TIME=$(grep "System time" "$TIME_FILE" | awk '{print $4}' || true)
    PEAK_MEMORY_KB=$(grep "Maximum resident set size" "$TIME_FILE" | awk '{print $6}' || true)
    WALL_TIME=$(grep "Elapsed (wall clock) time" "$TIME_FILE" | awk '{print $8}' || true)

    USER_TIME=${USER_TIME:-0}
    SYSTEM_TIME=${SYSTEM_TIME:-0}
    PEAK_MEMORY_KB=${PEAK_MEMORY_KB:-0}
    WALL_TIME=${WALL_TIME:-""}

    if [ "$EXIT_STATUS" -eq 0 ]; then
        RESULT=$(tail -n 1 "$STDOUT_FILE")
    else
        RESULT=""
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
      "benchmark": "$BENCHMARK_NAME",
      "benchmark_file": "$BENCHMARK_FILE",
      "status": "$STATUS",
      "exit_status": $EXIT_STATUS,
      "error": $ERROR_TYPE,
      "result": "$RESULT",
      "wall_time": "$WALL_TIME",
      "user_time_seconds": $USER_TIME,
      "system_time_seconds": $SYSTEM_TIME,
      "cpu_time_seconds": $CPU_TIME,
      "peak_memory_kb": $PEAK_MEMORY_KB
    }
EOF_JSON

    rm "$TIME_FILE" "$STDOUT_FILE" "$STDERR_FILE"
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
