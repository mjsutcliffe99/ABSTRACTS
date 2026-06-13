#!/bin/bash

METHOD=$1
BENCHMARK_DIR=$2

echo "Running method: $METHOD"
echo "Benchmark directory: $BENCHMARK_DIR"

for BENCHMARK_FILE in "$BENCHMARK_DIR"/*; do
    echo
    echo "=== $BENCHMARK_FILE ==="

    /usr/bin/time -v ./methods/$METHOD/run.sh "$BENCHMARK_FILE"
done