#!/bin/bash

METHOD=$1
BENCHMARK_DIR=$2

RESULTS_DIR="results"
RESULTS_FILE="$RESULTS_DIR/${METHOD}_$(basename "$BENCHMARK_DIR").json"

CIRCUIT_TIMEOUT="10m"
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

    echo "Running $METHOD on $BENCHMARK_FILE"

    if /usr/bin/time -v -o "$TIME_FILE" \
        timeout "$CIRCUIT_TIMEOUT" \
        ./methods/"$METHOD"/run.sh "$BENCHMARK_FILE" \
        > "$STDOUT_FILE"
    then
        EXIT_STATUS=0
    else
        EXIT_STATUS=$?
    fi

    if [ "$EXIT_STATUS" -eq 0 ]; then
        STATUS="success"
    elif [ "$EXIT_STATUS" -eq 124 ]; then
        STATUS="timed out"
    else
        STATUS="failed"
    fi

    USER_TIME=$(grep "User time" "$TIME_FILE" | awk '{print $4}')
    SYSTEM_TIME=$(grep "System time" "$TIME_FILE" | awk '{print $4}')
    PEAK_MEMORY_KB=$(grep "Maximum resident set size" "$TIME_FILE" | awk '{print $6}')
    WALL_TIME=$(grep "Elapsed (wall clock) time" "$TIME_FILE" | awk '{print $8}')
    RESULT=$(tail -n 1 "$STDOUT_FILE")

    CPU_TIME=$(python3 - <<EOF
print(float("$USER_TIME") + float("$SYSTEM_TIME"))
EOF
)

    if [ "$FIRST" = false ]; then
        echo "," >> "$RESULTS_FILE"
    fi

    FIRST=false

    cat >> "$RESULTS_FILE" <<EOF
    {
      "benchmark": "$BENCHMARK_NAME",
      "benchmark_file": "$BENCHMARK_FILE",
      "status": "$STATUS",
      "exit_status": $EXIT_STATUS,
      "result": "$RESULT",
      "wall_time": "$WALL_TIME",
      "user_time_seconds": $USER_TIME,
      "system_time_seconds": $SYSTEM_TIME,
      "cpu_time_seconds": $CPU_TIME,
      "peak_memory_kb": $PEAK_MEMORY_KB
    }
EOF

    rm "$TIME_FILE" "$STDOUT_FILE"
done

END_TIME=$(date +%s)
FINISHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TOTAL_WALL_TIME_SECONDS=$((END_TIME - START_TIME))

cat >> "$RESULTS_FILE" <<EOF

  ],
  "finished_at": "$FINISHED_AT",
  "total_wall_time_seconds": $TOTAL_WALL_TIME_SECONDS
}
EOF

echo "Wrote results to $RESULTS_FILE"