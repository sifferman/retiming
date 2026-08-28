import gzip
import json
import re
from pathlib import Path

from benchmark_lib.opensta_timing_report import extract_timing_metrics
from benchmark_lib.text_extraction import (
    first_float_matching, first_integer_matching, first_string_matching,
    last_integer_matching, read_text_file_or_empty)

METRICS_FILE_NAME = "metrics.json"
TOOL_EMITTED_METRICS_FILE_NAME = "metrics_tcl.json"

class ToolResultParser:
    tool_name = "unknown"

    def __init__(self, result_directory):
        self.result_directory = Path(result_directory)

    def read_report(self, file_name):
        return read_text_file_or_empty(self.result_directory / file_name)

    def read_compressed_report(self, glob_pattern):
        for path in sorted(self.result_directory.glob(glob_pattern)):
            try:
                if path.name.endswith(".gz"):
                    return gzip.open(path, "rt", errors="replace").read()
                return path.read_text(errors="replace")
            except OSError:
                continue
        return ""

    def read_tool_emitted_metrics(self):
        path = self.result_directory / TOOL_EMITTED_METRICS_FILE_NAME
        if not path.exists():
            return {}
        try:
            return json.loads(path.read_text())
        except json.JSONDecodeError:
            return {}

    def extract_metrics(self):
        raise NotImplementedError

    def write_metrics_file(self):
        metrics = self.read_tool_emitted_metrics()
        metrics.setdefault("tool", self.tool_name)
        metrics.update(self.extract_metrics())
        wall_seconds = first_float_matching(
            self.read_report("wall.txt"), r"([\d.]+)")
        if wall_seconds is not None:
            metrics["wall_seconds"] = wall_seconds
        output_path = self.result_directory / METRICS_FILE_NAME
        output_path.write_text(json.dumps(metrics, indent=2) + "\n")
        return metrics

class OpenStaBasedParser(ToolResultParser):
    def extract_metrics(self):
        return extract_timing_metrics(self.read_report("timing.rpt"))

class YosysResultParser(OpenStaBasedParser):
    tool_name = "yosys"
    MAPPED_CELL_COUNT_PATTERN = r"^\s*(\d+) cells in clk="
    GENERIC_CELL_COUNT_PATTERN = r"^\s*(\d+) cells$"
    CHIP_AREA_PATTERN = r"Chip area for (?:top )?module '?\\?(\S+?)'?:\s*([\d.]+)"
    LIBERTY_CELL_LINE_PATTERN = r"^\s*(\d+)\s+[\d.eE+]+\s+(\S+)$"
    FLIP_FLOP_CELL_NAME_PATTERN = r"__s?dff|^S?DFF"

    def extract_metrics(self):
        metrics = super().extract_metrics()
        log = self.read_report("yosys.log")
        area_match = re.search(self.CHIP_AREA_PATTERN, log)
        if area_match:
            metrics["top"] = area_match.group(1).lstrip("\\")
            metrics["area_um2"] = float(area_match.group(2))
        cell_count = last_integer_matching(log, self.MAPPED_CELL_COUNT_PATTERN)
        if cell_count is None:
            cell_count = last_integer_matching(log, self.GENERIC_CELL_COUNT_PATTERN)
        if cell_count is not None:
            metrics["num_cells"] = cell_count
        flip_flop_count = sum(
            int(match.group(1))
            for match in re.finditer(self.LIBERTY_CELL_LINE_PATTERN, log, re.MULTILINE)
            if re.search(self.FLIP_FLOP_CELL_NAME_PATTERN, match.group(2)))
        if flip_flop_count:
            metrics["num_ffs"] = flip_flop_count
        version = first_string_matching(log, r"^Yosys (\d+\.\d+)", re.MULTILINE)
        if version:
            metrics["tool_version"] = version
        return metrics

class OpenRoadResultParser(OpenStaBasedParser):
    tool_name = "openroad"
    CELL_USAGE_FILE_NAME = "cells.rpt"
    FLIP_FLOP_CELL_NAME_PATTERN = r"S?DFF|LATCH|DLL"

    def extract_metrics(self):
        metrics = super().extract_metrics()
        flip_flop_count = self._count_flip_flops_in_cell_usage_report()
        if flip_flop_count:
            metrics["num_ffs"] = flip_flop_count
            metrics["num_ffs_source"] = self.CELL_USAGE_FILE_NAME
        return metrics

    def _count_flip_flops_in_cell_usage_report(self):
        report = self.read_report(self.CELL_USAGE_FILE_NAME)
        if not report:
            return 0
        try:
            cell_usage = json.loads(report).get("cell_usage_info", [])
        except json.JSONDecodeError:
            return 0
        return sum(int(entry.get("count") or 0) for entry in cell_usage
                   if re.match(self.FLIP_FLOP_CELL_NAME_PATTERN,
                               entry.get("name") or "", re.IGNORECASE))

class GenusResultParser(ToolResultParser):
    tool_name = "genus"
    SLACK_WITH_UNITS_PATTERN = (
        r"Path 1:\s+(MET|VIOLATED)\s+\(\s*(-?[\d.]+)\s*(ps|ns)\)")
    FALLBACK_SLACK_PATTERN = r"Slack:=\s*(-?[\d.]+)"
    DATA_PATH_PICOSECONDS_PATTERN = r"Data Path:-\s*(-?[\d.]+)"
    ENDPOINT_PATTERN = r"Endpoint:\s*\([RF]\)\s*(\S+)"
    AREA_LINE_PATTERN = r"^\s*(\S+)\s+(\d+)\s+([\d.]+)\s+([\d.]+)"
    TOTAL_GATE_COUNT_PATTERN = r"Total\s+(\d+)\s+"

    def extract_metrics(self):
        metrics = {}
        timing_report = self.read_report("timing.rpt")
        metrics.update(self._extract_slack(timing_report))
        data_path_picoseconds = first_float_matching(
            timing_report, self.DATA_PATH_PICOSECONDS_PATTERN)
        if data_path_picoseconds is not None:
            metrics["data_path_ns"] = data_path_picoseconds / 1000.0
        endpoint = first_string_matching(timing_report, self.ENDPOINT_PATTERN)
        if endpoint:
            metrics["critical_endpoint"] = endpoint
        area = self._extract_area(self.read_report("area.rpt"))
        if area is not None:
            metrics["area_um2"] = area
        gate_count = first_integer_matching(
            self.read_report("gates.rpt"), self.TOTAL_GATE_COUNT_PATTERN)
        if gate_count is not None:
            metrics["num_cells"] = gate_count
        return metrics

    def _extract_slack(self, timing_report):
        match = re.search(self.SLACK_WITH_UNITS_PATTERN, timing_report)
        if match:
            slack = float(match.group(2))
            if match.group(3) == "ps":
                slack /= 1000.0
            return {"wns_ns": slack, "timing_status": match.group(1)}
        fallback = first_float_matching(timing_report, self.FALLBACK_SLACK_PATTERN)
        if fallback is None:
            return {}
        return {"wns_ns": fallback / 1000.0}

    def _extract_area(self, area_report):
        total_area = None
        for line in area_report.splitlines():
            match = re.match(self.AREA_LINE_PATTERN, line)
            if match:
                total_area = float(match.group(3))
        return total_area

class InnovusResultParser(ToolResultParser):
    tool_name = "innovus"
    WIRELENGTH_TOTAL_PATTERN = r"\|\s*Total\s*\|\s*([\d.]+)\s*um\s*\|"
    PER_LAYER_WIRELENGTH_PATTERN = r"\|\s*(metal\d+)\s*\|\s*([\d.]+)\s*um\s*\|"
    CONGESTION_OVERFLOW_PATTERN = (
        r"Overflow:\s*(\d+)\s*=.*?([\d.]+)%\s*H.*?([\d.]+)%\s*V")
    PATH_GROUP_SUMMARY_PATTERN = r"\|\s*{label}[^|]*\|\s*(-?[\d.]+)\s*\|\s*(-?[\d.]+)\s*\|"
    REG2REG_SLACK_PATTERN = r"^Path 1:.*?= Slack Time\s+(-?[\d.]+)"
    REG2REG_ENDPOINTS_PATTERN = (
        r"^Path 1:.*?Endpoint:\s+(\S+).*?Beginpoint:\s+(\S+)")

    def extract_metrics(self):
        metrics = {}
        metrics.update(self._extract_wirelength())
        metrics.update(self._extract_congestion_overflow())
        metrics.update(self._extract_path_group_slack_summary())
        metrics.update(self._extract_reg2reg_critical_path())
        return metrics

    def _extract_wirelength(self):
        log = self.read_report("innovus.log")
        totals = re.findall(self.WIRELENGTH_TOTAL_PATTERN, log)
        if not totals:
            return {}
        metrics = {"routed_wirelength_um": float(totals[-1]),
                   "wirelength_source": "innovus.log Wire Length Statistics"}
        per_layer = dict(re.findall(self.PER_LAYER_WIRELENGTH_PATTERN, log))
        if per_layer:
            metrics["wirelength_by_layer_um"] = {
                layer: float(length) for layer, length in per_layer.items()}
        return metrics

    def _extract_congestion_overflow(self):
        metrics = {}
        for file_name, stage in (("congestion_route.rpt", "route"),
                                 ("congestion_place.rpt", "place")):
            match = re.search(self.CONGESTION_OVERFLOW_PATTERN,
                              self.read_report(file_name), re.DOTALL)
            if not match:
                continue
            metrics[f"overflow_{stage}"] = int(match.group(1))
            metrics[f"overflow_{stage}_h_pct"] = float(match.group(2))
            metrics[f"overflow_{stage}_v_pct"] = float(match.group(3))
            if stage == "route":
                metrics["route_legal"] = int(match.group(1)) == 0
        return metrics

    def _extract_path_group_slack_summary(self):
        summary = self.read_compressed_report("timing_postroute/*postRoute.summary*")
        metrics = {}
        for label, key in (("WNS", "wns"), ("TNS", "tns"),
                           ("Violating Paths", "violating")):
            match = re.search(self.PATH_GROUP_SUMMARY_PATTERN.format(label=label),
                              summary)
            if match:
                metrics[f"postroute_{key}_all"] = float(match.group(1))
                metrics[f"postroute_{key}_reg2reg"] = float(match.group(2))
        return metrics

    def _extract_reg2reg_critical_path(self):
        report = self.read_compressed_report("timing_postroute/*reg2reg*.tarpt*")
        slack = first_float_matching(report, self.REG2REG_SLACK_PATTERN,
                                     re.DOTALL | re.MULTILINE)
        if slack is None:
            return {}
        metrics = {"postroute_wns_reg2reg_ns": slack,
                   "postroute_status_reg2reg": "MET" if slack >= 0 else "VIOLATED"}
        endpoints = re.search(self.REG2REG_ENDPOINTS_PATTERN, report,
                              re.DOTALL | re.MULTILINE)
        if endpoints:
            metrics["reg2reg_endpoint"] = endpoints.group(1)
            metrics["reg2reg_beginpoint"] = endpoints.group(2)
        return metrics

class VivadoResultParser(ToolResultParser):
    tool_name = "vivado"
    SLACK_TABLE_PATTERN = (
        r"WNS\(ns\)\s+TNS\(ns\).*?\n\s*-+.*?\n\s*(-?[\d.]+)\s+(-?[\d.]+)")
    FAILING_ENDPOINT_COUNT_PATTERN = r"Number of Failing Endpoints:\s*(\d+)"
    LOOKUP_TABLE_COUNT_PATTERN = r"\|\s*(?:Slice|CLB) LUTs\s*\|\s*(\d+)"
    FLIP_FLOP_COUNT_PATTERN = r"\|\s*(?:Slice|CLB) Registers\s*\|\s*(\d+)"
    TOTAL_POWER_PATTERN = r"Total On-Chip Power \(W\)\s*\|\s*([\d.]+)"
    DYNAMIC_POWER_PATTERN = r"Dynamic \(W\)\s*\|\s*([\d.]+)"
    STATIC_POWER_PATTERN = r"Device Static \(W\)\s*\|\s*([\d.]+)"
    CONGESTION_LEVEL_PATTERN = r"^\|\s*\w+\s*\|\s*\w+\s*\|\s*(\d+)\s*\|"
    UNROUTED_NET_COUNT_PATTERN = r"#\s*of\s+unrouted\s+nets\s*[:.]*\s*(\d+)"
    WALL_SECONDS_PATTERN = r"WALL_SECONDS\s+([\d.]+)"

    def extract_metrics(self):
        metrics = {}
        for report_file_name, prefix in (("timing_impl.rpt", "impl"),
                                         ("timing_synth.rpt", "synth")):
            for key, value in self._extract_slack_table(
                    self.read_report(report_file_name)).items():
                metrics[f"{prefix}_{key}"] = value
        metrics.update(self._choose_reported_timing(metrics))
        metrics.update(self._extract_utilization())
        metrics.update(self._extract_power())
        metrics.update(self._extract_congestion_levels())
        unrouted_nets = first_integer_matching(
            self.read_report("route_status.rpt"),
            self.UNROUTED_NET_COUNT_PATTERN, re.IGNORECASE)
        if unrouted_nets is not None:
            metrics["unrouted_nets"] = unrouted_nets
        return metrics

    def _extract_slack_table(self, report_text):
        match = re.search(self.SLACK_TABLE_PATTERN, report_text, re.DOTALL)
        metrics = {}
        if match:
            metrics["wns_ns"] = float(match.group(1))
            metrics["tns_ns"] = float(match.group(2))
        failing_endpoints = first_integer_matching(
            report_text, self.FAILING_ENDPOINT_COUNT_PATTERN)
        if failing_endpoints is not None:
            metrics["failing_endpoints"] = failing_endpoints
        return metrics

    def _choose_reported_timing(self, metrics):
        register_to_register_slack = self.read_tool_emitted_metrics().get(
            "wns_reg2reg_ns")
        try:
            register_to_register_slack = float(register_to_register_slack)
        except (TypeError, ValueError):
            register_to_register_slack = None
        if register_to_register_slack is not None:
            return {"wns_reg2reg_ns": register_to_register_slack,
                    "wns_ns": register_to_register_slack,
                    "timing_status": ("MET" if register_to_register_slack >= 0
                                      else "VIOLATED")}
        implementation_slack = metrics.get("impl_wns_ns")
        if implementation_slack is None:
            return {}
        return {"wns_ns": implementation_slack,
                "timing_status": "MET" if implementation_slack >= 0 else "VIOLATED"}

    def _extract_utilization(self):
        report = self.read_report("util_impl.rpt")
        metrics = {}
        lookup_tables = first_integer_matching(report, self.LOOKUP_TABLE_COUNT_PATTERN)
        if lookup_tables is not None:
            metrics["num_lut"] = lookup_tables
        flip_flops = first_integer_matching(report, self.FLIP_FLOP_COUNT_PATTERN)
        if flip_flops is not None:
            metrics["num_ffs"] = flip_flops
        return metrics

    def _extract_power(self):
        report = self.read_report("power.rpt")
        metrics = {}
        for pattern, key in ((self.TOTAL_POWER_PATTERN, "power_mw"),
                             (self.DYNAMIC_POWER_PATTERN, "power_dynamic_mw"),
                             (self.STATIC_POWER_PATTERN, "power_static_mw")):
            watts = first_float_matching(report, pattern)
            if watts is not None:
                metrics[key] = watts * 1000.0
        return metrics

    def _extract_congestion_levels(self):
        report = self.read_report("congestion.rpt")
        metrics = {}
        for section_title, key in (("Placer Final Level Congestion", "place"),
                                   ("Initial Estimated Router Congestion", "route")):
            section_start = report.find(section_title)
            if section_start < 0:
                continue
            section = report[section_start:section_start + 4000]
            levels = [int(level) for level in re.findall(
                self.CONGESTION_LEVEL_PATTERN, section, re.MULTILINE)]
            metrics[f"congestion_{key}_max_level"] = max(levels) if levels else 0
            metrics[f"congestion_{key}_windows"] = len(levels)
        return metrics
