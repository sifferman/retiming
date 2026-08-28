import re
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
BENCHMARKS_DIRECTORY = REPOSITORY_ROOT / "benchmarks"

TOP_LEVEL_FIELD_NAMES = (
    "id", "name", "top", "class", "primary_metric",
    "latency_preserving", "density_target", "latency_delta")
INDENTED_STRING_FIELD_NAMES = ("part_usplus", "part")
INDENTED_NUMBER_FIELD_NAMES = (
    "clock_period_ns", "core_density", "fpga_clock_period_ns", "max_fanout")

VARIANT_NAMES = ("orig", "retimed", "directive")

class Benchmark:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.name = self.directory.name
        self.fields = self._read_specification_fields()

    def _read_specification_fields(self):
        specification_path = self.directory / "bench.yaml"
        if not specification_path.exists():
            return {}
        specification_text = specification_path.read_text()
        fields = {}
        for field_name in TOP_LEVEL_FIELD_NAMES:
            match = re.search(rf"^{field_name}:\s*(.+?)\s*$",
                              specification_text, re.MULTILINE)
            if match:
                fields[field_name] = match.group(1).strip().strip('"')
        for field_name in INDENTED_STRING_FIELD_NAMES:
            match = re.search(rf"^\s+{field_name}:\s*(\S+)",
                              specification_text, re.MULTILINE)
            if match:
                fields[field_name] = match.group(1)
        for field_name in INDENTED_NUMBER_FIELD_NAMES:
            match = re.search(rf"^\s+{field_name}:\s*([\d.]+)",
                              specification_text, re.MULTILINE)
            if match:
                fields[field_name] = float(match.group(1))
        return fields

    @property
    def top_module_name(self):
        return self.fields.get("top", self.name)

    @property
    def declared_clock_period_ns(self):
        return self.fields.get("clock_period_ns")

    @property
    def declared_core_density(self):
        return self.fields.get("core_density", 0.6)

    @property
    def primary_metric(self):
        return self.fields.get("primary_metric", "fmax")

    @property
    def preserves_latency(self):
        return str(self.fields.get("latency_preserving", "true")).lower() == "true"

    @property
    def available_variant_names(self):
        return [name for name in VARIANT_NAMES
                if (self.directory / "variants" / name).is_dir()]

    def variant_directory(self, variant_name):
        return self.directory / "variants" / variant_name

    def source_files(self, variant_name):
        return sorted(self.variant_directory(variant_name).glob("*.sv"))

def every_benchmark():
    return [Benchmark(directory)
            for directory in sorted(BENCHMARKS_DIRECTORY.iterdir())
            if (directory / "variants" / "orig").is_dir()]

def benchmark_named(name):
    return Benchmark(BENCHMARKS_DIRECTORY / name)
