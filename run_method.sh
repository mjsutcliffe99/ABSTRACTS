#!/bin/bash

METHOD=$1
BENCHMARK_DIR=$2

RESULTS_DIR="results"
RESULTS_FILE="$RESULTS_DIR/${METHOD}_$(basename "$BENCHMARK_DIR").json"

mkdir -p "$RESULTS_DIR"

{
echo "{"
echo "  \"method\": \"$METHOD\","
echo "  \"benchmark_set\": \"$BENCHMARK_DIR\","
echo "  \"runs\": ["
} > "$RESULTS_FILE"

FIRST=true

for BENCHMARK_FILE in "$BENCHMARK_DIR"/*; do
    BENCHMARK_NAME=$(basename "$BENCHMARK_FILE")
    TIME_FILE=$(mktemp)
    STDOUT_FILE=$(mktemp)

    echo "Running $METHOD on $BENCHMARK_FILE"

    /usr/bin/time -v -o "$TIME_FILE" \
        ./methods/$METHOD/run.sh "$BENCHMARK_FILE" \
        > "$STDOUT_FILE"

    EXIT_STATUS=$?

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
      "status": "$([ $EXIT_STATUS -eq 0 ] && echo success || echo failed)",
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

cat >> "$RESULTS_FILE" <<EOF

  ]
}
EOF

echo "Wrote results to $RESULTS_FILE"