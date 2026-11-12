rtl/core/lpu_pkg.sv
rtl/program_load/lpu_program_load_pkg.sv
rtl/icu/lpu_qctl_pkg.sv
rtl/core/lpu_native_config_pkg.sv
rtl/queue/lpu_queue_fifo.sv
rtl/core/lpu_schedule_clock.sv
-f sim/filelist_rtl_core.f

rtl/icu/lpu_qctl_shared_pool.sv
rtl/icu/lpu_qctl_queue_controller.sv
rtl/icu/lpu_qctl_fabric.sv

rtl/program_load/lpu_program_command_sequencer.sv
rtl/program_load/lpu_program_config_fifo.sv
rtl/program_load/lpu_instruction_dma.sv
rtl/program_load/lpu_program_reassembler.sv
rtl/program_load/lpu_program_word_fifo.sv
rtl/program_load/lpu_program_transfer_path.sv
rtl/program_load/lpu_program_load_elastic_stage.sv
rtl/program_load/lpu_program_load_distributor.sv
rtl/program_load/lpu_program_distribution_ingress.sv
rtl/program_load/lpu_program_load_relay.sv
rtl/program_load/lpu_program_load_relay_chain.sv
rtl/program_load/lpu_program_distribution_network.sv
rtl/program_load/lpu_program_load_controller.sv

rtl/mem/lpu_mem_local_imem.sv
rtl/mem/lpu_mem_imem_fetch.sv
rtl/mem/lpu_mem_macro_decoder.sv
rtl/mem/lpu_mem_macro_scheduler.sv
rtl/mem/lpu_mem_macro_frontend.sv
rtl/mem/lpu_mem_local_imem_frontend.sv
rtl/mem/lpu_mem_bank_queue.sv

rtl/srf/ftlpu_sr_superlane_col_dir.sv
rtl/srf/ftlpu_sr_column_dir.sv
rtl/srf/ftlpu_sr_direction_fabric.sv
rtl/srf/ftlpu_sr_hemisphere_fabric.sv

rtl/mem_native/mem_c7_primitive_adapter.sv
rtl/mem_native/mem_bank_control_column.sv
rtl/mem_native/mem_bank_superlane_leaf.sv
rtl/mem_native/mem_logical_bank_column.sv
rtl/mem_native/mem_slice.sv
rtl/mem_native/mem_group.sv
rtl/mem_native/mem_hemisphere.sv
rtl/integration/lpu_mem_srf_integration.sv
rtl/integration/lpu_mem_command_adapter.sv
rtl/integration/lpu_mem_srf_command_integration.sv
rtl/mem/lpu_mem_subsystem.sv

rtl/mxm/lpu_mxm_local_imem.sv
rtl/mxm/lpu_mxm_imem_fetch.sv
rtl/mxm/lpu_mxm_macro_decoder_core.sv
rtl/mxm/lpu_mxm_load_macro_decoder.sv
rtl/mxm/lpu_mxm_load_macro_scheduler.sv
rtl/mxm/lpu_mxm_load_macro_frontend.sv
rtl/mxm/lpu_mxm_dequant_macro_decoder.sv
rtl/mxm/lpu_mxm_dequant_macro_scheduler.sv
rtl/mxm/lpu_mxm_dequant_macro_frontend.sv
rtl/mxm/lpu_mxm_compute_macro_decoder.sv
rtl/mxm/lpu_mxm_compute_macro_scheduler.sv
rtl/mxm/lpu_mxm_compute_macro_frontend.sv
rtl/mxm/lpu_mxm_local_imem_frontend.sv
rtl/mxm/lpu_mxm_issue_queue.sv
rtl/mxm/lpu_mxm_local_coordinator.sv
rtl/mxm/lpu_mxm_subsystem.sv

rtl/sxm/lpu_sxm_subsystem.sv
rtl/vxm/lpu_vxm_subsystem.sv
rtl/core/lpu_fu_subsystem_cluster.sv
rtl/lpu_top.sv
