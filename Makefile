# Retiming benchmark suite -- convenience entry points.
#
# The heavy lifting lives in scripts/; this file exists so the common operations
# have one obvious name each.

SHELL   := /bin/bash
PY      := python3
# JOBS: concurrent heavyweight tool runs (shared lab machine + shared licenses)
JOBS    ?= 4
# CYCLES: equivalence-check length
CYCLES  ?= 3000
BENCH   ?= all

.PHONY: help check lec audit repair phases plots push matrix matrix-vivado oss csv index verdict clean-results

help:
	@echo "make check              verify every reference solution vs its original"
	@echo "make lec                formal check (Conformal); MODE=directive|retimed|both"
	@echo "make push               sync sources + PDK to eq1"
	@echo "make matrix             Fmax sweep, Genus, all benchmarks   (JOBS=$(JOBS))"
	@echo "make matrix-vivado      Fmax sweep, Vivado/Artix-7"
	@echo "make oss                yosys+ABC and OpenROAD-syn on all benchmarks"
	@echo "make csv                rebuild results/results.csv and summary.csv"
	@echo "make verdict            score each benchmark on its primary metric"
	@echo "make plots              % improvement SVGs (light + dark) in docs/"
	@echo "make phases             run the remaining measurement phases in order"
	@echo "make audit              check data integrity before quoting numbers"
	@echo "make repair             re-pull runs whose transfer from eq1 dropped"
	@echo "make BENCH=rNN_name ... restrict a target to one benchmark"

# --- correctness -------------------------------------------------------------
check:
	CYCLES=$(CYCLES) ./commands/check_all_equivalence.sh

# Formal equivalence.  MODE=directive is the one the license can actually
# prove; MODE=retimed is expected to report license-blocked.
MODE ?= directive
lec:
	./commands/check_all_logical_equivalence.sh $(MODE)

# --- remote setup ------------------------------------------------------------
push:
	@source commands/remote_execution.sh && eq_push && eq_push_pdk >/dev/null && echo "pushed to eq1"

# --- measurement -------------------------------------------------------------
matrix: push
	$(PY) -u commands/run_measurement_matrix.py $(BENCH) --tool genus  --jobs $(JOBS) \
	    --out results/matrix_genus.json

matrix-vivado: push
	$(PY) -u commands/run_measurement_matrix.py $(BENCH) --tool vivado --jobs $(JOBS) \
	    --out results/matrix_vivado.json

# The open-source flows run locally, so they do not need the eq1 push.
oss:
	@for b in $$(ls benchmarks); do \
	  for v in orig retimed directive; do \
	    [ -d benchmarks/$$b/variants/$$v ] || continue; \
	    p=$$($(PY) commands/read_benchmark_field.py benchmarks/$$b | sed -n 's/^clock_period_ns=//p'); \
	    ./commands/run_yosys.sh      $$b $$v on  $${p:-6.0} >/dev/null 2>&1; \
	    ./commands/run_yosys.sh      $$b $$v off $${p:-6.0} >/dev/null 2>&1; \
	    ./commands/run_openroad_syn.sh $$b $$v none $${p:-6.0} >/dev/null 2>&1; \
	    echo "  oss done: $$b/$$v"; \
	  done; \
	done

# Sequential remaining-measurement run (r15 refix, bound closing, orsyn,
# vivado, Innovus PnR, then rebuild+audit+score).  flock-guarded.
phases:
	./commands/run_phases.sh

audit:
	./commands/audit_dataset_integrity.sh

repair:
	./commands/refetch_missing_results.sh

# Improvement figure. Colours are checked by commands/validate_color_palette.py
# (a Python port of the dataviz skill's validator -- no node on this host).
plots: csv
	$(PY) commands/aggregate_improvements.py
	$(PY) commands/generate_improvement_chart.py --mode light
	$(PY) commands/generate_improvement_chart.py --mode dark

# --- reporting ---------------------------------------------------------------
index:
	$(PY) commands/generate_benchmark_index.py

csv:
	@for d in results/*/*/; do \
	  case "$$d" in \
	    *genus*innovus*) $(PY) commands/parse_tool_result.py  "$$d" >/dev/null 2>&1 ;; \
	    *genus*)         $(PY) commands/parse_tool_result.py    "$$d" >/dev/null 2>&1 ;; \
	    *vivado*)        $(PY) commands/parse_tool_result.py   "$$d" >/dev/null 2>&1 ;; \
	    *yosys*orpnr*)   $(PY) commands/parse_tool_result.py "$$d" >/dev/null 2>&1 ;; \
	    *yosys*)         $(PY) commands/parse_tool_result.py    "$$d" >/dev/null 2>&1 ;; \
	    *orsyn*|*orpnr*) $(PY) commands/parse_tool_result.py "$$d" >/dev/null 2>&1 ;; \
	  esac; \
	done
	$(PY) commands/summarize_results.py

verdict: csv
	$(PY) commands/report_verdicts.py

clean-results:
	rm -rf results/*/ results/results.csv results/summary.csv
