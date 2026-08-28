CONFIGURATION_COLORS = {
    "orig/off": "#2a78d6",
    "orig/on": "#eb6834",
    "directive/off": "#9b5cc4",
    "retimed/off": "#2e9e6b",
}
CONFIGURATION_LABELS = {
    "orig/off": "original (no retiming)",
    "orig/on": "tool retiming",
    "directive/off": "directive only",
    "retimed/off": "manual (hand-retimed)",
}
CONFIGURATION_SHORT_LABELS = {
    "orig/off": "orig",
    "orig/on": "tool",
    "directive/off": "direct",
    "retimed/off": "manual",
}
INK_COLOR = "#1a1a19"
MUTED_COLOR = "#6b6b68"
GRIDLINE_COLOR = "#e6e6e3"
SURFACE_COLOR = "#fcfcfb"
BLOCKED_MARKER_COLOR = "#c0392b"

TOOL_PANEL_ORDER = (
    "innovus-nangate45",
    "vivado-xc7a100t",
    "vivado-xcau7p",
    "vivado-xcau15p",
    "innovus-nangate45-congested",
)

def abbreviate_tool_name(tool_name):
    return (tool_name
            .replace("innovus-", "")
            .replace("vivado-", "viv ")
            .replace("nangate45", "n45"))

def apply_axis_style(axis):
    axis.set_facecolor(SURFACE_COLOR)
    axis.grid(axis="y", color=GRIDLINE_COLOR, linewidth=0.8)
    axis.set_axisbelow(True)
    for side in ("top", "right"):
        axis.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        axis.spines[side].set_color(GRIDLINE_COLOR)
    axis.tick_params(colors=MUTED_COLOR, length=0, labelsize=8)
