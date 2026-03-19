# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'rbconfig'

require 'rhdl/codegen'
require 'rhdl/codegen/verilog/sim/verilog_simulator'
require 'fiddle'

require_relative 'ir_runner'
require_relative '../import/cpu_importer'

module RHDL
  module Examples
    module AO486
      class VerilatorRunner < IrRunner
        DEFAULT_MAX_CYCLES = IrRunner::PARITY_DEFAULT_MAX_CYCLES
        BUILD_ROOT = File.expand_path('../../.verilator_build', __dir__)
        attr_reader :binary_path

        FetchWordEvent = Struct.new(:address, :word, keyword_init: true)
        FetchGroupEvent = Struct.new(:address, :bytes, keyword_init: true)
        FetchPcGroupEvent = Struct.new(:pc, :bytes, keyword_init: true)
        StepEvent = Struct.new(:eip, :consumed, :bytes, keyword_init: true)

        class << self
          def runtime_bundle(threads: 1)
            normalized_threads = RHDL::Codegen::Verilog::VerilogSimulator.normalize_threads(threads)
            mutex.synchronize do
              runtime_cache[normalized_threads] ||= build_runtime_bundle(threads: normalized_threads)
            end
          end

          private

          def mutex
            @mutex ||= Mutex.new
          end

          def runtime_cache
            @runtime_cache ||= {}
          end

          def build_runtime_bundle(threads:)
            out_dir = Dir.mktmpdir('rhdl_ao486_verilator_out')
            workspace_dir = Dir.mktmpdir('rhdl_ao486_verilator_ws')
            build_dir = File.join(BUILD_ROOT, 'ao486_runner')
            FileUtils.mkdir_p(build_dir)

            importer = RHDL::Examples::AO486::Import::CpuImporter.new(
              output_dir: out_dir,
              workspace_dir: workspace_dir,
              keep_workspace: true,
              import_strategy: :tree,
              patches_dir: RHDL::Examples::AO486::Import::CpuImporter::DEFAULT_PATCHES_ROOT,
              strict: false
            )
            diagnostics = []
            command_log = []
            source_prep = importer.send(
              :prepare_import_source_tree,
              workspace_dir,
              diagnostics: diagnostics,
              command_log: command_log
            )
            unless source_prep[:success]
              raise diagnostics.join("\n")
            end

            prepared = importer.send(:prepare_workspace, workspace_dir, strategy: :tree)
            wrapper_path = File.join(build_dir, 'verilog', 'ao486_runner_wrapper.cpp')
            FileUtils.mkdir_p(File.dirname(wrapper_path))

            File.write(wrapper_path, wrapper_source)

            simulator = RHDL::Codegen::Verilog::VerilogSimulator.new(
              backend: :verilator,
              build_dir: build_dir,
              library_basename: 'ao486_runner',
              top_module: 'ao486',
              verilator_prefix: 'Vao486',
              x_assign: '0',
              x_initial: '0',
              extra_verilator_flags: [
                '--public-flat-rw',
                '-Wno-UNOPTFLAT',
                '-Wno-PINMISSING',
                '-Wno-WIDTHEXPAND',
                '-Wno-WIDTHTRUNC',
                *prepared.fetch(:staged_include_dirs).map { |dir| "-I#{dir}" }
              ],
              threads: threads
            )
            simulator.prepare_build_dirs!
            simulator.compile_backend(
              verilog_file: prepared.fetch(:wrapper_path),
              wrapper_file: wrapper_path
            )

            {
              prepared: prepared,
              build_dir: build_dir,
              library_path: simulator.shared_library_path
            }
          end

          def wrapper_source
            <<~CPP
              #include "Vao486.h"
              #include "Vao486___024root.h"
              #include "verilated.h"
              #include <cstring>
              #include <cstdint>

              double sc_time_stamp() { return 0; }

              struct SimContext {
                Vao486* dut;
              };

              extern "C" {

              void* sim_create() {
                const char* args[] = {""};
                Verilated::commandArgs(1, args);
                auto* ctx = new SimContext();
                ctx->dut = new Vao486();
                ctx->dut->clk = 0;
                ctx->dut->rst_n = 0;
                ctx->dut->eval();
                return ctx;
              }

              void sim_destroy(void* sim) {
                auto* ctx = static_cast<SimContext*>(sim);
                if (!ctx) return;
                delete ctx->dut;
                delete ctx;
              }

              void sim_eval(void* sim) {
                auto* ctx = static_cast<SimContext*>(sim);
                if (!ctx || !ctx->dut) return;
                ctx->dut->eval();
              }

              void sim_poke(void* sim, const char* name, uint32_t value) {
                auto* ctx = static_cast<SimContext*>(sim);
                if (!ctx || !ctx->dut || !name) return;
                auto* root = ctx->dut->rootp;
                if      (!std::strcmp(name, "clk"))               ctx->dut->clk = value;
                else if (!std::strcmp(name, "rst_n"))             ctx->dut->rst_n = value;
                else if (!std::strcmp(name, "a20_enable"))        ctx->dut->a20_enable = value;
                else if (!std::strcmp(name, "cache_disable"))     ctx->dut->cache_disable = value;
                else if (!std::strcmp(name, "interrupt_do"))      ctx->dut->interrupt_do = value;
                else if (!std::strcmp(name, "interrupt_vector"))  ctx->dut->interrupt_vector = value;
                else if (!std::strcmp(name, "avm_waitrequest"))   ctx->dut->avm_waitrequest = value;
                else if (!std::strcmp(name, "avm_readdatavalid")) ctx->dut->avm_readdatavalid = value;
                else if (!std::strcmp(name, "avm_readdata"))      ctx->dut->avm_readdata = value;
                else if (!std::strcmp(name, "dma_address"))       ctx->dut->dma_address = value;
                else if (!std::strcmp(name, "dma_16bit"))         ctx->dut->dma_16bit = value;
                else if (!std::strcmp(name, "dma_write"))         ctx->dut->dma_write = value;
                else if (!std::strcmp(name, "dma_writedata"))     ctx->dut->dma_writedata = value;
                else if (!std::strcmp(name, "dma_read"))          ctx->dut->dma_read = value;
                else if (!std::strcmp(name, "io_read_data"))      ctx->dut->io_read_data = value;
                else if (!std::strcmp(name, "io_read_done"))      ctx->dut->io_read_done = value;
                else if (!std::strcmp(name, "io_write_done"))     ctx->dut->io_write_done = value;
                else if (!std::strcmp(name, "pipeline_inst__acflag")) root->ao486__DOT__pipeline_inst__DOT__acflag = value;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__acflag")) root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__acflag = value;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__acflag")) root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__acflag = value;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__acflag_to_reg")) root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__acflag_to_reg = value;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__acflag")) root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__acflag = value;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__acflag_to_reg")) root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__acflag_to_reg = value;
                else if (!std::strcmp(name, "memory_inst__acflag")) root->ao486__DOT__memory_inst__DOT__acflag = value;
                else if (!std::strcmp(name, "memory_inst__tlb_inst__acflag")) root->ao486__DOT__memory_inst__DOT__tlb_inst__DOT__acflag = value;
              }

              uint32_t sim_peek_u32(void* sim, const char* name) {
                auto* ctx = static_cast<SimContext*>(sim);
                if (!ctx || !ctx->dut || !name) return 0;
                auto* root = ctx->dut->rootp;
                if      (!std::strcmp(name, "rst_n")) return ctx->dut->rst_n;
                else if (!std::strcmp(name, "interrupt_done")) return ctx->dut->interrupt_done;
                else if (!std::strcmp(name, "avm_address")) return ctx->dut->avm_address;
                else if (!std::strcmp(name, "avm_writedata")) return ctx->dut->avm_writedata;
                else if (!std::strcmp(name, "avm_byteenable")) return ctx->dut->avm_byteenable;
                else if (!std::strcmp(name, "avm_burstcount")) return ctx->dut->avm_burstcount;
                else if (!std::strcmp(name, "avm_write")) return ctx->dut->avm_write;
                else if (!std::strcmp(name, "avm_read")) return ctx->dut->avm_read;
                else if (!std::strcmp(name, "io_read_do")) return ctx->dut->io_read_do;
                else if (!std::strcmp(name, "io_read_address")) return ctx->dut->io_read_address;
                else if (!std::strcmp(name, "io_read_length")) return ctx->dut->io_read_length;
                else if (!std::strcmp(name, "io_write_do")) return ctx->dut->io_write_do;
                else if (!std::strcmp(name, "io_write_address")) return ctx->dut->io_write_address;
                else if (!std::strcmp(name, "io_write_length")) return ctx->dut->io_write_length;
                else if (!std::strcmp(name, "io_write_data")) return ctx->dut->io_write_data;
                else if (!std::strcmp(name, "trace_retired")) return ctx->dut->trace_retired;
                else if (!std::strcmp(name, "trace_wr_finished")) return ctx->dut->trace_wr_finished;
                else if (!std::strcmp(name, "trace_wr_ready")) return ctx->dut->trace_wr_ready;
                else if (!std::strcmp(name, "trace_wr_hlt_in_progress")) return ctx->dut->trace_wr_hlt_in_progress;
                else if (!std::strcmp(name, "trace_wr_consumed")) return ctx->dut->trace_wr_consumed;
                else if (!std::strcmp(name, "trace_fetch_valid")) return ctx->dut->trace_fetch_valid;
                else if (!std::strcmp(name, "trace_dec_acceptable")) return ctx->dut->trace_dec_acceptable;
                else if (!std::strcmp(name, "trace_fetch_accept_length")) return ctx->dut->trace_fetch_accept_length;
                else if (!std::strcmp(name, "trace_prefetchfifo_accept_empty")) return ctx->dut->trace_prefetchfifo_accept_empty;
                else if (!std::strcmp(name, "trace_prefetchfifo_accept_do")) return ctx->dut->trace_prefetchfifo_accept_do;
                else if (!std::strcmp(name, "trace_wr_eip")) return ctx->dut->trace_wr_eip;
                else if (!std::strcmp(name, "trace_prefetch_eip")) return ctx->dut->trace_prefetch_eip;
                else if (!std::strcmp(name, "trace_arch_eax")) return ctx->dut->trace_arch_eax;
                else if (!std::strcmp(name, "trace_arch_ebx")) return ctx->dut->trace_arch_ebx;
                else if (!std::strcmp(name, "trace_arch_ecx")) return ctx->dut->trace_arch_ecx;
                else if (!std::strcmp(name, "trace_arch_edx")) return ctx->dut->trace_arch_edx;
                else if (!std::strcmp(name, "trace_arch_esi")) return ctx->dut->trace_arch_esi;
                else if (!std::strcmp(name, "trace_arch_edi")) return ctx->dut->trace_arch_edi;
                else if (!std::strcmp(name, "trace_arch_esp")) return ctx->dut->trace_arch_esp;
                else if (!std::strcmp(name, "trace_arch_ebp")) return ctx->dut->trace_arch_ebp;
                else if (!std::strcmp(name, "trace_arch_eip")) return ctx->dut->trace_arch_eip;
                else if (!std::strcmp(name, "pipeline_inst__acflag")) return root->ao486__DOT__pipeline_inst__DOT__acflag;
                else if (!std::strcmp(name, "pipeline_inst__cr0_am")) return root->ao486__DOT___pipeline_inst_cr0_am;
                else if (!std::strcmp(name, "pipeline_inst__wr_int")) return root->ao486__DOT___pipeline_inst_wr_int;
                else if (!std::strcmp(name, "pipeline_inst__wr_int_soft_int")) return root->ao486__DOT___pipeline_inst_wr_int_soft_int;
                else if (!std::strcmp(name, "pipeline_inst__wr_int_vector")) return root->ao486__DOT___pipeline_inst_wr_int_vector;
                else if (!std::strcmp(name, "pipeline_inst__glob_param_1")) return root->ao486__DOT___pipeline_inst_glob_param_1_value;
                else if (!std::strcmp(name, "pipeline_inst__glob_param_2")) return root->ao486__DOT___pipeline_inst_glob_param_2_value;
                else if (!std::strcmp(name, "pipeline_inst__glob_param_3")) return root->ao486__DOT___pipeline_inst_glob_param_3_value;
                else if (!std::strcmp(name, "global_regs_inst__glob_param_1")) return root->ao486__DOT___global_regs_inst_glob_param_1;
                else if (!std::strcmp(name, "global_regs_inst__glob_param_2")) return root->ao486__DOT___global_regs_inst_glob_param_2;
                else if (!std::strcmp(name, "global_regs_inst__glob_param_3")) return root->ao486__DOT___global_regs_inst_glob_param_3;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__fetch_valid")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__fetch_valid;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__consume_count")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__consume_count;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__consume_count_local")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__consume_count_local;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__consume_one")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__consume_one;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__consume_one_one")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__consume_one_one;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__consume_call_jmp_imm")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__consume_call_jmp_imm;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decoder_count")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decoder_count;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__dec_ready_one_one")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__dec_ready_one_one;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__dec_ready_call_jmp_imm")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__dec_ready_call_jmp_imm;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__dec_cmd")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__dec_cmd;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__dec_cmdex")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__dec_cmdex;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__dec_exception_ud")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__dec_exception_ud;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_ready_inst__decoder_count")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_ready_inst__DOT__decoder_count;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_ready_inst__consume_count_local")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_ready_inst__DOT__consume_count_local;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_ready_inst__consume_one")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_ready_inst__DOT__consume_one;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_ready_inst__consume_one_one")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_ready_inst__DOT__consume_one_one;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_ready_inst__consume_call_jmp_imm")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_ready_inst__DOT__consume_call_jmp_imm;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_ready_inst__dec_ready_one_one")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_ready_inst__DOT__dec_ready_one_one;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_ready_inst__dec_ready_call_jmp_imm")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_ready_inst__DOT__dec_ready_call_jmp_imm;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_ready_inst__call_jmp_imm_len")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_ready_inst__DOT__call_jmp_imm_len;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_regs_inst__decoder_count")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_regs_inst__DOT__decoder_count;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decode_regs_inst__after_consume_count")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decode_regs_inst__DOT__after_consume_count;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decoder_w0")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decoder[0];
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decoder_w1")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decoder[1];
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decoder_w2")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decoder[2];
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__micro_busy")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__micro_busy;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__eip")) return root->ao486__DOT___pipeline_inst_dec_eip;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__rd_cmd")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__rd_cmd;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__rd_cmdex")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__rd_cmdex;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__rd_eip")) return root->ao486__DOT___pipeline_inst_rd_eip;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__rd_busy")) return root->ao486__DOT__pipeline_inst__DOT___read_inst_rd_busy;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__rd_ready")) return root->ao486__DOT__pipeline_inst__DOT___read_inst_rd_ready;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__read_address")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__read_address;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__read_commands_inst__read_4")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__read_commands_inst__DOT__read_4;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__read_commands_inst__rd_glob_param_1_value")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__read_commands_inst__DOT__rd_glob_param_1_value;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__read_commands_inst__rd_glob_param_2_value")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__read_commands_inst__DOT__rd_glob_param_2_value;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__read_commands_inst__rd_glob_param_3_value")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__read_commands_inst__DOT__rd_glob_param_3_value;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__read_commands_inst__address_stack_save")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__read_commands_inst__DOT__address_stack_save;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__read_commands_inst__address_stack_pop_next")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__read_commands_inst__DOT__address_stack_pop_next;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__read_commands_inst__address_stack_for_iret_to_v86")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__read_commands_inst__DOT__address_stack_for_iret_to_v86;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_do")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_do;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_length")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_length;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_address")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_address;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_data")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_data;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__acflag")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__acflag;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__wr_string_es_fault")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__wr_string_es_fault;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__wr_cmd")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__wr_cmd;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__wr_cmdex")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__wr_cmdex;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__acflag")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__acflag;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__acflag_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__acflag_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_rmw_virtual")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_rmw_virtual;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_virtual")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_virtual;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_rmw_system_dword")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_rmw_system_dword;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_system_word")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_system_word;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_system_dword")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_system_dword;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_system_busy_tss")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_system_busy_tss;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_system_touch")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_system_touch;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_string_es_virtual")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_string_es_virtual;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_seg_cache")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_seg_cache;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_seg_cache_valid")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_seg_cache_valid;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__cs_cache_valid_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__cs_cache_valid_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__ss_cache_valid_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__ss_cache_valid_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__glob_param_1")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__glob_param_1;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__glob_param_2")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__glob_param_2;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__glob_param_3")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__glob_param_3;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__wr_glob_param_1_value")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__wr_glob_param_1_value;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__wr_glob_param_3_value")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__wr_glob_param_3_value;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__write_seg_cache")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__write_seg_cache;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__write_seg_cache_valid")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__write_seg_cache_valid;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__cs_cache_valid_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__cs_cache_valid_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ss_cache_valid_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ss_cache_valid_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__cs_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__cs_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__ss_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__ss_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__cs_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__cs_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ss_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ss_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__esp_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__esp_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__ebp_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__ebp_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__eip")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__eip;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__esp_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__esp_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ebp_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ebp_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__write_stack_virtual")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__write_stack_virtual;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__wr_stack_esp")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__wr_stack_esp;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_string_inst__wr_string_es_linear")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_string_inst__DOT__wr_string_es_linear;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_string_inst__es_cache_valid")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_string_inst__DOT__es_cache_valid;
                else if (!std::strcmp(name, "pipeline_inst__fetch_inst__fetch_limit")) return root->ao486__DOT__pipeline_inst__DOT__fetch_inst__DOT__fetch_limit;
                else if (!std::strcmp(name, "pipeline_inst__fetch_inst__fetch_page_fault")) return root->ao486__DOT__pipeline_inst__DOT__fetch_inst__DOT__fetch_page_fault;
                else if (!std::strcmp(name, "pipeline_inst__fetch_inst__prefetchfifo_accept_do")) return root->ao486__DOT__pipeline_inst__DOT__fetch_inst__DOT__prefetchfifo_accept_do;
                else if (!std::strcmp(name, "pipeline_inst__execute_inst__exe_eip")) return root->ao486__DOT__pipeline_inst__DOT___execute_inst_exe_eip_final;
                else if (!std::strcmp(name, "memory_inst__prefetch_inst__prefetch_address")) return root->ao486__DOT__memory_inst__DOT__prefetch_inst__DOT__prefetch_address;
                else if (!std::strcmp(name, "memory_inst__prefetch_inst__prefetch_length")) return root->ao486__DOT__memory_inst__DOT__prefetch_inst__DOT__prefetch_length;
                else if (!std::strcmp(name, "memory_inst__prefetch_inst__delivered_eip")) return root->ao486__DOT__memory_inst__DOT__prefetch_inst__DOT__delivered_eip;
                else if (!std::strcmp(name, "memory_inst__prefetch_control_inst__prefetchfifo_used")) return root->ao486__DOT__memory_inst__DOT__prefetch_control_inst__DOT__prefetchfifo_used;
                else if (!std::strcmp(name, "memory_inst__prefetch_control_inst__state")) return root->ao486__DOT__memory_inst__DOT__prefetch_control_inst__DOT__state;
                else if (!std::strcmp(name, "memory_inst__avalon_mem_inst__state")) return root->ao486__DOT__memory_inst__DOT__avalon_mem_inst__DOT__state;
                else if (!std::strcmp(name, "memory_inst__prefetch_control_inst__tlbcoderequest_do")) return root->ao486__DOT__memory_inst__DOT__prefetch_control_inst__DOT__tlbcoderequest_do;
                else if (!std::strcmp(name, "memory_inst__prefetch_control_inst__icacheread_do")) return root->ao486__DOT__memory_inst__DOT__prefetch_control_inst__DOT__icacheread_do;
                else if (!std::strcmp(name, "memory_inst__prefetch_control_inst__icacheread_address")) return root->ao486__DOT__memory_inst__DOT__prefetch_control_inst__DOT__icacheread_address;
                else if (!std::strcmp(name, "memory_inst__prefetch_control_inst__icacheread_length")) return root->ao486__DOT__memory_inst__DOT__prefetch_control_inst__DOT__icacheread_length;
                else if (!std::strcmp(name, "memory_inst__prefetch_fifo_inst__prefetchfifo_used")) return root->ao486__DOT__memory_inst__DOT__prefetch_fifo_inst__DOT__prefetchfifo_used;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__write_do")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__write_do;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__write_done")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__write_done;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__write_length")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__write_length;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__write_address")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__write_address;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__write_data")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__write_data;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__ac_fault")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__ac_fault;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__tlbwrite_do")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__tlbwrite_do;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__tlbwrite_length")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__tlbwrite_length;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__tlbwrite_address")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__tlbwrite_address;
                else if (!std::strcmp(name, "memory_inst__memory_write_inst__tlbwrite_data")) return root->ao486__DOT__memory_inst__DOT__memory_write_inst__DOT__tlbwrite_data;
                else if (!std::strcmp(name, "memory_inst__memory_read_inst__read_ac_fault")) return root->ao486__DOT__memory_inst__DOT__memory_read_inst__DOT__read_ac_fault;
                else if (!std::strcmp(name, "memory_inst__read_ac_fault")) return root->ao486__DOT___memory_inst_read_ac_fault;
                else if (!std::strcmp(name, "memory_inst__write_ac_fault")) return root->ao486__DOT___memory_inst_write_ac_fault;
                else if (!std::strcmp(name, "memory_inst__icache_inst__readcode_do")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__readcode_do;
                else if (!std::strcmp(name, "memory_inst__icache_inst__readcode_address")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__readcode_address;
                else if (!std::strcmp(name, "memory_inst__icache_inst__prefetched_do")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__prefetched_do;
                else if (!std::strcmp(name, "memory_inst__icache_inst__prefetched_length")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__prefetched_length;
                else if (!std::strcmp(name, "memory_inst__icache_inst__reset_prefetch")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__reset_prefetch;
                else if (!std::strcmp(name, "memory_inst__icache_inst__prefetchfifo_write_do")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__prefetchfifo_write_do;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__state")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__state;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__fillcount")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__fillcount;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__cache_mux")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__cache_mux;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__memory_addr_a")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__memory_addr_a;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__read_addr")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__read_addr;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__CPU_VALID")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__CPU_VALID;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__CPU_DONE")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__CPU_DONE;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__MEM_REQ")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__MEM_REQ;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__MEM_ADDR")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__MEM_ADDR;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__tags_dirty_out")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__tags_dirty_out;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__LRU_addr")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__LRU_addr;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__LRU_out_0")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__LRU_out[0];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__LRU_out_1")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__LRU_out[1];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__LRU_out_2")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__LRU_out[2];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__LRU_out_3")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__LRU_out[3];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__tags_read_0")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__tags_read[0];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__tags_read_1")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__tags_read[1];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__tags_read_2")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__tags_read[2];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__tags_read_3")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__tags_read[3];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__readdata_cache_0")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__readdata_cache[0];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__readdata_cache_1")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__readdata_cache[1];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__readdata_cache_2")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__readdata_cache[2];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__readdata_cache_3")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__readdata_cache[3];
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__ram0_q_b")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__gcache__BRA__0__KET____DOT__ram__DOT__q_b;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__ram1_q_b")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__gcache__BRA__1__KET____DOT__ram__DOT__q_b;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__ram2_q_b")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__gcache__BRA__2__KET____DOT__ram__DOT__q_b;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__ram3_q_b")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__gcache__BRA__3__KET____DOT__ram__DOT__q_b;
                else if (!std::strcmp(name, "memory_inst__icache_inst__l1_icache_inst__ram0_address_b_reg_clock0")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__l1_icache_inst__DOT__gcache__BRA__0__KET____DOT__ram__DOT__address_b_reg_clock0;
                else if (!std::strcmp(name, "memory_inst__avalon_mem_inst__readcode_do")) return root->ao486__DOT__memory_inst__DOT__avalon_mem_inst__DOT__readcode_do;
                else if (!std::strcmp(name, "memory_inst__avalon_mem_inst__readcode_address")) return root->ao486__DOT__memory_inst__DOT__avalon_mem_inst__DOT__readcode_address;
                else if (!std::strcmp(name, "memory_inst__avalon_mem_inst__readcode_done")) return root->ao486__DOT__memory_inst__DOT__avalon_mem_inst__DOT__readcode_done;
                else if (!std::strcmp(name, "memory_inst__prefetch_inst__prefetchfifo_signal_limit_do")) return root->ao486__DOT__memory_inst__DOT__prefetch_inst__DOT__prefetchfifo_signal_limit_do;
                else if (!std::strcmp(name, "memory_inst__tlb_inst__prefetchfifo_signal_pf_do")) return root->ao486__DOT__memory_inst__DOT__tlb_inst__DOT__prefetchfifo_signal_pf_do;
                else if (!std::strcmp(name, "memory_inst__acflag")) return root->ao486__DOT__memory_inst__DOT__acflag;
                else if (!std::strcmp(name, "memory_inst__tlb_inst__acflag")) return root->ao486__DOT__memory_inst__DOT__tlb_inst__DOT__acflag;
                else if (!std::strcmp(name, "memory_inst__tlb_inst__tlbread_ac_fault")) return root->ao486__DOT__memory_inst__DOT__tlb_inst__DOT__tlbread_ac_fault;
                else if (!std::strcmp(name, "memory_inst__tlb_inst__tlbwrite_ac_fault")) return root->ao486__DOT__memory_inst__DOT__tlb_inst__DOT__tlbwrite_ac_fault;
                else if (!std::strcmp(name, "exception_inst__exc_vector")) return root->ao486__DOT___exception_inst_exc_vector;
                else if (!std::strcmp(name, "exception_inst__exc_eip")) return root->ao486__DOT___exception_inst_exc_eip;
                return 0;
              }

              uint64_t sim_peek_u64(void* sim, const char* name) {
                auto* ctx = static_cast<SimContext*>(sim);
                if (!ctx || !ctx->dut || !name) return 0;
                auto* root = ctx->dut->rootp;
                if (!std::strcmp(name, "trace_cs_cache")) return ctx->dut->trace_cs_cache;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__cs_cache")) return ctx->dut->trace_cs_cache;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__fetch")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__fetch;
                else if (!std::strcmp(name, "pipeline_inst__fetch_inst__fetch")) return root->ao486__DOT__pipeline_inst__DOT__fetch_inst__DOT__fetch;
                else if (!std::strcmp(name, "trace_fetch_bytes")) return ctx->dut->trace_fetch_bytes;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__ds_cache")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__ds_cache;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__ss_cache")) return root->ao486__DOT__pipeline_inst__DOT__read_inst__DOT__ss_cache;
                else if (!std::strcmp(name, "pipeline_inst__execute_inst__zflag")) return root->ao486__DOT__pipeline_inst__DOT__execute_inst__DOT__zflag;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__es_cache")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__es_cache;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__ds_cache")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__ds_cache;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__zflag")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__zflag;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__cs_cache_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__cs_cache_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__ds_cache_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__ds_cache_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__ss_cache_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__ss_cache_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__cs_cache")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__cs_cache;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__acflag")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__acflag;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__eax")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__eax;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ebx")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ebx;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ecx")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ecx;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__edx")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__edx;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ds_cache")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ds_cache;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ss_cache")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ss_cache;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__zflag")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__zflag;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__cs_cache_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__cs_cache_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__acflag_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__acflag_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ds_cache_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ds_cache_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ss_cache_to_reg")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ss_cache_to_reg;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__wr_seg_cache_mask")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__wr_seg_cache_mask;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__es_cache")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT___write_register_inst_es_cache;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__ebp")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__ebp;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__exe_buffer")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__exe_buffer;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__exe_buffer_shifted_w0")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__exe_buffer_shifted[0];
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__exe_buffer_shifted_w1")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__exe_buffer_shifted[1];
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__exe_buffer_shifted_w2")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__exe_buffer_shifted[2];
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_commands_inst__exe_buffer_shifted_w3")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_commands_inst__DOT__exe_buffer_shifted[3];
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_register_inst__ebp")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_register_inst__DOT__ebp;
                else if (!std::strcmp(name, "pipeline_inst__write_inst__write_string_inst__es_cache")) return root->ao486__DOT__pipeline_inst__DOT__write_inst__DOT__write_string_inst__DOT__es_cache;
                else if (!std::strcmp(name, "memory_inst__icache_inst__prefetchfifo_write_data")) return root->ao486__DOT__memory_inst__DOT__icache_inst__DOT__prefetchfifo_write_data;
                else if (!std::strcmp(name, "pipeline_inst__fetch_inst__prefetchfifo_accept_data")) {
                  return static_cast<uint64_t>(root->ao486__DOT__pipeline_inst__DOT__fetch_inst__DOT__prefetchfifo_accept_data[0])
                    | (static_cast<uint64_t>(root->ao486__DOT__pipeline_inst__DOT__fetch_inst__DOT__prefetchfifo_accept_data[1]) << 32);
                }
                else if (!std::strcmp(name, "pipeline_inst__fetch_inst__prefetchfifo_accept_tag")) {
                  return static_cast<uint64_t>(root->ao486__DOT__pipeline_inst__DOT__fetch_inst__DOT__prefetchfifo_accept_data[2]) & 0xF;
                }
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decoder_lo")) {
                  return static_cast<uint64_t>(root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decoder[0])
                    | (static_cast<uint64_t>(root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__decoder[1]) << 32);
                }
                return static_cast<uint64_t>(sim_peek_u32(sim, name));
              }

              }
            CPP
          end
        end

        def self.build_from_cleaned_mlir(mlir_text, work_dir:, threads: 1)
          new(headless: true, threads: threads).tap do |runner|
            runner.send(:build_imported_parity!, mlir_text, work_dir: work_dir)
          end
        end

        def initialize(threads: 1, **kwargs)
          @threads = RHDL::Codegen::Verilog::VerilogSimulator.normalize_threads(threads)
          super(runner_backend: :verilator, **kwargs)
          @work_dir = nil
          @binary_path = nil


        end

        def simulator_type
          :ao486_verilator
        end

        def run(cycles: nil, speed: nil, headless: @headless, max_cycles: nil)
          super
        end

        def ensure_sim!
          return @sim if @sim

          bundle = self.class.runtime_bundle(threads: @threads)
          @sim = SimBridge.new(bundle.fetch(:library_path))
          sync_loaded_artifacts_to_sim!
          sync_runtime_windows!
          @runtime_loaded = true
          @sim
        end

        private

        class SimBridge
          BIOS_TICKS_PER_DAY = 0x0018_00B0
          DMA_FDC_CHANNEL = 2
          DEFAULT_FLOPPY_GEOMETRY = {
            bytes_per_sector: 512,
            sectors_per_track: 18,
            heads: 2,
            cylinders: 80,
            drive_type: 4
          }.freeze
          GENERIC_DOS_STAGE_CHS_HELPER_OFFSET = 0x0332
          GENERIC_DOS_STAGE_CHS_HELPER_ORIGINAL = [
            0x2E, 0x8B, 0x16, 0x8D, 0x00, 0x50, 0x8B, 0xC2,
            0x33, 0xD2, 0x2E, 0xF7, 0x36, 0x85, 0x00, 0x2E,
            0xA3, 0x8D, 0x00, 0x58, 0x2E, 0xF7, 0x36, 0x85,
            0x00, 0x8A, 0xF2, 0xB1, 0x06, 0xD2, 0xE4, 0x0A,
            0xE3, 0x8A, 0xE8, 0x8A, 0xCC, 0x8B, 0xDF, 0x2E,
            0x8A, 0x16, 0xAD, 0x00, 0x8B, 0xC6, 0xB4, 0x02
          ].freeze
          GENERIC_DOS_STAGE_CHS_HELPER_PATCH = (
            [
              0x31, 0xD2,
              0x2E, 0xF7, 0x36, 0x85, 0x00,
              0x8A, 0xF2,
              0x88, 0xC5,
              0x88, 0xD9,
              0x8B, 0xDF,
              0x2E, 0x8A, 0x16, 0xAD, 0x00,
              0x8B, 0xC6,
              0xB4, 0x02
            ] + Array.new(GENERIC_DOS_STAGE_CHS_HELPER_ORIGINAL.length - 24, 0x90)
          ).freeze
          DOS_INT2F_VECTOR = 0x2F
          DOS_INT2F_WRAPPER_SEGMENT = 0x7000
          DOS_INT2F_WRAPPER_OFFSET = 0x0000
          DOS_INT2F_BOOTSTRAP_DOS_SEGMENT = 0x0070
          DOS_INT2F_BOOTSTRAP_DOS_OFFSET = 0x1CAF
          DOS_INT2F_LATE_FALLBACK_AFTER_CYCLES = 4_500_000
          DOS_INT2F_LATE_FALLBACK_AFTER_LBA = 226
          DOS_INT2F_LATE_FALLBACK_AX = [
            0x1902, 0x1123, 0x1116, 0xAE00, 0x1119, 0x122E, 0x1125
          ].freeze
          DOS_INT12_WRAPPER_SEGMENT = 0x0070
          DOS_INT12_WRAPPER_OFFSET = 0x03CD
          DOS_INT12_WRAPPER_SAVED_VECTOR_OFFSET = DOS_INT12_WRAPPER_OFFSET - 4
          DOS_INT12_BIOS_SEGMENT = 0xF000
          DOS_INT12_BIOS_OFFSET = 0xF841
          DOS_INT13_RESULT_PORTS = {
            0x0EDC => [:dos_int13_result_ax, 0],
            0x0EDD => [:dos_int13_result_ax, 8],
            0x0F10 => [:dos_int13_result_bx, 0],
            0x0F11 => [:dos_int13_result_bx, 8],
            0x0F12 => [:dos_int13_result_cx, 0],
            0x0F13 => [:dos_int13_result_cx, 8],
            0x0F14 => [:dos_int13_result_dx, 0],
            0x0F15 => [:dos_int13_result_dx, 8]
          }.freeze
          DOS_INT10_RESULT_PORTS = {
            0x0EEA => [:dos_int10_result_ax, 0],
            0x0EEB => [:dos_int10_result_ax, 8],
            0x0EEC => [:dos_int10_result_bx, 0],
            0x0EED => [:dos_int10_result_bx, 8],
            0x0EEE => [:dos_int10_result_cx, 0],
            0x0EEF => [:dos_int10_result_cx, 8],
            0x0EF0 => [:dos_int10_result_dx, 0],
            0x0EF1 => [:dos_int10_result_dx, 8]
          }.freeze
          DOS_INT16_RESULT_PORTS = {
            0x0EFC => [:dos_int16_result_ax, 0],
            0x0EFD => [:dos_int16_result_ax, 8]
          }.freeze
          DOS_INT1A_RESULT_PORTS = {
            0x0F08 => [:dos_int1a_result_ax, 0],
            0x0F09 => [:dos_int1a_result_ax, 8],
            0x0F0A => [:dos_int1a_result_cx, 0],
            0x0F0B => [:dos_int1a_result_cx, 8],
            0x0F0C => [:dos_int1a_result_dx, 0],
            0x0F0D => [:dos_int1a_result_dx, 8]
          }.freeze
          WIDE_SIGNAL_NAMES = %w[
            trace_cs_cache
            pipeline_inst__decode_inst__cs_cache
            pipeline_inst__decode_inst__decoder_lo
            pipeline_inst__decode_inst__fetch
            pipeline_inst__fetch_inst__fetch
            trace_fetch_bytes
            memory_inst__icache_inst__prefetchfifo_write_data
            pipeline_inst__fetch_inst__prefetchfifo_accept_data
            pipeline_inst__read_inst__ds_cache
            pipeline_inst__read_inst__ss_cache
            pipeline_inst__execute_inst__zflag
            pipeline_inst__write_inst__ds_cache
            pipeline_inst__write_inst__es_cache
            pipeline_inst__write_inst__zflag
            pipeline_inst__write_inst__write_register_inst__es_cache
            pipeline_inst__write_inst__write_string_inst__es_cache
            pipeline_inst__write_inst__write_commands_inst__cs_cache_to_reg
            pipeline_inst__write_inst__write_commands_inst__ds_cache_to_reg
            pipeline_inst__write_inst__write_commands_inst__ss_cache_to_reg
            pipeline_inst__write_inst__write_register_inst__cs_cache
            pipeline_inst__write_inst__write_register_inst__eax
            pipeline_inst__write_inst__write_register_inst__ebx
            pipeline_inst__write_inst__write_register_inst__ecx
            pipeline_inst__write_inst__write_register_inst__edx
            pipeline_inst__write_inst__write_register_inst__ds_cache
            pipeline_inst__write_inst__write_register_inst__ss_cache
            pipeline_inst__write_inst__write_register_inst__zflag
            pipeline_inst__write_inst__write_register_inst__cs_cache_to_reg
            pipeline_inst__write_inst__write_register_inst__ds_cache_to_reg
            pipeline_inst__write_inst__write_register_inst__ss_cache_to_reg
            pipeline_inst__write_inst__write_register_inst__wr_seg_cache_mask
          ].freeze

          ReadBurst = Struct.new(:base, :beat_index, :beats_total, :started, keyword_init: true)

          def initialize(library_path)
            @lib = self.class.load_shared_library(library_path)
            @sim_create = Fiddle::Function.new(@lib['sim_create'], [], Fiddle::TYPE_VOIDP)
            @sim_destroy = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_eval = Fiddle::Function.new(@lib['sim_eval'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_poke = Fiddle::Function.new(@lib['sim_poke'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT], Fiddle::TYPE_VOID)
            @sim_peek_u32 = Fiddle::Function.new(@lib['sim_peek_u32'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_UINT)
            @sim_peek_u64 = Fiddle::Function.new(@lib['sim_peek_u64'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG_LONG)
            @ctx = @sim_create.call
            @memory = Hash.new(0)
            @rom = {}
            @disk_drives = Hash.new { |hash, key| hash[key] = {} }
            @hdd_store = Hash.new(0)
            @hdd_geometry = nil
            @floppy_geometries = Hash.new { |hash, key| hash[key] = DEFAULT_FLOPPY_GEOMETRY.dup }
            set_floppy_geometry(0, DEFAULT_FLOPPY_GEOMETRY)
            reset_host_state!
          end

          def floppy_geometry=(geometry)
            set_floppy_geometry(0, geometry)
          end

          def runner_load_hdd(data, offset = 0)
            load_store!(@hdd_store, data, offset)
          end

          def set_hdd_geometry(geometry)
            @hdd_geometry = geometry&.dup
          end

          def set_floppy_geometry(drive, geometry)
            drive_index = drive.to_i & 0x01
            config = DEFAULT_FLOPPY_GEOMETRY.merge(geometry || {})
            @floppy_geometries[drive_index] = config
            return unless @cmos

            if drive_index.zero?
              @cmos[0x10] = (@cmos[0x10] & 0x0F) | ((config.fetch(:drive_type).to_i & 0x0F) << 4)
            else
              @cmos[0x10] = (@cmos[0x10] & 0xF0) | (config.fetch(:drive_type).to_i & 0x0F)
            end
          end

          def self.load_shared_library(library_path)
            sign_darwin_shared_library(library_path)
            Fiddle.dlopen(library_path)
          rescue Fiddle::DLError
            raise unless RbConfig::CONFIG['host_os'] =~ /darwin/

            sign_darwin_shared_library(library_path)
            sleep 0.1
            Fiddle.dlopen(library_path)
          end

          def self.sign_darwin_shared_library(library_path)
            return unless RbConfig::CONFIG['host_os'] =~ /darwin/
            return unless File.exist?(library_path)
            return unless system('which', 'codesign', out: File::NULL, err: File::NULL)

            system('codesign', '--force', '--sign', '-', '--timestamp=none', library_path, out: File::NULL, err: File::NULL)
          end

          def reset
            @sim_destroy.call(@ctx) if @ctx
            @ctx = @sim_create.call
            reset_host_state!
          end

          def poke(name, value)
            @sim_poke.call(@ctx, Fiddle::Pointer[name.to_s], value.to_i & 0xFFFF_FFFF)
          end

          def evaluate
            @sim_eval.call(@ctx)
          end

          def peek(name)
            signal_name = name.to_s
            if WIDE_SIGNAL_NAMES.include?(signal_name)
              @sim_peek_u64.call(@ctx, Fiddle::Pointer[signal_name])
            else
              @sim_peek_u32.call(@ctx, Fiddle::Pointer[signal_name])
            end
          end

          def runner_load_memory(data, offset = 0, _mapped = false)
            load_store!(@memory, data, offset)
          end

          def runner_load_rom(data, offset = 0)
            load_store!(@rom, data, offset)
          end

          def runner_load_disk(data, offset = 0)
            runner_load_disk_for_drive(data, 0, offset)
          end

          def runner_load_disk_for_drive(data, drive, offset = 0)
            load_store!(disk_store_for_drive(drive), data, offset)
          end

          def runner_replace_disk(data)
            drive_store = disk_store_for_drive(0)
            drive_store.clear
            load_store!(drive_store, data, 0)
          end

          def runner_read_disk(offset, length, drive = 0)
            read_store(disk_store_for_drive(drive), offset, length, mapped: false)
          end

          def runner_read_memory(offset, length, mapped: true)
            read_store(@memory, offset, length, mapped: mapped)
          end

          def runner_write_memory(offset, data, mapped: true)
            bytes = data.is_a?(String) ? data.bytes : Array(data)
            bytes.each_with_index do |byte, idx|
              addr = offset + idx
              next if mapped && @rom.key?(addr)

              @memory[addr] = byte.to_i & 0xFF
            end
            bytes.length
          end

          def runner_run_cycles(n, key_data = 0, key_ready = false)
            @text_dirty = false
            key_cleared = key_ready ? enqueue_keyboard_byte(key_data.to_i & 0xFF) : false

            n.times do
              committed_writes = {}
              reset_active = @reset_cycles_remaining.positive?
              irq_vector = reset_active ? nil : active_irq_vector
              @last_irq_vector = irq_vector if irq_vector
              read_response = if !reset_active && @pending_read_burst&.started && read_burst_consumer_active?
                addr = @pending_read_burst.base + (@pending_read_burst.beat_index * 4)
                little_endian_word(addr)
              end
              io_read_response = reset_active ? nil : @pending_io_read_data.tap { @pending_io_read_data = nil }
              io_write_done = if reset_active
                false
              else
                @pending_io_write_ack.tap { @pending_io_write_ack = false }
              end

              apply_default_inputs(reset_active, irq_vector)
              unless read_response.nil?
                poke('avm_readdatavalid', 1)
                poke('avm_readdata', read_response)
              end
              unless io_read_response.nil?
                poke('io_read_data', io_read_response)
                poke('io_read_done', 1)
              end
              poke('io_write_done', 1) if io_write_done

              evaluate
              commit_memory_write_if_needed(committed_writes) unless reset_active
              retargeted = retarget_code_burst_if_needed
              if retargeted
                poke('avm_readdatavalid', 0)
                poke('avm_readdata', 0)
                evaluate
                commit_memory_write_if_needed(committed_writes) unless reset_active
              end

              current_io_read_do = !reset_active && peek('io_read_do') != 0
              current_io_write_do = !reset_active && peek('io_write_do') != 0

              unless reset_active
                arm_read_burst_if_needed
                queue_follow_on_code_burst_if_needed
                drop_stale_unstarted_code_burst_if_needed
                queue_io_requests_if_needed(current_io_read_do, current_io_write_do)
              end

              poke('clk', 1)
              evaluate
              record_pc_history unless reset_active

              unless reset_active
                commit_memory_write_if_needed(committed_writes)
                maybe_repair_generic_dos_stage_vars
                maybe_repair_dos_int12_wrapper_chain
                maybe_install_late_dos_int2f_fallback
                handle_interrupt_ack
                maybe_seed_post_init_ivt
                advance_timers
              end
              advance_read_burst(retargeted ? false : !read_response.nil?)
              @reset_cycles_remaining = [@reset_cycles_remaining - 1, 0].max
              @host_cycles_total += 1
              @prev_io_read_do = current_io_read_do
              @prev_io_write_do = current_io_write_do
            end

            {
              cycles_run: n,
              key_cleared: key_cleared,
              text_dirty: @text_dirty,
              speaker_toggles: 0
            }
          end

          def runner_ao486_last_io_read
            @last_io_read_meta
          end

          def runner_ao486_last_io_write
            @last_io_write_meta
          end

          def runner_ao486_last_irq_vector
            @last_irq_vector
          end

          def runner_ao486_pc_history
            @pc_history.map(&:dup)
          end

          def runner_ao486_dos_int13_state
            {
              ax: @dos_int13_ax,
              bx: @dos_int13_bx,
              cx: @dos_int13_cx,
              dx: @dos_int13_dx,
              es: @dos_int13_es,
              result_ax: @dos_int13_result_ax,
              result_bx: @dos_int13_result_bx,
              result_cx: @dos_int13_result_cx,
              result_dx: @dos_int13_result_dx,
              flags: @dos_int13_result_flags
            }
          end

          def runner_ao486_dos_int13_history
            @dos_int13_history.map(&:dup)
          end

          def runner_ao486_dos_int10_state
            {
              ax: @dos_int10_ax,
              result_ax: @dos_int10_result_ax
            }
          end

          def runner_ao486_dos_int16_state
            {
              ax: @dos_int16_ax,
              result_ax: @dos_int16_result_ax,
              flags: @dos_int16_result_flags
            }
          end

          def runner_ao486_dos_int1a_state
            {
              ax: @dos_int1a_ax,
              cx: @dos_int1a_cx,
              dx: @dos_int1a_dx,
              result_ax: @dos_int1a_result_ax,
              result_cx: @dos_int1a_result_cx,
              result_dx: @dos_int1a_result_dx,
              flags: @dos_int1a_result_flags
            }
          end

          def serial_output
            @serial_output.dup
          end

        def reset_host_state!
            @cmos = default_cmos
            @pic_master_mask = 0xFF
            @pic_slave_mask = 0xFF
            @pic_master_pending = 0
            @pic_master_in_service = 0
            @pic_master_base = 0x08
            @pit_reload = 0
            @pit_counter = 0
            @pit_access_mode = :lohi
            @pit_next_write_low = true
            @pit_pending_low_byte = 0
            @dma_flip_flop_low = true
            @dma_ch2_base_addr = 0
            @dma_ch2_current_addr = 0
            @dma_ch2_base_count = 0
            @dma_ch2_current_count = 0
            @dma_ch2_page = 0
            @dma_ch2_mode = 0
            @dma_ch2_masked = true
            @fdc_dor = 0
            @fdc_data_rate = 0
            @fdc_current_cylinder = 0
            @fdc_last_st0 = 0x80
            @fdc_last_pcn = 0
            @fdc_command = []
            @fdc_expected_len = 0
            @fdc_result = []
            @pending_read_burst = nil
            @queued_code_bursts = []
            @pending_io_read_data = nil
            @pending_io_write_ack = false
            @post_init_ivt_seeded = false
            @dos_int13_ax = @dos_int13_bx = @dos_int13_cx = @dos_int13_dx = @dos_int13_es = 0
            @dos_int13_result_ax = @dos_int13_result_bx = @dos_int13_result_cx = @dos_int13_result_dx = 0
            @dos_int13_result_flags = 0
            @dos_int13_history = []
            @dos_int10_ax = @dos_int10_bx = @dos_int10_cx = @dos_int10_dx = @dos_int10_bp = @dos_int10_es = 0
            @dos_int10_result_ax = @dos_int10_result_bx = @dos_int10_result_cx = @dos_int10_result_dx = 0
            @dos_int16_ax = @dos_int16_result_ax = @dos_int16_result_flags = 0
            @dos_int1a_ax = @dos_int1a_cx = @dos_int1a_dx = 0
            @dos_int1a_result_ax = @dos_int1a_result_cx = @dos_int1a_result_dx = @dos_int1a_result_flags = 0
            @generic_dos_stage_vars_repaired = false
            @generic_dos_stage_bases = [0x0700]
            @keyboard_queue = []
            @keyboard_scan_queue = []
            @serial_output = +''
            @text_dirty = false
            @prev_io_read_do = false
            @prev_io_write_do = false
            @last_io_read_meta = nil
            @last_io_write_meta = nil
            @last_irq_vector = nil
            @pc_history = []
            @host_cycles_total = 0
            @dos_int2f_wrapper_installed = false
            write_bios_tick_count(0)
            @memory[0x0470] = 0
            @reset_cycles_remaining = 1
          end

          def load_store!(store, data, offset)
            bytes = data.is_a?(String) ? data.bytes : Array(data)
            bytes.each_with_index { |byte, idx| store[offset + idx] = byte.to_i & 0xFF }
            true
          end

          def read_store(store, offset, length, mapped:)
            Array.new(length) do |idx|
              addr = offset + idx
              if mapped && @rom.key?(addr)
                @rom[addr]
              else
                store.fetch(addr, 0)
              end
            end
          end

          def apply_default_inputs(reset_active, irq_vector)
            poke('clk', 0)
            poke('rst_n', reset_active ? 0 : 1)
            poke('a20_enable', 1)
            poke('cache_disable', 1)
            poke('interrupt_do', irq_vector ? 1 : 0)
            poke('interrupt_vector', irq_vector || 0)
            poke('avm_waitrequest', 0)
            poke('avm_readdatavalid', 0)
            poke('avm_readdata', 0)
            poke('dma_address', 0)
            poke('dma_16bit', 0)
            poke('dma_write', 0)
            poke('dma_writedata', 0)
            poke('dma_read', 0)
            poke('io_read_data', 0)
            poke('io_read_done', 0)
            poke('io_write_done', 0)
          end

          def commit_memory_write_if_needed(committed_writes = nil)
            return if peek('avm_write').zero?

            addr = peek('avm_address') << 2
            data = peek('avm_writedata') & 0xFFFF_FFFF
            byteenable = peek('avm_byteenable') & 0xF
            if committed_writes
              signature = [addr, data, byteenable]
              return if committed_writes.key?(signature)

              committed_writes[signature] = true
            end
            4.times do |index|
              next if ((byteenable >> index) & 1).zero?

              byte_val = (data >> (index * 8)) & 0xFF
              byte_addr = addr + index
              @memory[byte_addr] = byte_val
            end
          end

          def arm_read_burst_if_needed
            return if @pending_read_burst || peek('avm_read').zero?

            is_code_read = current_avm_read_is_code_burst?
            beats_total = is_code_read ? 8 : [peek('avm_burstcount'), 1].max
            base = if is_code_read
              peek('avm_address') << 2
            else
              peek('avm_address') << 2
            end
            @pending_read_burst = ReadBurst.new(base: base, beat_index: 0, beats_total: beats_total, started: true)
          end

          def queue_follow_on_code_burst_if_needed
            return unless @pending_read_burst
            return unless @pending_read_burst.beats_total == 8
            return if peek('memory_inst__avalon_mem_inst__readcode_do').zero?

            target = peek('memory_inst__avalon_mem_inst__readcode_address') & ~0x3
            return if target == @pending_read_burst.base
            return if @queued_code_bursts.any? { |burst| burst.base == target }

            @queued_code_bursts << ReadBurst.new(base: target, beat_index: 0, beats_total: 8, started: false)
          end

          def drop_stale_unstarted_code_burst_if_needed
            return unless @pending_read_burst
            return unless @pending_read_burst.beats_total == 8
            return if @pending_read_burst.started

            linear_pc = current_linear_code_pointer
            return unless linear_pc
            return if code_burst_relevant_to_linear?(@pending_read_burst.base, linear_pc)

            replacement = @queued_code_bursts.find { |burst| code_burst_relevant_to_linear?(burst.base, linear_pc) }
            @queued_code_bursts.delete(replacement) if replacement
            @pending_read_burst = replacement
          end

          def retarget_code_burst_if_needed
            return false unless current_avm_read_is_code_burst?
            return false unless @pending_read_burst
            return false if @pending_read_burst.beats_total != 8 || @pending_read_burst.started

            target = peek('avm_address') << 2
            return false if @pending_read_burst.base == target

            @pending_read_burst.base = target
            @pending_read_burst.beat_index = 0
            @pending_read_burst.started = false
            true
          end

          def advance_read_burst(delivered)
            return unless @pending_read_burst

            if delivered
              @pending_read_burst.beat_index += 1
              if @pending_read_burst.beat_index >= @pending_read_burst.beats_total
                @pending_read_burst = @queued_code_bursts.shift
              end
            else
              @pending_read_burst.started = true
            end
          end

          def current_avm_read_is_code_burst?
            peek('avm_read') != 0 &&
              peek('avm_burstcount') >= 8
          end

          def read_burst_consumer_active?
            return true if peek('avm_read') != 0

            case peek('memory_inst__avalon_mem_inst__state')
            when 2, 3, 5 then true
            else false
            end
          end

          def current_linear_code_pointer
            cs_base = current_stage_cs_base
            return nil if cs_base.nil?
            return nil if cs_base >= 0x10_0000

            eip = [peek('pipeline_inst__decode_inst__eip'), peek('trace_arch_eip'), peek('trace_wr_eip')].find do |value|
              value.to_i.positive?
            end
            return nil unless eip

            (cs_base + (eip & 0xFFFF_FFFF)) & 0xFFFF_FFFF
          end

          def code_burst_covers_linear?(base, linear_pc)
            return false if base.nil? || linear_pc.nil?

            linear_pc >= base && linear_pc < (base + 32)
          end

          def code_burst_relevant_to_linear?(base, linear_pc)
            return false if base.nil? || linear_pc.nil?

            linear_pc >= (base - 32) && linear_pc < (base + 64)
          end

          def queue_io_requests_if_needed(current_io_read_do, current_io_write_do)
            @last_io_read_sig = nil unless current_io_read_do
            read_addr = peek('io_read_address') & 0xFFFF
            read_len = [peek('io_read_length') & 0x7, 1].max
            read_sig = [read_addr, read_len]
            if current_io_read_do && @pending_io_read_data.nil? && (!@prev_io_read_do || @last_io_read_sig != read_sig)
              @pending_io_read_data = read_io_value(read_addr, read_len)
              @last_io_read_sig = read_sig
              @last_io_read_meta = { address: read_addr, length: read_len }
            end

            @last_io_write_sig = nil unless current_io_write_do
            write_addr = peek('io_write_address') & 0xFFFF
            write_len = [peek('io_write_length') & 0x7, 1].max
            write_data = peek('io_write_data') & 0xFFFF_FFFF
            write_sig = [write_addr, write_len, write_data]
            if current_io_write_do && !@pending_io_write_ack && (!@prev_io_write_do || @last_io_write_sig != write_sig)
              write_io_value(write_addr, write_len, write_data)
              @pending_io_write_ack = true
              @last_io_write_sig = write_sig
              @last_io_write_meta = { address: write_addr, length: write_len, data: write_data }
            end
          end

          def active_irq_vector
            ready = @pic_master_pending & ~@pic_master_mask & ~@pic_master_in_service
            return nil if ready.zero?

            @pic_master_base + Math.log2(ready & -ready).to_i
          end

          def handle_interrupt_ack
            return if peek('interrupt_done').zero?

            ready = @pic_master_pending & ~@pic_master_mask & ~@pic_master_in_service
            return if ready.zero?

            irq_bit = Math.log2(ready & -ready).to_i
            mask = 1 << irq_bit
            @pic_master_pending &= ~mask
            @pic_master_in_service |= mask
          end

          def advance_timers
            return if @pit_counter.to_i <= 0

            @pit_counter -= 1
            return unless @pit_counter.zero?

            increment_bios_tick_count
            @pic_master_pending |= 1
            @pit_counter = @pit_reload
          end

          def raise_irq(irq_bit)
            @pic_master_pending |= (1 << irq_bit.to_i)
          end

          def maybe_seed_post_init_ivt
            return if @post_init_ivt_seeded

            helper_active = [peek('trace_wr_eip'), peek('pipeline_inst__decode_inst__eip')].any? do |value|
              (0x8BF3..0x8C03).cover?(value) || (0xE0CC..0xE0D4).cover?(value) || (0x1080..0x10EE).cover?(value)
            end
            return unless helper_active

            120.times { |vector| write_interrupt_vector(vector, 0xF000, 0xFF53) }
            (0x08..0x0F).each { |vector| write_interrupt_vector(vector, 0xF000, 0xE9E6) }
            (0x70..0x77).each { |vector| write_interrupt_vector(vector, 0xF000, 0xE9EC) }
            write_interrupt_vector(0x11, 0xF000, 0xF84D)
            write_interrupt_vector(0x12, 0xF000, 0xF841)
            write_interrupt_vector(0x15, 0xF000, VerilatorRunner::DOS_INT15_STUB_OFFSET)
            write_interrupt_vector(0x2A, 0xF000, VerilatorRunner::DOS_INT2A_STUB_OFFSET)
            write_interrupt_vector(0x2F, 0xF000, VerilatorRunner::DOS_INT2F_STUB_OFFSET)
            write_interrupt_vector(0x17, 0xF000, 0xEFD2)
            write_interrupt_vector(0x18, 0xF000, 0x8666)
            {
              0x08 => 0xFEA5, 0x09 => 0xE987, 0x0E => 0xEF57, 0x10 => 0xF065,
              0x13 => 0xE3FE, 0x14 => 0xE739, 0x16 => 0xE82E, 0x1A => 0xFE6E,
              0x40 => 0xEC59, 0x70 => 0xFE6E, 0x71 => 0xE987, 0x75 => 0xE2C3
            }.each { |vector, offset| write_interrupt_vector(vector, 0xF000, offset) }
            boot_drive_empty = disk_store_for_drive(0).empty?
            write_interrupt_vector(0x19, boot_drive_empty ? 0xF000 : 0x0000, boot_drive_empty ? 0xE6F2 : VerilatorRunner::DOS_INT19_STUB_ADDR)
            [0x1D, 0x1F, *(0x60..0x67), *(0x78..0xFF)].each { |vector| clear_interrupt_vector(vector) }
            @pic_master_base = 0x08
            @pic_master_mask = 0xB8
            @pit_reload = 65_536
            @pit_counter = 65_536
            @post_init_ivt_seeded = true
          end

          def write_interrupt_vector(vector, segment, offset)
            base = vector * 4
            @memory[base] = offset & 0xFF
            @memory[base + 1] = (offset >> 8) & 0xFF
            @memory[base + 2] = segment & 0xFF
            @memory[base + 3] = (segment >> 8) & 0xFF
          end

          def clear_interrupt_vector(vector)
            write_interrupt_vector(vector, 0, 0)
          end

          def read_io_value(address, length)
            (0...[length, 4].min).sum do |offset|
              read_io_byte(address + offset) << (offset * 8)
            end
          end

          def read_io_byte(address)
            if DOS_INT13_RESULT_PORTS.key?(address)
              field, shift = DOS_INT13_RESULT_PORTS[address]
              return ((instance_variable_get("@#{field}") >> shift) & 0xFF)
            elsif DOS_INT10_RESULT_PORTS.key?(address)
              field, shift = DOS_INT10_RESULT_PORTS[address]
              return ((instance_variable_get("@#{field}") >> shift) & 0xFF)
            elsif DOS_INT16_RESULT_PORTS.key?(address)
              field, shift = DOS_INT16_RESULT_PORTS[address]
              return ((instance_variable_get("@#{field}") >> shift) & 0xFF)
            elsif DOS_INT1A_RESULT_PORTS.key?(address)
              field, shift = DOS_INT1A_RESULT_PORTS[address]
              return ((instance_variable_get("@#{field}") >> shift) & 0xFF)
            end

            case address
            when 0x60 then read_keyboard_data_port
            when 0x61 then 0x20
            when 0x64 then keyboard_status_port
            when 0x03F2 then @fdc_dor & 0xFF
            when 0x03F4 then fdc_main_status
            when 0x03F5 then @fdc_result.shift || 0
            when 0x03F7 then fdc_disk_change_status
            when 0x70 then @cmos_index & 0x7F
            when 0x71 then @cmos[@cmos_index & 0x7F]
            when 0x20 then @pic_master_pending
            when 0x21 then @pic_master_mask
            when 0xA1 then @pic_slave_mask
            when 0x40 then @pit_counter & 0xFF
            when 0x43 then 0x36
            when 0x0F16 then @dos_int13_result_flags & 0x01
            when 0x0EFE then @dos_int16_result_flags & 0x01
            when 0x0F0E then @dos_int1a_result_flags & 0x01
            when 0x3DA then 0x08
            when 0x3D4, 0x3D5, 0x3B4, 0x3B5 then 0x00
            when 0x3C0..0x3CF then 0x00
            else 0xFF
            end
          end

          def write_io_value(address, length, data)
            [length, 4].min.times do |offset|
              addr = address + offset
              byte = (data >> (offset * 8)) & 0xFF
              case addr
              when 0x0ED0 then @dos_int13_ax = (@dos_int13_ax & 0xFF00) | byte
              when 0x0ED1 then @dos_int13_ax = (@dos_int13_ax & 0x00FF) | (byte << 8)
              when 0x0ED2 then @dos_int13_bx = (@dos_int13_bx & 0xFF00) | byte
              when 0x0ED3 then @dos_int13_bx = (@dos_int13_bx & 0x00FF) | (byte << 8)
              when 0x0ED4 then @dos_int13_cx = (@dos_int13_cx & 0xFF00) | byte
              when 0x0ED5 then @dos_int13_cx = (@dos_int13_cx & 0x00FF) | (byte << 8)
              when 0x0ED6 then @dos_int13_dx = (@dos_int13_dx & 0xFF00) | byte
              when 0x0ED7 then @dos_int13_dx = (@dos_int13_dx & 0x00FF) | (byte << 8)
              when 0x0ED8 then @dos_int13_es = (@dos_int13_es & 0xFF00) | byte
              when 0x0ED9 then @dos_int13_es = (@dos_int13_es & 0x00FF) | (byte << 8)
              when 0x0EDA then execute_dos_int13_request
              when 0x0EE0 then @dos_int10_ax = (@dos_int10_ax & 0xFF00) | byte
              when 0x0EE1 then @dos_int10_ax = (@dos_int10_ax & 0x00FF) | (byte << 8)
              when 0x0EE2 then @dos_int10_bx = (@dos_int10_bx & 0xFF00) | byte
              when 0x0EE3 then @dos_int10_bx = (@dos_int10_bx & 0x00FF) | (byte << 8)
              when 0x0EE4 then @dos_int10_cx = (@dos_int10_cx & 0xFF00) | byte
              when 0x0EE5 then @dos_int10_cx = (@dos_int10_cx & 0x00FF) | (byte << 8)
              when 0x0EE6 then @dos_int10_dx = (@dos_int10_dx & 0xFF00) | byte
              when 0x0EE7 then @dos_int10_dx = (@dos_int10_dx & 0x00FF) | (byte << 8)
              when 0x0EF2 then @dos_int10_bp = (@dos_int10_bp & 0xFF00) | byte
              when 0x0EF3 then @dos_int10_bp = (@dos_int10_bp & 0x00FF) | (byte << 8)
              when 0x0EF4 then @dos_int10_es = (@dos_int10_es & 0xFF00) | byte
              when 0x0EF5 then @dos_int10_es = (@dos_int10_es & 0x00FF) | (byte << 8)
              when 0x0EE8 then execute_dos_int10_request
              when 0x0EF8 then @dos_int16_ax = (@dos_int16_ax & 0xFF00) | byte
              when 0x0EF9 then @dos_int16_ax = (@dos_int16_ax & 0x00FF) | (byte << 8)
              when 0x0EFA then execute_dos_int16_request
              when 0x0F00 then @dos_int1a_ax = (@dos_int1a_ax & 0xFF00) | byte
              when 0x0F01 then @dos_int1a_ax = (@dos_int1a_ax & 0x00FF) | (byte << 8)
              when 0x0F02 then @dos_int1a_cx = (@dos_int1a_cx & 0xFF00) | byte
              when 0x0F03 then @dos_int1a_cx = (@dos_int1a_cx & 0x00FF) | (byte << 8)
              when 0x0F04 then @dos_int1a_dx = (@dos_int1a_dx & 0xFF00) | byte
              when 0x0F05 then @dos_int1a_dx = (@dos_int1a_dx & 0x00FF) | (byte << 8)
              when 0x0F06 then execute_dos_int1a_request
              when 0x20 then @pic_master_in_service &= ~(@pic_master_in_service & -@pic_master_in_service) if (byte & 0x20) != 0
              when 0x21 then @pic_master_mask = byte
              when 0xA1 then @pic_slave_mask = byte
              when 0x0004 then write_dma_channel2_addr(byte)
              when 0x0005 then write_dma_channel2_count(byte)
              when 0x0081 then @dma_ch2_page = byte
              when 0x000A then write_dma_mask(byte)
              when 0x000B then @dma_ch2_mode = byte
              when 0x000C then @dma_flip_flop_low = true
              when 0x000D then reset_dma_controller
              when 0x40 then write_pit_counter_byte(byte)
              when 0x43 then program_pit_control(byte)
              when 0x03F2 then write_fdc_dor(byte)
              when 0x03F5 then write_fdc_data(byte)
              when 0x03F7 then @fdc_data_rate = byte
              when 0x70 then @cmos_index = byte & 0x7F
              when 0x71 then @cmos[@cmos_index & 0x7F] = byte
              when 0x02F8, 0x03F8 then @serial_output << byte.chr(Encoding::BINARY)
              end
            end
          end

          def execute_dos_int13_request
            function = (@dos_int13_ax >> 8) & 0xFF
            @dos_int13_result_bx = @dos_int13_bx
            @dos_int13_result_cx = @dos_int13_cx
            @dos_int13_result_dx = @dos_int13_dx
            @dos_int13_result_flags = 0
            @dos_int13_result_ax =
              case function
              when 0x00 then execute_dos_int13_reset
              when 0x01 then execute_dos_int13_read_status
              when 0x02 then execute_dos_int13_read
              when 0x03 then execute_dos_int13_write
              when 0x08 then execute_dos_int13_get_parameters
              when 0x15 then execute_dos_int13_get_drive_type
              when 0x16 then execute_dos_int13_get_change_line_status
              else
                @dos_int13_result_flags = 1
                @memory[0x0441] = 0x01
                0x0100
              end
            log_dos_int13_request(function)
          end

          def execute_dos_int13_reset
            dl = @dos_int13_dx & 0xFF
            if hdd_drive?(dl)
              @memory[0x0474] = 0x00
              return 0
            end
            drive = normalize_dos_floppy_drive(dl)
            unless drive
              @dos_int13_result_flags = 1
              write_bios_diskette_result_bytes(0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
              return 0x0100
            end

            write_bios_diskette_result_bytes(0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
            write_bios_floppy_current_cylinder(drive, 0)
            0
          end

          def execute_dos_int13_read_status
            status = @memory.fetch(0x0441, 0)
            @dos_int13_result_flags = status.zero? ? 0 : 1
            status << 8
          end

          def execute_dos_int13_read
            dl = @dos_int13_dx & 0xFF
            return execute_dos_int13_disk_read(@hdd_store, @hdd_geometry) if hdd_drive?(dl)

            drive = normalize_dos_floppy_drive(dl)
            unless drive
              write_bios_diskette_result_bytes(0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
              @dos_int13_result_flags = 1
              return 0x0100
            end
            execute_dos_int13_disk_read(disk_store_for_drive(drive), floppy_geometry_for_drive(drive), floppy_drive: drive)
          end

          def execute_dos_int13_write
            dl = @dos_int13_dx & 0xFF
            return execute_dos_int13_disk_write(@hdd_store, @hdd_geometry) if hdd_drive?(dl)

            @dos_int13_result_flags = 1
            @memory[0x0441] = 0x03
            0x0300
          end

          def execute_dos_int13_disk_read(store, geometry, floppy_drive: nil)
            count = @dos_int13_ax & 0xFF
            buffer = (@dos_int13_es << 4) + @dos_int13_bx
            cl = @dos_int13_cx & 0xFF
            ch = (@dos_int13_cx >> 8) & 0xFF
            head = (@dos_int13_dx >> 8) & 0xFF
            sector = cl & 0x3F
            cylinder = ch | ((cl & 0xC0) << 2)
            return invalid_dos_disk_request(cylinder, head, sector) if count.zero? || sector.zero?
            return invalid_dos_disk_request(cylinder, head, sector) if head >= geometry.fetch(:heads).to_i
            return invalid_dos_disk_request(cylinder, head, sector) if sector > geometry.fetch(:sectors_per_track).to_i

            bps = geometry.fetch(:bytes_per_sector).to_i
            start_lba = ((cylinder * geometry.fetch(:heads).to_i) + head) * geometry.fetch(:sectors_per_track).to_i + (sector - 1)
            disk_offset = start_lba * bps
            (count * bps).times { |i| @memory[buffer + i] = store.fetch(disk_offset + i, 0) }

            end_lba = start_lba + count - 1
            track_span = geometry.fetch(:heads).to_i * geometry.fetch(:sectors_per_track).to_i
            end_cylinder = end_lba / track_span
            end_rem = end_lba % track_span
            end_head = end_rem / geometry.fetch(:sectors_per_track).to_i
            end_sector = (end_rem % geometry.fetch(:sectors_per_track).to_i) + 1
            if floppy_drive
              st0 = 0x20 | (end_head & 0x01)
              write_bios_diskette_result_bytes(0x00, st0, 0x00, 0x00, end_cylinder, end_head, end_sector, 0x02)
              write_bios_floppy_current_cylinder(floppy_drive, end_cylinder)
            end
            @dos_int13_result_cx = ((end_cylinder & 0xFF) << 8) | ((end_cylinder >> 2) & 0xC0) | (end_sector & 0x3F)
            @dos_int13_result_dx = ((end_head & 0xFF) << 8) | (@dos_int13_dx & 0x00FF)
            @dos_int13_result_flags = 0
            count
          end

          def execute_dos_int13_disk_write(store, geometry)
            count = @dos_int13_ax & 0xFF
            buffer = (@dos_int13_es << 4) + @dos_int13_bx
            cl = @dos_int13_cx & 0xFF
            ch = (@dos_int13_cx >> 8) & 0xFF
            head = (@dos_int13_dx >> 8) & 0xFF
            sector = cl & 0x3F
            cylinder = ch | ((cl & 0xC0) << 2)
            return invalid_dos_disk_request(cylinder, head, sector) if count.zero? || sector.zero?

            bps = geometry.fetch(:bytes_per_sector).to_i
            start_lba = ((cylinder * geometry.fetch(:heads).to_i) + head) * geometry.fetch(:sectors_per_track).to_i + (sector - 1)
            disk_offset = start_lba * bps
            (count * bps).times { |i| store[disk_offset + i] = @memory.fetch(buffer + i, 0) }

            @dos_int13_result_flags = 0
            count
          end

          def invalid_dos_disk_request(cylinder, head, sector)
            @dos_int13_result_flags = 1
            @memory[0x0441] = 0x01
            0x0100
          end

          def execute_dos_int13_get_parameters
            dl = @dos_int13_dx & 0xFF
            if hdd_drive?(dl)
              return invalid_dos_disk_request(0, 0, 0) unless @hdd_geometry

              max_cyl = [@hdd_geometry.fetch(:cylinders).to_i - 1, 0].max
              max_head = [@hdd_geometry.fetch(:heads).to_i - 1, 0].max
              spt = @hdd_geometry.fetch(:sectors_per_track).to_i
              @dos_int13_result_bx = 0
              @dos_int13_result_cx = ((max_cyl & 0xFF) << 8) | ((max_cyl >> 2) & 0xC0) | (spt & 0x3F)
              @dos_int13_result_dx = ((max_head & 0xFF) << 8) | 0x01
              @memory[0x0474] = 0x00
              return 0
            end

            return invalid_dos_floppy_request unless normalize_dos_floppy_drive(dl)

            @dos_int13_result_bx = 0x0400
            geometry = floppy_geometry_for_drive(normalize_dos_floppy_drive(dl))
            @dos_int13_result_cx = ((geometry.fetch(:cylinders).to_i - 1) << 8) | geometry.fetch(:sectors_per_track).to_i
            @dos_int13_result_dx = ((geometry.fetch(:heads).to_i - 1) << 8) | floppy_drive_count
            @memory[0x0441] = 0x00
            0
          end

          def execute_dos_int13_get_drive_type
            dl = @dos_int13_dx & 0xFF
            if hdd_drive?(dl)
              return 0x0000 unless @hdd_geometry

              total = @hdd_geometry.fetch(:total_sectors, 0)
              @dos_int13_result_cx = (total >> 16) & 0xFFFF
              @dos_int13_result_dx = total & 0xFFFF
              @dos_int13_result_flags = 0
              return 0x0300
            end

            drive = normalize_dos_floppy_drive(dl)
            return 0x0000 unless drive

            geometry = floppy_geometry_for_drive(drive)
            drive_type = geometry.fetch(:drive_type).to_i & 0x0F
            @dos_int13_result_flags = 0
            drive_type.zero? ? 0x0000 : 0x0100
          end

          def execute_dos_int13_get_change_line_status
            dl = @dos_int13_dx & 0xFF
            return 0x0000 if hdd_drive?(dl)

            return invalid_dos_floppy_request unless normalize_dos_floppy_drive(dl)

            @memory[0x0441] = 0x06
            @dos_int13_result_flags = 1
            0x0600
          end

          def log_dos_int13_request(function)
            dl = @dos_int13_dx & 0xFF
            cl = @dos_int13_cx & 0xFF
            ch = (@dos_int13_cx >> 8) & 0xFF
            head = (@dos_int13_dx >> 8) & 0xFF
            sector = cl & 0x3F
            cylinder = ch | ((cl & 0xC0) << 2)
            is_hdd = hdd_drive?(dl)
            drive = is_hdd ? (dl & 0x7F) : normalize_dos_floppy_drive(dl)
            geometry = if is_hdd
              @hdd_geometry
            elsif drive
              floppy_geometry_for_drive(drive)
            end
            lba = if geometry && sector.positive? && head < geometry.fetch(:heads).to_i
              ((cylinder * geometry.fetch(:heads).to_i) + head) * geometry.fetch(:sectors_per_track).to_i + (sector - 1)
            end

            @dos_int13_history << {
              function: function,
              ax: @dos_int13_ax,
              bx: @dos_int13_bx,
              cx: @dos_int13_cx,
              dx: @dos_int13_dx,
              es: @dos_int13_es,
              drive: is_hdd ? (0x80 | drive.to_i) : drive,
              cylinder: cylinder,
              head: head,
              sector: sector,
              lba: lba,
              result_ax: @dos_int13_result_ax,
              flags: @dos_int13_result_flags
            }
            @dos_int13_history.shift while @dos_int13_history.length > 64
          end

          def record_pc_history
            entry = {
              trace: peek('trace_wr_eip') & 0xFFFF_FFFF,
              decode: peek('pipeline_inst__decode_inst__eip') & 0xFFFF_FFFF,
              arch: peek('trace_arch_eip') & 0xFFFF_FFFF,
              cs_cache: peek('trace_cs_cache'),
              exception_vector: peek('exception_inst__exc_vector') & 0xFF,
              exception_eip: peek('exception_inst__exc_eip') & 0xFFFF_FFFF
            }
            return if @pc_history.last == entry

            @pc_history << entry
            @pc_history.shift while @pc_history.length > 2048
          end

          def maybe_repair_generic_dos_stage_vars

            bytes_per_sector = memory_u16(0x7C0B)
            sectors_per_cluster = @memory.fetch(0x7C0D, 0)
            reserved_sectors = memory_u16(0x7C0E)
            fats = @memory.fetch(0x7C10, 0)
            root_entries = memory_u16(0x7C11)
            total_sectors_low = memory_u16(0x7C13)
            sectors_per_fat = memory_u16(0x7C16)
            sectors_per_track = memory_u16(0x7C18)
            heads = memory_u16(0x7C1A)
            hidden_sectors = memory_u32(0x7C1C)
            total_sectors = if total_sectors_low.zero?
              memory_u32(0x7C20)
            else
              total_sectors_low
            end
            return if bytes_per_sector.zero? || sectors_per_cluster.zero?

            root_dir_sectors = ((root_entries * 32) + (bytes_per_sector - 1)) / bytes_per_sector
            data_start_sector = reserved_sectors + (fats * sectors_per_fat) + root_dir_sectors
            data_sectors = total_sectors - data_start_sector
            cluster_count = data_sectors / sectors_per_cluster
            fat_mode = cluster_count >= 0x0FF6 ? 0x04 : 0x01

            expected = {
              heads: heads,
              sectors_per_fat: sectors_per_fat,
              hidden_sectors: hidden_sectors,
              bytes_per_sector: bytes_per_sector,
              reserved_sectors: reserved_sectors,
              data_start_sector: data_start_sector,
              total_sectors: total_sectors,
              sectors_per_track: sectors_per_track,
              fat_mode: fat_mode,
              sectors_per_cluster: sectors_per_cluster
            }

            candidate_bases = @generic_dos_stage_bases.dup
            current_base = current_stage_cs_base
            if current_base && generic_dos_stage_header_at?(current_base)
              @generic_dos_stage_bases << current_base unless @generic_dos_stage_bases.include?(current_base)
              candidate_bases << current_base
            end

            candidate_bases.each do |base|
              next unless generic_dos_stage_header_at?(base)

              repair_generic_dos_stage_vars_at(base, expected)
              repair_generic_dos_stage_chs_helper_at(base)
            end
          end

          def current_stage_cs_base
            cache = peek('trace_cs_cache')
            base_high = (cache >> 56) & 0xFF
            base_low = (cache >> 16) & 0xFFFFFF
            (base_high << 24) | base_low
          end

          def generic_dos_stage_header_at?(base)
            @memory.fetch(base, 0) == 0xE9 && @memory.fetch(base + 1, 0) == 0xB5
          end

          def repair_generic_dos_stage_vars_at(base, expected)
            write_u16(base + 0x85, expected.fetch(:heads)) if memory_u16(base + 0x85).zero?
            write_u16(base + 0x95, expected.fetch(:sectors_per_fat)) if memory_u16(base + 0x95).zero?

            hidden = expected.fetch(:hidden_sectors)
            write_u16(base + 0x97, hidden & 0xFFFF) if memory_u16(base + 0x97) != (hidden & 0xFFFF)
            write_u16(base + 0x99, (hidden >> 16) & 0xFFFF) if memory_u16(base + 0x99) != ((hidden >> 16) & 0xFFFF)

            write_u16(base + 0x9B, expected.fetch(:bytes_per_sector)) if memory_u16(base + 0x9B).zero?
            write_u16(base + 0x9D, expected.fetch(:reserved_sectors)) if memory_u16(base + 0x9D).zero?

            data_start = expected.fetch(:data_start_sector)
            write_u16(base + 0xA3, data_start & 0xFFFF) if memory_u16(base + 0xA3).zero? || memory_u16(base + 0xA5) != ((data_start >> 16) & 0xFFFF)
            write_u16(base + 0xA5, (data_start >> 16) & 0xFFFF) if memory_u16(base + 0xA5) != ((data_start >> 16) & 0xFFFF)

            total = expected.fetch(:total_sectors)
            write_u16(base + 0xA7, total & 0xFFFF) if memory_u16(base + 0xA7).zero?
            write_u16(base + 0xA9, (total >> 16) & 0xFFFF) if memory_u16(base + 0xA9) != ((total >> 16) & 0xFFFF)

            write_u16(base + 0xAB, expected.fetch(:sectors_per_track)) if memory_u16(base + 0xAB).zero?
            @memory[base + 0xAE] = expected.fetch(:fat_mode) & 0xFF if @memory.fetch(base + 0xAE, 0).zero?
            @memory[base + 0xB7] = expected.fetch(:sectors_per_cluster) & 0xFF if @memory.fetch(base + 0xB7, 0).zero?
          end

          def repair_generic_dos_stage_chs_helper_at(base)
            helper_base = base + GENERIC_DOS_STAGE_CHS_HELPER_OFFSET
            current = read_store(@memory, helper_base, GENERIC_DOS_STAGE_CHS_HELPER_ORIGINAL.length, mapped: false)
            return if current == GENERIC_DOS_STAGE_CHS_HELPER_PATCH
            return unless current == GENERIC_DOS_STAGE_CHS_HELPER_ORIGINAL

            load_store!(@memory, GENERIC_DOS_STAGE_CHS_HELPER_PATCH, helper_base)
          end

          def maybe_repair_dos_int12_wrapper_chain
            return unless memory_u16(0x12 * 4) == DOS_INT12_WRAPPER_OFFSET
            return unless memory_u16((0x12 * 4) + 2) == DOS_INT12_WRAPPER_SEGMENT

            wrapper_base = DOS_INT12_WRAPPER_SEGMENT << 4
            saved_vector_addr = wrapper_base + DOS_INT12_WRAPPER_SAVED_VECTOR_OFFSET
            return if memory_u16(saved_vector_addr) == DOS_INT12_BIOS_OFFSET &&
                      memory_u16(saved_vector_addr + 2) == DOS_INT12_BIOS_SEGMENT

            write_u16(saved_vector_addr, DOS_INT12_BIOS_OFFSET)
            write_u16(saved_vector_addr + 2, DOS_INT12_BIOS_SEGMENT)
          end

          def maybe_install_late_dos_int2f_fallback
            return if @dos_int2f_wrapper_installed
            return unless @host_cycles_total >= DOS_INT2F_LATE_FALLBACK_AFTER_CYCLES
            return unless @dos_int13_history.any? { |entry| entry[:lba] == DOS_INT2F_LATE_FALLBACK_AFTER_LBA }

            current_offset = memory_u16(DOS_INT2F_VECTOR * 4)
            current_segment = memory_u16((DOS_INT2F_VECTOR * 4) + 2)
            if current_offset == DOS_INT2F_WRAPPER_OFFSET &&
               current_segment == DOS_INT2F_WRAPPER_SEGMENT
              @dos_int2f_wrapper_installed = true
              return
            end

            return unless current_offset == DOS_INT2F_BOOTSTRAP_DOS_OFFSET
            return unless current_segment == DOS_INT2F_BOOTSTRAP_DOS_SEGMENT

            load_store!(
              @memory,
              dos_int2f_late_fallback_wrapper_bytes(current_offset, current_segment),
              (DOS_INT2F_WRAPPER_SEGMENT << 4) + DOS_INT2F_WRAPPER_OFFSET
            )
            write_interrupt_vector(DOS_INT2F_VECTOR, DOS_INT2F_WRAPPER_SEGMENT, DOS_INT2F_WRAPPER_OFFSET)
            @dos_int2f_wrapper_installed = true
          end

          def dos_int2f_late_fallback_wrapper_bytes(old_offset, old_segment)
            bytes = []
            DOS_INT2F_LATE_FALLBACK_AX.each do |value|
              bytes.concat(
                [
                  0x9C,
                  0x3D, value & 0xFF, (value >> 8) & 0xFF,
                  0x75, 0x02,
                  0x9D,
                  0xCF,
                  0x9D
                ]
              )
            end
            bytes.concat([0xEA, old_offset & 0xFF, (old_offset >> 8) & 0xFF, old_segment & 0xFF, (old_segment >> 8) & 0xFF])
            bytes
          end

          def memory_u16(addr)
            @memory.fetch(addr, 0) | (@memory.fetch(addr + 1, 0) << 8)
          end

          def memory_u32(addr)
            memory_u16(addr) | (memory_u16(addr + 2) << 16)
          end

          def write_u16(addr, value)
            @memory[addr] = value & 0xFF
            @memory[addr + 1] = (value >> 8) & 0xFF
          end

          def execute_dos_int10_request
            @dos_int10_result_ax = @dos_int10_ax
            @dos_int10_result_bx = @dos_int10_bx
            @dos_int10_result_cx = @dos_int10_cx
            @dos_int10_result_dx = @dos_int10_dx
            function = (@dos_int10_ax >> 8) & 0xFF
            page = (@dos_int10_bx >> 8) & 0xFF
            case function
            when 0x00 then initialize_text_mode(@dos_int10_ax & 0xFF)
            when 0x01
            when 0x02 then set_cursor_position_for_page(page, (@dos_int10_dx >> 8) & 0xFF, @dos_int10_dx & 0xFF)
            when 0x03
              row, col = cursor_position_for_page(page)
              @dos_int10_result_cx = 0x0607
              @dos_int10_result_dx = (row << 8) | col
            when 0x08
              row, col = cursor_position_for_page(page)
              ch, attr = read_text_cell_for_page(page, row, col)
              @dos_int10_result_ax = (attr << 8) | ch
            when 0x09
              write_repeated_char(page, @dos_int10_ax & 0xFF, @dos_int10_bx & 0xFF, @dos_int10_cx, false)
            when 0x0A
              write_repeated_char(page, @dos_int10_ax & 0xFF, nil, @dos_int10_cx, false)
            when 0x05 then set_active_video_page(@dos_int10_ax & 0xFF)
            when 0x06, 0x07
              if (@dos_int10_ax & 0xFF).zero?
                active_page = active_video_page
                clear_text_screen_for_page(active_page)
                set_cursor_position_for_page(active_page, 0, 0)
              end
            when 0x0E then video_teletype(page, @dos_int10_ax & 0xFF)
            when 0x0F
              @dos_int10_result_ax = (80 << 8) | 0x03
              @dos_int10_result_bx = (@dos_int10_result_bx & 0x00FF) | (active_video_page << 8)
            when 0x13
              write_string(page, (@dos_int10_dx >> 8) & 0xFF, @dos_int10_dx & 0xFF, @dos_int10_cx, @dos_int10_bx & 0xFF,
                           (@dos_int10_ax & 0x02) != 0, (@dos_int10_ax & 0x01) != 0, @dos_int10_es, @dos_int10_bp)
            end
          end

          def execute_dos_int16_request
            @dos_int16_result_ax = 0
            @dos_int16_result_flags = 0
            function = (@dos_int16_ax >> 8) & 0xFF
            case function
            when 0x00, 0x10
              if (key = @keyboard_queue.shift)
                @keyboard_scan_queue.shift
                @dos_int16_result_ax = key
                @dos_int16_result_flags = 1
              end
            when 0x01, 0x11
              if (key = @keyboard_queue.first)
                @dos_int16_result_ax = key
                @dos_int16_result_flags = 1
              end
            when 0x02
              @dos_int16_result_flags = 0
            end
          end

          def execute_dos_int1a_request
            @dos_int1a_result_ax = 0
            @dos_int1a_result_cx = 0
            @dos_int1a_result_dx = 0
            @dos_int1a_result_flags = 0
            function = (@dos_int1a_ax >> 8) & 0xFF
            case function
            when 0x00
              ticks = read_bios_tick_count
              midnight = @memory.fetch(0x0470, 0)
              @dos_int1a_result_ax = midnight
              @dos_int1a_result_cx = (ticks >> 16) & 0xFFFF
              @dos_int1a_result_dx = ticks & 0xFFFF
              @memory[0x0470] = 0
            when 0x01
              write_bios_tick_count((@dos_int1a_cx << 16) | @dos_int1a_dx)
              @memory[0x0470] = 0
            when 0x02
              @dos_int1a_result_cx = ((@cmos[0x04] & 0xFF) << 8) | (@cmos[0x02] & 0xFF)
              @dos_int1a_result_dx = (@cmos[0x00] & 0xFF) << 8
            when 0x04
              @dos_int1a_result_cx = ((@cmos[0x32] & 0xFF) << 8) | (@cmos[0x09] & 0xFF)
              @dos_int1a_result_dx = ((@cmos[0x08] & 0xFF) << 8) | (@cmos[0x07] & 0xFF)
            else
              @dos_int1a_result_ax = @dos_int1a_ax
              @dos_int1a_result_cx = @dos_int1a_cx
              @dos_int1a_result_dx = @dos_int1a_dx
            end
          end

          def initialize_text_mode(mode)
            @memory[0x0449] = mode
            @memory[0x044A] = 80
            @memory[0x044B] = 0
            set_active_video_page(0)
            clear_text_screen
          end

          def clear_text_screen
            8.times do |page|
              clear_text_screen_for_page(page)
              set_cursor_position_for_page(page, 0, 0)
            end
          end

          def clear_text_screen_for_page(page)
            25.times do |row|
              80.times do |col|
                write_text_cell_for_page(page, row, col, 32, 0x07)
              end
            end
          end

          def active_video_page
            @memory.fetch(RHDL::Examples::AO486::DisplayAdapter::VIDEO_PAGE_BDA, 0) & 0x07
          end

          def set_active_video_page(page)
            @memory[RHDL::Examples::AO486::DisplayAdapter::VIDEO_PAGE_BDA] = page & 0x07
          end

          def cursor_position_for_page(page)
            base = RHDL::Examples::AO486::DisplayAdapter::CURSOR_BDA + ((page & 0x07) * 2)
            [@memory.fetch(base + 1, 0), @memory.fetch(base, 0)]
          end

          def set_cursor_position_for_page(page, row, col)
            base = RHDL::Examples::AO486::DisplayAdapter::CURSOR_BDA + ((page & 0x07) * 2)
            @memory[base] = [col, 79].min
            @memory[base + 1] = [row, 24].min
          end

          def video_teletype(page, byte)
            row, col = cursor_position_for_page(page)
            if byte == 13
              col = 0
            elsif byte == 10
              row += 1
            elsif byte == 8
              col = [col - 1, 0].max
            else
              write_text_cell_for_page(page, row, col, byte, 0x07)
              col += 1
            end
            if col >= 80
              col = 0
              row += 1
            end
            if row >= 25
              scroll_text_up(page)
              row = 24
            end
            set_cursor_position_for_page(page, row, col)
          end

          def scroll_text_up(page)
            base = text_page_base(page)
            @text_dirty = true
            (1...25).each do |row|
              80.times do |col|
                from = base + row * 160 + col * 2
                to = base + (row - 1) * 160 + col * 2
                @memory[to] = @memory.fetch(from, 32)
                @memory[to + 1] = @memory.fetch(from + 1, 0x07)
              end
            end
            80.times { |col| write_text_cell_for_page(page, 24, col, 32, 0x07) }
          end

          def write_text_cell_for_page(page, row, col, ch, attr)
            return if row >= 25 || col >= 80

            base = text_page_base(page) + row * 160 + col * 2
            @memory[base] = ch
            @memory[base + 1] = attr
            @text_dirty = true
          end

          def read_text_cell_for_page(page, row, col)
            return [32, 0x07] if row >= 25 || col >= 80

            base = text_page_base(page) + row * 160 + col * 2
            [@memory.fetch(base, 32), @memory.fetch(base + 1, 0x07)]
          end

          def write_repeated_char(page, ch, attr_override, count, update_cursor)
            row, col = cursor_position_for_page(page)
            existing_ch, existing_attr = read_text_cell_for_page(page, row, col)
            attr = attr_override.nil? ? existing_attr : attr_override
            byte = ch.zero? ? existing_ch : ch

            count.times do
              write_text_cell_for_page(page, row, col, byte, attr)
              col += 1
              if col >= 80
                col = 0
                row += 1
              end
              if row >= 25
                scroll_text_up(page)
                row = 24
              end
            end

            set_cursor_position_for_page(page, row, col) if update_cursor
          end

          def text_page_base(page)
            RHDL::Examples::AO486::DisplayAdapter::TEXT_BASE + (page & 0x07) * RHDL::Examples::AO486::DisplayAdapter::BUFFER_SIZE
          end

          def write_string(page, row, col, count, default_attr, with_attr, update_cursor, segment, offset)
            base = (segment << 4) + offset
            row = [row, 24].min
            col = [col, 79].min
            count.times do |index|
              item_offset = with_attr ? index * 2 : index
              ch = @memory.fetch(base + item_offset, 32)
              attr = with_attr ? @memory.fetch(base + item_offset + 1, default_attr) : default_attr
              write_text_cell_for_page(page, row, col, ch, attr)
              col += 1
              if col >= 80
                col = 0
                row += 1
              end
              if row >= 25
                scroll_text_up(page)
                row = 24
              end
            end
            set_cursor_position_for_page(page, row, col) if update_cursor
          end

          def enqueue_keyboard_byte(byte)
            key = ascii_to_bios_key(byte)
            return false unless key

            @keyboard_queue << key
            @keyboard_scan_queue << ((key >> 8) & 0xFF)
            @pic_master_pending |= (1 << 1)
            true
          end

          def read_keyboard_data_port
            scan = @keyboard_scan_queue.shift || 0
            @keyboard_queue.shift if scan != 0
            scan
          end

          def keyboard_status_port
            @keyboard_scan_queue.empty? ? 0x18 : 0x19
          end

          def ascii_to_bios_key(byte)
            case byte
            when 10, 13 then 0x1C0D
            when 8 then 0x0E08
            when 9 then 0x0F09
            when 32 then 0x3920
            when 48..57 then (((byte - 47) & 0xFF) << 8) | byte
            when 97, 65 then 0x1E00 | byte
            when 98, 66 then 0x3000 | byte
            when 99, 67 then 0x2E00 | byte
            when 100, 68 then 0x2000 | byte
            else
              (0x20..0x7E).cover?(byte) ? byte : nil
            end
          end

          def reset_dma_controller
            @dma_flip_flop_low = true
            @dma_ch2_masked = true
            @dma_ch2_mode = 0
          end

          def write_dma_mask(byte)
            return unless (byte & 0x3) == DMA_FDC_CHANNEL

            @dma_ch2_masked = (byte & 0x4) != 0
          end

          def write_dma_channel2_addr(byte)
            if @dma_flip_flop_low
              @dma_ch2_base_addr = (@dma_ch2_base_addr & 0xFF00) | byte
              @dma_ch2_current_addr = (@dma_ch2_current_addr & 0xFF00) | byte
            else
              @dma_ch2_base_addr = (@dma_ch2_base_addr & 0x00FF) | (byte << 8)
              @dma_ch2_current_addr = (@dma_ch2_current_addr & 0x00FF) | (byte << 8)
            end
            @dma_flip_flop_low = !@dma_flip_flop_low
          end

          def write_dma_channel2_count(byte)
            if @dma_flip_flop_low
              @dma_ch2_base_count = (@dma_ch2_base_count & 0xFF00) | byte
              @dma_ch2_current_count = (@dma_ch2_current_count & 0xFF00) | byte
            else
              @dma_ch2_base_count = (@dma_ch2_base_count & 0x00FF) | (byte << 8)
              @dma_ch2_current_count = (@dma_ch2_current_count & 0x00FF) | (byte << 8)
            end
            @dma_flip_flop_low = !@dma_flip_flop_low
          end

          def write_fdc_dor(byte)
            was_reset = (@fdc_dor & 0x04).zero?
            now_enabled = (byte & 0x04) != 0
            @fdc_dor = byte
            return unless was_reset && now_enabled

            @fdc_last_st0 = 0x20
            @fdc_last_pcn = @fdc_current_cylinder
            raise_irq(6)
          end

          def write_fdc_data(byte)
            if @fdc_expected_len.zero?
              @fdc_command = [byte]
              @fdc_result.clear
              @fdc_expected_len = fdc_command_length(byte)
              execute_fdc_command if @fdc_expected_len == 1
              return
            end

            @fdc_command << byte
            execute_fdc_command if @fdc_command.length >= @fdc_expected_len
          end

          def execute_fdc_command
            command = @fdc_command.dup
            opcode = command.first.to_i

            case opcode & 0x1F
            when 0x03
              nil
            when 0x07
              @fdc_current_cylinder = 0
              @fdc_last_st0 = 0x20
              @fdc_last_pcn = 0
              raise_irq(6)
            when 0x08
              @fdc_result << @fdc_last_st0
              @fdc_result << @fdc_last_pcn
            when 0x0F
              @fdc_current_cylinder = command[2].to_i
              @fdc_last_st0 = 0x20
              @fdc_last_pcn = @fdc_current_cylinder
              raise_irq(6)
            when 0x06
              execute_fdc_read_data(command)
            end

            @fdc_command.clear
            @fdc_expected_len = 0
          end

          def execute_fdc_read_data(command)
            return if command.length < 9

            drive_head = command[1].to_i
            cylinder = command[2].to_i
            head = command[3].to_i
            sector = [command[4].to_i, 1].max
            sector_size_code = command[5].to_i
            eot = [command[6].to_i, command[4].to_i].max
            sector_size = 128 << [sector_size_code, 7].min
            sectors_to_transfer = [eot - sector + 1, 1].max
            dma_capacity = @dma_ch2_current_count.to_i + 1
            requested_len = sectors_to_transfer * sector_size
            transfer_len = [requested_len, dma_capacity].min
            drive = drive_head & 0x03
            geometry = floppy_geometry_for_drive(drive)
            disk_store = disk_store_for_drive(drive)
            start_lba = ((cylinder * geometry.fetch(:heads).to_i) + head) * geometry.fetch(:sectors_per_track).to_i + (sector - 1)
            disk_offset = start_lba * geometry.fetch(:bytes_per_sector).to_i
            dma_address = dma_address_ch2

            unless @dma_ch2_masked
              transfer_len.times do |index|
                @memory[dma_address + index] = disk_store.fetch(disk_offset + index, 0)
              end
              @dma_ch2_current_addr = (@dma_ch2_current_addr + transfer_len) & 0xFFFF
              @dma_ch2_current_count = (@dma_ch2_current_count - [transfer_len - 1, 0].max) & 0xFFFF
            end

            end_sector = sector + sectors_to_transfer - 1
            @fdc_current_cylinder = cylinder & 0xFF
            @fdc_last_st0 = 0x20 | (drive_head & 0x03)
            @fdc_last_pcn = @fdc_current_cylinder
            @fdc_result << @fdc_last_st0
            @fdc_result << 0x00
            @fdc_result << 0x00
            @fdc_result << (cylinder & 0xFF)
            @fdc_result << (head & 0xFF)
            @fdc_result << (end_sector & 0xFF)
            @fdc_result << (sector_size_code & 0xFF)
            raise_irq(6)
          end

          def fdc_main_status
            @fdc_result.empty? ? 0x80 : 0xD0
          end

          def fdc_disk_change_status
            disk_store_for_drive(@fdc_dor & 0x03).empty? ? 0x00 : 0x80
          end

          def dma_address_ch2
            ((@dma_ch2_page & 0xFF) << 16) | (@dma_ch2_current_addr & 0xFFFF)
          end

          def fdc_command_length(opcode)
            case opcode & 0x1F
            when 0x03 then 3
            when 0x07 then 2
            when 0x08 then 1
            when 0x0F then 3
            when 0x06 then 9
            else 1
            end
          end

          def read_bios_tick_count
            4.times.sum { |idx| @memory.fetch(0x046C + idx, 0) << (idx * 8) }
          end

          def write_bios_tick_count(value)
            4.times { |idx| @memory[0x046C + idx] = (value >> (idx * 8)) & 0xFF }
          end

          def increment_bios_tick_count
            next_ticks = read_bios_tick_count + 1
            if next_ticks >= BIOS_TICKS_PER_DAY
              write_bios_tick_count(next_ticks - BIOS_TICKS_PER_DAY)
              @memory[0x0470] = 1
            else
              write_bios_tick_count(next_ticks)
            end
          end

          def write_bios_diskette_result_bytes(status, st0, st1, st2, cylinder, head, sector, size_code)
            @memory[0x0441] = status & 0xFF
            @memory[0x0442] = st0 & 0xFF
            @memory[0x0443] = st1 & 0xFF
            @memory[0x0444] = st2 & 0xFF
            @memory[0x0445] = cylinder & 0xFF
            @memory[0x0446] = head & 0xFF
            @memory[0x0447] = sector & 0xFF
            @memory[0x0448] = size_code & 0xFF
          end

          def write_bios_floppy_current_cylinder(drive, cylinder)
            @memory[0x0494 + drive] = cylinder & 0xFF
          end

          def normalize_dos_floppy_drive(drive)
            value = drive & 0xFF
            case value
            when 0x00 then 0x00
            when 0x01 then 0x01
            when 0x80 then @hdd_store.empty? ? 0x00 : nil
            when 0x81 then @hdd_store.empty? ? (disk_store_for_drive(1).empty? ? 0x00 : 0x01) : nil
            else nil
            end
          end

          def hdd_drive?(drive)
            (drive & 0xFF) == 0x80 && !@hdd_store.empty?
          end

          def invalid_dos_floppy_request
            @memory[0x0441] = 0x01
            @dos_int13_result_flags = 1
            0x0100
          end

          def floppy_geometry_for_drive(drive)
            @floppy_geometries[(drive || 0).to_i & 0x01]
          end

          def disk_store_for_drive(drive)
            @disk_drives[(drive || 0).to_i & 0x01]
          end

          def floppy_drive_count
            count = @disk_drives.count { |store| !store.empty? }
            count.positive? ? count : 1
          end

          def default_cmos
            Array.new(128, 0).tap do |cmos|
              seed_cmos_datetime!(cmos)
              cmos[0x0A] = 0x26
              cmos[0x0B] = 0x02
              cmos[0x0D] = 0x80
              cmos[0x10] = 0x40
              cmos[0x12] = 0xF0
              cmos[0x14] = 0x0D
              cmos[0x15] = 0x80
              cmos[0x16] = 0x02
              cmos[0x17] = 0x00
              cmos[0x18] = 0xFC
              cmos[0x19] = 0x2F
              cmos[0x1B] = 0x00
              cmos[0x1C] = 0x04
              cmos[0x1D] = 0x10
              cmos[0x20] = 0xC8
              cmos[0x21] = 0x00
              cmos[0x22] = 0x04
              cmos[0x23] = 0x3F
              cmos[0x2D] = 0x20
              cmos[0x30] = 0x00
              cmos[0x31] = 0xFC
              cmos[0x32] = 0x20
              cmos[0x34] = 0x00
              cmos[0x35] = 0x07
              cmos[0x37] = 0x20
              cmos[0x38] = 0x20
              cmos[0x3D] = 0x2F
              cmos[0x5B] = 0x00
              cmos[0x5C] = 0x07
            end
          end

          def seed_cmos_datetime!(cmos, time = Time.now.getlocal)
            seconds = time.sec
            seconds = 1 if time.hour.zero? && time.min.zero? && seconds.zero?

            cmos[0x00] = encode_cmos_bcd(seconds)
            cmos[0x02] = encode_cmos_bcd(time.min)
            cmos[0x04] = encode_cmos_bcd(time.hour)
            cmos[0x06] = encode_cmos_bcd(time.wday.zero? ? 7 : time.wday)
            cmos[0x07] = encode_cmos_bcd(time.day)
            cmos[0x08] = encode_cmos_bcd(time.month)
            cmos[0x09] = encode_cmos_bcd(time.year % 100)
            cmos[0x32] = encode_cmos_bcd(time.year / 100)
          end

          def encode_cmos_bcd(value)
            normalized = value.to_i.abs
            ((normalized / 10) << 4) | (normalized % 10)
          end

          def set_pit_reload(value)
            reload = value.to_i.zero? ? 65_536 : value.to_i
            @pit_reload = reload
            @pit_counter = reload
          end

          def program_pit_control(byte)
            channel = (byte >> 6) & 0x03
            return unless channel.zero?

            @pit_access_mode =
              case (byte >> 4) & 0x03
              when 0x01 then :low
              when 0x02 then :high
              when 0x03 then :lohi
              else :latch
              end
            @pit_next_write_low = true
            @pit_pending_low_byte = 0
          end

          def write_pit_counter_byte(byte)
            case @pit_access_mode
            when :low
              set_pit_reload((@pit_reload & 0xFF00) | byte)
            when :high
              set_pit_reload((@pit_reload & 0x00FF) | (byte << 8))
            when :lohi
              if @pit_next_write_low
                @pit_pending_low_byte = byte
                @pit_next_write_low = false
              else
                set_pit_reload((byte << 8) | @pit_pending_low_byte)
                @pit_next_write_low = true
              end
            end
          end

          def little_endian_word(addr)
            4.times.sum do |idx|
              byte_addr = addr + idx
              byte = if @rom.key?(byte_addr)
                @rom.fetch(byte_addr)
              else
                @memory.fetch(byte_addr, 0)
              end
              byte << (idx * 8)
            end
          end
        end

        def run_fetch_words(max_cycles: DEFAULT_MAX_CYCLES)
          capture_run_stats(operation: :run_fetch_words, cycles: max_cycles) do
            run_fetch_trace(max_cycles: max_cycles).map(&:word)
          end
        end

        def run_fetch_trace(max_cycles: DEFAULT_MAX_CYCLES)
          capture_run_stats(operation: :run_fetch_trace, cycles: max_cycles) do
            stdout = run_harness(max_cycles: max_cycles)
            parse_fetch_trace(stdout)
          end
        end

        def run_fetch_groups(max_cycles: DEFAULT_MAX_CYCLES)
          capture_run_stats(operation: :run_fetch_groups, cycles: max_cycles) do
            run_fetch_trace(max_cycles: max_cycles).map do |event|
              FetchGroupEvent.new(
                address: event.address,
                bytes: word_to_bytes(event.word)
              )
            end
          end
        end

        def run_fetch_pc_groups(max_cycles: DEFAULT_MAX_CYCLES)
          capture_run_stats(operation: :run_fetch_pc_groups, cycles: max_cycles) do
            run_fetch_groups(max_cycles: max_cycles).map do |event|
              next if event.address < IrRunner::STARTUP_CS_BASE

              FetchPcGroupEvent.new(
                pc: event.address - IrRunner::STARTUP_CS_BASE,
                bytes: event.bytes
              )
            end.compact
          end
        end

        def run_step_trace(max_cycles: DEFAULT_MAX_CYCLES)
          capture_run_stats(operation: :run_step_trace, cycles: max_cycles) do
            parse_step_trace(run_harness(max_cycles: max_cycles))
          end
        end

        def run_final_state(max_cycles: DEFAULT_MAX_CYCLES)
          capture_run_stats(operation: :run_final_state, cycles: max_cycles) do
            parse_final_state(run_harness(max_cycles: max_cycles))
          end
        end

        private

        def build_imported_parity!(mlir_text, work_dir:)
          @work_dir = File.expand_path(work_dir)
          FileUtils.mkdir_p(@work_dir)

          mlir_path = File.join(@work_dir, 'cpu_parity.mlir')
          verilog_path = File.join(@work_dir, 'cpu_parity.v')
          cpp_path = File.join(@work_dir, 'cpu_parity_tb.cpp')
          obj_dir = File.join(@work_dir, 'obj_dir')

          File.write(mlir_path, mlir_text)

          firtool_stdout, firtool_stderr, firtool_status = Open3.capture3(
            'firtool',
            mlir_path,
            '--verilog',
            '-o',
            verilog_path
          )
          unless firtool_status.success?
            raise "firtool export failed:\n#{firtool_stdout}\n#{firtool_stderr}"
          end

          File.write(cpp_path, verilator_harness_cpp)

          verilator_cmd = [
            'verilator',
            '--cc',
            '--top-module', 'ao486',
            '--x-assign', '0',
            '--x-initial', '0',
            '-Wno-fatal',
            '-Wno-UNOPTFLAT',
            '-Wno-PINMISSING',
            '-Wno-WIDTHEXPAND',
            '-Wno-WIDTHTRUNC',
            '--Mdir', obj_dir,
            verilog_path,
            '--exe', cpp_path
          ]
          stdout, stderr, status = Open3.capture3(*verilator_cmd)
          raise "Verilator compile failed:\n#{stdout}\n#{stderr}" unless status.success?

          make_stdout, make_stderr, make_status = Open3.capture3('make', '-C', obj_dir, '-f', 'Vao486.mk')
          raise "Verilator make failed:\n#{make_stdout}\n#{make_stderr}" unless make_status.success?

          @binary_path = File.join(obj_dir, 'Vao486')
        end

        def run_harness(max_cycles:)
          raise 'Verilator binary not built' unless @binary_path && File.exist?(@binary_path)

          memory_path = File.join(@work_dir, 'memory_init.txt')
          write_memory_file(memory_path)

          stdout, stderr, status = Open3.capture3(@binary_path, memory_path, max_cycles.to_i.to_s)
          raise "Verilator parity runner failed:\n#{stdout}\n#{stderr}" unless status.success?

          replace_memory!(read_memory_file(memory_path))
          stdout
        end

        def replace_memory!(new_memory)
          memory_store.clear
          new_memory.each do |addr, byte|
            memory_store[addr] = byte
          end
        end

        def write_memory_file(path)
          lines = memory_store.keys.sort.map do |addr|
            format('%08X %02X', addr, memory_store.fetch(addr))
          end
          File.write(path, lines.join("\n") + "\n")
        end

        def read_memory_file(path)
          mem = Hash.new(0)
          File.readlines(path, chomp: true).each do |line|
            next if line.empty?

            addr_hex, byte_hex = line.split(/\s+/, 2)
            next unless addr_hex && byte_hex

            mem[addr_hex.to_i(16)] = byte_hex.to_i(16) & 0xFF
          end
          mem
        end

        def parse_fetch_trace(stdout)
          stdout.lines.filter_map do |line|
            match = line.to_s.strip.match(/\Afetch_word 0x([0-9A-Fa-f]+) 0x([0-9A-Fa-f]+)\z/)
            next unless match

            FetchWordEvent.new(
              address: match[1].to_i(16),
              word: match[2].to_i(16)
            )
          end
        end

        def parse_step_trace(stdout)
          stdout.lines.filter_map do |line|
            match = line.to_s.strip.match(/\Astep_trace 0x([0-9A-Fa-f]+) 0x([0-9A-Fa-f]+)\z/)
            next unless match

            wr_eip = match[1].to_i(16)
            consumed = match[2].to_i(16)
            start_eip = wr_eip - consumed

            StepEvent.new(
              eip: start_eip,
              consumed: consumed,
              bytes: read_bytes(IrRunner::STARTUP_CS_BASE + start_eip, consumed)
            )
          end
        end

        def parse_final_state(stdout)
          stdout.lines.each_with_object({}) do |line, state|
            match = line.to_s.strip.match(/\Afinal_state ([A-Za-z0-9_]+) 0x([0-9A-Fa-f]+)\z/)
            next unless match

            state[match[1]] = match[2].to_i(16)
          end
        end

        def word_to_bytes(word)
          Array.new(4) { |idx| (word >> (idx * 8)) & 0xFF }
        end

        def verilator_harness_cpp
          <<~CPP
            #include "Vao486.h"
            #include "verilated.h"

            #include <cstdint>
            #include <cstdio>
            #include <cstdlib>
            #include <fstream>
            #include <iomanip>
            #include <string>
            #include <unordered_map>

            struct BurstState {
              bool active = false;
              bool started = false;
              uint32_t base = 0;
              int beat_index = 0;
              int beats_total = 8;
            };

            static std::unordered_map<uint32_t, uint8_t> load_memory(const char* path) {
              std::unordered_map<uint32_t, uint8_t> mem;
              std::ifstream in(path);
              if (!in) {
                std::fprintf(stderr, "failed to open memory file: %s\\n", path);
                std::exit(2);
              }

              uint32_t addr = 0;
              unsigned value = 0;
              while (in >> std::hex >> addr >> value) {
                mem[addr] = static_cast<uint8_t>(value & 0xFFu);
              }
              return mem;
            }

            static uint32_t little_endian_word(const std::unordered_map<uint32_t, uint8_t>& mem, uint32_t addr) {
              uint32_t word = 0;
              for (int idx = 0; idx < 4; ++idx) {
                auto it = mem.find(addr + static_cast<uint32_t>(idx));
                uint32_t byte = (it == mem.end()) ? 0u : static_cast<uint32_t>(it->second);
                word |= (byte << (idx * 8));
              }
              return word;
            }

            static void write_word(std::unordered_map<uint32_t, uint8_t>& mem, uint32_t addr, uint32_t word, uint32_t byteenable) {
              for (int idx = 0; idx < 4; ++idx) {
                if (((byteenable >> idx) & 1u) == 0u) continue;
                mem[addr + static_cast<uint32_t>(idx)] = static_cast<uint8_t>((word >> (idx * 8)) & 0xFFu);
              }
            }

            static void save_memory(const char* path, const std::unordered_map<uint32_t, uint8_t>& mem) {
              std::ofstream out(path, std::ios::trunc);
              if (!out) {
                std::fprintf(stderr, "failed to write memory file: %s\\n", path);
                std::exit(3);
              }

              out << std::uppercase << std::hex << std::setfill('0');
              for (const auto& entry : mem) {
                out << std::setw(8) << static_cast<unsigned>(entry.first)
                    << ' '
                    << std::setw(2) << static_cast<unsigned>(entry.second)
                    << "\\n";
              }
            }

            static void apply_defaults(Vao486* dut) {
              dut->a20_enable = 1;
              dut->cache_disable = 1;
              dut->interrupt_do = 0;
              dut->interrupt_vector = 0;
              dut->avm_waitrequest = 0;
              dut->avm_readdatavalid = 0;
              dut->avm_readdata = 0;
              dut->dma_address = 0;
              dut->dma_16bit = 0;
              dut->dma_write = 0;
              dut->dma_writedata = 0;
              dut->dma_read = 0;
              dut->io_read_data = 0;
              dut->io_read_done = 0;
              dut->io_write_done = 0;
            }

            int main(int argc, char** argv) {
              if (argc < 3) {
                std::fprintf(stderr, "usage: %s <memory_init.txt> <max_cycles>\\n", argv[0]);
                return 2;
              }

              Verilated::commandArgs(argc, argv);
              auto mem = load_memory(argv[1]);
              int max_cycles = std::atoi(argv[2]);

              Vao486* dut = new Vao486();
              apply_defaults(dut);

              dut->clk = 0;
              dut->rst_n = 0;
              dut->eval();
              dut->clk = 1;
              dut->eval();

              BurstState burst;
              uint32_t prev_trace_wr_eip = 0;
              uint32_t prev_trace_wr_consumed = 0;

              auto emit_step_trace = [&]() {
                if (dut->trace_retired &&
                    !(dut->trace_wr_eip == 0 && dut->trace_wr_consumed == 0) &&
                    !(dut->trace_wr_eip == prev_trace_wr_eip &&
                      dut->trace_wr_consumed == prev_trace_wr_consumed)) {
                  std::printf("step_trace 0x%08X 0x%08X\\n",
                              static_cast<uint32_t>(dut->trace_wr_eip),
                              static_cast<uint32_t>(dut->trace_wr_consumed));
                  prev_trace_wr_eip = static_cast<uint32_t>(dut->trace_wr_eip);
                  prev_trace_wr_consumed = static_cast<uint32_t>(dut->trace_wr_consumed);
                }
              };

              for (int cycle = 0; cycle < max_cycles; ++cycle) {
                bool deliver_read_beat = burst.active && burst.started;
                if (deliver_read_beat) {
                  uint32_t addr = burst.base + static_cast<uint32_t>(burst.beat_index * 4);
                  dut->avm_readdatavalid = 1;
                  dut->avm_readdata = little_endian_word(mem, addr);
                } else {
                  dut->avm_readdatavalid = 0;
                  dut->avm_readdata = 0;
                }

                dut->clk = 0;
                dut->rst_n = 1;
                dut->eval();

                if (!burst.active && dut->avm_read) {
                  burst.active = true;
                  burst.started = false;
                  burst.base = static_cast<uint32_t>(dut->avm_address) << 2;
                  burst.beat_index = 0;
                  burst.beats_total = static_cast<int>(dut->avm_burstcount);
                  if (burst.beats_total <= 0) burst.beats_total = 1;
                }

                dut->clk = 1;
                dut->eval();

                if (dut->avm_write) {
                  write_word(
                    mem,
                    static_cast<uint32_t>(dut->avm_address) << 2,
                    static_cast<uint32_t>(dut->avm_writedata),
                    static_cast<uint32_t>(dut->avm_byteenable)
                  );
                }

                if (dut->avm_readdatavalid) {
                  std::printf("fetch_word 0x%08X 0x%08X\\n",
                              burst.base + static_cast<uint32_t>(burst.beat_index * 4),
                              static_cast<uint32_t>(dut->avm_readdata));
                }

                emit_step_trace();

                if (burst.active) {
                  if (deliver_read_beat) {
                    burst.beat_index += 1;
                    if (burst.beat_index >= burst.beats_total) {
                      burst = BurstState{};
                    }
                  } else {
                    burst.started = true;
                  }
                }
              }

              const char* final_state_names[] = {
                "trace_arch_new_export",
                "trace_arch_eax",
                "trace_arch_ebx",
                "trace_arch_ecx",
                "trace_arch_edx",
                "trace_arch_esi",
                "trace_arch_edi",
                "trace_arch_esp",
                "trace_arch_ebp",
                "trace_arch_eip",
                "trace_wr_eip",
                "trace_wr_consumed",
                "trace_wr_hlt_in_progress",
                "trace_wr_finished",
                "trace_wr_ready",
                "trace_retired"
              };
              const uint32_t final_state_values[] = {
                static_cast<uint32_t>(dut->trace_arch_new_export),
                static_cast<uint32_t>(dut->trace_arch_eax),
                static_cast<uint32_t>(dut->trace_arch_ebx),
                static_cast<uint32_t>(dut->trace_arch_ecx),
                static_cast<uint32_t>(dut->trace_arch_edx),
                static_cast<uint32_t>(dut->trace_arch_esi),
                static_cast<uint32_t>(dut->trace_arch_edi),
                static_cast<uint32_t>(dut->trace_arch_esp),
                static_cast<uint32_t>(dut->trace_arch_ebp),
                static_cast<uint32_t>(dut->trace_arch_eip),
                static_cast<uint32_t>(dut->trace_wr_eip),
                static_cast<uint32_t>(dut->trace_wr_consumed),
                static_cast<uint32_t>(dut->trace_wr_hlt_in_progress),
                static_cast<uint32_t>(dut->trace_wr_finished),
                static_cast<uint32_t>(dut->trace_wr_ready),
                static_cast<uint32_t>(dut->trace_retired)
              };

              for (size_t idx = 0; idx < sizeof(final_state_values) / sizeof(final_state_values[0]); ++idx) {
                std::printf("final_state %s 0x%08X\\n", final_state_names[idx], final_state_values[idx]);
              }

              save_memory(argv[1], mem);

              delete dut;
              return 0;
            }
          CPP
        end
      end
    end
  end
end
