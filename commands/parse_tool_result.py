#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from benchmark_lib.tool_result_parser import (

    GenusResultParser, InnovusResultParser, OpenRoadResultParser,
    VivadoResultParser, YosysResultParser)

PARSER_FOR_TOOL_NAME = {
    "genus": GenusResultParser,
    "innovus": InnovusResultParser,
    "vivado": VivadoResultParser,
    "yosys": YosysResultParser,
    "openroad": OpenRoadResultParser,
    "openroad_syn": OpenRoadResultParser,
    "orsyn": OpenRoadResultParser,
}

DIRECTORY_NAME_MARKERS = (
    ("__innovus", "innovus"),
    ("__genus", "genus"),
    ("__vivado", "vivado"),
    ("__yosys", "yosys"),
    ("__orsyn", "openroad_syn"),
    ("__orpnr", "openroad"),
)

def tool_name_from_directory(result_directory):
    directory_name = Path(result_directory).name
    for marker, tool_name in DIRECTORY_NAME_MARKERS:
        if marker in directory_name:
            return tool_name
    return None

def parse_tool_result(result_directory, tool_name=None):
    tool_name = tool_name or tool_name_from_directory(result_directory)
    parser_class = PARSER_FOR_TOOL_NAME.get(tool_name)
    if parser_class is None:
        raise SystemExit(f"cannot determine tool for {result_directory}")
    return parser_class(result_directory).write_metrics_file()

def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: parse_tool_result.py <result_directory> [tool_name]")
    tool_name = sys.argv[2] if len(sys.argv) > 2 else None
    parse_tool_result(sys.argv[1], tool_name)
    return 0

if __name__ == "__main__":
    sys.exit(main())
