#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_RESULTS_DIR = Path("results")
DEFAULT_METHODS_DIR = Path("methods")
DEFAULT_OUTPUT_FILE = Path("docs/data/dashboard.json")


class DashboardBuildError(RuntimeError):
    """Raised when dashboard data cannot be built safely."""


def load_json(path: Path) -> Any:
    """Load a JSON file and produce a useful error message on failure."""
    try:
        with path.open("r", encoding="utf-8") as file:
            return json.load(file)

    except FileNotFoundError as error:
        raise DashboardBuildError(
            f"File does not exist: {path}"
        ) from error

    except json.JSONDecodeError as error:
        raise DashboardBuildError(
            f"Invalid JSON in {path}: "
            f"line {error.lineno}, column {error.colno}: {error.msg}"
        ) from error


def parse_wall_time(value: Any) -> float | None:
    """
    Convert wall-time values into seconds.

    Examples:
        "0:01.60"    -> 1.6
        "1:02:03.4"  -> 3723.4
        1.6          -> 1.6
    """
    if value is None:
        return None

    if isinstance(value, bool):
        raise DashboardBuildError(
            f"Unsupported wall-time value: {value!r}"
        )

    if isinstance(value, (int, float)):
        result = float(value)
        return result if math.isfinite(result) else None

    if not isinstance(value, str):
        raise DashboardBuildError(
            f"Unsupported wall-time value: {value!r}"
        )

    text = value.strip()

    if not text:
        return None

    parts = text.split(":")

    try:
        if len(parts) == 1:
            total_seconds = float(parts[0])

        elif len(parts) == 2:
            minutes = int(parts[0])
            seconds = float(parts[1])

            total_seconds = minutes * 60 + seconds

        elif len(parts) == 3:
            hours = int(parts[0])
            minutes = int(parts[1])
            seconds = float(parts[2])

            total_seconds = (
                hours * 3600
                + minutes * 60
                + seconds
            )

        else:
            raise ValueError(
                "too many colon-separated components"
            )

    except ValueError as error:
        raise DashboardBuildError(
            f"Could not parse wall-time value: {value!r}"
        ) from error

    return total_seconds if math.isfinite(total_seconds) else None


def parse_complex_result(
    value: Any,
) -> tuple[float | None, float | None]:
    """
    Convert a Python-style complex string into separate components.

    Example:
        "(-0.006-0.018j)" -> (-0.006, -0.018)

    Also accepts:
        {"real": -0.006, "imag": -0.018}
    """
    if value is None:
        return None, None

    if isinstance(value, dict):
        real = value.get("real")
        imag = value.get("imag")

        return (
            number_or_none(real, field_name="result.real"),
            number_or_none(imag, field_name="result.imag"),
        )

    if not isinstance(value, str):
        raise DashboardBuildError(
            f"Unsupported complex-result value: {value!r}"
        )

    text = value.strip()

    if not text:
        return None, None

    try:
        parsed = complex(text)

    except ValueError as error:
        raise DashboardBuildError(
            f"Could not parse complex result: {value!r}"
        ) from error

    if not (
        math.isfinite(parsed.real)
        and math.isfinite(parsed.imag)
    ):
        return None, None

    return parsed.real, parsed.imag


def number_or_none(
    value: Any,
    *,
    field_name: str,
    source: Path | None = None,
) -> int | float | None:
    """Validate a numeric field and convert non-finite values to null."""
    if value is None:
        return None

    if isinstance(value, bool) or not isinstance(value, (int, float)):
        location = f"{source}: " if source is not None else ""

        raise DashboardBuildError(
            f"{location}field {field_name!r} should be numeric, "
            f"not {value!r}"
        )

    if not math.isfinite(float(value)):
        return None

    return value


def require_string(
    value: Any,
    *,
    field_name: str,
    source: Path,
) -> str:
    """Require a non-empty string field."""
    if not isinstance(value, str) or not value.strip():
        raise DashboardBuildError(
            f"{source}: field {field_name!r} must be a "
            f"non-empty string"
        )

    return value.strip()


def first_present(
    data: dict[str, Any],
    *field_names: str,
) -> Any:
    """Return the first present, non-null field value."""
    for field_name in field_names:
        if field_name in data and data[field_name] is not None:
            return data[field_name]

    return None


def load_simulators(
    methods_dir: Path,
) -> dict[str, dict[str, Any]]:
    """
    Load simulator metadata from:

        methods/<simulator_id>/metadata.json
    """
    simulators: dict[str, dict[str, Any]] = {}

    metadata_paths = sorted(
        methods_dir.glob("*/metadata.json")
    )

    if not metadata_paths:
        raise DashboardBuildError(
            f"No method metadata files found under {methods_dir}"
        )

    for metadata_path in metadata_paths:
        simulator_id = metadata_path.parent.name
        metadata = load_json(metadata_path)

        if not isinstance(metadata, dict):
            raise DashboardBuildError(
                f"{metadata_path} must contain a JSON object"
            )

        display_name = require_string(
            metadata.get("display_name"),
            field_name="display_name",
            source=metadata_path,
        )

        language = require_string(
            metadata.get("language"),
            field_name="language",
            source=metadata_path,
        )

        simulator = dict(metadata)
        simulator["display_name"] = display_name
        simulator["language"] = language

        if "simulator_id" in simulator:
            declared_id = require_string(
                simulator["simulator_id"],
                field_name="simulator_id",
                source=metadata_path,
            )

            if declared_id != simulator_id:
                raise DashboardBuildError(
                    f"{metadata_path}: simulator_id {declared_id!r} "
                    f"does not match folder name {simulator_id!r}"
                )

        simulator.pop("simulator_id", None)

        if simulator_id in simulators:
            raise DashboardBuildError(
                f"Duplicate simulator ID: {simulator_id!r}"
            )

        simulators[simulator_id] = simulator

    return dict(sorted(simulators.items()))


def infer_method_id(
    result_path: Path,
    result_data: dict[str, Any],
) -> str:
    """
    Determine the simulator ID.

    If a top-level "method" field exists, it must agree with the
    result filename.

    Example:
        results/pyzx_bss.json
        "method": "pyzx_bss"
    """
    filename_id = result_path.stem
    declared_method = result_data.get("method")

    if declared_method is None:
        return filename_id

    method_id = require_string(
        declared_method,
        field_name="method",
        source=result_path,
    )

    if method_id != filename_id:
        raise DashboardBuildError(
            f"{result_path}: top-level method {method_id!r} "
            f"does not match filename {filename_id!r}"
        )

    return method_id


def normalise_circuit_id(benchmark: str) -> str:
    """Use the benchmark filename stem as the circuit ID."""
    return Path(benchmark).stem


def metadata_path_for_run(run: dict[str, Any]) -> Path:
    """
    Convert:

        circuits/random_clifford_t/example.qasm

    into:

        circuits/random_clifford_t/example.json
    """
    benchmark_file = run.get("benchmark_file")

    if not isinstance(benchmark_file, str) or not benchmark_file.strip():
        raise DashboardBuildError(
            f"Run has no valid benchmark_file: {run!r}"
        )

    return Path(benchmark_file).with_suffix(".json")


def build_circuit_entry(
    circuit_id: str,
    metadata: dict[str, Any],
    metadata_path: Path,
) -> dict[str, Any]:
    """
    Convert a circuit metadata sidecar into dashboard format.

    Expected structure:

        {
          "display_name": "...",
          "circuit_class": "...",
          "benchmark_set": "...",
          "metrics": {
            "qubits": 10,
            "depth": 51,
            "gate_count": 287,
            "t_count": 23,
            "seed": 1,
            "sigma": "inf"
          }
        }
    """
    metrics = metadata.get("metrics")

    if not isinstance(metrics, dict):
        raise DashboardBuildError(
            f"{metadata_path}: field 'metrics' must be a JSON object"
        )

    circuit_class = first_present(
        metadata,
        "circuit_class",
        "class",
        "circuit_type",
    )

    qubits = first_present(
        metrics,
        "qubits",
        "qubit_count",
        "n_qubits",
    )

    depth = first_present(
        metrics,
        "depth",
        "circuit_depth",
    )

    gate_count = first_present(
        metrics,
        "gate_count",
        "gatecount",
        "gates",
    )

    t_count = first_present(
        metrics,
        "t_count",
        "tcount",
        "T_count",
    )

    if circuit_class is None:
        raise DashboardBuildError(
            f"{metadata_path}: missing required field "
            f"'circuit_class'"
        )

    circuit_class = require_string(
        circuit_class,
        field_name="circuit_class",
        source=metadata_path,
    )

    required_numeric_fields = {
        "qubits": qubits,
        "depth": depth,
        "gate_count": gate_count,
        "t_count": t_count,
    }

    missing_fields = [
        name
        for name, value in required_numeric_fields.items()
        if value is None
    ]

    if missing_fields:
        raise DashboardBuildError(
            f"{metadata_path}: missing required metrics: "
            f"{', '.join(missing_fields)}"
        )

    circuit: dict[str, Any] = {
        "display_name": metadata.get(
            "display_name",
            circuit_id,
        ),
        "circuit_class": circuit_class,
        "benchmark_set": metadata.get(
            "benchmark_set",
            circuit_class,
        ),
        "qubits": number_or_none(
            qubits,
            field_name="metrics.qubits",
            source=metadata_path,
        ),
        "depth": number_or_none(
            depth,
            field_name="metrics.depth",
            source=metadata_path,
        ),
        "gate_count": number_or_none(
            gate_count,
            field_name="metrics.gate_count",
            source=metadata_path,
        ),
        "t_count": number_or_none(
            t_count,
            field_name="metrics.t_count",
            source=metadata_path,
        ),
    }

    optional_metric_fields = (
        "clifford_count",
        "ccz_count",
        "seed",
        "sigma",
    )

    for field_name in optional_metric_fields:
        if field_name in metrics:
            circuit[field_name] = metrics[field_name]

    optional_metadata_fields = (
        "source",
        "generator",
        "description",
    )

    for field_name in optional_metadata_fields:
        if field_name in metadata:
            circuit[field_name] = metadata[field_name]

    return circuit


def build_record(
    run: dict[str, Any],
    *,
    circuit_id: str,
    simulator_id: str,
    result_path: Path,
    result_file_data: dict[str, Any],
) -> dict[str, Any]:
    """Convert one raw benchmark run into one dashboard record."""
    result_real, result_imag = parse_complex_result(
        run.get("result")
    )

    wall_time_value = first_present(
        run,
        "wall_time_seconds",
        "wall_time",
    )

    record: dict[str, Any] = {
        "circuit_id": circuit_id,
        "simulator_id": simulator_id,
        "status": run.get("status", "unknown"),
        "exit_status": run.get("exit_status"),
        "wall_time_seconds": parse_wall_time(
            wall_time_value
        ),
        "user_time_seconds": number_or_none(
            run.get("user_time_seconds"),
            field_name="user_time_seconds",
            source=result_path,
        ),
        "system_time_seconds": number_or_none(
            run.get("system_time_seconds"),
            field_name="system_time_seconds",
            source=result_path,
        ),
        "cpu_time_seconds": number_or_none(
            run.get("cpu_time_seconds"),
            field_name="cpu_time_seconds",
            source=result_path,
        ),
        "peak_memory_kb": number_or_none(
            run.get("peak_memory_kb"),
            field_name="peak_memory_kb",
            source=result_path,
        ),
        "result_real": result_real,
        "result_imag": result_imag,
    }

    optional_run_fields = (
        "absolute_error",
        "relative_error",
        "fidelity",
        "repeat_index",
    )

    for field_name in optional_run_fields:
        if field_name in run:
            record[field_name] = run[field_name]

    provenance_fields = (
        "git_commit",
        "started_at",
        "finished_at",
        "benchmark_set",
    )

    for field_name in provenance_fields:
        value = result_file_data.get(field_name)

        if value is not None:
            record[field_name] = value

    return record


def build_dashboard(
    results_dir: Path,
    methods_dir: Path,
) -> dict[str, Any]:
    """Build the complete dashboard data structure."""
    simulators = load_simulators(methods_dir)

    circuits: dict[str, dict[str, Any]] = {}
    records: list[dict[str, Any]] = []

    result_paths = sorted(results_dir.glob("*.json"))

    if not result_paths:
        raise DashboardBuildError(
            f"No JSON result files found in {results_dir}"
        )

    seen_pairs: set[tuple[str, str]] = set()

    for result_path in result_paths:
        result_data = load_json(result_path)

        if not isinstance(result_data, dict):
            raise DashboardBuildError(
                f"{result_path} must contain a JSON object"
            )

        simulator_id = infer_method_id(
            result_path,
            result_data,
        )

        if simulator_id not in simulators:
            expected_metadata_path = (
                methods_dir
                / simulator_id
                / "metadata.json"
            )

            raise DashboardBuildError(
                f"{result_path}: simulator {simulator_id!r} "
                f"has no metadata file at "
                f"{expected_metadata_path}"
            )

        runs = result_data.get("runs")

        if not isinstance(runs, list):
            raise DashboardBuildError(
                f"{result_path}: 'runs' must be an array"
            )

        for run_index, run in enumerate(runs):
            if not isinstance(run, dict):
                raise DashboardBuildError(
                    f"{result_path}: run {run_index} "
                    f"is not a JSON object"
                )

            benchmark = run.get("benchmark")

            if not isinstance(benchmark, str) or not benchmark.strip():
                raise DashboardBuildError(
                    f"{result_path}: run {run_index} "
                    f"has no valid benchmark"
                )

            circuit_id = normalise_circuit_id(
                benchmark
            )

            metadata_path = metadata_path_for_run(
                run
            )

            metadata = load_json(metadata_path)

            if not isinstance(metadata, dict):
                raise DashboardBuildError(
                    f"{metadata_path} must contain a JSON object"
                )

            circuit_entry = build_circuit_entry(
                circuit_id,
                metadata,
                metadata_path,
            )

            existing_circuit = circuits.get(
                circuit_id
            )

            if existing_circuit is None:
                circuits[circuit_id] = circuit_entry

            elif existing_circuit != circuit_entry:
                raise DashboardBuildError(
                    f"Conflicting metadata found for circuit "
                    f"{circuit_id!r}"
                )

            pair = (
                circuit_id,
                simulator_id,
            )

            if pair in seen_pairs:
                raise DashboardBuildError(
                    f"Duplicate result for circuit "
                    f"{circuit_id!r} and simulator "
                    f"{simulator_id!r}"
                )

            seen_pairs.add(pair)

            record = build_record(
                run,
                circuit_id=circuit_id,
                simulator_id=simulator_id,
                result_path=result_path,
                result_file_data=result_data,
            )

            records.append(record)

    circuits = dict(
        sorted(circuits.items())
    )

    records.sort(
        key=lambda record: (
            record["simulator_id"],
            record["circuit_id"],
        )
    )

    return {
        "schema_version": 1,
        "generated_at": (
            datetime.now(timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z")
        ),
        "simulators": simulators,
        "circuits": circuits,
        "records": records,
    }


def write_dashboard(
    dashboard: dict[str, Any],
    output_file: Path,
) -> None:
    """Write the dashboard atomically."""
    output_file.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    temporary_file = output_file.with_suffix(
        output_file.suffix + ".tmp"
    )

    with temporary_file.open(
        "w",
        encoding="utf-8",
    ) as file:
        json.dump(
            dashboard,
            file,
            indent=2,
            ensure_ascii=False,
            allow_nan=False,
        )

        file.write("\n")

    temporary_file.replace(
        output_file
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build ABSTRACTS dashboard data from raw "
            "benchmark results and per-method metadata"
        )
    )

    parser.add_argument(
        "--results-dir",
        type=Path,
        default=DEFAULT_RESULTS_DIR,
        help=(
            "Directory containing raw result JSON files "
            f"(default: {DEFAULT_RESULTS_DIR})"
        ),
    )

    parser.add_argument(
        "--methods-dir",
        type=Path,
        default=DEFAULT_METHODS_DIR,
        help=(
            "Directory containing "
            "methods/<simulator_id>/metadata.json "
            f"(default: {DEFAULT_METHODS_DIR})"
        ),
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT_FILE,
        help=(
            "Generated dashboard JSON path "
            f"(default: {DEFAULT_OUTPUT_FILE})"
        ),
    )

    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()

    dashboard = build_dashboard(
        results_dir=arguments.results_dir,
        methods_dir=arguments.methods_dir,
    )

    write_dashboard(
        dashboard,
        arguments.output,
    )

    print(
        f"Wrote {len(dashboard['records'])} records, "
        f"{len(dashboard['circuits'])} circuits, and "
        f"{len(dashboard['simulators'])} simulators to "
        f"{arguments.output}"
    )


if __name__ == "__main__":
    try:
        main()

    except DashboardBuildError as error:
        raise SystemExit(
            f"Dashboard build failed: {error}"
        ) from error