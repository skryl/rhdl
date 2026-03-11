# frozen_string_literal: true

require 'open3'
require 'fileutils'

require 'rhdl/codegen'
require 'rhdl/codegen/verilog/sim/verilog_simulator'
require 'fiddle'

require_relative 'ir_runner'

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
          def runtime_bundle
            mutex.synchronize do
              @runtime_bundle ||= build_runtime_bundle
            end
          end

          private

          def mutex
            @mutex ||= Mutex.new
          end

          def build_runtime_bundle
            out_dir = Dir.mktmpdir('rhdl_ao486_verilator_out')
            workspace_dir = Dir.mktmpdir('rhdl_ao486_verilator_ws')
            build_dir = File.join(BUILD_ROOT, 'ao486_runner')
            FileUtils.mkdir_p(build_dir)

            import_result = RHDL::Examples::AO486::Import::CpuImporter.new(
              output_dir: out_dir,
              workspace_dir: workspace_dir,
              keep_workspace: true,
              patch_profile: :runner,
              strict: false
            ).run
            raise Array(import_result.diagnostics).join("\n") unless import_result.success?

            mlir_path = File.join(build_dir, 'ao486_runner.mlir')
            verilog_path = File.join(build_dir, 'verilog', 'ao486_runner.v')
            wrapper_path = File.join(build_dir, 'verilog', 'ao486_runner_wrapper.cpp')
            FileUtils.mkdir_p(File.dirname(verilog_path))
            FileUtils.cp(import_result.normalized_core_mlir_path, mlir_path)

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

            File.write(wrapper_path, wrapper_source)

            simulator = RHDL::Codegen::Verilog::VerilogSimulator.new(
              backend: :verilator,
              build_dir: build_dir,
              library_basename: 'ao486_runner',
              top_module: 'ao486',
              verilator_prefix: 'Vao486',
              x_assign: '0',
              x_initial: '0',
              extra_verilator_flags: ['--public-flat-rw', '-Wno-UNOPTFLAT', '-Wno-PINMISSING', '-Wno-WIDTHEXPAND', '-Wno-WIDTHTRUNC']
            )
            simulator.prepare_build_dirs!
            simulator.compile_backend(verilog_file: verilog_path, wrapper_file: wrapper_path)

            {
              import_result: import_result,
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
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__fetch_valid")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__fetch_valid;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__decoder_count")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT___decode_regs_inst_decoder_count;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__micro_busy")) return root->ao486__DOT__pipeline_inst__DOT__decode_inst__DOT__micro_busy;
                else if (!std::strcmp(name, "pipeline_inst__decode_inst__eip")) return root->ao486__DOT___pipeline_inst_dec_eip;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__rd_eip")) return root->ao486__DOT___pipeline_inst_rd_eip;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__rd_busy")) return root->ao486__DOT__pipeline_inst__DOT___read_inst_rd_busy;
                else if (!std::strcmp(name, "pipeline_inst__read_inst__rd_ready")) return root->ao486__DOT__pipeline_inst__DOT___read_inst_rd_ready;
                else if (!std::strcmp(name, "pipeline_inst__execute_inst__exe_eip")) return root->ao486__DOT__pipeline_inst__DOT___execute_inst_exe_eip_final;
                else if (!std::strcmp(name, "memory_inst__prefetch_inst__prefetch_address")) return root->ao486__DOT__memory_inst__DOT___prefetch_control_inst_icacheread_address;
                else if (!std::strcmp(name, "memory_inst__prefetch_inst__prefetch_length")) return root->ao486__DOT__memory_inst__DOT___prefetch_inst_prefetch_length;
                else if (!std::strcmp(name, "memory_inst__prefetch_control_inst__prefetchfifo_used")) return root->ao486__DOT__memory_inst__DOT__prefetch_control_inst__DOT__prefetchfifo_used;
                else if (!std::strcmp(name, "memory_inst__icache_inst__readcode_do")) return root->ao486__DOT__memory_inst__DOT___icache_inst_readcode_do;
                else if (!std::strcmp(name, "memory_inst__icache_inst__readcode_address")) return root->ao486__DOT__memory_inst__DOT___icache_inst_readcode_address;
                else if (!std::strcmp(name, "memory_inst__icache_inst__prefetched_do")) return root->ao486__DOT__memory_inst__DOT___icache_inst_prefetched_do;
                else if (!std::strcmp(name, "memory_inst__icache_inst__prefetched_length")) return root->ao486__DOT__memory_inst__DOT___icache_inst_prefetched_length;
                else if (!std::strcmp(name, "memory_inst__icache_inst__reset_prefetch")) return root->ao486__DOT__memory_inst__DOT___icache_inst_reset_prefetch;
                else if (!std::strcmp(name, "memory_inst__icache_inst__prefetchfifo_write_do")) return root->ao486__DOT__memory_inst__DOT___icache_inst_prefetchfifo_write_do;
                else if (!std::strcmp(name, "memory_inst__prefetch_inst__prefetchfifo_signal_limit_do")) return root->ao486__DOT__memory_inst__DOT___prefetch_inst_prefetchfifo_signal_limit_do;
                else if (!std::strcmp(name, "memory_inst__tlb_inst__prefetchfifo_signal_pf_do")) return root->ao486__DOT__memory_inst__DOT___tlb_inst_prefetchfifo_signal_pf_do;
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
                else if (!std::strcmp(name, "trace_fetch_bytes")) return ctx->dut->trace_fetch_bytes;
                else if (!std::strcmp(name, "memory_inst__icache_inst__prefetchfifo_write_data")) return root->ao486__DOT__memory_inst__DOT___icache_inst_prefetchfifo_write_data;
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

        def self.build_from_cleaned_mlir(mlir_text, work_dir:)
          new(headless: true).tap do |runner|
            runner.send(:build_imported_parity!, mlir_text, work_dir: work_dir)
          end
        end

        def initialize(**kwargs)
          super(runner_backend: :verilator, **kwargs)
          @work_dir = nil
          @binary_path = nil
        end

        def simulator_type
          :ao486_verilator
        end

        def ensure_sim!
          return @sim if @sim

          bundle = self.class.runtime_bundle
          @sim = SimBridge.new(bundle.fetch(:library_path))
          sync_loaded_artifacts_to_sim!
          sync_runtime_windows!
          @runtime_loaded = true
          @sim
        end

        class SimBridge
          BIOS_TICKS_PER_DAY = 0x0018_00B0
          FLOPPY_HEADS = 2
          FLOPPY_SECTORS_PER_TRACK = 18
          FLOPPY_BYTES_PER_SECTOR = 512
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
          WIDE_SIGNAL_NAMES = %w[trace_cs_cache pipeline_inst__decode_inst__cs_cache trace_fetch_bytes].freeze

          ReadBurst = Struct.new(:base, :beat_index, :beats_total, :started, keyword_init: true)

          def initialize(library_path)
            @lib = Fiddle.dlopen(library_path)
            @sim_create = Fiddle::Function.new(@lib['sim_create'], [], Fiddle::TYPE_VOIDP)
            @sim_destroy = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_eval = Fiddle::Function.new(@lib['sim_eval'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_poke = Fiddle::Function.new(@lib['sim_poke'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT], Fiddle::TYPE_VOID)
            @sim_peek_u32 = Fiddle::Function.new(@lib['sim_peek_u32'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_UINT)
            @sim_peek_u64 = Fiddle::Function.new(@lib['sim_peek_u64'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG_LONG)
            @ctx = @sim_create.call
            @memory = Hash.new(0)
            @rom = {}
            @disk = {}
            reset_host_state!
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
            load_store!(@disk, data, offset)
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
              reset_active = @reset_cycles_remaining.positive?
              irq_vector = reset_active ? nil : active_irq_vector
              @last_irq_vector = irq_vector if irq_vector
              read_response = if !reset_active && @pending_read_burst&.started
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
              retargeted = retarget_code_burst_if_needed
              if retargeted
                poke('avm_readdatavalid', 0)
                poke('avm_readdata', 0)
                evaluate
              end

              current_io_read_do = !reset_active && peek('io_read_do') != 0
              current_io_write_do = !reset_active && peek('io_write_do') != 0

              unless reset_active
                arm_read_burst_if_needed
                queue_io_requests_if_needed(current_io_read_do, current_io_write_do)
              end

              poke('clk', 1)
              evaluate

              unless reset_active
                commit_memory_write_if_needed
                handle_interrupt_ack
                maybe_seed_post_init_ivt
                advance_timers
              end
              advance_read_burst(retargeted ? false : !read_response.nil?)
              @reset_cycles_remaining = [@reset_cycles_remaining - 1, 0].max
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

          def runner_ao486_dos_int13_state
            {
              ax: @dos_int13_ax,
              bx: @dos_int13_bx,
              cx: @dos_int13_cx,
              dx: @dos_int13_dx,
              es: @dos_int13_es,
              result_ax: @dos_int13_result_ax,
              flags: @dos_int13_result_flags
            }
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
              result_ax: @dos_int1a_result_ax,
              flags: @dos_int1a_result_flags
            }
          end

          private

          def reset_host_state!
            @cmos = Array.new(128, 0)
            @cmos[0x10] = 0x40
            @pic_master_mask = 0xFF
            @pic_slave_mask = 0xFF
            @pic_master_pending = 0
            @pic_master_in_service = 0
            @pic_master_base = 0x08
            @pit_reload = 0
            @pit_counter = 0
            @pending_read_burst = nil
            @pending_io_read_data = nil
            @pending_io_write_ack = false
            @post_init_ivt_seeded = false
            @dos_int13_ax = @dos_int13_bx = @dos_int13_cx = @dos_int13_dx = @dos_int13_es = 0
            @dos_int13_result_ax = @dos_int13_result_bx = @dos_int13_result_cx = @dos_int13_result_dx = 0
            @dos_int13_result_flags = 0
            @dos_int10_ax = @dos_int10_bx = @dos_int10_cx = @dos_int10_dx = @dos_int10_bp = @dos_int10_es = 0
            @dos_int10_result_ax = @dos_int10_result_bx = @dos_int10_result_cx = @dos_int10_result_dx = 0
            @dos_int16_ax = @dos_int16_result_ax = @dos_int16_result_flags = 0
            @dos_int1a_ax = @dos_int1a_cx = @dos_int1a_dx = 0
            @dos_int1a_result_ax = @dos_int1a_result_cx = @dos_int1a_result_dx = @dos_int1a_result_flags = 0
            @keyboard_queue = []
            @keyboard_scan_queue = []
            @text_dirty = false
            @prev_io_read_do = false
            @prev_io_write_do = false
            @last_io_read_meta = nil
            @last_io_write_meta = nil
            @last_irq_vector = nil
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

          def commit_memory_write_if_needed
            return if peek('avm_write').zero?

            addr = peek('avm_address') << 2
            data = peek('avm_writedata') & 0xFFFF_FFFF
            byteenable = peek('avm_byteenable') & 0xF
            4.times do |index|
              next if ((byteenable >> index) & 1).zero?

              @memory[addr + index] = (data >> (index * 8)) & 0xFF
            end
          end

          def arm_read_burst_if_needed
            return if @pending_read_burst || peek('avm_read').zero?

            is_code_read = current_avm_read_is_code_burst?
            beats_total = is_code_read ? 8 : [peek('avm_burstcount'), 1].max
            base = if is_code_read
              peek('memory_inst__icache_inst__readcode_address') & ~0x3
            else
              peek('avm_address') << 2
            end
            @pending_read_burst = ReadBurst.new(base: base, beat_index: 0, beats_total: beats_total, started: false)
          end

          def retarget_code_burst_if_needed
            return false unless current_avm_read_is_code_burst?
            return false unless @pending_read_burst
            return false if @pending_read_burst.beats_total != 8 || @pending_read_burst.started

            target = peek('memory_inst__icache_inst__readcode_address') & ~0x3
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
              @pending_read_burst = nil if @pending_read_burst.beat_index >= @pending_read_burst.beats_total
            else
              @pending_read_burst.started = true
            end
          end

          def current_avm_read_is_code_burst?
            peek('avm_read') != 0 &&
              peek('memory_inst__icache_inst__readcode_do') != 0 &&
              peek('avm_burstcount') >= 8
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
            write_interrupt_vector(0x15, 0xF000, 0xF859)
            write_interrupt_vector(0x17, 0xF000, 0xEFD2)
            write_interrupt_vector(0x18, 0xF000, 0x8666)
            {
              0x08 => 0xFEA5, 0x09 => 0xE987, 0x0E => 0xEF57, 0x10 => 0xF065,
              0x13 => 0xE3FE, 0x14 => 0xE739, 0x16 => 0xE82E, 0x1A => 0xFE6E,
              0x40 => 0xEC59, 0x70 => 0xFE6E, 0x71 => 0xE987, 0x75 => 0xE2C3
            }.each { |vector, offset| write_interrupt_vector(vector, 0xF000, offset) }
            write_interrupt_vector(0x19, @disk.empty? ? 0xF000 : 0x0000, @disk.empty? ? 0xE6F2 : VerilatorRunner::DOS_INT19_STUB_ADDR)
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
              when 0x40 then set_pit_reload((@pit_reload & 0xFF00) | byte)
              when 0x70 then @cmos_index = byte & 0x7F
              when 0x71 then @cmos[@cmos_index & 0x7F] = byte
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
              when 0x08 then execute_dos_int13_get_parameters
              when 0x15 then execute_dos_int13_get_drive_type
              when 0x16 then execute_dos_int13_get_change_line_status
              else
                @dos_int13_result_flags = 1
                @memory[0x0441] = 0x01
                0x0100
              end
          end

          def execute_dos_int13_reset
            @memory[0x0441] = 0x00
            @memory[0x0442] = 0x20
            0
          end

          def execute_dos_int13_read_status
            status = @memory.fetch(0x0441, 0)
            @dos_int13_result_flags = status.zero? ? 0 : 1
            status << 8
          end

          def execute_dos_int13_read
            count = @dos_int13_ax & 0xFF
            buffer = (@dos_int13_es << 4) + @dos_int13_bx
            cl = @dos_int13_cx & 0xFF
            ch = (@dos_int13_cx >> 8) & 0xFF
            head = (@dos_int13_dx >> 8) & 0xFF
            sector = cl & 0x3F
            cylinder = ch
            if count.zero? || head >= FLOPPY_HEADS || sector.zero? || sector > FLOPPY_SECTORS_PER_TRACK
              @dos_int13_result_flags = 1
              @memory[0x0441] = 0x01
              return 0x0100
            end
            start_lba = ((cylinder * FLOPPY_HEADS) + head) * FLOPPY_SECTORS_PER_TRACK + (sector - 1)
            byte_count = count * FLOPPY_BYTES_PER_SECTOR
            disk_offset = start_lba * FLOPPY_BYTES_PER_SECTOR
            byte_count.times do |index|
              @memory[buffer + index] = @disk.fetch(disk_offset + index, 0)
            end
            @memory[0x0441] = 0
            @dos_int13_result_flags = 0
            count
          end

          def execute_dos_int13_get_parameters
            @dos_int13_result_bx = 0x0400
            @dos_int13_result_cx = (79 << 8) | FLOPPY_SECTORS_PER_TRACK
            @dos_int13_result_dx = ((FLOPPY_HEADS - 1) << 8) | 0x0002
            @memory[0x0441] = 0
            0
          end

          def execute_dos_int13_get_drive_type
            @dos_int13_result_flags = 0
            0x0100
          end

          def execute_dos_int13_get_change_line_status
            @memory[0x0441] = 0x06
            @dos_int13_result_flags = 1
            0x0600
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
            when 0x02 then set_cursor_position_for_page(page, (@dos_int10_dx >> 8) & 0xFF, @dos_int10_dx & 0xFF)
            when 0x03
              row, col = cursor_position_for_page(page)
              @dos_int10_result_cx = 0x0607
              @dos_int10_result_dx = (row << 8) | col
            when 0x05 then set_active_video_page(@dos_int10_ax & 0xFF)
            when 0x06, 0x07
              if (@dos_int10_ax & 0xFF).zero?
                active_page = active_video_page
                clear_text_screen_for_page(active_page)
                set_cursor_position_for_page(active_page, 0, 0)
              end
            when 0x0E then video_teletype(page, @dos_int10_ax & 0xFF)
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
              @dos_int16_result_flags = 1
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

          def set_pit_reload(value)
            reload = value.to_i.zero? ? 65_536 : value.to_i
            @pit_reload = reload
            @pit_counter = reload
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
