import re

from benchmark_lib.text_extraction import first_float_matching

WORST_NEGATIVE_SLACK_PATTERN = r"worst slack max\s+(-?[\d.]+)"
TOTAL_NEGATIVE_SLACK_PATTERN = r"tns max\s+(-?[\d.]+)"
DATA_ARRIVAL_TIME_PATTERN = r"^\s*(-?[\d.]+)\s+data arrival time"

def extract_timing_metrics(report_text):
    metrics = {}
    worst_negative_slack = first_float_matching(
        report_text, WORST_NEGATIVE_SLACK_PATTERN)
    if worst_negative_slack is not None:
        metrics["wns_ns"] = worst_negative_slack
        metrics["timing_status"] = (
            "MET" if worst_negative_slack >= 0 else "VIOLATED")
    total_negative_slack = first_float_matching(
        report_text, TOTAL_NEGATIVE_SLACK_PATTERN)
    if total_negative_slack is not None:
        metrics["tns_ns"] = total_negative_slack
    data_arrival_time = first_float_matching(
        report_text, DATA_ARRIVAL_TIME_PATTERN, re.MULTILINE)
    if data_arrival_time is not None:
        metrics["data_path_ns"] = data_arrival_time
    return metrics
