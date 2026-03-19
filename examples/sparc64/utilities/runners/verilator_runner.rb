# frozen_string_literal: true

# SPARC64 Standard-ABI Verilator Runner
#
# Uses the standard runner ABI (lib/rhdl/sim/native/abi.rb) instead of the
# custom SharedRuntimeSupport adapter.  The C++ wrapper exports the canonical
# sim_create / sim_signal / sim_exec / sim_blob / runner_* functions so the
# shared library can be loaded through Verilator::Runtime.open and validated
# with ensure_runner_abi!.
#
# The Wishbone protocol logic is identical to the legacy VerilogRunner but is
# now wrapped inside standard ABI dispatch functions.

require 'digest'
require 'fiddle'
require 'fileutils'
require 'json'
require 'rbconfig'
require 'rhdl/codegen'
require 'rhdl/sim/native/verilog/verilator/runtime'

require_relative '../integration/constants'
require_relative '../integration/import_loader'
require_relative '../integration/staged_verilog_bundle'

module RHDL
  module Examples
    module SPARC64
      class VerilatorRunner
        include Integration

        GENERATED_SOURCE_BUILD_ROOT = File.expand_path('../../.verilator_std_build', __dir__).freeze
        GeneratedSourceBundle = Struct.new(
          :build_dir,
          :staged_root,
          :top_module,
          :top_file,
          :include_dirs,
          :source_files,
          :verilator_args,
          :fast_boot,
          keyword_init: true
        )

        INPUT_SIGNAL_WIDTHS = {
          'sys_clock_i' => 1,
          'sys_reset_i' => 1,
          'eth_irq_i' => 1,
          'wbm_ack_i' => 1,
          'wbm_data_i' => 64
        }.freeze

        OUTPUT_SIGNAL_WIDTHS = {
          'wbm_cycle_o' => 1,
          'wbm_strobe_o' => 1,
          'wbm_we_o' => 1,
          'wbm_sel_o' => 8,
          'wbm_addr_o' => 64,
          'wbm_data_o' => 64
        }.freeze

        DEBUG_SIGNAL_WIDTHS = {
          'os2wb_inst__state' => 5,
          'os2wb_inst__cpx_ready' => 1,
          'os2wb_inst__cpu' => 1,
          'os2wb_inst__pcx_req_d' => 5,
          'os2wb_inst__wb_cycle' => 1,
          'os2wb_inst__wb_strobe' => 1,
          'os2wb_inst__wb_we' => 1,
          'os2wb_inst__wb_addr' => 64,
          'sparc_0__ifu__errdp__fdp_erb_pc_f' => 48,
          'sparc_0__tlu__misctl__ifu_npc_w' => 49,
          'sparc_0__ifu__swl__thrfsm0__thr_state' => 5,
          'sparc_0__ifu__swl__thrfsm1__thr_state' => 5,
          'sparc_0__ifu__swl__thrfsm2__thr_state' => 5,
          'sparc_0__ifu__swl__thrfsm3__thr_state' => 5,
          'sparc_0__ifu__swl__dtu_fcl_nextthr_bf' => 4,
          'sparc_0__ifu__swl__completion' => 4,
          'sparc_0__ifu__swl__schedule' => 4,
          'sparc_0__ifu__swl__int_activate' => 4,
          'sparc_0__ifu__swl__start_thread' => 4,
          'sparc_0__ifu__swl__thaw_thread' => 4,
          'sparc_0__ifu__swl__resum_thread' => 4,
          'sparc_0__ifu__swl__rdy' => 4,
          'sparc_0__ifu__swl__retr_thr_wakeup' => 4,
          'sparc_0__ifu__fcl__rune_ff__q' => 1,
          'sparc_0__ifu__fcl__rund_ff__q' => 1,
          'sparc_0__ifu__fcl__runm_ff__q' => 1,
          'sparc_0__ifu__fcl__runw_ff__q' => 1,
          'sparc_1__ifu__errdp__fdp_erb_pc_f' => 48,
          'sparc_1__tlu__misctl__ifu_npc_w' => 49,
          'sparc_1__ifu__swl__thrfsm0__thr_state' => 5,
          'sparc_1__ifu__swl__thrfsm1__thr_state' => 5,
          'sparc_1__ifu__swl__thrfsm2__thr_state' => 5,
          'sparc_1__ifu__swl__thrfsm3__thr_state' => 5,
          'sparc_1__ifu__swl__dtu_fcl_nextthr_bf' => 4,
          'sparc_1__ifu__swl__completion' => 4,
          'sparc_1__ifu__swl__schedule' => 4,
          'sparc_1__ifu__swl__int_activate' => 4,
          'sparc_1__ifu__swl__start_thread' => 4,
          'sparc_1__ifu__swl__thaw_thread' => 4,
          'sparc_1__ifu__swl__resum_thread' => 4,
          'sparc_1__ifu__swl__rdy' => 4,
          'sparc_1__ifu__swl__retr_thr_wakeup' => 4,
          'sparc_1__ifu__fcl__rune_ff__q' => 1,
          'sparc_1__ifu__fcl__rund_ff__q' => 1,
          'sparc_1__ifu__fcl__runm_ff__q' => 1,
          'sparc_1__ifu__fcl__runw_ff__q' => 1
        }.freeze

        SIGNAL_WIDTHS = INPUT_SIGNAL_WIDTHS.merge(OUTPUT_SIGNAL_WIDTHS).merge(DEBUG_SIGNAL_WIDTHS).freeze

        VERILATOR_WARNING_FLAGS = %w[
          --no-timing
          -Wno-fatal
          -Wno-ASCRANGE
          -Wno-MULTIDRIVEN
          -Wno-PINMISSING
          -Wno-WIDTHEXPAND
          -Wno-WIDTHTRUNC
          -Wno-UNOPTFLAT
          -Wno-CASEINCOMPLETE
          --public-flat-rw
        ].freeze

        VERILATOR_DEFAULT_FLAGS = %w[
          -DFPGA_SYN
          -DCMP_CLK_PERIOD=1333
        ].freeze

        attr_reader :sim, :clock_count, :source_kind

        def initialize(fast_boot: true,
                       source_kind: :staged_verilog,
                       source_bundle: nil, source_bundle_class: Integration::StagedVerilogBundle,
                       source_bundle_options: {},
                       import_dir: nil,
                       build_cache_root: Integration::ImportLoader::DEFAULT_BUILD_CACHE_ROOT,
                       reference_root: Integration::ImportLoader::DEFAULT_REFERENCE_ROOT,
                       import_top: Integration::ImportLoader::DEFAULT_IMPORT_TOP,
                       import_top_file: nil,
                       top: 'S1Top',
                       component_class: nil,
                       compile_now: true,
                       threads: 1)
          @source_kind = normalize_source_kind(source_kind)
          @threads = RHDL::Codegen::Verilog::VerilogSimulator.normalize_threads(threads)
          @source_bundle = source_bundle || resolve_source_bundle(
            fast_boot: fast_boot,
            source_bundle_class: source_bundle_class,
            source_bundle_options: source_bundle_options,
            import_dir: import_dir,
            build_cache_root: build_cache_root,
            reference_root: reference_root,
            import_top: import_top,
            import_top_file: import_top_file,
            top: top,
            component_class: component_class
          )
          @top_module = @source_bundle.top_module
          @verilator_prefix = "V#{@top_module}"
          @clock_count = 0

          build_and_load if compile_now
        end

        def native?
          true
        end

        def simulator_type
          :hdl_verilator
        end

        def backend
          :verilator
        end

        def reset!
          @sim.reset
          @clock_count = 0
          self
        end

        def run_cycles(n)
          result = @sim.runner_run_cycles(n.to_i)
          return nil unless result

          @clock_count += result[:cycles_run].to_i
          result
        end

        def load_images(boot_image:, program_image:)
          reset!
          load_flash(boot_image, base_addr: Integration::FLASH_BOOT_BASE)
          load_memory(boot_image, base_addr: 0)
          load_memory(boot_image, base_addr: Integration::BOOT_PROM_ALIAS_BASE)
          load_memory(program_image, base_addr: Integration::PROGRAM_BASE)
          self
        end

        def load_flash(bytes, base_addr: 0)
          @sim.runner_load_rom(bytes, base_addr.to_i)
        end

        def load_memory(bytes, base_addr: 0)
          @sim.runner_load_memory(bytes, base_addr.to_i, false)
        end

        def read_memory(addr, length)
          @sim.runner_read_memory(addr.to_i, length.to_i, mapped: false)
        end

        def write_memory(addr, bytes)
          @sim.runner_write_memory(addr.to_i, bytes, mapped: false)
        end

        def read_u64(addr)
          decode_u64_be(read_memory(addr, 8))
        end

        def write_u64(addr, value)
          write_memory(addr, encode_u64_be(value))
        end

        def mailbox_status
          read_u64(Integration::MAILBOX_STATUS)
        end

        def mailbox_value
          read_u64(Integration::MAILBOX_VALUE)
        end

        def completed?
          mailbox_status != 0
        end

        def run_until_complete(max_cycles:, batch_cycles: 1_000)
          while clock_count < max_cycles.to_i
            run_cycles([batch_cycles.to_i, max_cycles.to_i - clock_count].min)
            return completion_result if completed?

            faults = unmapped_accesses
            return completion_result(faults: faults) if faults.any?
          end

          completion_result(timeout: true)
        end

        def wishbone_trace
          raw = @sim.runner_sparc64_wishbone_trace
          Integration.normalize_wishbone_trace(raw)
        end

        def unmapped_accesses
          Array(@sim.runner_sparc64_unmapped_accesses)
        end

        def debug_snapshot
          {
            reset: {
              cycle_counter: clock_count,
              mailbox_status: mailbox_status,
              mailbox_value: mailbox_value
            },
            bridge: compact_hash({
              state: peek_first('os2wb_inst__state'),
              cpx_ready: peek_bool('os2wb_inst__cpx_ready'),
              cpu: peek_first('os2wb_inst__cpu'),
              pcx_req_d: peek_first('os2wb_inst__pcx_req_d'),
              wb_cycle: peek_bool('os2wb_inst__wb_cycle'),
              wb_strobe: peek_bool('os2wb_inst__wb_strobe'),
              wb_we: peek_bool('os2wb_inst__wb_we'),
              wb_addr: peek_first('os2wb_inst__wb_addr')
            }),
            thread0: thread_debug_snapshot(0),
            thread1: thread_debug_snapshot(1)
          }
        end

        private

        def normalize_source_kind(value)
          case (value || :staged_verilog).to_sym
          when :staged, :staged_verilog
            :staged_verilog
          when :rhdl, :rhdl_verilog
            :rhdl_verilog
          else
            raise ArgumentError,
                  "Unsupported SPARC64 Verilator source #{value.inspect}. Use :staged_verilog or :rhdl_verilog."
          end
        end

        def resolve_source_bundle(fast_boot:, source_bundle_class:, source_bundle_options:, import_dir:, build_cache_root:,
                                  reference_root:, import_top:, import_top_file:, top:, component_class:)
          case source_kind
          when :staged_verilog
            source_bundle_class.new(
              fast_boot: fast_boot,
              **source_bundle_options
            ).build
          when :rhdl_verilog
            build_rhdl_source_bundle!(
              fast_boot: fast_boot,
              import_dir: import_dir,
              build_cache_root: build_cache_root,
              reference_root: reference_root,
              import_top: import_top,
              import_top_file: import_top_file,
              top: top,
              component_class: component_class
            )
          else
            raise ArgumentError, "Unhandled SPARC64 Verilator source kind #{source_kind.inspect}"
          end
        end

        def build_rhdl_source_bundle!(fast_boot:, import_dir:, build_cache_root:, reference_root:, import_top:, import_top_file:,
                                      top:, component_class:)
          resolved_import_dir = import_dir && Integration::ImportLoader.resolve_import_dir(import_dir: import_dir)
          component_class ||= Integration::ImportLoader.load_component_class(
            top: top,
            import_dir: resolved_import_dir,
            fast_boot: fast_boot,
            build_cache_root: build_cache_root,
            reference_root: reference_root,
            import_top: import_top,
            import_top_file: import_top_file
          )
          resolved_import_dir ||= Integration::ImportLoader.loaded_from
          top_module = component_class.respond_to?(:verilog_module_name) ? component_class.verilog_module_name.to_s : import_top.to_s
          build_dir = File.join(
            GENERATED_SOURCE_BUILD_ROOT,
            "#{sanitize_identifier(top_module)}_#{Digest::SHA256.hexdigest([resolved_import_dir, fast_boot, top_module].join('|'))[0, 12]}"
          )
          source_dir = File.join(build_dir, 'source_inputs')
          top_file = File.join(source_dir, "#{sanitize_identifier(top_module)}.v")
          FileUtils.mkdir_p(source_dir)
          write_file_if_changed(top_file, component_class.to_verilog_hierarchy(top_name: top_module))
          GeneratedSourceBundle.new(
            build_dir: build_dir,
            staged_root: source_dir,
            top_module: top_module,
            top_file: top_file,
            include_dirs: [],
            source_files: [],
            verilator_args: [],
            fast_boot: fast_boot
          )
        end

        def completion_result(timeout: false, faults: nil)
          trace = wishbone_trace
          faults ||= unmapped_accesses
          {
            completed: completed?,
            timeout: timeout,
            cycles: clock_count,
            boot_handoff_seen: trace.any? do |event|
              event.op == :read &&
                event.addr.to_i >= Integration::PROGRAM_BASE &&
                event.addr.to_i < Integration::FLASH_BOOT_BASE
            end,
            secondary_core_parked: faults.empty?,
            mailbox_status: mailbox_status,
            mailbox_value: mailbox_value,
            unmapped_accesses: faults,
            wishbone_trace: trace
          }
        end

        def decode_u64_be(bytes)
          arr = Array(bytes)
          return 0 if arr.length < 8

          arr[0, 8].each_with_index.reduce(0) do |acc, (byte, idx)|
            acc | (byte.to_i << ((7 - idx) * 8))
          end
        end

        def encode_u64_be(value)
          (0..7).map { |i| (value >> ((7 - i) * 8)) & 0xFF }
        end

        def thread_debug_snapshot(cpu_index)
          compact_hash({
            fetch_pc_f: peek_first("sparc_#{cpu_index}__ifu__errdp__fdp_erb_pc_f"),
            npc_w: peek_first("sparc_#{cpu_index}__tlu__misctl__ifu_npc_w"),
            scheduler: compact_hash({
              nextthr: peek_first("sparc_#{cpu_index}__ifu__swl__dtu_fcl_nextthr_bf"),
              completion: peek_first("sparc_#{cpu_index}__ifu__swl__completion"),
              schedule: peek_first("sparc_#{cpu_index}__ifu__swl__schedule"),
              int_activate: peek_first("sparc_#{cpu_index}__ifu__swl__int_activate"),
              start_thread: peek_first("sparc_#{cpu_index}__ifu__swl__start_thread"),
              thaw_thread: peek_first("sparc_#{cpu_index}__ifu__swl__thaw_thread"),
              resum_thread: peek_first("sparc_#{cpu_index}__ifu__swl__resum_thread"),
              rdy: peek_first("sparc_#{cpu_index}__ifu__swl__rdy"),
              retr_thr_wakeup: peek_first("sparc_#{cpu_index}__ifu__swl__retr_thr_wakeup")
            }),
            thread_states: (0..3).map do |thread_idx|
              peek_first("sparc_#{cpu_index}__ifu__swl__thrfsm#{thread_idx}__thr_state")
            end.compact,
            run_flags: compact_hash({
              rune: peek_bool("sparc_#{cpu_index}__ifu__fcl__rune_ff__q"),
              rund: peek_bool("sparc_#{cpu_index}__ifu__fcl__rund_ff__q"),
              runm: peek_bool("sparc_#{cpu_index}__ifu__fcl__runm_ff__q"),
              runw: peek_bool("sparc_#{cpu_index}__ifu__fcl__runw_ff__q")
            })
          })
        end

        def peek_first(*candidates)
          return nil unless sim.respond_to?(:has_signal?) && sim.respond_to?(:peek)

          name = candidates.find { |candidate| sim.has_signal?(candidate) }
          return nil unless name

          sim.peek(name)
        end

        def peek_bool(*candidates)
          value = peek_first(*candidates)
          return nil if value.nil?

          !value.to_i.zero?
        end

        def compact_hash(hash)
          hash.each_with_object({}) do |(key, value), acc|
            next if value.nil?
            next if value.respond_to?(:empty?) && value.empty?

            acc[key] =
              case value
              when Hash
                compact_hash(value)
              else
                value
              end
          end
        end

        # ---- Build pipeline ----

        def build_and_load
          verilog_sim = verilog_simulator
          verilog_sim.prepare_build_dirs!

          wrapper_file = File.join(verilog_sim.verilog_dir, "std_abi_wrapper_#{sanitize_identifier(@top_module)}.cpp")
          header_file = File.join(verilog_sim.verilog_dir, "std_abi_wrapper_#{sanitize_identifier(@top_module)}.h")
          write_std_abi_wrapper(wrapper_file, header_file)

          lib_file = verilog_sim.shared_library_path
          build_deps = [
            @source_bundle.top_file,
            *@source_bundle.source_files,
            wrapper_file,
            header_file,
            __FILE__,
            File.expand_path('../../../../lib/rhdl/codegen/verilog/sim/verilog_simulator.rb', __dir__),
            File.expand_path('../integration/staged_verilog_bundle.rb', __dir__)
          ].select { |path| File.exist?(path) }

          needs_build = !File.exist?(lib_file) ||
                        build_deps.any? { |path| File.mtime(path) > File.mtime(lib_file) }
          verilog_sim.compile_backend(
            verilog_file: @source_bundle.top_file,
            wrapper_file: wrapper_file,
            log_file: verilator_build_log
          ) if needs_build

          load_shared_library(lib_file)
        end

        def verilog_simulator
          @verilog_simulator ||= RHDL::Codegen::Verilog::VerilogSimulator.new(
            backend: :verilator,
            build_dir: @source_bundle.build_dir,
            library_basename: "sparc64_std_sim_#{sanitize_identifier(@top_module)}",
            top_module: @top_module,
            verilator_prefix: @verilator_prefix,
            extra_verilator_flags: (VERILATOR_WARNING_FLAGS + VERILATOR_DEFAULT_FLAGS + @source_bundle.verilator_args).uniq,
            threads: @threads
          ).tap(&:ensure_backend_available!)
        end

        def load_shared_library(lib_path)
          @sim = RHDL::Sim::Native::Verilog::Verilator::Runtime.open(
            lib_path: lib_path,
            config: {},
            signal_widths_by_name: SIGNAL_WIDTHS,
            signal_widths_by_idx: SIGNAL_WIDTHS.values,
            backend_label: 'SPARC64 Verilator'
          )
          ensure_runner_abi!(@sim, expected_kind: :sparc64, backend_label: 'SPARC64 Verilator')
        end

        def ensure_runner_abi!(sim, expected_kind:, backend_label:)
          unless sim.runner_supported?
            sim.close
            raise RuntimeError, "#{backend_label} shared library does not expose runner ABI"
          end

          actual_kind = sim.runner_kind
          return if actual_kind == expected_kind

          sim.close
          raise RuntimeError, "#{backend_label} shared library exposes runner kind #{actual_kind.inspect}, expected #{expected_kind.inspect}"
        end

        def sanitize_identifier(name)
          name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
        end

        def verilator_build_log
          return File.join(@source_bundle.build_dir, 'verilator_std_abi_build.log') if @threads == 1

          File.join(@source_bundle.build_dir, "verilator_std_abi_build_threads#{@threads}.log")
        end

        def write_file_if_changed(path, content)
          return if File.exist?(path) && File.read(path) == content

          File.write(path, content)
        end

        # ---- C++ wrapper generation ----

        def write_std_abi_wrapper(cpp_file, header_file)
          input_signal_names = INPUT_SIGNAL_WIDTHS.keys
          output_signal_names = OUTPUT_SIGNAL_WIDTHS.keys
          debug_signal_names = DEBUG_SIGNAL_WIDTHS.keys
          input_names_csv = input_signal_names.join(',')
          output_names_csv = output_signal_names.join(',')

          header = <<~H
            #pragma once
            #include <cstdint>
            #include <cstddef>
            extern "C" {
            void* sim_create(const char* json, std::size_t json_len, unsigned int sub_cycles, char** err_out);
            void sim_destroy(void* sim);
            void sim_free_error(char* err);
            void sim_free_string(char* str);
            void* sim_wasm_alloc(std::size_t size);
            void sim_wasm_dealloc(void* ptr, std::size_t size);
            void sim_reset(void* sim);
            void sim_eval(void* sim);
            void sim_poke(void* sim, const char* name, unsigned int value);
            unsigned long long sim_peek(void* sim, const char* name);
            int sim_get_caps(const void* sim, unsigned int* caps_out);
            int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value);
            int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, void* error_out);
            int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value);
            unsigned long sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, unsigned long out_len);
            int runner_get_caps(const void* sim, unsigned int* caps_out);
            unsigned long runner_mem(void* sim, unsigned int op, unsigned int space, unsigned long offset, unsigned char* data, unsigned long len, unsigned int flags);
            int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, void* result_out);
            int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1);
            unsigned long long runner_probe(void* sim, unsigned int op, unsigned int arg0);
            }
          H

          cpp = <<~CPP
            #include "#{@verilator_prefix}.h"
            #include "#{@verilator_prefix}___024root.h"
            #include "verilated.h"
            #include "std_abi_wrapper_#{sanitize_identifier(@top_module)}.h"
            #include <algorithm>
            #include <cstdint>
            #include <cstdlib>
            #include <cstring>
            #include <string>
            #include <unordered_map>
            #include <vector>

            double sc_time_stamp() { return 0; }

            namespace {

            // ---- Memory map constants ----
            constexpr std::uint64_t kFlashBootBase = 0x#{Integration::FLASH_BOOT_BASE.to_s(16).upcase}ULL;
            constexpr std::uint64_t kMailboxStatus = 0x#{Integration::MAILBOX_STATUS.to_s(16).upcase}ULL;
            constexpr std::uint64_t kMailboxValue = 0x#{Integration::MAILBOX_VALUE.to_s(16).upcase}ULL;
            constexpr std::uint64_t kPhysicalAddrMask = 0x#{Integration::PHYSICAL_ADDR_MASK.to_s(16).upcase}ULL;
            constexpr std::size_t kResetCycles = 4;

            // ---- Trace / fault records ----
            struct WishboneTraceRecord {
              std::uint64_t cycle;
              std::uint64_t op;   // 0=read, 1=write
              std::uint64_t addr;
              std::uint64_t sel;
              std::uint64_t write_data;
              std::uint64_t read_data;
            };

            struct FaultRecord {
              std::uint64_t cycle;
              std::uint64_t op;
              std::uint64_t addr;
              std::uint64_t sel;
            };

            struct PendingResponse {
              bool valid = false;
              bool write = false;
              bool unmapped = false;
              std::uint64_t addr = 0;
              std::uint64_t data = 0;
              std::uint64_t read_data = 0;
              std::uint64_t sel = 0;
            };

            struct SimContext {
              #{@verilator_prefix}* dut;
              std::unordered_map<std::uint64_t, std::uint8_t> flash;
              std::unordered_map<std::uint64_t, std::uint8_t> dram;
              std::unordered_map<std::uint64_t, std::uint8_t> mailbox_mmio;
              std::vector<WishboneTraceRecord> trace;
              std::vector<FaultRecord> faults;
              PendingResponse pending_response;
              std::uint64_t protected_dram_limit = 0;
              std::size_t reset_cycles_remaining = kResetCycles;
              std::uint64_t cycles = 0;
              // Cached JSON blobs for sim_blob
              std::string trace_json;
              std::string faults_json;
              bool trace_json_dirty = true;
              bool faults_json_dirty = true;
            };

            // ---- Address helpers ----
            std::uint64_t canonical_bus_addr(std::uint64_t addr) {
              return addr & kPhysicalAddrMask;
            }

            bool is_flash_addr(std::uint64_t addr) {
              return canonical_bus_addr(addr) >= kFlashBootBase;
            }

            bool is_mailbox_mmio_addr(std::uint64_t addr) {
              const std::uint64_t physical = canonical_bus_addr(addr);
              return (physical >= kMailboxStatus && physical < (kMailboxStatus + 8ULL)) ||
                     (physical >= kMailboxValue && physical < (kMailboxValue + 8ULL));
            }

            bool is_dram_addr(std::uint64_t addr) {
              return canonical_bus_addr(addr) < kFlashBootBase;
            }

            bool lane_selected(std::uint64_t sel, int lane) {
              return (sel & (0x80ULL >> lane)) != 0;
            }

            // ---- Memory read/write ----
            bool read_mapped_byte(SimContext* ctx, std::uint64_t addr, std::uint8_t* out) {
              const std::uint64_t physical = canonical_bus_addr(addr);
              if (is_mailbox_mmio_addr(physical)) {
                auto it = ctx->mailbox_mmio.find(physical);
                *out = it == ctx->mailbox_mmio.end() ? 0 : it->second;
                return true;
              }
              if (is_flash_addr(physical)) {
                auto it = ctx->flash.find(physical);
                *out = it == ctx->flash.end() ? 0 : it->second;
                return true;
              }
              if (is_dram_addr(physical)) {
                auto it = ctx->dram.find(physical);
                *out = it == ctx->dram.end() ? 0 : it->second;
                return true;
              }
              return false;
            }

            std::uint64_t read_wishbone_word(SimContext* ctx, std::uint64_t addr, std::uint64_t sel, bool* mapped) {
              std::uint64_t value = 0;
              bool any_selected = false;
              for (int lane = 0; lane < 8; ++lane) {
                std::uint8_t byte = 0;
                if (!read_mapped_byte(ctx, addr + static_cast<std::uint64_t>(lane), &byte)) {
                  if (lane_selected(sel, lane)) {
                    if (mapped) *mapped = false;
                    return 0;
                  }
                  byte = 0;
                }
                value |= static_cast<std::uint64_t>(byte) << ((7 - lane) * 8);
                any_selected = any_selected || lane_selected(sel, lane);
              }
              if (mapped) *mapped = any_selected;
              return value;
            }

            bool write_wishbone_word(SimContext* ctx, std::uint64_t addr, std::uint64_t data, std::uint64_t sel) {
              bool any_mapped = false;
              for (int lane = 0; lane < 8; ++lane) {
                if (!lane_selected(sel, lane)) continue;
                std::uint64_t byte_addr = canonical_bus_addr(addr + static_cast<std::uint64_t>(lane));
                if (is_mailbox_mmio_addr(byte_addr)) {
                  ctx->mailbox_mmio[byte_addr] = static_cast<std::uint8_t>((data >> ((7 - lane) * 8)) & 0xFFULL);
                  any_mapped = true;
                  continue;
                }
                if (is_flash_addr(byte_addr)) return false;
                if (!is_dram_addr(byte_addr)) return false;
                if (byte_addr < ctx->protected_dram_limit) { any_mapped = true; continue; }
                ctx->dram[byte_addr] = static_cast<std::uint8_t>((data >> ((7 - lane) * 8)) & 0xFFULL);
                any_mapped = true;
              }
              return any_mapped;
            }

            // ---- Wishbone cycle stepping ----
            void drive_defaults(SimContext* ctx) {
              ctx->dut->sys_clock_i = 0;
              ctx->dut->sys_reset_i = 0;
              ctx->dut->eth_irq_i = 0;
              ctx->dut->wbm_ack_i = 0;
              ctx->dut->wbm_data_i = 0;
            }

            void clear_runtime_state(SimContext* ctx) {
              ctx->trace.clear();
              ctx->faults.clear();
              ctx->pending_response = PendingResponse{};
              ctx->reset_cycles_remaining = kResetCycles;
              ctx->cycles = 0;
              ctx->trace_json_dirty = true;
              ctx->faults_json_dirty = true;
            }

            void apply_inputs(SimContext* ctx, bool reset_active, const PendingResponse* response) {
              ctx->dut->sys_clock_i = 0;
              ctx->dut->sys_reset_i = reset_active ? 1 : 0;
              ctx->dut->eth_irq_i = 0;
              if (response && response->valid) {
                ctx->dut->wbm_ack_i = 1;
                ctx->dut->wbm_data_i = response->read_data;
              } else {
                ctx->dut->wbm_ack_i = 0;
                ctx->dut->wbm_data_i = 0;
              }
            }

            PendingResponse sample_request(SimContext* ctx) {
              PendingResponse request;
              if (!ctx->dut->wbm_cycle_o || !ctx->dut->wbm_strobe_o) return request;
              request.valid = true;
              request.write = (ctx->dut->wbm_we_o != 0);
              request.addr = canonical_bus_addr(static_cast<std::uint64_t>(ctx->dut->wbm_addr_o));
              request.data = static_cast<std::uint64_t>(ctx->dut->wbm_data_o);
              request.sel = static_cast<std::uint64_t>(ctx->dut->wbm_sel_o) & 0xFFULL;
              return request;
            }

            bool requests_equal(const PendingResponse& lhs, const PendingResponse& rhs) {
              return lhs.valid == rhs.valid && lhs.write == rhs.write &&
                     lhs.addr == rhs.addr && lhs.data == rhs.data && lhs.sel == rhs.sel;
            }

            PendingResponse service_request(SimContext* ctx, const PendingResponse& request) {
              PendingResponse response = request;
              if (!request.valid) return response;
              if (request.write) {
                response.read_data = 0;
                response.unmapped = !write_wishbone_word(ctx, request.addr, request.data, request.sel);
              } else {
                bool mapped = false;
                response.read_data = read_wishbone_word(ctx, request.addr, request.sel, &mapped);
                response.unmapped = !mapped;
              }
              return response;
            }

            void record_acknowledged_response(SimContext* ctx, const PendingResponse& response) {
              if (!response.valid) return;
              if (response.unmapped) {
                ctx->faults.push_back(FaultRecord{
                  ctx->cycles,
                  response.write ? 1ULL : 0ULL,
                  response.addr,
                  response.sel
                });
                ctx->faults_json_dirty = true;
              }
              ctx->trace.push_back(WishboneTraceRecord{
                ctx->cycles,
                response.write ? 1ULL : 0ULL,
                response.addr,
                response.sel,
                response.write ? response.data : 0ULL,
                response.write ? 0ULL : response.read_data
              });
              ctx->trace_json_dirty = true;
            }

            void step_cycle(SimContext* ctx) {
              bool reset_active = ctx->reset_cycles_remaining > 0;
              PendingResponse acked_response = reset_active ? PendingResponse{} : ctx->pending_response;

              apply_inputs(ctx, reset_active, acked_response.valid ? &acked_response : nullptr);
              ctx->dut->eval();

              if (acked_response.valid) record_acknowledged_response(ctx, acked_response);

              PendingResponse next_response;
              if (!reset_active) {
                PendingResponse request = sample_request(ctx);
                if (request.valid && !(acked_response.valid && requests_equal(acked_response, request))) {
                  next_response = service_request(ctx, request);
                }
              }

              ctx->dut->sys_clock_i = 1;
              ctx->dut->eval();
              ctx->pending_response = next_response;
              ctx->cycles += 1;
              if (ctx->reset_cycles_remaining > 0) ctx->reset_cycles_remaining -= 1;
            }

            // ---- JSON serialisation for sim_blob ----
            static void ensure_trace_json(SimContext* ctx) {
              if (!ctx->trace_json_dirty) return;
              std::string json = "[";
              for (std::size_t i = 0; i < ctx->trace.size(); ++i) {
                const auto& r = ctx->trace[i];
                if (i > 0) json += ',';
                char buf[256];
                std::snprintf(buf, sizeof(buf),
                  R"({"cycle":%llu,"op":"%s","addr":%llu,"sel":%llu,"write_data":%llu,"read_data":%llu})",
                  (unsigned long long)r.cycle,
                  r.op == 1 ? "write" : "read",
                  (unsigned long long)r.addr,
                  (unsigned long long)r.sel,
                  (unsigned long long)r.write_data,
                  (unsigned long long)r.read_data);
                json += buf;
              }
              json += ']';
              ctx->trace_json = std::move(json);
              ctx->trace_json_dirty = false;
            }

            static void ensure_faults_json(SimContext* ctx) {
              if (!ctx->faults_json_dirty) return;
              std::string json = "[";
              for (std::size_t i = 0; i < ctx->faults.size(); ++i) {
                const auto& f = ctx->faults[i];
                if (i > 0) json += ',';
                char buf[192];
                std::snprintf(buf, sizeof(buf),
                  R"({"cycle":%llu,"op":"%s","addr":%llu,"sel":%llu})",
                  (unsigned long long)f.cycle,
                  f.op == 1 ? "write" : "read",
                  (unsigned long long)f.addr,
                  (unsigned long long)f.sel);
                json += buf;
              }
              json += ']';
              ctx->faults_json = std::move(json);
              ctx->faults_json_dirty = false;
            }

            // ---- Standard ABI constants ----
            enum {
              SIM_CAP_SIGNAL_INDEX = 1u << 0,
              SIM_CAP_RUNNER = 1u << 6
            };
            enum {
              SIM_SIGNAL_HAS = 0u, SIM_SIGNAL_GET_INDEX = 1u, SIM_SIGNAL_PEEK = 2u,
              SIM_SIGNAL_POKE = 3u, SIM_SIGNAL_PEEK_INDEX = 4u, SIM_SIGNAL_POKE_INDEX = 5u
            };
            enum {
              SIM_EXEC_EVALUATE = 0u, SIM_EXEC_TICK = 1u, SIM_EXEC_TICK_FORCED = 2u,
              SIM_EXEC_SET_PREV_CLOCK = 3u, SIM_EXEC_GET_CLOCK_LIST_IDX = 4u,
              SIM_EXEC_RESET = 5u, SIM_EXEC_RUN_TICKS = 6u,
              SIM_EXEC_SIGNAL_COUNT = 7u, SIM_EXEC_REG_COUNT = 8u
            };
            enum {
              SIM_TRACE_ENABLED = 3u
            };
            enum {
              SIM_BLOB_INPUT_NAMES = 0u, SIM_BLOB_OUTPUT_NAMES = 1u,
              SIM_BLOB_SPARC64_WISHBONE_TRACE = 5u, SIM_BLOB_SPARC64_UNMAPPED_ACCESSES = 6u
            };
            enum {
              RUNNER_KIND_SPARC64 = 6
            };
            enum {
              RUNNER_MEM_OP_LOAD = 0u, RUNNER_MEM_OP_READ = 1u, RUNNER_MEM_OP_WRITE = 2u
            };
            enum {
              RUNNER_MEM_SPACE_MAIN = 0u, RUNNER_MEM_SPACE_ROM = 1u
            };
            enum {
              RUNNER_RUN_MODE_BASIC = 0u
            };
            enum {
              RUNNER_PROBE_KIND = 0u, RUNNER_PROBE_IS_MODE = 1u, RUNNER_PROBE_SIGNAL = 9u
            };

            struct RunnerCaps {
              int kind;
              unsigned int mem_spaces;
              unsigned int control_ops;
              unsigned int probe_ops;
            };

            struct RunnerRunResult {
              int text_dirty;
              int key_cleared;
              unsigned int cycles_run;
              unsigned int speaker_toggles;
              unsigned int frames_completed;
            };

            // ---- Signal tables ----
            static const char* k_input_signal_names[] = {
              #{input_signal_names.map { |n| %("#{n}") }.join(", ")}
            };
            static const char* k_output_signal_names[] = {
              #{output_signal_names.map { |n| %("#{n}") }.join(", ")}
            };
            static const char* k_debug_signal_names[] = {
              #{debug_signal_names.map { |n| %("#{n}") }.join(", ")}
            };
            static const char k_input_names_csv[] = "#{input_names_csv}";
            static const char k_output_names_csv[] = "#{output_names_csv}";
            static const unsigned int k_input_signal_count = #{input_signal_names.length}u;
            static const unsigned int k_output_signal_count = #{output_signal_names.length}u;
            static const unsigned int k_debug_signal_count = #{debug_signal_names.length}u;

            static inline void write_out_ulong(unsigned long* out, unsigned long value) { if (out) *out = value; }
            static unsigned int total_signal_count() { return k_input_signal_count + k_output_signal_count + k_debug_signal_count; }

            static const char* signal_name_from_index(unsigned int idx) {
              if (idx < k_input_signal_count) return k_input_signal_names[idx];
              idx -= k_input_signal_count;
              if (idx < k_output_signal_count) return k_output_signal_names[idx];
              idx -= k_output_signal_count;
              return idx < k_debug_signal_count ? k_debug_signal_names[idx] : nullptr;
            }

            static int signal_index_from_name(const char* name) {
              if (!name) return -1;
              for (unsigned int i = 0; i < k_input_signal_count; i++)
                if (!std::strcmp(name, k_input_signal_names[i])) return static_cast<int>(i);
              for (unsigned int i = 0; i < k_output_signal_count; i++)
                if (!std::strcmp(name, k_output_signal_names[i])) return static_cast<int>(k_input_signal_count + i);
              for (unsigned int i = 0; i < k_debug_signal_count; i++)
                if (!std::strcmp(name, k_debug_signal_names[i])) return static_cast<int>(k_input_signal_count + k_output_signal_count + i);
              return -1;
            }

            static std::size_t copy_blob(unsigned char* out_ptr, std::size_t out_len, const char* text, std::size_t text_len) {
              if (out_ptr && out_len && text_len) {
                const std::size_t n = text_len < out_len ? text_len : out_len;
                std::memcpy(out_ptr, text, n);
              }
              return text_len;
            }

            }  // namespace

            // ============================================================
            // Standard ABI extern "C" exports
            // ============================================================
            extern "C" {

            void* sim_create(const char* json, std::size_t json_len, unsigned int sub_cycles, char** err_out) {
              (void)json; (void)json_len; (void)sub_cycles;
              if (err_out) *err_out = nullptr;
              const char* empty_args[] = {""};
              Verilated::commandArgs(1, empty_args);
              SimContext* ctx = new SimContext();
              ctx->dut = new #{@verilator_prefix}();
              drive_defaults(ctx);
              ctx->dut->eval();
              clear_runtime_state(ctx);
              return ctx;
            }

            void sim_destroy(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              delete ctx->dut;
              delete ctx;
            }

            void sim_free_error(char* err) { if (err) std::free(err); }
            void sim_free_string(char* str) { if (str) std::free(str); }
            void* sim_wasm_alloc(std::size_t size) { return std::malloc(size > 0 ? size : 1); }
            void sim_wasm_dealloc(void* ptr, std::size_t size) { (void)size; std::free(ptr); }

            void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              clear_runtime_state(ctx);
              drive_defaults(ctx);
              ctx->dut->sys_reset_i = 1;
              ctx->dut->sys_clock_i = 0;
              ctx->dut->eval();
            }

            void sim_eval(void* sim) {
              static_cast<SimContext*>(sim)->dut->eval();
            }

            void sim_poke(void* sim, const char* n, unsigned int v) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!std::strcmp(n, "sys_clock_i"))  ctx->dut->sys_clock_i = v;
              else if (!std::strcmp(n, "sys_reset_i")) ctx->dut->sys_reset_i = v;
              else if (!std::strcmp(n, "eth_irq_i"))   ctx->dut->eth_irq_i = v;
              else if (!std::strcmp(n, "wbm_ack_i"))   ctx->dut->wbm_ack_i = v;
              else if (!std::strcmp(n, "wbm_data_i"))  ctx->dut->wbm_data_i = static_cast<std::uint64_t>(v);
            }

            unsigned long long sim_peek(void* sim, const char* n) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!std::strcmp(n, "wbm_cycle_o"))  return ctx->dut->wbm_cycle_o;
              if (!std::strcmp(n, "wbm_strobe_o")) return ctx->dut->wbm_strobe_o;
              if (!std::strcmp(n, "wbm_we_o"))     return ctx->dut->wbm_we_o;
              if (!std::strcmp(n, "wbm_sel_o"))    return static_cast<unsigned long long>(ctx->dut->wbm_sel_o & 0xFFu);
              if (!std::strcmp(n, "wbm_addr_o"))   return static_cast<unsigned long long>(ctx->dut->wbm_addr_o);
              if (!std::strcmp(n, "wbm_data_o"))   return static_cast<unsigned long long>(ctx->dut->wbm_data_o);

              auto* root = ctx->dut->rootp;
              if (!std::strcmp(n, "os2wb_inst__state")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__os2wb_inst__DOT__state);
              if (!std::strcmp(n, "os2wb_inst__cpx_ready")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__os2wb_inst__DOT__cpx_ready);
              if (!std::strcmp(n, "os2wb_inst__cpu")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__os2wb_inst__DOT__cpu);
              if (!std::strcmp(n, "os2wb_inst__pcx_req_d")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__os2wb_inst__DOT__pcx_req_d);
              if (!std::strcmp(n, "os2wb_inst__wb_cycle")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__os2wb_inst__DOT__wb_cycle);
              if (!std::strcmp(n, "os2wb_inst__wb_strobe")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__os2wb_inst__DOT__wb_strobe);
              if (!std::strcmp(n, "os2wb_inst__wb_we")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__os2wb_inst__DOT__wb_we);
              if (!std::strcmp(n, "os2wb_inst__wb_addr")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__os2wb_inst__DOT__wb_addr);
              if (!std::strcmp(n, "sparc_0__ifu__errdp__fdp_erb_pc_f")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__errdp__DOT__fdp_erb_pc_f);
              if (!std::strcmp(n, "sparc_0__tlu__misctl__ifu_npc_w")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__tlu__DOT__misctl__DOT__ifu_npc_w);
              if (!std::strcmp(n, "sparc_0__ifu__swl__thrfsm0__thr_state")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm0__DOT__thr_state);
              if (!std::strcmp(n, "sparc_0__ifu__swl__thrfsm1__thr_state")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm1__DOT__thr_state);
              if (!std::strcmp(n, "sparc_0__ifu__swl__thrfsm2__thr_state")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm2__DOT__thr_state);
              if (!std::strcmp(n, "sparc_0__ifu__swl__thrfsm3__thr_state")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm3__DOT__thr_state);
              if (!std::strcmp(n, "sparc_0__ifu__swl__dtu_fcl_nextthr_bf")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__dtu_fcl_nextthr_bf);
              if (!std::strcmp(n, "sparc_0__ifu__swl__completion")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__completion);
              if (!std::strcmp(n, "sparc_0__ifu__swl__schedule")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__schedule);
              if (!std::strcmp(n, "sparc_0__ifu__swl__int_activate")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__int_activate);
              if (!std::strcmp(n, "sparc_0__ifu__swl__start_thread")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__start_thread);
              if (!std::strcmp(n, "sparc_0__ifu__swl__thaw_thread")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thaw_thread);
              if (!std::strcmp(n, "sparc_0__ifu__swl__resum_thread")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__resum_thread);
              if (!std::strcmp(n, "sparc_0__ifu__swl__rdy")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__rdy);
              if (!std::strcmp(n, "sparc_0__ifu__swl__retr_thr_wakeup")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__retr_thr_wakeup);
              if (!std::strcmp(n, "sparc_0__ifu__fcl__rune_ff__q")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__rune_ff__DOT__q);
              if (!std::strcmp(n, "sparc_0__ifu__fcl__rund_ff__q")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__rund_ff__DOT__q);
              if (!std::strcmp(n, "sparc_0__ifu__fcl__runm_ff__q")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__runm_ff__DOT__q);
              if (!std::strcmp(n, "sparc_0__ifu__fcl__runw_ff__q")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__runw_ff__DOT__q);
              if (!std::strcmp(n, "sparc_1__ifu__errdp__fdp_erb_pc_f")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__errdp__DOT__fdp_erb_pc_f);
              if (!std::strcmp(n, "sparc_1__tlu__misctl__ifu_npc_w")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__tlu__DOT__misctl__DOT__ifu_npc_w);
              if (!std::strcmp(n, "sparc_1__ifu__swl__thrfsm0__thr_state")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm0__DOT__thr_state);
              if (!std::strcmp(n, "sparc_1__ifu__swl__thrfsm1__thr_state")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm1__DOT__thr_state);
              if (!std::strcmp(n, "sparc_1__ifu__swl__thrfsm2__thr_state")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm2__DOT__thr_state);
              if (!std::strcmp(n, "sparc_1__ifu__swl__thrfsm3__thr_state")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm3__DOT__thr_state);
              if (!std::strcmp(n, "sparc_1__ifu__swl__dtu_fcl_nextthr_bf")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__dtu_fcl_nextthr_bf);
              if (!std::strcmp(n, "sparc_1__ifu__swl__completion")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__completion);
              if (!std::strcmp(n, "sparc_1__ifu__swl__schedule")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__schedule);
              if (!std::strcmp(n, "sparc_1__ifu__swl__int_activate")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__int_activate);
              if (!std::strcmp(n, "sparc_1__ifu__swl__start_thread")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__start_thread);
              if (!std::strcmp(n, "sparc_1__ifu__swl__thaw_thread")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thaw_thread);
              if (!std::strcmp(n, "sparc_1__ifu__swl__resum_thread")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__resum_thread);
              if (!std::strcmp(n, "sparc_1__ifu__swl__rdy")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__rdy);
              if (!std::strcmp(n, "sparc_1__ifu__swl__retr_thr_wakeup")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__retr_thr_wakeup);
              if (!std::strcmp(n, "sparc_1__ifu__fcl__rune_ff__q")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__rune_ff__DOT__q);
              if (!std::strcmp(n, "sparc_1__ifu__fcl__rund_ff__q")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__rund_ff__DOT__q);
              if (!std::strcmp(n, "sparc_1__ifu__fcl__runm_ff__q")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__runm_ff__DOT__q);
              if (!std::strcmp(n, "sparc_1__ifu__fcl__runw_ff__q")) return static_cast<unsigned long long>(root->#{sanitize_identifier(@top_module)}__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__runw_ff__DOT__q);
              return 0ull;
            }

            int sim_get_caps(const void* sim, unsigned int* caps_out) {
              (void)sim;
              if (!caps_out) return 0;
              *caps_out = SIM_CAP_SIGNAL_INDEX | SIM_CAP_RUNNER;
              return 1;
            }

            int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value) {
              int resolved_idx = (name && name[0]) ? signal_index_from_name(name) : static_cast<int>(idx);
              const char* resolved_name = (name && name[0]) ? name : signal_name_from_index(idx);
              switch (op) {
              case SIM_SIGNAL_HAS:
                write_out_ulong(out_value, resolved_idx >= 0 ? 1ul : 0ul);
                return resolved_idx >= 0 ? 1 : 0;
              case SIM_SIGNAL_GET_INDEX:
                if (resolved_idx < 0) { write_out_ulong(out_value, 0ul); return 0; }
                write_out_ulong(out_value, static_cast<unsigned long>(resolved_idx));
                return 1;
              case SIM_SIGNAL_PEEK: case SIM_SIGNAL_PEEK_INDEX:
                if (resolved_idx < 0 || !resolved_name) { write_out_ulong(out_value, 0ul); return 0; }
                write_out_ulong(out_value, static_cast<unsigned long>(sim_peek(sim, resolved_name)));
                return 1;
              case SIM_SIGNAL_POKE: case SIM_SIGNAL_POKE_INDEX:
                if (resolved_idx < 0 || !resolved_name) { write_out_ulong(out_value, 0ul); return 0; }
                sim_poke(sim, resolved_name, static_cast<unsigned int>(value));
                write_out_ulong(out_value, 1ul);
                return 1;
              default:
                write_out_ulong(out_value, 0ul);
                return 0;
              }
            }

            int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, void* error_out) {
              (void)arg1; (void)error_out;
              SimContext* ctx = static_cast<SimContext*>(sim);
              switch (op) {
              case SIM_EXEC_EVALUATE:
                ctx->dut->eval();
                write_out_ulong(out_value, 0ul);
                return 1;
              case SIM_EXEC_TICK: case SIM_EXEC_TICK_FORCED:
                step_cycle(ctx);
                write_out_ulong(out_value, 0ul);
                return 1;
              case SIM_EXEC_RESET:
                sim_reset(sim);
                write_out_ulong(out_value, 0ul);
                return 1;
              case SIM_EXEC_RUN_TICKS:
                for (unsigned long i = 0; i < arg0; ++i) step_cycle(ctx);
                write_out_ulong(out_value, 0ul);
                return 1;
              case SIM_EXEC_SIGNAL_COUNT:
                write_out_ulong(out_value, static_cast<unsigned long>(total_signal_count()));
                return 1;
              case SIM_EXEC_REG_COUNT:
                write_out_ulong(out_value, 0ul);
                return 1;
              default:
                write_out_ulong(out_value, 0ul);
                return 0;
              }
            }

            int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value) {
              (void)sim; (void)str_arg;
              write_out_ulong(out_value, 0ul);
              return (op == SIM_TRACE_ENABLED) ? 1 : 0;
            }

            unsigned long sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, unsigned long out_len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              switch (op) {
              case SIM_BLOB_INPUT_NAMES:
                return copy_blob(out_ptr, out_len, k_input_names_csv, sizeof(k_input_names_csv) - 1);
              case SIM_BLOB_OUTPUT_NAMES:
                return copy_blob(out_ptr, out_len, k_output_names_csv, sizeof(k_output_names_csv) - 1);
              case SIM_BLOB_SPARC64_WISHBONE_TRACE:
                ensure_trace_json(ctx);
                return copy_blob(out_ptr, out_len, ctx->trace_json.c_str(), ctx->trace_json.size());
              case SIM_BLOB_SPARC64_UNMAPPED_ACCESSES:
                ensure_faults_json(ctx);
                return copy_blob(out_ptr, out_len, ctx->faults_json.c_str(), ctx->faults_json.size());
              default:
                return 0u;
              }
            }

            // ---- Runner ABI ----
            int runner_get_caps(const void* sim, unsigned int* caps_out) {
              (void)sim;
              if (!caps_out) return 0;
              RunnerCaps* caps = reinterpret_cast<RunnerCaps*>(caps_out);
              caps->kind = RUNNER_KIND_SPARC64;
              caps->mem_spaces = (1u << RUNNER_MEM_SPACE_MAIN) | (1u << RUNNER_MEM_SPACE_ROM);
              caps->control_ops = 0u;
              caps->probe_ops = (1u << RUNNER_PROBE_KIND) | (1u << RUNNER_PROBE_IS_MODE) | (1u << RUNNER_PROBE_SIGNAL);
              return 1;
            }

            unsigned long runner_mem(void* sim, unsigned int op, unsigned int space, unsigned long offset,
                                     unsigned char* data, unsigned long len, unsigned int flags) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx || !data || len == 0u) return 0u;
              (void)flags;

              if (op == RUNNER_MEM_OP_LOAD) {
                if (space == RUNNER_MEM_SPACE_ROM) {
                  for (unsigned long i = 0; i < len; ++i)
                    ctx->flash[canonical_bus_addr(offset + i)] = data[i];
                  return len;
                }
                if (space == RUNNER_MEM_SPACE_MAIN) {
                  for (unsigned long i = 0; i < len; ++i)
                    ctx->dram[canonical_bus_addr(offset + i)] = data[i];
                  if (canonical_bus_addr(offset) == 0ULL)
                    ctx->protected_dram_limit = std::max<std::uint64_t>(ctx->protected_dram_limit, len);
                  return len;
                }
                return 0u;
              }

              if (op == RUNNER_MEM_OP_READ) {
                for (unsigned long i = 0; i < len; ++i) {
                  std::uint8_t byte = 0;
                  read_mapped_byte(ctx, offset + i, &byte);
                  data[i] = byte;
                }
                return len;
              }

              if (op == RUNNER_MEM_OP_WRITE) {
                if (space == RUNNER_MEM_SPACE_MAIN) {
                  for (unsigned long i = 0; i < len; ++i)
                    ctx->dram[offset + i] = data[i];
                  return len;
                }
                return 0u;
              }

              return 0u;
            }

            int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready,
                           unsigned int mode, void* result_out) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              (void)key_data; (void)key_ready; (void)mode;
              for (unsigned int i = 0; i < cycles; ++i) step_cycle(ctx);
              RunnerRunResult* result = static_cast<RunnerRunResult*>(result_out);
              if (result) {
                result->text_dirty = 0;
                result->key_cleared = 0;
                result->cycles_run = cycles;
                result->speaker_toggles = 0;
                result->frames_completed = 0;
              }
              return 1;
            }

            int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1) {
              (void)sim; (void)op; (void)arg0; (void)arg1;
              return 0;
            }

            unsigned long long runner_probe(void* sim, unsigned int op, unsigned int arg0) {
              if (!sim) return 0ull;
              if (op == RUNNER_PROBE_KIND) return static_cast<unsigned long long>(RUNNER_KIND_SPARC64);
              if (op == RUNNER_PROBE_IS_MODE) return 1ull;
              if (op == RUNNER_PROBE_SIGNAL) {
                const char* name = signal_name_from_index(arg0);
                return name ? static_cast<unsigned long long>(sim_peek(sim, name)) : 0ull;
              }
              return 0ull;
            }

            }  // extern "C"
          CPP

          write_file_if_changed(header_file, header)
          write_file_if_changed(cpp_file, cpp)
        end
      end

    end
  end
end
