from pathlib import Path
import re

PORT_DECLARATION_PATTERN = (
    r"\b(input|output)\s+(?:wire|logic|reg)?\s*(?:\[([^\]]+)\]\s*)?(\w+)")
BIT_RANGE_PATTERN = r"^\s*(\d+)\s*:\s*(\d+)\s*$"

class Port:
    def __init__(self, direction, bit_range, name):
        self.direction = direction
        self.bit_range = bit_range
        self.name = name

    @property
    def width_in_bits(self):
        if not self.bit_range:
            return 1
        match = re.match(BIT_RANGE_PATTERN, self.bit_range)
        if not match:
            return None
        return int(match.group(1)) - int(match.group(2)) + 1

    @property
    def is_input(self):
        return self.direction == "input"

    @property
    def is_output(self):
        return self.direction == "output"

    def declaration_prefix(self):
        return f"[{self.bit_range}] " if self.bit_range else ""

class SystemVerilogModule:
    def __init__(self, source_text, module_name):
        self.source_text = source_text
        self.module_name = module_name
        self.ports = self._read_ports()

    def _read_ports(self):
        header_start = re.search(rf"\bmodule\s+{re.escape(self.module_name)}\b",
                                 self.source_text)
        if not header_start:
            return []
        remainder = self.source_text[header_start.end():]
        header = remainder[:remainder.index(");")]
        return [Port(*match.groups())
                for match in re.finditer(PORT_DECLARATION_PATTERN, header)]

    @property
    def data_input_ports(self):
        return [port for port in self.ports
                if port.is_input and port.name not in ("clk", "rst_n")]

    @property
    def output_ports(self):
        return [port for port in self.ports if port.is_output]

    @property
    def has_reset_port(self):
        return any(port.name == "rst_n" for port in self.ports)

    @property
    def total_pin_count(self):
        return sum(port.width_in_bits or 1 for port in self.ports)


def parse_module(source_path_or_text, module_name=None):
    text = source_path_or_text
    if not isinstance(text, str) or "\n" not in text:
        text = Path(source_path_or_text).read_text(errors="replace")
    if module_name is None:
        match = re.search(r"\bmodule\s+(\w+)", text)
        if not match:
            raise SystemExit(f"no module found in {source_path_or_text}")
        module_name = match.group(1)
    module = SystemVerilogModule(text, module_name)
    port_dictionaries = []
    for port in module.ports:
        bit_range = port.bit_range or ""
        msb, _, lsb = bit_range.partition(":")
        port_dictionaries.append({
            "dir": port.direction,
            "name": port.name,
            "msb": msb.strip() or None,
            "lsb": lsb.strip() or None,
            "width": port.width_in_bits,
        })
    return module_name, port_dictionaries
