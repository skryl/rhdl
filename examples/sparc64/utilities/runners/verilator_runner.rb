# frozen_string_literal: true

require 'fiddle'
require 'json'
require 'rbconfig'
require 'rhdl/codegen'

require_relative '../integration/constants'
require_relative '../integration/staged_verilog_bundle'

module RHDL
  module Examples
    module SPARC64
      class VerilogRunner
        include Integration

        class DefaultAdapter
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
          TRACE_WORDS = 6
          FAULT_WORDS = 4
	          DEBUG_WORDS = 144

          attr_reader :top_module

          def initialize(source_bundle: nil, source_bundle_class: Integration::StagedVerilogBundle,
                         source_bundle_options: {}, fast_boot: true)
            @source_bundle = source_bundle || source_bundle_class.new(
              fast_boot: fast_boot,
              **source_bundle_options
            ).build
            @top_module = @source_bundle.top_module
            @verilator_prefix = "V#{@top_module}"

            build_verilator_simulation
            ObjectSpace.define_finalizer(self, self.class.finalizer(@sim_destroy, @sim_ctx))
          end

          def simulator_type
            :hdl_verilator
          end

          def reset!
            @sim_reset.call(@sim_ctx)
            self
          end

          def run_cycles(n)
            @sim_run_cycles_fn.call(@sim_ctx, n.to_i).to_i
          end

          def load_images(boot_image:, program_image:)
            @sim_clear_memory_fn.call(@sim_ctx)
            load_flash(boot_image, base_addr: Integration::FLASH_BOOT_BASE)
            # The staged s1_top still fetches its reset vector from low DRAM.
            # Mirror the boot shim there until the flash alias is wired end to end.
            load_memory(boot_image, base_addr: 0)
            load_memory(program_image, base_addr: Integration::PROGRAM_BASE)
            reset!
            self
          end

          def load_flash(bytes, base_addr:)
            payload = pack_bytes(bytes)
            @sim_load_flash_fn.call(@sim_ctx, Fiddle::Pointer[payload], base_addr.to_i, payload.bytesize)
          end

          def load_memory(bytes, base_addr:)
            payload = pack_bytes(bytes)
            @sim_load_memory_fn.call(@sim_ctx, Fiddle::Pointer[payload], base_addr.to_i, payload.bytesize)
          end

          def read_memory(addr, length)
            len = length.to_i
            return [] if len <= 0

            buffer = Fiddle::Pointer.malloc(len)
            copied = @sim_read_memory_fn.call(@sim_ctx, addr.to_i, buffer, len).to_i
            buffer.to_s(copied).bytes
          end

          def write_memory(addr, bytes)
            payload = pack_bytes(bytes)
            @sim_write_memory_fn.call(@sim_ctx, addr.to_i, Fiddle::Pointer[payload], payload.bytesize).to_i
          end

          def mailbox_status
            decode_u64_be(read_memory(Integration::MAILBOX_STATUS, 8))
          end

          def mailbox_value
            decode_u64_be(read_memory(Integration::MAILBOX_VALUE, 8))
          end

          def wishbone_trace
            count = @sim_wishbone_trace_count_fn.call(@sim_ctx).to_i
            return [] if count <= 0

            buffer = Fiddle::Pointer.malloc(count * TRACE_WORDS * 8)
            copied = @sim_copy_wishbone_trace_fn.call(@sim_ctx, buffer, count).to_i
            unpack_u64_words(buffer, copied * TRACE_WORDS).each_slice(TRACE_WORDS).map do |cycle, op, addr, sel, write_data, read_data|
              write = !op.zero?
              {
                cycle: cycle,
                op: write ? :write : :read,
                addr: addr,
                sel: sel,
                write_data: write ? write_data : nil,
                read_data: write ? nil : read_data
              }
            end
          end

          def unmapped_accesses
            count = @sim_unmapped_access_count_fn.call(@sim_ctx).to_i
            return [] if count <= 0

            buffer = Fiddle::Pointer.malloc(count * FAULT_WORDS * 8)
            copied = @sim_copy_unmapped_accesses_fn.call(@sim_ctx, buffer, count).to_i
            unpack_u64_words(buffer, copied * FAULT_WORDS).each_slice(FAULT_WORDS).map do |cycle, op, addr, sel|
              {
                cycle: cycle,
                op: op.zero? ? :read : :write,
                addr: addr,
                sel: sel
              }
            end
          end

	          def debug_snapshot
	            buffer = Fiddle::Pointer.malloc(DEBUG_WORDS * 8)
	            copied = @sim_copy_debug_snapshot_fn.call(@sim_ctx, buffer, DEBUG_WORDS).to_i
	            words = unpack_u64_words(buffer, copied).fill(0, copied...DEBUG_WORDS)

	            {
              reset: {
                cycle_counter: words[0],
                sys_reset_final: !words[1].zero?,
                cluster_cken: !words[2].zero?,
                cmp_grst_l: !words[3].zero?,
                cmp_arst_l: !words[4].zero?,
                gdbginit_l: !words[5].zero?
              },
	              bridge: {
	                state: words[6],
	                cpu: words[7],
	                cpx_ready: !words[8].zero?,
	                pcx_req_d: words[9],
	                pcx_packet_type: words[10],
	                cpx_two_packet: !words[11].zero?
	              },
	              bridge_capture: decode_bridge_capture_debug(words, 100),
	              core0: decode_core_debug(words, 12, 40),
	              core0_ifq: decode_ifq_debug(words, 112),
	              core0_ifq_fill: decode_ifq_fill_debug(words, 124),
	              core1: decode_core_debug(words, 26, 70)
	            }
	          end

          def self.finalizer(sim_destroy, sim_ctx)
            proc do
              sim_destroy&.call(sim_ctx) if sim_ctx
            rescue StandardError
              nil
            end
          end

          private

          def build_verilator_simulation
            verilog_simulator.prepare_build_dirs!

            wrapper_file = File.join(verilog_simulator.verilog_dir, "sim_wrapper_#{sanitize_identifier(@top_module)}.cpp")
            header_file = File.join(verilog_simulator.verilog_dir, "sim_wrapper_#{sanitize_identifier(@top_module)}.h")
            create_cpp_wrapper(wrapper_file, header_file)

            lib_file = verilog_simulator.shared_library_path
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
            verilog_simulator.compile_backend(
              verilog_file: @source_bundle.top_file,
              wrapper_file: wrapper_file,
              log_file: File.join(@source_bundle.build_dir, 'verilator_build.log')
            ) if needs_build

            load_shared_library(lib_file)
          end

          def verilog_simulator
            @verilog_simulator ||= RHDL::Codegen::Verilog::VerilogSimulator.new(
              backend: :verilator,
              build_dir: @source_bundle.build_dir,
              library_basename: "sparc64_sim_#{sanitize_identifier(@top_module)}",
              top_module: @top_module,
              verilator_prefix: @verilator_prefix,
              extra_verilator_flags: (VERILATOR_WARNING_FLAGS + VERILATOR_DEFAULT_FLAGS + @source_bundle.verilator_args).uniq
            ).tap(&:ensure_backend_available!)
          end

          def create_cpp_wrapper(cpp_file, header_file)
            header = <<~HEADER
              #ifndef SPARC64_SIM_WRAPPER_H
              #define SPARC64_SIM_WRAPPER_H

              #ifdef __cplusplus
              extern "C" {
              #endif

              void* sim_create(void);
              void sim_destroy(void* sim);
              void sim_clear_memory(void* sim);
              void sim_reset(void* sim);
              void sim_load_flash(void* sim, const unsigned char* data, unsigned long long base_addr, unsigned int len);
              void sim_load_memory(void* sim, const unsigned char* data, unsigned long long base_addr, unsigned int len);
              unsigned int sim_read_memory(void* sim, unsigned long long addr, unsigned char* out, unsigned int len);
              unsigned int sim_write_memory(void* sim, unsigned long long addr, const unsigned char* data, unsigned int len);
              unsigned int sim_run_cycles(void* sim, unsigned int n_cycles);
              unsigned int sim_wishbone_trace_count(void* sim);
              unsigned int sim_copy_wishbone_trace(void* sim, unsigned long long* out_words, unsigned int max_records);
              unsigned int sim_unmapped_access_count(void* sim);
              unsigned int sim_copy_unmapped_accesses(void* sim, unsigned long long* out_words, unsigned int max_records);
              unsigned int sim_copy_debug_snapshot(void* sim, unsigned long long* out_words, unsigned int max_words);

              #ifdef __cplusplus
              }
              #endif

              #endif
            HEADER

            cpp = <<~CPP
              #include "#{@verilator_prefix}.h"
              #include "#{@verilator_prefix}___024root.h"
              #include "verilated.h"
              #include "sim_wrapper_#{sanitize_identifier(@top_module)}.h"
              #include <algorithm>
              #include <cstdint>
              #include <cstring>
              #include <unordered_map>
              #include <vector>

              double sc_time_stamp() { return 0; }

              namespace {
              constexpr std::uint64_t kFlashBootBase = 0x#{Integration::FLASH_BOOT_BASE.to_s(16).upcase}ULL;
              constexpr std::uint64_t kPhysicalAddrMask = 0x#{Integration::PHYSICAL_ADDR_MASK.to_s(16).upcase}ULL;
              constexpr std::uint64_t kTraceOpRead = 0;
              constexpr std::uint64_t kTraceOpWrite = 1;
              constexpr std::size_t kResetCycles = 4;
              constexpr unsigned int kDebugWords = #{DEBUG_WORDS};

              struct WishboneTraceRecord {
                std::uint64_t cycle;
                std::uint64_t op;
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
                std::vector<WishboneTraceRecord> trace;
                std::vector<FaultRecord> faults;
                PendingResponse pending_response;
                std::uint64_t protected_dram_limit = 0;
                std::size_t reset_cycles_remaining = kResetCycles;
                std::uint64_t cycles = 0;
              };

              std::uint64_t canonical_bus_addr(std::uint64_t addr) {
                return addr & kPhysicalAddrMask;
              }

              bool is_flash_addr(std::uint64_t addr) {
                return canonical_bus_addr(addr) >= kFlashBootBase;
              }

              bool is_dram_addr(std::uint64_t addr) {
                return canonical_bus_addr(addr) < kFlashBootBase;
              }

              bool lane_selected(std::uint64_t sel, int lane) {
                return (sel & (0x80ULL >> lane)) != 0;
              }

              std::uint8_t read_dram_byte(SimContext* ctx, std::uint64_t addr) {
                auto it = ctx->dram.find(addr);
                return it == ctx->dram.end() ? 0 : it->second;
              }

              bool read_mapped_byte(SimContext* ctx, std::uint64_t addr, std::uint8_t* out) {
                const std::uint64_t physical = canonical_bus_addr(addr);
                if (is_flash_addr(physical)) {
                  auto it = ctx->flash.find(physical);
                  *out = it == ctx->flash.end() ? 0 : it->second;
                  return true;
                }
                if (is_dram_addr(physical)) {
                  *out = read_dram_byte(ctx, physical);
                  return true;
                }
                return false;
              }

              std::uint64_t read_wishbone_word(SimContext* ctx, std::uint64_t addr, std::uint64_t sel, bool* mapped) {
                std::uint64_t value = 0;
                bool any_mapped = false;
                for (int lane = 0; lane < 8; ++lane) {
                  if (!lane_selected(sel, lane)) {
                    continue;
                  }
                  std::uint8_t byte = 0;
                  if (!read_mapped_byte(ctx, addr + static_cast<std::uint64_t>(lane), &byte)) {
                    if (mapped) *mapped = false;
                    return 0;
                  }
                  value |= static_cast<std::uint64_t>(byte) << ((7 - lane) * 8);
                  any_mapped = true;
                }
                if (mapped) *mapped = any_mapped;
                return value;
              }

              bool write_wishbone_word(SimContext* ctx, std::uint64_t addr, std::uint64_t data, std::uint64_t sel) {
                bool any_mapped = false;
                for (int lane = 0; lane < 8; ++lane) {
                  if (!lane_selected(sel, lane)) {
                    continue;
                  }
                  std::uint64_t byte_addr = canonical_bus_addr(addr + static_cast<std::uint64_t>(lane));
                  if (is_flash_addr(byte_addr)) {
                    return false;
                  }
                  if (!is_dram_addr(byte_addr)) {
                    return false;
                  }
                  if (byte_addr < ctx->protected_dram_limit) {
                    any_mapped = true;
                    continue;
                  }
                  std::uint8_t byte = static_cast<std::uint8_t>((data >> ((7 - lane) * 8)) & 0xFFULL);
                  ctx->dram[byte_addr] = byte;
                  any_mapped = true;
                }
                return any_mapped;
              }

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
                if (!ctx->dut->wbm_cycle_o || !ctx->dut->wbm_strobe_o) {
                  return request;
                }
                request.valid = true;
                request.write = (ctx->dut->wbm_we_o != 0);
                request.addr = canonical_bus_addr(static_cast<std::uint64_t>(ctx->dut->wbm_addr_o));
                request.data = static_cast<std::uint64_t>(ctx->dut->wbm_data_o);
                request.sel = static_cast<std::uint64_t>(ctx->dut->wbm_sel_o) & 0xFFULL;
                return request;
              }

              bool requests_equal(const PendingResponse& lhs, const PendingResponse& rhs) {
                return lhs.valid == rhs.valid &&
                       lhs.write == rhs.write &&
                       lhs.addr == rhs.addr &&
                       lhs.data == rhs.data &&
                       lhs.sel == rhs.sel;
              }

              PendingResponse service_request(SimContext* ctx, const PendingResponse& request) {
                PendingResponse response = request;
                if (!request.valid) {
                  return response;
                }
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
                if (!response.valid) {
                  return;
                }

                if (response.unmapped) {
                  ctx->faults.push_back(FaultRecord{
                    ctx->cycles,
                    response.write ? kTraceOpWrite : kTraceOpRead,
                    response.addr,
                    response.sel
                  });
                }

                ctx->trace.push_back(WishboneTraceRecord{
                  ctx->cycles,
                  response.write ? kTraceOpWrite : kTraceOpRead,
                  response.addr,
                  response.sel,
                  response.write ? response.data : 0ULL,
                  response.write ? 0ULL : response.read_data
                });
              }

              unsigned int copy_debug_snapshot(SimContext* ctx, unsigned long long* out_words, unsigned int max_words) {
                if (!out_words || max_words == 0) {
                  return 0;
                }

                const auto* root = ctx->dut->rootp;
                const unsigned int count = std::min<unsigned int>(max_words, kDebugWords);
                std::fill(out_words, out_words + count, 0ULL);

                if (count > 0) out_words[0] = root->s1_top__DOT__rst_ctrl_0__DOT__cycle_counter;
                if (count > 1) out_words[1] = root->s1_top__DOT__sys_reset_final;
                if (count > 2) out_words[2] = root->s1_top__DOT__cluster_cken;
                if (count > 3) out_words[3] = root->s1_top__DOT__cmp_grst_l;
                if (count > 4) out_words[4] = root->s1_top__DOT__cmp_arst_l;
                if (count > 5) out_words[5] = root->s1_top__DOT__gdbginit_l;
                if (count > 6) out_words[6] = root->s1_top__DOT__os2wb_inst__DOT__state;
                if (count > 7) out_words[7] = root->s1_top__DOT__os2wb_inst__DOT__cpu;
                if (count > 8) out_words[8] = root->s1_top__DOT__os2wb_inst__DOT__cpx_ready;
                if (count > 9) out_words[9] = root->s1_top__DOT__os2wb_inst__DOT__pcx_req_d;
                if (count > 10) out_words[10] = (root->s1_top__DOT__os2wb_inst__DOT__pcx_packet_d[3U] >> 22U) & 0x1FU;
                if (count > 11) out_words[11] = root->s1_top__DOT__os2wb_inst__DOT__cpx_two_packet;

                if (count > 12) out_words[12] = root->s1_top__DOT__sparc_0__DOT__spc_pcx_req_pq;
                if (count > 13) out_words[13] = root->s1_top__DOT__sparc_0__DOT__cpx_spc_data_rdy_cx2;
                if (count > 14) out_words[14] = root->s1_top__DOT__sparc_0__DOT__tlu__DOT__tcl__DOT__tlu_self_boot_rst_g;
                if (count > 15) out_words[15] = root->s1_top__DOT__sparc_0__DOT__tlu__DOT__tcl__DOT__tlu_self_boot_rst_w2;
                if (count > 16) out_words[16] = root->s1_top__DOT__sparc_0__DOT__tlu__DOT__tlu_ifu_rstthr_i2;
                if (count > 17) out_words[17] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__fcl_reset;
                if (count > 18) out_words[18] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__ifu_reset_l;
                if (count > 19) out_words[19] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__errdp__DOT__fdp_erb_pc_f;
                if (count > 20) out_words[20] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fdp__DOT__npcw_reg__DOT__q;
                if (count > 21) out_words[21] = root->s1_top__DOT__sparc_0__DOT__tlu__DOT__misctl__DOT__dff_ifu_pc_w__DOT__q;
                if (count > 22) out_words[22] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm0__DOT__thr_state;
                if (count > 23) out_words[23] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm1__DOT__thr_state;
                if (count > 24) out_words[24] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm2__DOT__thr_state;
                if (count > 25) out_words[25] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm3__DOT__thr_state;

                if (count > 26) out_words[26] = root->s1_top__DOT__sparc_1__DOT__spc_pcx_req_pq;
                if (count > 27) out_words[27] = root->s1_top__DOT__sparc_1__DOT__cpx_spc_data_rdy_cx2;
                if (count > 28) out_words[28] = root->s1_top__DOT__sparc_1__DOT__tlu__DOT__tcl__DOT__tlu_self_boot_rst_g;
                if (count > 29) out_words[29] = root->s1_top__DOT__sparc_1__DOT__tlu__DOT__tcl__DOT__tlu_self_boot_rst_w2;
                if (count > 30) out_words[30] = root->s1_top__DOT__sparc_1__DOT__tlu__DOT__tlu_ifu_rstthr_i2;
                if (count > 31) out_words[31] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__fcl_reset;
                if (count > 32) out_words[32] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__ifu_reset_l;
                if (count > 33) out_words[33] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__errdp__DOT__fdp_erb_pc_f;
                if (count > 34) out_words[34] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fdp__DOT__npcw_reg__DOT__q;
                if (count > 35) out_words[35] = root->s1_top__DOT__sparc_1__DOT__tlu__DOT__misctl__DOT__dff_ifu_pc_w__DOT__q;
                if (count > 36) out_words[36] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm0__DOT__thr_state;
                if (count > 37) out_words[37] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm1__DOT__thr_state;
                if (count > 38) out_words[38] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm2__DOT__thr_state;
                if (count > 39) out_words[39] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm3__DOT__thr_state;
                if (count > 40) out_words[40] = root->s1_top__DOT__sparc_0__DOT__tlu__DOT__intctl__DOT__tlu_ifu_resumint_i2;
                if (count > 41) out_words[41] = root->s1_top__DOT__sparc_0__DOT__tlu__DOT__intctl__DOT__tlu_ifu_rstthr_i2;
                if (count > 42) out_words[42] = root->s1_top__DOT__sparc_0__DOT__tlu__DOT__intctl__DOT__lsu_tlu_cpx_vld;
                if (count > 43) out_words[43] = root->s1_top__DOT__sparc_0__DOT__tlu__DOT__intctl__DOT__lsu_tlu_cpx_req;
                if (count > 44) out_words[44] = root->s1_top__DOT__sparc_0__DOT__tlu__DOT__intctl__DOT__ind_inc_thrid_i1;
                if (count > 45) out_words[45] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__resum_thr_w;
                if (count > 46) out_words[46] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm0__DOT__completion;
                if (count > 47) out_words[47] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thrfsm0__DOT__schedule;
                if (count > 48) out_words[48] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__start_thread;
                if (count > 49) out_words[49] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__thaw_thread;
                if (count > 50) out_words[50] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__resum_thread;
                if (count > 51) out_words[51] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__all_stall;
                if (count > 52) out_words[52] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__wm_imiss;
                if (count > 53) out_words[53] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__ifq_dtu_thrrdy;
                if (count > 54) out_words[54] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__switch_out;
                if (count > 55) out_words[55] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__dtu_fcl_ntr_s;
                if (count > 56) out_words[56] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__fcl_dtu_stall_bf;
                if (count > 57) out_words[57] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__fcl_swl_swout_f;
                if (count > 58) out_words[58] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__swl__DOT__ifq_swl_stallreq;
                if (count > 59) out_words[59] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__dtu_fcl_ntr_s;
                if (count > 60) out_words[60] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__fetch_bf;
                if (count > 61) out_words[61] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__inst_vld_f;
                if (count > 62) out_words[62] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__kill_curr_f;
                if (count > 63) out_words[63] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__late_flush_w2;
                if (count > 64) out_words[64] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__all_stallreq;
                if (count > 65) out_words[65] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__rst_stallreq;
                if (count > 66) out_words[66] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__lsu_stallreq_d1;
                if (count > 67) out_words[67] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__ffu_stallreq_d1;
                if (count > 68) out_words[68] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__itlb_starv_alert;
                if (count > 69) out_words[69] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__fcl__DOT__ifq_fcl_stallreq;
                if (count > 70) out_words[70] = root->s1_top__DOT__sparc_1__DOT__tlu__DOT__intctl__DOT__tlu_ifu_resumint_i2;
                if (count > 71) out_words[71] = root->s1_top__DOT__sparc_1__DOT__tlu__DOT__intctl__DOT__tlu_ifu_rstthr_i2;
                if (count > 72) out_words[72] = root->s1_top__DOT__sparc_1__DOT__tlu__DOT__intctl__DOT__lsu_tlu_cpx_vld;
                if (count > 73) out_words[73] = root->s1_top__DOT__sparc_1__DOT__tlu__DOT__intctl__DOT__lsu_tlu_cpx_req;
                if (count > 74) out_words[74] = root->s1_top__DOT__sparc_1__DOT__tlu__DOT__intctl__DOT__ind_inc_thrid_i1;
                if (count > 75) out_words[75] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__resum_thr_w;
                if (count > 76) out_words[76] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm0__DOT__completion;
                if (count > 77) out_words[77] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thrfsm0__DOT__schedule;
                if (count > 78) out_words[78] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__start_thread;
                if (count > 79) out_words[79] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__thaw_thread;
                if (count > 80) out_words[80] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__resum_thread;
                if (count > 81) out_words[81] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__all_stall;
                if (count > 82) out_words[82] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__wm_imiss;
                if (count > 83) out_words[83] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__ifq_dtu_thrrdy;
                if (count > 84) out_words[84] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__switch_out;
                if (count > 85) out_words[85] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__dtu_fcl_ntr_s;
                if (count > 86) out_words[86] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__fcl_dtu_stall_bf;
                if (count > 87) out_words[87] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__fcl_swl_swout_f;
                if (count > 88) out_words[88] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__swl__DOT__ifq_swl_stallreq;
                if (count > 89) out_words[89] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__dtu_fcl_ntr_s;
                if (count > 90) out_words[90] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__fetch_bf;
                if (count > 91) out_words[91] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__inst_vld_f;
                if (count > 92) out_words[92] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__kill_curr_f;
                if (count > 93) out_words[93] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__late_flush_w2;
                if (count > 94) out_words[94] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__all_stallreq;
                if (count > 95) out_words[95] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__rst_stallreq;
                if (count > 96) out_words[96] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__lsu_stallreq_d1;
                if (count > 97) out_words[97] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__ffu_stallreq_d1;
                if (count > 98) out_words[98] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__itlb_starv_alert;
	                if (count > 99) out_words[99] = root->s1_top__DOT__sparc_1__DOT__ifu__DOT__fcl__DOT__ifq_fcl_stallreq;
	                if (count > 100) out_words[100] = root->s1_top__DOT__os2wb_inst__DOT__pcx_req;
	                if (count > 101) out_words[101] = root->s1_top__DOT__os2wb_inst__DOT__pcx_req_1;
	                if (count > 102) out_words[102] = root->s1_top__DOT__os2wb_inst__DOT__pcx_req_2;
	                if (count > 103) out_words[103] = root->s1_top__DOT__os2wb_inst__DOT__pcx_atom;
	                if (count > 104) out_words[104] = root->s1_top__DOT__os2wb_inst__DOT__pcx_atom_1;
	                if (count > 105) out_words[105] = root->s1_top__DOT__os2wb_inst__DOT__pcx_atom_2;
	                if (count > 106) out_words[106] = (root->s1_top__DOT__os2wb_inst__DOT__pcx_data[3U] >> 27U) & 0x1U;
	                if (count > 107) out_words[107] = root->s1_top__DOT__os2wb_inst__DOT__pcx_data_123_d;
	                if (count > 108) out_words[108] = root->s1_top__DOT__os2wb_inst__DOT__pcx_fifo_empty;
	                if (count > 109) out_words[109] = root->s1_top__DOT__os2wb_inst__DOT__fifo_rd;
	                if (count > 110) out_words[110] = root->s1_top__DOT__os2wb_inst__DOT__pcx1_fifo_empty;
	                if (count > 111) out_words[111] = root->s1_top__DOT__os2wb_inst__DOT__fifo_rd1;
	                if (count > 112) out_words[112] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__req_valid_d;
	                if (count > 113) out_words[113] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__req_pending_d;
	                if (count > 114) out_words[114] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__lsu_ifu_pcxpkt_ack_d;
	                if (count > 115) out_words[115] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__ifu_lsu_pcxreq_d;
	                if (count > 116) out_words[116] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__newreq_valid;
	                if (count > 117) out_words[117] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__oldreq_valid;
	                if (count > 118) out_words[118] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__nextreq_valid_s;
	                if (count > 119) out_words[119] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__icmiss_qual_s;
	                if (count > 120) out_words[120] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__mil_thr_ready;
	                if (count > 121) out_words[121] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__all_retry_rdy_m1;
	                if (count > 122) out_words[122] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__pcxreq_qual_s;
	                if (count > 123) out_words[123] = root->s1_top__DOT__sparc_0__DOT__lsu__DOT__qctl1__DOT__lsu_ifu_pcxpkt_ack_d;
	                if (count > 124) out_words[124] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__wrt_tir;
	                if (count > 125) out_words[125] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__ifq_fcl_fill_thr;
	                if (count > 126) out_words[126] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__ifc_inv_ifqadv_i2;
	                if (count > 127) out_words[127] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__filltid_i2;
	                if (count > 128) out_words[128] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__imissrtn_next_i2;
	                if (count > 129) out_words[129] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__pred_rdy_i2;
	                if (count > 130) out_words[130] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__finst_i2;
	                if (count > 131) out_words[131] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifq_fcl_fill_thr;
	                if (count > 132) out_words[132] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__mil0_state;
	                if (count > 133) out_words[133] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__fill_retn_thr_i2;
	                if (count > 134) out_words[134] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__imissrtn_i2;
	                if (count > 135) out_words[135] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__ifd_ifc_cpxvld_i2;
	                if (count > 136) out_words[136] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__cpxreq_i2;
	                if (count > 137) out_words[137] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__ifqadv_i1;
	                if (count > 138) out_words[138] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__fcl_ifq_thr_s1;
	                if (count > 139) out_words[139] = root->s1_top__DOT__sparc_0__DOT__ifu__DOT__ifqctl__DOT__fcl_ifq_icmiss_s1;
	                if (count > 140) out_words[140] = root->s1_top__DOT__os2wb_inst__DOT__cpx_packet[4U];
	                if (count > 141) out_words[141] = root->s1_top__DOT__cpx_spc_data_cx2[4U];
	                if (count > 142) out_words[142] = root->s1_top__DOT__os2wb_inst__DOT__cpx_packet_1[4U];
	                if (count > 143) out_words[143] = root->s1_top__DOT__os2wb_inst__DOT__cpx_packet_2[4U];

	                return count;
	              }

              void step_cycle(SimContext* ctx) {
                bool reset_active = ctx->reset_cycles_remaining > 0;
                PendingResponse acked_response = reset_active ? PendingResponse{} : ctx->pending_response;

                apply_inputs(ctx, reset_active, acked_response.valid ? &acked_response : nullptr);
                ctx->dut->eval();

                if (acked_response.valid) {
                  record_acknowledged_response(ctx, acked_response);
                }

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
                if (ctx->reset_cycles_remaining > 0) {
                  ctx->reset_cycles_remaining -= 1;
                }
              }

              }  // namespace

              extern "C" {

              void* sim_create(void) {
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

              void sim_clear_memory(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                ctx->flash.clear();
                ctx->dram.clear();
                ctx->protected_dram_limit = 0;
                clear_runtime_state(ctx);
              }

              void sim_reset(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                clear_runtime_state(ctx);
                drive_defaults(ctx);
                ctx->dut->sys_reset_i = 1;
                ctx->dut->sys_clock_i = 0;
                ctx->dut->eval();
              }

              void sim_load_flash(void* sim, const unsigned char* data, unsigned long long base_addr, unsigned int len) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                for (unsigned int i = 0; i < len; ++i) {
                  ctx->flash[canonical_bus_addr(base_addr + i)] = data[i];
                }
              }

              void sim_load_memory(void* sim, const unsigned char* data, unsigned long long base_addr, unsigned int len) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                for (unsigned int i = 0; i < len; ++i) {
                  ctx->dram[canonical_bus_addr(base_addr + i)] = data[i];
                }
                if (canonical_bus_addr(base_addr) == 0ULL) {
                  ctx->protected_dram_limit = std::max<std::uint64_t>(ctx->protected_dram_limit, static_cast<std::uint64_t>(len));
                }
              }

              unsigned int sim_read_memory(void* sim, unsigned long long addr, unsigned char* out, unsigned int len) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                for (unsigned int i = 0; i < len; ++i) {
                  std::uint8_t byte = 0;
                  read_mapped_byte(ctx, addr + i, &byte);
                  out[i] = byte;
                }
                return len;
              }

              unsigned int sim_write_memory(void* sim, unsigned long long addr, const unsigned char* data, unsigned int len) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                for (unsigned int i = 0; i < len; ++i) {
                  ctx->dram[addr + i] = data[i];
                }
                return len;
              }

              unsigned int sim_run_cycles(void* sim, unsigned int n_cycles) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                for (unsigned int ran = 0; ran < n_cycles; ++ran) {
                  step_cycle(ctx);
                }
                return n_cycles;
              }

              unsigned int sim_wishbone_trace_count(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                return static_cast<unsigned int>(ctx->trace.size());
              }

              unsigned int sim_copy_wishbone_trace(void* sim, unsigned long long* out_words, unsigned int max_records) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                unsigned int count = std::min<unsigned int>(max_records, static_cast<unsigned int>(ctx->trace.size()));
                for (unsigned int i = 0; i < count; ++i) {
                  const auto& record = ctx->trace[i];
                  out_words[i * 6 + 0] = record.cycle;
                  out_words[i * 6 + 1] = record.op;
                  out_words[i * 6 + 2] = record.addr;
                  out_words[i * 6 + 3] = record.sel;
                  out_words[i * 6 + 4] = record.write_data;
                  out_words[i * 6 + 5] = record.read_data;
                }
                return count;
              }

              unsigned int sim_unmapped_access_count(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                return static_cast<unsigned int>(ctx->faults.size());
              }

              unsigned int sim_copy_unmapped_accesses(void* sim, unsigned long long* out_words, unsigned int max_records) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                unsigned int count = std::min<unsigned int>(max_records, static_cast<unsigned int>(ctx->faults.size()));
                for (unsigned int i = 0; i < count; ++i) {
                  const auto& record = ctx->faults[i];
                  out_words[i * 4 + 0] = record.cycle;
                  out_words[i * 4 + 1] = record.op;
                  out_words[i * 4 + 2] = record.addr;
                  out_words[i * 4 + 3] = record.sel;
                }
                return count;
              }

              unsigned int sim_copy_debug_snapshot(void* sim, unsigned long long* out_words, unsigned int max_words) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                return copy_debug_snapshot(ctx, out_words, max_words);
              }

              }  // extern "C"
            CPP

            write_file_if_changed(header_file, header)
            write_file_if_changed(cpp_file, cpp)
          end

          def load_shared_library(lib_path)
            @lib = verilog_simulator.load_library!(lib_path)
            @sim_create = Fiddle::Function.new(@lib['sim_create'], [], Fiddle::TYPE_VOIDP)
            @sim_destroy = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_clear_memory_fn = Fiddle::Function.new(@lib['sim_clear_memory'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_reset = Fiddle::Function.new(@lib['sim_reset'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_load_flash_fn = Fiddle::Function.new(
              @lib['sim_load_flash'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_UINT],
              Fiddle::TYPE_VOID
            )
            @sim_load_memory_fn = Fiddle::Function.new(
              @lib['sim_load_memory'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_UINT],
              Fiddle::TYPE_VOID
            )
            @sim_read_memory_fn = Fiddle::Function.new(
              @lib['sim_read_memory'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_write_memory_fn = Fiddle::Function.new(
              @lib['sim_write_memory'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_run_cycles_fn = Fiddle::Function.new(
              @lib['sim_run_cycles'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_wishbone_trace_count_fn = Fiddle::Function.new(
              @lib['sim_wishbone_trace_count'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )
            @sim_copy_wishbone_trace_fn = Fiddle::Function.new(
              @lib['sim_copy_wishbone_trace'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_unmapped_access_count_fn = Fiddle::Function.new(
              @lib['sim_unmapped_access_count'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )
            @sim_copy_unmapped_accesses_fn = Fiddle::Function.new(
              @lib['sim_copy_unmapped_accesses'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_copy_debug_snapshot_fn = Fiddle::Function.new(
              @lib['sim_copy_debug_snapshot'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_ctx = @sim_create.call
          end

	          def decode_core_debug(words, base, extra_base)
	            {
              pcx_req: words[base],
              cpx_ready: !words[base + 1].zero?,
              self_boot_rst_g: !words[base + 2].zero?,
              self_boot_rst_w2: !words[base + 3].zero?,
              rstthr_i2: words[base + 4],
              fcl_reset: !words[base + 5].zero?,
              ifu_reset_l: !words[base + 6].zero?,
              fetch_pc_f: words[base + 7],
              npc_w: words[base + 8],
              ifu_pc_w: words[base + 9],
              thread_states: [
                words[base + 10],
                words[base + 11],
                words[base + 12],
                words[base + 13]
              ],
              resumint_i2: !words[extra_base].zero?,
              rstthr_i2_intctl: words[extra_base + 1],
              lsu_tlu_cpx_vld: !words[extra_base + 2].zero?,
              lsu_tlu_cpx_req: words[extra_base + 3],
              int_thread_id: words[extra_base + 4],
              resum_thr_w: !words[extra_base + 5].zero?,
              completion: words[extra_base + 6],
              schedule: words[extra_base + 7],
              start_thread: words[extra_base + 8],
              thaw_thread: words[extra_base + 9],
              resum_thread: words[extra_base + 10],
              all_stall: words[extra_base + 11],
              wm_imiss: words[extra_base + 12],
              ifq_dtu_thrrdy: words[extra_base + 13],
              switch_out: words[extra_base + 14],
              next_thread_ready_swl: words[extra_base + 15],
              stall_bf: words[extra_base + 16],
              swout_f: words[extra_base + 17],
              ifq_stallreq: words[extra_base + 18],
              next_thread_ready_ifu: words[extra_base + 19],
              fetch_bf: words[extra_base + 20],
              inst_vld_f: words[extra_base + 21],
              kill_curr_f: words[extra_base + 22],
              late_flush_w2: words[extra_base + 23],
              all_stallreq: words[extra_base + 24],
              rst_stallreq: words[extra_base + 25],
              lsu_stallreq_d1: words[extra_base + 26],
              ffu_stallreq_d1: words[extra_base + 27],
              itlb_starv_alert: words[extra_base + 28],
	              ifq_fcl_stallreq: words[extra_base + 29]
	            }
	          end

	          def decode_bridge_capture_debug(words, base)
	            {
	              pcx_req: words[base],
	              pcx_req_1: words[base + 1],
	              pcx_req_2: words[base + 2],
	              pcx_atom: !words[base + 3].zero?,
	              pcx_atom_1: !words[base + 4].zero?,
	              pcx_atom_2: !words[base + 5].zero?,
	              pcx_data_123: !words[base + 6].zero?,
	              pcx_data_123_d: !words[base + 7].zero?,
	              pcx_fifo_empty: !words[base + 8].zero?,
	              fifo_rd: !words[base + 9].zero?,
	              pcx1_fifo_empty: !words[base + 10].zero?,
	              fifo_rd1: !words[base + 11].zero?
	            }
	          end

	          def decode_ifq_debug(words, base)
	            {
	              req_valid_d: !words[base].zero?,
	              req_pending_d: !words[base + 1].zero?,
	              lsu_ifu_pcxpkt_ack_d: !words[base + 2].zero?,
	              ifu_lsu_pcxreq_d: !words[base + 3].zero?,
	              newreq_valid: !words[base + 4].zero?,
	              oldreq_valid: !words[base + 5].zero?,
	              nextreq_valid_s: !words[base + 6].zero?,
	              icmiss_qual_s: !words[base + 7].zero?,
	              mil_thr_ready: words[base + 8],
	              all_retry_rdy_m1: words[base + 9],
	              pcxreq_qual_s: words[base + 10],
	              lsu_qctl_ack_d: !words[base + 11].zero?
	            }
	          end

	          def decode_ifq_fill_debug(words, base)
	            {
	              wrt_tir: words[base],
	              ifq_fcl_fill_thr: words[base + 1],
	              ifc_inv_ifqadv_i2: !words[base + 2].zero?,
	              filltid_i2: words[base + 3],
	              imissrtn_next_i2: !words[base + 4].zero?,
	              pred_rdy_i2: words[base + 5],
	              finst_i2: words[base + 6],
	              ifu_ifq_fcl_fill_thr: words[base + 7],
	              mil0_state: words[base + 8],
	              fill_retn_thr_i2: words[base + 9],
	              imissrtn_i2: !words[base + 10].zero?,
	              ifd_ifc_cpxvld_i2: !words[base + 11].zero?,
	              cpxreq_i2: words[base + 12],
	              ifqadv_i1: !words[base + 13].zero?,
	              fcl_ifq_thr_s1: words[base + 14],
	              fcl_ifq_icmiss_s1: !words[base + 15].zero?,
	              os2wb_cpx_packet_word4: words[base + 16],
	              top_cpx_packet_word4: words[base + 17],
	              os2wb_cpx_packet1_word4: words[base + 18],
	              os2wb_cpx_packet2_word4: words[base + 19]
	            }
	          end

	          def decode_u64_be(bytes)
            Array(bytes).first(8).reduce(0) { |acc, byte| (acc << 8) | (byte.to_i & 0xFF) }
          end

          def pack_bytes(bytes)
            if bytes.is_a?(String)
              bytes.b
            elsif bytes.respond_to?(:pack)
              Array(bytes).pack('C*')
            else
              Array(bytes).pack('C*')
            end
          end

          def unpack_u64_words(pointer, count)
            pointer.to_s(count * 8).unpack('Q<*')
          end

          def sanitize_identifier(value)
            value.to_s.gsub(/[^A-Za-z0-9_]/, '_')
          end

          def write_file_if_changed(path, content)
            verilog_simulator.write_file_if_changed(path, content)
          end
        end

        attr_reader :clock_count

        def initialize(adapter: nil, adapter_factory: nil, fast_boot: true)
          factory = adapter_factory || -> { DefaultAdapter.new(fast_boot: fast_boot) }
          @adapter = adapter || factory.call
          @clock_count = 0
        end

        def native?
          true
        end

        def simulator_type
          @adapter.respond_to?(:simulator_type) ? @adapter.simulator_type : :hdl_verilator
        end

        def backend
          :verilator
        end

        def reset!
          @clock_count = 0
          @adapter.reset!
          self
        end

        def run_cycles(n)
          ran = @adapter.run_cycles(n.to_i)
          @clock_count += n.to_i if ran.nil?
          @clock_count += ran.to_i if ran
          ran
        end

        def load_images(boot_image:, program_image:)
          @clock_count = 0
          @adapter.load_images(boot_image: boot_image, program_image: program_image)
          self
        end

        def read_memory(addr, length)
          @adapter.read_memory(addr.to_i, length.to_i)
        end

        def write_memory(addr, bytes)
          @adapter.write_memory(addr.to_i, bytes)
        end

        def mailbox_status
          @adapter.mailbox_status
        end

        def mailbox_value
          @adapter.mailbox_value
        end

        def wishbone_trace
          Integration.normalize_wishbone_trace(@adapter.wishbone_trace)
        end

        def unmapped_accesses
          Array(@adapter.unmapped_accesses)
        end

        def debug_snapshot
          return {} unless @adapter.respond_to?(:debug_snapshot)

          @adapter.debug_snapshot
        end

        def completed?
          mailbox_status != 0
        end

        def run_until_complete(max_cycles:, batch_cycles: 1_000)
          while clock_count < max_cycles.to_i
            run_cycles([batch_cycles.to_i, max_cycles.to_i - clock_count].min)
            return completion_result if completed? || unmapped_accesses.any?
          end

          completion_result(timeout: true)
        end

        private

        def completion_result(timeout: false)
          trace = wishbone_trace
          faults = unmapped_accesses
          {
            completed: completed?,
            timeout: timeout,
            cycles: clock_count,
            boot_handoff_seen: trace.any? { |event| event.addr.to_i >= Integration::PROGRAM_BASE },
            secondary_core_parked: faults.empty?,
            mailbox_status: mailbox_status,
            mailbox_value: mailbox_value,
            unmapped_accesses: faults,
            wishbone_trace: trace
          }
        end
      end

      VerilatorRunner = VerilogRunner
    end
  end
end
