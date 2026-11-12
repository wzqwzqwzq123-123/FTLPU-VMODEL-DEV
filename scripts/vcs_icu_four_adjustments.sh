#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_dir="$repo_dir/../vcs_runs"
vcs_bin=${VCS_BIN:-/home/EDA/synopsys/vcs/X-2025.06-SP1/linux64/bin/vcs}
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-27000@andromeda}
export TMPDIR="$repo_dir/../tmp"
export TEMP="$TMPDIR"
export TMP="$TMPDIR"
mkdir -p "$build_dir" "$TMPDIR"

formal_filelist="$repo_dir/sim/filelist_program_load_system.f"

compile_only() {
	local top=$1
	local name=$2
	local test_dir="$build_dir/$name"
	mkdir -p "$test_dir"
	(
		cd "$repo_dir"
		"$vcs_bin" -full64 -sverilog -timescale=1ns/1ps \
			-top "$top" -f "$formal_filelist" -o "$test_dir/simv" \
			-Mdir="$test_dir/csrc" -l "$test_dir/compile.log"
	)
}

run_test() {
	local top=$1
	local name=$2
	local test_dir="$build_dir/$name"
	local test_source
	test_source=$(find "$repo_dir/sim/tb" -name "$top.sv" -print -quit)
	if [[ -z "$test_source" ]]; then
		echo "$name failed: no Testbench source found for $top" >&2
		exit 1
	fi
	mkdir -p "$test_dir"
	(
		cd "$repo_dir"
		"$vcs_bin" -full64 -sverilog -timescale=1ns/1ps \
			-top "$top" -f "$formal_filelist" "$test_source" \
			-o "$test_dir/simv" -Mdir="$test_dir/csrc" -l "$test_dir/compile.log"
		cd "$test_dir"
		./simv -l run.log
		if grep -Eq 'Fatal:|FAIL ' run.log; then
			echo "$name failed: fatal marker found in run.log" >&2
			exit 1
		fi
	)
}

requested_test=${1:-all}

should_run() {
	[[ "$requested_test" == "all" || "$requested_test" == "$1" ]]
}

should_run compile_lpu_top && compile_only lpu_top compile_lpu_top
should_run program_config_fifo && run_test lpu_program_config_fifo_tb program_config_fifo
should_run program_elastic_stage && run_test lpu_program_load_elastic_stage_tb program_elastic_stage
should_run program_reassembler && run_test lpu_program_reassembler_tb program_reassembler
should_run program_relay && run_test lpu_program_load_relay_tb program_relay
should_run program_relay_chain && run_test lpu_program_load_relay_chain_tb program_relay_chain
should_run program_load_control && run_test lpu_program_load_control_tb program_load_control
should_run mem_sram_execution && run_test lpu_mem_sram_execution_tb mem_sram_execution
should_run qctl_shared_pool && run_test lpu_qctl_shared_pool_tb qctl_shared_pool
should_run qctl_queue_controller && run_test lpu_qctl_queue_controller_tb qctl_queue_controller
should_run qctl_fabric && run_test lpu_qctl_fabric_tb qctl_fabric
should_run macro_frontend_cluster && run_test lpu_top_macro_frontend_cluster_tb macro_frontend_cluster
should_run top_fu_subsystem_program && run_test lpu_top_fu_subsystem_program_tb top_fu_subsystem_program

echo "ICU_FOUR_ADJUSTMENTS_VCS PASS"
