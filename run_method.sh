#!/bin/bash

METHOD=$1
BENCHMARK_FILE=$2

echo "Running method: $METHOD"

./methods/$METHOD/run.sh "$BENCHMARK_FILE"