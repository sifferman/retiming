#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from benchmark_lib.benchmark import Benchmark

def main():
    if len(sys.argv) < 2:
        raise SystemExit(
            "usage: read_benchmark_field.py <benchmark_directory> [--top]")
    benchmark = Benchmark(sys.argv[1])
    if "--top" in sys.argv[2:]:
        print(benchmark.top_module_name)
        return 0
    for field_name, value in benchmark.fields.items():
        print(f"{field_name}={value}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
