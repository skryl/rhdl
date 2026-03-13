# frozen_string_literal: true

require 'digest'
require 'etc'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'shellwords'

require 'rhdl/codegen'

require_relative '../integration/import_loader'
require_relative 'shared_runtime_support'

module RHDL
  module Examples
    module SPARC64
      class ArcilatorRunner
        include Integration
        include SharedRuntimeSupport::AdapterMethods

        BUILD_BASE = File.expand_path('../../.arcilator_build', __dir__).freeze
        OBSERVE_FLAGS = %w[--observe-ports --observe-wires --observe-registers].freeze
        DEFAULT_JIT_RESET_CYCLES = 4
        DEFAULT_JIT_SMOKE_CYCLES = 32
        DEBUG_WORDS = 99
        DEBUG_SIGNAL_SPECS = {
          core0_stb_cam_wr_data_hi30_q: { name: 'sparc_0/lsu/stb_cam/rt_tmp_1_30', preferred_type: 'register' },
          core0_stb_cam_wr_data_lo15_q: { name: 'sparc_0/lsu/stb_cam/rt_tmp_2_15', preferred_type: 'register' },
          core0_pcx_xmit_ff_q: { name: 'sparc_0/lsu/qdp1/pcx_xmit_ff/q', preferred_type: 'register' },
          core0_ff_cpx_data_cx3: { name: 'sparc_0/ff_cpx/cpx_spc_data_cx3', preferred_type: 'register' },
          core0_qctl2_ifill_pkt_fwd_done_ff: { name: 'sparc_0/lsu/qctl2/ifill_pkt_fwd_done_ff/q', preferred_type: 'register' },
          core0_qctl2_dfq_wptr_ff: { name: 'sparc_0/lsu/qctl2/dfq_wptr_ff/q', preferred_type: 'register' },
          core0_qctl2_dfq_vld: { name: 'sparc_0/lsu/qctl2/dfq_vld/q', preferred_type: 'register' },
          core0_qctl2_dfq_inv: { name: 'sparc_0/lsu/qctl2/dfq_inv/q', preferred_type: 'register' },
          core0_qctl2_rvld_stgd1: { name: 'sparc_0/lsu/qctl2/rvld_stgd1/q', preferred_type: 'register' },
          core0_qctl2_rvld_stgd1_new: { name: 'sparc_0/lsu/qctl2/rvld_stgd1_new/q', preferred_type: 'register' },
          core0_qdp2_dfq_data_stg: { name: 'sparc_0/lsu/qdp2/dfq_data_stg/q', preferred_type: 'register' },
          core0_pcx_atom_q: { name: 'sparc_0/lsu/qctl1/ff_spc_pcx_atom_pq/q', preferred_type: 'register' },
          core0_store_pkt_d1: { name: 'sparc_0/lsu/qdp1/ff_spu_lsu_ldst_pckt_d1/q', preferred_type: 'register' },
          core0_stb_cam_wptr_vld_q: { name: 'sparc_0/lsu/stb_cam/rt_tmp_3_1', preferred_type: 'register' },
          core0_stb_cam_rptr_vld_q: { name: 'sparc_0/lsu/stb_cam/rt_tmp_4_1', preferred_type: 'register' },
          core0_stb_cam_rw_tid_q: { name: 'sparc_0/lsu/stb_cam/rt_tmp_5_2', preferred_type: 'register' },
          core0_stb_cam_alt_wsel_q: { name: 'sparc_0/lsu/stb_cam/rt_tmp_6_1', preferred_type: 'register' },
          core0_stb_cam_rw_addr_q: { name: 'sparc_0/lsu/stb_cam/rt_tmp_7_5', preferred_type: 'register' },
          core0_stb_cam_r0_addr: { name: 'sparc_0/lsu/stb_cam/stb_ramc_ext/R0_addr', preferred_type: 'wire' },
          core0_stb_cam_rdata_q: { name: 'sparc_0/lsu/stb_cam/rt_tmp_8_45', preferred_type: 'register' },
          core0_stb_cam_r0_data: { name: 'sparc_0/lsu/stb_cam/stb_ramc_ext/R0_data', preferred_type: 'wire' },
          core0_stb_data_local_dout: { name: 'sparc_0/lsu/stb_data/local_dout', preferred_type: 'register' },
          core0_dtlb_bypass_e: { name: 'sparc_0/lsu/dctl_lsu_dtlb_bypass_e', preferred_type: 'wire' },
          core0_dtlb_bypass_va: { name: 'sparc_0/lsu/dtlb__tlb_bypass_va__bridge', preferred_type: 'wire' },
          core0_dtlb_cam_key: { name: 'sparc_0/lsu/dtlb__tlb_cam_key__bridge', preferred_type: 'wire' },
          core0_dtlb_va_tag_plus: { name: 'sparc_0/lsu/dtlb/rt_tmp_3_31', preferred_type: 'register' },
          core0_dtlb_vrtl_pgnum_m: { name: 'sparc_0/lsu/dtlb/rt_tmp_4_30', preferred_type: 'register' },
          core0_dtlb_bypass_d: { name: 'sparc_0/lsu/dtlb/rt_tmp_5_1', preferred_type: 'register' },
          core0_dtlb_pgnum_m: { name: 'sparc_0/lsu/dtlb/rt_tmp_6_30', preferred_type: 'register' },
          core0_dtlb_pgnum_crit: { name: 'sparc_0/lsu/dtlb_tlb_pgnum_crit', preferred_type: 'wire' },
          core0_dctldp_va_stgm: { name: 'sparc_0/lsu/dctldp/va_stgm/q', preferred_type: 'register' },
          core0_exu_rs1_data_dff: { name: 'sparc_0/exu/bypass/rs1_data_dff/q', preferred_type: 'register' },
          core0_exu_rs2_data_dff: { name: 'sparc_0/exu/bypass/rs2_data_dff/q', preferred_type: 'register' },
          core0_exu_c_used_dff: { name: 'sparc_0/exu/ecl/c_used_dff/q', preferred_type: 'register' },
          core0_exu_sub_dff: { name: 'sparc_0/exu/alu/addsub/sub_dff/q', preferred_type: 'register' },
          core0_exu_rd_data_e2m: { name: 'sparc_0/exu/bypass/dff_rd_data_e2m/q', preferred_type: 'register' },
          core0_exu_rd_data_m2w: { name: 'sparc_0/exu/bypass/dff_rd_data_m2w/q', preferred_type: 'register' },
          core0_exu_rd_data_g2w: { name: 'sparc_0/exu/bypass/dff_rd_data_g2w/q', preferred_type: 'register' },
          core0_exu_dfill_data_dff: { name: 'sparc_0/exu/bypass/dfill_data_dff/q', preferred_type: 'register' },
          core0_tlu_stgg_eldxa: { name: 'sparc_0/tlu/mmu_dp/stgg_eldxa/q', preferred_type: 'register' },
          core0_irf_active_win_thr_rd_w_neg: { name: 'sparc_0/exu/irf/active_win_thr_rd_w_neg', preferred_type: 'register' },
          core0_irf_thr_rd_w_neg: { name: 'sparc_0/exu/irf/thr_rd_w_neg', preferred_type: 'register' },
          core0_irf_active_win_thr_rd_w2_neg: { name: 'sparc_0/exu/irf/active_win_thr_rd_w2_neg', preferred_type: 'register' },
          core0_irf_thr_rd_w2_neg: { name: 'sparc_0/exu/irf/thr_rd_w2_neg', preferred_type: 'register' },
          core0_ifq_thrrdy_ctr: { name: 'sparc_0/ifu/swl/thrrdy_ctr/q', preferred_type: 'register' },
          core0_ifqop_reg: { name: 'sparc_0/ifu/ifqdp/ifqop_reg/q', preferred_type: 'register' },
          core0_ifq_ibuf: { name: 'sparc_0/ifu/ifqdp/ibuf/q', preferred_type: 'register' },
          core0_ifq_imsf_ff: { name: 'sparc_0/ifu/ifqctl/imsf_ff/q', preferred_type: 'register' },
          core0_ifq_cpxreq_reg: { name: 'sparc_0/ifu/ifqctl/cpxreq_reg/q', preferred_type: 'register' },
          core0_ifq_qadv_ff: { name: 'sparc_0/ifu/ifqctl/qadv_ff/q', preferred_type: 'register' },
          core0_ifq_pcxreq_reg: { name: 'sparc_0/ifu/ifqdp/pcxreq_reg/q', preferred_type: 'register' },
          core0_ifq_pcxreqvd_ff: { name: 'sparc_0/ifu/ifqctl/pcxreqvd_ff/q', preferred_type: 'register' },
          core0_ifq_pcxreqve_ff: { name: 'sparc_0/ifu/ifqctl/pcxreqve_ff/q', preferred_type: 'register' },
          os2wb_rt_tmp_42: { name: 'os2wb_inst/rt_tmp_42_145', preferred_type: 'register' },
          os2wb_rt_tmp_43: { name: 'os2wb_inst/rt_tmp_43_145', preferred_type: 'register' },
          os2wb_rt_tmp_19: { name: 'os2wb_inst/rt_tmp_19_145', preferred_type: 'register' },
          os2wb_rt_tmp_30: { name: 'os2wb_inst/rt_tmp_30_145', preferred_type: 'register' },
          os2wb_fifo_state: { name: 'os2wb_inst/pcx_fifo_inst/rt_tmp_3_3', preferred_type: 'register' },
          os2wb_rt_tmp_16_5: { name: 'os2wb_inst/rt_tmp_16_5', preferred_type: 'register' },
          os2wb_rt_tmp_20_1: { name: 'os2wb_inst/rt_tmp_20_1', preferred_type: 'wire' },
          os2wb_rt_tmp_21_1: { name: 'os2wb_inst/rt_tmp_21_1', preferred_type: 'wire' },
          os2wb_rt_tmp_22_1: { name: 'os2wb_inst/rt_tmp_22_1', preferred_type: 'wire' },
          os2wb_rt_tmp_23_8: { name: 'os2wb_inst/rt_tmp_23_8', preferred_type: 'wire' },
          os2wb_rt_tmp_24_64: { name: 'os2wb_inst/rt_tmp_24_64', preferred_type: 'wire' },
          os2wb_rt_tmp_25_64: { name: 'os2wb_inst/rt_tmp_25_64', preferred_type: 'wire' },
          os2wb_rt_tmp_26_124: { name: 'os2wb_inst/rt_tmp_26_124', preferred_type: 'register' },
          os2wb_rt_tmp_38_1: { name: 'os2wb_inst/rt_tmp_38_1', preferred_type: 'wire' },
          os2wb_fifo_rd_ptr: { name: 'os2wb_inst/pcx_fifo_inst/rt_tmp_1_2', preferred_type: 'register' },
          os2wb_fifo_wr_ptr: { name: 'os2wb_inst/pcx_fifo_inst/rt_tmp_2_2', preferred_type: 'register' },
          os2wb_fifo_slot0_meta: { name: 'os2wb_inst/pcx_fifo_inst/rt_tmp_4_6', preferred_type: 'register' },
          os2wb_fifo_slot0_payload: { name: 'os2wb_inst/pcx_fifo_inst/rt_tmp_5_124', preferred_type: 'register' },
          os2wb_fifo_slot1_meta: { name: 'os2wb_inst/pcx_fifo_inst/rt_tmp_6_6', preferred_type: 'register' },
          os2wb_fifo_slot1_payload: { name: 'os2wb_inst/pcx_fifo_inst/rt_tmp_7_124', preferred_type: 'register' }
        }.freeze

        attr_reader :import_dir, :build_dir, :top_module_name, :core_mlir_path, :build_result, :clock_count, :cleanup_mode

        def initialize(import_dir: nil, fast_boot: true,
                       build_cache_root: Integration::ImportLoader::DEFAULT_BUILD_CACHE_ROOT,
                       reference_root: Integration::ImportLoader::DEFAULT_REFERENCE_ROOT,
                       import_top: Integration::ImportLoader::DEFAULT_IMPORT_TOP,
                       import_top_file: nil,
                       build_dir: nil,
                       compile_now: true,
                       jit: false,
                       cleanup_mode: :syntax_only)
          @import_dir = resolve_import_dir(
            import_dir: import_dir,
            fast_boot: fast_boot,
            build_cache_root: build_cache_root,
            reference_root: reference_root,
            import_top: import_top,
            import_top_file: import_top_file
          )
          @jit = !!jit
          @cleanup_mode = (cleanup_mode || :syntax_only).to_sym
          @top_module_name = import_top.to_s
          @core_mlir_path = resolve_core_mlir_path!
          @build_dir = File.expand_path(build_dir || default_build_dir)
          @clock_count = 0
          @build_result = compile_now ? build! : nil
        end

        def native?
          true
        end

        def simulator_type
          :hdl_arcilator
        end

        def backend
          :arcilator
        end

        def jit?
          @jit
        end

        def compiled?
          !!(@build_result && @build_result[:success])
        end

        def runtime_contract_ready?
          true
        end

        def subprocess_runtime?
          true
        end

        def run_cycles(n)
          ensure_runtime_built!
          response = send_jit_command("RUN #{n.to_i}")
          _tag, cycles_run = response.split(' ', 2)
          ran = cycles_run.to_i
          @clock_count += ran
          ran
        end

        def reset!
          @clock_count = 0
          ensure_runtime_built!
          send_jit_command('RESET')
          self
        end

        def load_images(boot_image:, program_image:)
          @clock_count = 0
          ensure_runtime_built!
          send_jit_command('CLEAR_MEMORY')
          load_flash(boot_image, base_addr: Integration::FLASH_BOOT_BASE)
          load_memory(boot_image, base_addr: 0)
          load_memory(boot_image, base_addr: Integration::BOOT_PROM_ALIAS_BASE)
          load_memory(program_image, base_addr: Integration::PROGRAM_BASE)
          reset!
          self
        end

        def load_flash(bytes, base_addr:)
          ensure_runtime_built!
          send_jit_payload_command("LOAD_FLASH #{base_addr.to_i}", bytes)
          self
        end

        def load_memory(bytes, base_addr:)
          ensure_runtime_built!
          send_jit_payload_command("LOAD_MEMORY #{base_addr.to_i}", bytes)
          self
        end

        def read_memory(addr, length)
          ensure_runtime_built!
          response = send_jit_command("READ_MEMORY #{addr.to_i} #{length.to_i}")
          _tag, hex = response.split(' ', 2)
          parse_jit_hex_bytes(hex)
        end

        def write_memory(addr, bytes)
          ensure_runtime_built!
          response = send_jit_payload_command("WRITE_MEMORY #{addr.to_i}", bytes)
          _tag, count = response.split(' ', 2)
          count.to_i
        end

        def wishbone_trace
          ensure_runtime_built!
          response = send_jit_command('TRACE')
          _tag, count, hex = response.split(' ', 3)
          words = parse_jit_u64_words(hex, count.to_i * SharedRuntimeSupport::TRACE_WORDS)
          words.each_slice(SharedRuntimeSupport::TRACE_WORDS).map do |cycle, op, addr, sel, write_data, read_data|
            write = !op.to_i.zero?
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
          ensure_runtime_built!
          response = send_jit_command('FAULTS')
          _tag, count, hex = response.split(' ', 3)
          words = parse_jit_u64_words(hex, count.to_i * SharedRuntimeSupport::FAULT_WORDS)
          words.each_slice(SharedRuntimeSupport::FAULT_WORDS).map do |cycle, op, addr, sel|
            {
              cycle: cycle,
              op: op.to_i.zero? ? :read : :write,
              addr: addr,
              sel: sel
            }
          end
        end

        def completed?
          mailbox_status != 0
        end

        def run_until_complete(max_cycles:, batch_cycles: 1_000)
          ensure_runtime_built!
          while clock_count < max_cycles.to_i
            run_cycles([batch_cycles.to_i, max_cycles.to_i - clock_count].min)
            return completion_result if completed? || unmapped_accesses.any?
          end

          completion_result(timeout: true)
        end

        def debug_snapshot
          words =
            ensure_runtime_built!
            response = send_jit_command('DEBUG')
            _tag, count, hex = response.split(' ', 3)
            parse_jit_u64_words(hex, count.to_i)

          {
            cycle_counter: words[0],
            wbm_cycle_o: words[1],
            wbm_strobe_o: words[2],
            wbm_we_o: words[3],
            wbm_addr_o: words[4],
            wbm_data_o: words[5],
            wbm_sel_o: words[6],
            core0_pcx_xmit_ff_q_low64: words[7],
            core0_pcx_atom_q: words[8],
            os2wb_rt_tmp_42_low64: words[9],
            os2wb_rt_tmp_43_low64: words[10],
            os2wb_rt_tmp_19_low64: words[11],
            os2wb_fifo_state: words[12],
            core0_pcx_xmit_ff_q_hi64: words[13],
            os2wb_rt_tmp_42_hi64: words[14],
            os2wb_rt_tmp_43_hi64: words[15],
            os2wb_rt_tmp_19_hi64: words[16],
            os2wb_rt_tmp_30_hi64: words[17],
            os2wb_rt_tmp_42_top: words[18],
            os2wb_rt_tmp_43_top: words[19],
            os2wb_rt_tmp_19_top: words[20],
            os2wb_rt_tmp_30_top: words[21],
            os2wb_rt_tmp_16_5: words[22],
            os2wb_rt_tmp_20_1: words[23],
            os2wb_rt_tmp_21_1: words[24],
            os2wb_rt_tmp_22_1: words[25],
            os2wb_rt_tmp_23_8: words[26],
            os2wb_rt_tmp_24_64: words[27],
            os2wb_rt_tmp_25_64: words[28],
            os2wb_rt_tmp_26_low64: words[29],
            os2wb_rt_tmp_26_hi64: words[30],
            os2wb_rt_tmp_38_1: words[31],
            os2wb_fifo_rd_ptr: words[32],
            os2wb_fifo_wr_ptr: words[33],
            os2wb_fifo_slot0_meta: words[34],
            os2wb_fifo_slot0_low64: words[35],
            os2wb_fifo_slot0_hi64: words[36],
            os2wb_fifo_slot1_meta: words[37],
            os2wb_fifo_slot1_low64: words[38],
            os2wb_fifo_slot1_hi64: words[39],
            os2wb_fifo_slot1_top: words[40],
            core0_stb_cam_rdata_q: words[41],
            core0_stb_cam_r0_data: words[42],
            core0_stb_data_local_dout_low64: words[43],
            core0_stb_data_local_dout_hi16: words[44],
            core0_stb_cam_wptr_vld_q: words[45],
            core0_stb_cam_rptr_vld_q: words[46],
            core0_stb_cam_rw_tid_q: words[47],
            core0_stb_cam_rw_addr_q: words[48],
            core0_stb_cam_r0_addr: words[49],
            core0_stb_cam_wr_data_hi30_q: words[50],
            core0_stb_cam_wr_data_lo15_q: words[51],
            core0_stb_cam_wdata_ramc_q: ((words[50] << 15) | words[51]),
            core0_stb_cam_alt_wsel_q: words[52],
            core0_dtlb_bypass_e: words[53],
            core0_dtlb_bypass_va: words[54],
            core0_dtlb_cam_key: words[55],
            core0_dtlb_va_tag_plus: words[56],
            core0_dtlb_vrtl_pgnum_m: words[57],
            core0_dtlb_bypass_d: words[58],
            core0_dtlb_pgnum_m: words[59],
            core0_dtlb_pgnum_crit: words[60],
            core0_store_pkt_d1_low64: words[61],
            core0_store_pkt_d1_hi64: words[62],
            core0_store_pkt_d1_top: words[63],
            core0_dctldp_va_stgm: words[64],
            core0_exu_rs1_data_dff: words[65],
            core0_exu_rs2_data_dff: words[66],
            core0_exu_c_used_dff: words[67],
            core0_exu_sub_dff: words[68],
            core0_exu_rd_data_e2m: words[69],
            core0_exu_rd_data_m2w: words[70],
            core0_exu_rd_data_g2w: words[71],
            core0_exu_dfill_data_dff: words[72],
            core0_tlu_stgg_eldxa: words[73],
            core0_irf_active_win_thr_rd_w_neg: words[74],
            core0_irf_thr_rd_w_neg: words[75],
            core0_irf_active_win_thr_rd_w2_neg: words[76],
            core0_irf_thr_rd_w2_neg: words[77],
            core0_ifq_thrrdy_ctr: words[78],
            core0_ifq_imsf_ff: words[79],
            core0_ifq_pcxreqvd_ff: words[80],
            core0_ifq_pcxreqve_ff: words[81],
            core0_ifq_pcxreq_reg: words[82],
            core0_ifqop_reg_low64: words[83],
            core0_ifqop_reg_hi64: words[84],
            core0_ifqop_reg_top: words[85],
            core0_ifq_cpxreq_reg: words[86],
            core0_ifq_qadv_ff: words[87],
            core0_ifq_ibuf_top: words[88],
            core0_ff_cpx_data_cx3_top: words[89],
            core0_qctl2_ifill_pkt_fwd_done_ff: words[90],
            core0_qctl2_dfq_wptr_ff: words[91],
            core0_qctl2_dfq_vld: words[92],
            core0_qctl2_dfq_inv: words[93],
            core0_qctl2_rvld_stgd1: words[94],
            core0_qctl2_rvld_stgd1_new: words[95],
            core0_qdp2_dfq_data_stg_low64: words[96],
            core0_qdp2_dfq_data_stg_hi64: words[97],
            core0_qdp2_dfq_data_stg_top: words[98],
            core0_store_pkt_d1_addr: (words[61] & ((1 << 40) - 1)),
            core0_stb_data_addr_nibble: (words[44] & 0xF),
            core0_stb_packet_addr: (((words[41] >> 9) << 4) | (words[44] & 0xF)),
            core0_stb_cam_wdata_addr36_q: (words[50] >> 9),
            core0_stb_cam_wdata_meta15_q: words[51],
            core0_stb_cam_wdata_addr_low6_q: ((words[51] >> 9) & 0x3F),
            core0_stb_cam_wdata_flags9_q: (words[51] & 0x1FF),
            core0_stb_cam_wdata_addr40_q: (((words[50] << 6) | ((words[51] >> 9) & 0x3F)) << 4),
            core0_ifqop_cpxvld_bit: ((words[85] >> 16) & 0x1),
            core0_ifqop_cpxreq_top5: ((words[85] >> 12) & 0x1F),
            core0_ifq_ibuf_cpxreq_top5: ((words[88] >> 12) & 0x1F),
            core0_ff_cpx_cpxreq_top5: ((words[89] >> 12) & 0x1F),
            core0_qctl2_dfq_local_pkt: ((words[92] >> 9) & 0x1),
            core0_qctl2_dfq_byp_full: ((words[92] >> 6) & 0x1),
            core0_qctl2_dfq_ld_vld: ((words[92] >> 5) & 0x1),
            core0_qctl2_dfq_inv_vld: ((words[92] >> 4) & 0x1),
            core0_qctl2_dfq_st_vld: ((words[92] >> 3) & 0x1),
            core0_qctl2_dfq_local_inv: ((words[92] >> 2) & 0x1)
          }
        end

        def run_jit_smoke!(cycles: DEFAULT_JIT_SMOKE_CYCLES, reset_cycles: DEFAULT_JIT_RESET_CYCLES)
          raise ArgumentError, 'SPARC64 ArcilatorRunner JIT smoke requires jit: true' unless jit?
          raise RuntimeError, 'SPARC64 ArcilatorRunner JIT smoke requires a successful build' unless build_result&.fetch(:success, false)
          ensure_runtime_built!
          response = send_jit_command("SMOKE #{cycles.to_i} #{reset_cycles.to_i}")
          _tag, *fields = response.split
          stdout = +"JIT_OK"
          stdout << " cycles=#{fields[0]}"
          stdout << " reset_cycles=#{fields[1]}"
          stdout << " wbm_cycle_o=#{fields[2]}"
          stdout << " wbm_strobe_o=#{fields[3]}"
          stdout << " wbm_we_o=#{fields[4]}"
          stdout << " wbm_addr_o=#{fields[5]}"
          stdout << " wbm_data_o=#{fields[6]}"
          stdout << " wbm_sel_o=#{fields[7]}\n"
          {
            success: true,
            command: "lli --jit-kind=orc-lazy #{build_result[:jit_bitcode_path]}",
            stdout: stdout,
            stderr: '',
            cycles: cycles.to_i,
            reset_cycles: reset_cycles.to_i,
            jit_bitcode_path: build_result[:jit_bitcode_path]
          }
        end

        def build!
          return @build_result if compiled? && runtime_artifact_ready?

          check_tools_available!
          FileUtils.mkdir_p(build_dir)
          FileUtils.mkdir_p(arc_dir)

          prepare_start = monotonic_time
          prepared = RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_circt_mlir(
            mlir_path: core_mlir_path,
            work_dir: arc_dir,
            base_name: top_module_name,
            top: top_module_name,
            cleanup_mode: cleanup_mode
          )
          prepare_ms = elapsed_ms_since(prepare_start)

          result = {
            import_dir: import_dir,
            build_dir: build_dir,
            top_module_name: top_module_name,
            core_mlir_path: core_mlir_path,
            arc_mlir_path: prepared[:arc_mlir_path],
            prepared: prepared,
            prepare_ms: prepare_ms,
            arcilator_ms: nil,
            runtime_link_ms: nil,
            jit_link_ms: nil,
            state_path: state_path,
            llvm_ir_path: llvm_ir_path,
            runtime_executable_path: runtime_executable_path,
            jit_bitcode_path: jit_bitcode_path,
            log_path: log_path,
            jit: jit?,
            success: false,
            phase: :prepare
          }

          unless prepared[:success]
            @build_result = result.merge(
              stderr: prepared.dig(:arc, :stderr).to_s,
              command: prepared.dig(:arc, :command),
              unsupported_modules: prepared[:unsupported_modules]
            )
            return @build_result
          end

          RHDL::Codegen::CIRCT::Tooling.finalize_arc_mlir_for_arcilator!(
            arc_mlir_path: prepared.fetch(:arc_mlir_path),
            check_paths: [
              prepared[:normalized_llhd_mlir_path],
              prepared[:hwseq_mlir_path],
              prepared[:flattened_hwseq_mlir_path],
              prepared[:arc_mlir_path]
            ]
          )

          FileUtils.rm_f(state_path)
          FileUtils.rm_f(llvm_ir_path)
          cmd = RHDL::Codegen::CIRCT::Tooling.arcilator_command(
            mlir_path: prepared.fetch(:arc_mlir_path),
            state_file: state_path,
            out_path: llvm_ir_path,
            extra_args: OBSERVE_FLAGS
          )

          arcilator_start = monotonic_time
          stdout, stderr, status = Open3.capture3(*cmd)
          arcilator_ms = elapsed_ms_since(arcilator_start)
          append_log(log_path, stdout, stderr)

          unless status.success?
            @build_result = result.merge(
              success: false,
              phase: :arcilator,
              arcilator_ms: arcilator_ms,
              command: shell_join(cmd),
              stdout: stdout,
              stderr: stderr
            )
            return @build_result
          end

          state_info = parse_state_file!(state_path)
          if jit?
            FileUtils.rm_f(jit_wrapper_path)
            FileUtils.rm_f(jit_wrapper_ll_path)
            FileUtils.rm_f(jit_bitcode_path)
            File.write(runtime_header_path, SharedRuntimeSupport.wrapper_header)
            write_runtime_wrapper(path: jit_wrapper_path, state_info: state_info, include_jit_main: true)

            jit_link_start = monotonic_time
            compile_wrapper_llvm_ir!(
              wrapper_path: jit_wrapper_path,
              wrapper_ll_path: jit_wrapper_ll_path,
              jit_main: true
            )
            link_jit_bitcode!(
              ll_path: llvm_ir_path,
              wrapper_ll_path: jit_wrapper_ll_path,
              jit_bc_path: jit_bitcode_path
            )
            jit_link_ms = elapsed_ms_since(jit_link_start)

            @build_result = result.merge(
              success: true,
              phase: :jit_link,
              arcilator_ms: arcilator_ms,
              jit_link_ms: jit_link_ms,
              command: shell_join(cmd),
              stdout: stdout,
              stderr: stderr
            )
            return @build_result
          end

          runtime_link_start = monotonic_time
          build_runtime_executable!(state_info: state_info)
          runtime_link_ms = elapsed_ms_since(runtime_link_start)

          @build_result = result.merge(
            success: true,
            phase: :runtime_link,
            arcilator_ms: arcilator_ms,
            runtime_link_ms: runtime_link_ms,
            command: shell_join(cmd),
            stdout: stdout,
            stderr: stderr
          )
        end

        private

        def resolve_import_dir(import_dir:, fast_boot:, build_cache_root:, reference_root:, import_top:, import_top_file:)
          return File.expand_path(import_dir) if import_dir

          return Integration::ImportLoader.build_import_dir(
            build_cache_root: build_cache_root,
            reference_root: reference_root,
            import_top: import_top,
            import_top_file: import_top_file,
            fast_boot: true
          ) if fast_boot

          Integration::ImportLoader.resolve_import_dir
        end

        def resolve_core_mlir_path!
          report_path = File.join(import_dir, 'import_report.json')
          if File.file?(report_path)
            report = JSON.parse(File.read(report_path))
            # ARC should lower from the imported core MLIR artifact written before
            # the RHDL raise step. The normalized artifact is emitted later from
            # the raised tree and is only a compatibility fallback.
            artifact_path = report.dig('artifacts', 'core_mlir_path') ||
                            report.dig('artifacts', 'normalized_core_mlir_path')
            if artifact_path && File.file?(artifact_path)
              @top_module_name = report['top'].to_s unless report['top'].to_s.empty?
              return File.expand_path(artifact_path)
            end
          end

          fallback = File.join(import_dir, '.mixed_import', "#{top_module_name}.core.mlir")
          return fallback if File.file?(fallback)

          raise ArgumentError, "SPARC64 core MLIR not found under #{import_dir}"
        rescue JSON::ParserError => e
          raise ArgumentError, "Invalid SPARC64 import report at #{report_path}: #{e.message}"
        end

        def default_build_dir
          digest = Digest::SHA256.hexdigest("#{import_dir}|#{jit? ? 'jit' : 'runtime'}|#{cleanup_mode}")[0, 12]
          File.join(BUILD_BASE, "#{sanitize_filename(top_module_name)}_#{digest}")
        end

        def sanitize_filename(value)
          value.to_s.gsub(/[^A-Za-z0-9_.-]/, '_')
        end

        def sanitize_macro(value)
          value.to_s.upcase.gsub(/[^A-Z0-9]+/, '_')
        end

        def ensure_runtime_built!
          return if @jit_wait_thr&.alive?

          build! unless compiled?
          if jit?
            start_runtime_process(
              ['lli', '--jit-kind=orc-lazy', "--compile-threads=#{jit_compile_threads}", '-O0', jit_bitcode_path]
            )
          else
            start_runtime_process([runtime_executable_path])
          end
        end

        def arc_dir
          File.join(build_dir, 'arc')
        end

        def state_path
          File.join(build_dir, "#{top_module_name}.state.json")
        end

        def llvm_ir_path
          File.join(build_dir, "#{top_module_name}.arc.ll")
        end

        def runtime_header_path
          File.join(build_dir, "sim_wrapper_#{sanitize_identifier(top_module_name)}.h")
        end

        def runtime_wrapper_path
          File.join(build_dir, "sim_wrapper_#{sanitize_identifier(top_module_name)}.cpp")
        end

        def runtime_wrapper_ll_path
          File.join(build_dir, "#{top_module_name}.arc_runtime.ll")
        end

        def runtime_bitcode_path
          File.join(build_dir, "#{top_module_name}.arc_runtime.bc")
        end

        def runtime_executable_path
          File.join(build_dir, "#{top_module_name}.arc_runtime")
        end

        def llvm_object_path
          File.join(build_dir, "#{top_module_name}.arc.o")
        end

        def shared_lib_path
          File.join(build_dir, "lib#{sanitize_identifier(top_module_name)}_arcilator_runtime.#{shared_library_suffix}")
        end

        def jit_wrapper_path
          File.join(build_dir, "#{top_module_name}.arc_jit_main.cpp")
        end

        def jit_wrapper_ll_path
          File.join(build_dir, "#{top_module_name}.arc_jit_main.ll")
        end

        def jit_bitcode_path
          File.join(build_dir, "#{top_module_name}.arc_jit.bc")
        end

        def log_path
          File.join(build_dir, 'arcilator.log')
        end

        def check_tools_available!
          %w[circt-opt arcilator].each do |tool|
            raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
          end

          if jit?
            %w[clang++ llvm-link lli].each do |tool|
              raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
            end
          else
            raise LoadError, 'clang++ not found in PATH' unless command_available?('clang++')
            raise LoadError, 'llvm-link not found in PATH' unless command_available?('llvm-link')
            raise LoadError, 'llc not found in PATH' unless command_available?('llc')
            raise LoadError, 'No C++ linker found in PATH' unless command_available?('clang++') || command_available?('g++') || command_available?('c++')
          end
        end

        def parse_state_file!(path)
          state = JSON.parse(File.read(path))
          mod = state.find { |entry| entry['name'].to_s == top_module_name } || state.first
          raise "Arcilator state file missing module entries: #{path}" unless mod

          states = Array(mod['states'])
          signals = {
            sys_clock_i: locate_signal(states, 'sys_clock_i', preferred_type: 'input'),
            sys_reset_i: locate_signal(states, 'sys_reset_i', preferred_type: 'input'),
            eth_irq_i: locate_signal(states, 'eth_irq_i', preferred_type: 'input'),
            wbm_ack_i: locate_signal(states, 'wbm_ack_i', preferred_type: 'input'),
            wbm_data_i: locate_signal(states, 'wbm_data_i', preferred_type: 'input'),
            wbm_cycle_o: locate_signal(states, 'wbm_cycle_o', preferred_type: 'output'),
            wbm_strobe_o: locate_signal(states, 'wbm_strobe_o', preferred_type: 'output'),
            wbm_we_o: locate_signal(states, 'wbm_we_o', preferred_type: 'output'),
            wbm_addr_o: locate_signal(states, 'wbm_addr_o', preferred_type: 'output'),
            wbm_data_o: locate_signal(states, 'wbm_data_o', preferred_type: 'output'),
            wbm_sel_o: locate_signal(states, 'wbm_sel_o', preferred_type: 'output')
          }
          DEBUG_SIGNAL_SPECS.each do |key, spec|
            signals[key] = locate_signal(states, spec.fetch(:name), preferred_type: spec.fetch(:preferred_type))
          end

          required = %i[sys_clock_i sys_reset_i eth_irq_i wbm_ack_i wbm_data_i]
          missing = required.select { |key| signals[key].nil? }
          raise "Arcilator state layout missing required SPARC64 signals: #{missing.join(', ')}" unless missing.empty?

          {
            module_name: mod.fetch('name'),
            state_size: mod.fetch('numStateBytes').to_i,
            signals: signals
          }
        end

        def locate_signal(states, name, preferred_type:)
          matches = states.select { |entry| entry['name'].to_s == name.to_s }
          return nil if matches.empty?

          match = matches.find { |entry| entry['type'].to_s == preferred_type.to_s } || matches.first
          {
            name: match.fetch('name'),
            offset: match.fetch('offset').to_i,
            bits: match.fetch('numBits').to_i,
            type: match['type'].to_s
          }
        end

        def build_runtime_library!(state_info:)
          raise NotImplementedError, 'use build_runtime_executable!'
        end

        def build_runtime_executable!(state_info:)
          File.write(runtime_header_path, SharedRuntimeSupport.wrapper_header(include_debug_snapshot: true))
          write_runtime_wrapper(path: runtime_wrapper_path, state_info: state_info, include_jit_main: true)
          FileUtils.rm_f(runtime_wrapper_ll_path)
          FileUtils.rm_f(runtime_bitcode_path)
          FileUtils.rm_f(runtime_executable_path)
          compile_wrapper_llvm_ir!(
            wrapper_path: runtime_wrapper_path,
            wrapper_ll_path: runtime_wrapper_ll_path,
            jit_main: true
          )
          link_jit_bitcode!(
            ll_path: llvm_ir_path,
            wrapper_ll_path: runtime_wrapper_ll_path,
            jit_bc_path: runtime_bitcode_path
          )
          compile_llvm_ir_object!(ll_path: runtime_bitcode_path, obj_path: llvm_object_path)
          link_runtime_executable!(obj_path: llvm_object_path, exe_path: runtime_executable_path)
        end

        def signal_defines(signals)
          signals.filter_map do |key, meta|
            next unless meta

            macro = sanitize_macro(key)
            "#define OFF_#{macro} #{meta.fetch(:offset)}\n#define BITS_#{macro} #{meta.fetch(:bits)}"
          end.join("\n")
        end

        def read_debug_signal_expr(signals, key)
          meta = signals[key]
          return '0ULL' unless meta

          macro = sanitize_macro(key)
          "read_bits(ctx->state, OFF_#{macro}, BITS_#{macro})"
        end

        def read_debug_signal_word_expr(signals, key, word_idx)
          meta = signals[key]
          return '0ULL' unless meta

          bit_width = meta.fetch(:bits).to_i
          bit_offset = word_idx * 64
          return '0ULL' if bit_width <= bit_offset

          width = [bit_width - bit_offset, 64].min
          byte_offset = meta.fetch(:offset).to_i + (word_idx * 8)
          "read_bits(ctx->state, #{byte_offset}, #{width})"
        end

        def write_runtime_wrapper(path:, state_info:, include_jit_main: false)
          module_name = state_info.fetch(:module_name)
          state_size = state_info.fetch(:state_size)
          includes = <<~CPP
            #include "sim_wrapper_#{sanitize_identifier(top_module_name)}.h"
            #include <algorithm>
            #include <cstdio>
            #include <cstdlib>
            #include <cstdint>
            #include <cstring>
            #include <string>
            #include <unordered_map>
            #include <vector>

            extern "C" void #{module_name}_eval(void* state);

            #{signal_defines(state_info.fetch(:signals))}
            #define STATE_SIZE #{state_size}
          CPP

          backend_helpers = <<~CPP
            void drive_defaults(SimContext* ctx) {
              write_bits(ctx->state, OFF_SYS_CLOCK_I, BITS_SYS_CLOCK_I, 0u);
              write_bits(ctx->state, OFF_SYS_RESET_I, BITS_SYS_RESET_I, 0u);
              write_bits(ctx->state, OFF_ETH_IRQ_I, BITS_ETH_IRQ_I, 0u);
              write_bits(ctx->state, OFF_WBM_ACK_I, BITS_WBM_ACK_I, 0u);
              write_bits(ctx->state, OFF_WBM_DATA_I, BITS_WBM_DATA_I, 0u);
            }

            void apply_inputs(SimContext* ctx, bool reset_active, const PendingResponse* response) {
              write_bits(ctx->state, OFF_SYS_CLOCK_I, BITS_SYS_CLOCK_I, 0u);
              write_bits(ctx->state, OFF_SYS_RESET_I, BITS_SYS_RESET_I, reset_active ? 1u : 0u);
              write_bits(ctx->state, OFF_ETH_IRQ_I, BITS_ETH_IRQ_I, 0u);
              if (response && response->valid) {
                write_bits(ctx->state, OFF_WBM_ACK_I, BITS_WBM_ACK_I, 1u);
                write_bits(ctx->state, OFF_WBM_DATA_I, BITS_WBM_DATA_I, response->read_data);
              } else {
                write_bits(ctx->state, OFF_WBM_ACK_I, BITS_WBM_ACK_I, 0u);
                write_bits(ctx->state, OFF_WBM_DATA_I, BITS_WBM_DATA_I, 0u);
              }
            }

            PendingResponse sample_request(SimContext* ctx) {
              PendingResponse request;
              if (read_bits(ctx->state, OFF_WBM_CYCLE_O, BITS_WBM_CYCLE_O) == 0u ||
                  read_bits(ctx->state, OFF_WBM_STROBE_O, BITS_WBM_STROBE_O) == 0u) {
                return request;
              }
              request.valid = true;
              request.write = (read_bits(ctx->state, OFF_WBM_WE_O, BITS_WBM_WE_O) != 0u);
              request.addr = canonical_bus_addr(read_bits(ctx->state, OFF_WBM_ADDR_O, BITS_WBM_ADDR_O));
              request.data = read_bits(ctx->state, OFF_WBM_DATA_O, BITS_WBM_DATA_O);
              request.sel = read_bits(ctx->state, OFF_WBM_SEL_O, BITS_WBM_SEL_O) & 0xFFULL;
              return request;
            }

            void step_cycle(SimContext* ctx) {
              bool reset_active = ctx->reset_cycles_remaining > 0;
              PendingResponse acked_response = reset_active ? PendingResponse{} : ctx->pending_response;

              apply_inputs(ctx, reset_active, acked_response.valid ? &acked_response : nullptr);
              #{module_name}_eval(ctx->state);

              if (acked_response.valid) {
                record_acknowledged_response(ctx, acked_response);
              }

              PendingResponse next_response;
              if (!reset_active) {
                PendingResponse request = sample_request(ctx);
                if (request.valid && !(acked_response.valid && requests_equal(acked_response, request))) {
                  next_response = service_request(ctx, request);
                  ctx->deferred_request = PendingResponse{};
                } else if (!request.valid && ctx->deferred_request.valid &&
                           !(acked_response.valid && requests_equal(acked_response, ctx->deferred_request))) {
                  next_response = service_request(ctx, ctx->deferred_request);
                  ctx->deferred_request = PendingResponse{};
                } else if (request.valid) {
                  ctx->deferred_request = PendingResponse{};
                }
              }

              write_bits(ctx->state, OFF_SYS_CLOCK_I, BITS_SYS_CLOCK_I, 1u);
              #{module_name}_eval(ctx->state);

              if (!next_response.valid && !reset_active) {
                PendingResponse post_edge_request = sample_request(ctx);
                ctx->deferred_request = post_edge_request.valid ? post_edge_request : PendingResponse{};
              } else {
                ctx->deferred_request = PendingResponse{};
              }

              ctx->pending_response = next_response;
              ctx->cycles += 1;
              if (ctx->reset_cycles_remaining > 0) {
                ctx->reset_cycles_remaining -= 1;
              }
            }
          CPP

          sim_create_impl = <<~CPP
            void* sim_create(void) {
              SimContext* ctx = new SimContext();
              memset(ctx->state, 0, sizeof(ctx->state));
              ctx->deferred_request = PendingResponse{};
              drive_defaults(ctx);
              #{module_name}_eval(ctx->state);
              clear_runtime_state(ctx);
              return ctx;
            }
          CPP

          sim_destroy_impl = <<~CPP
            void sim_destroy(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              delete ctx;
            }
          CPP

          sim_reset_impl = <<~CPP
            void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              clear_runtime_state(ctx);
              ctx->deferred_request = PendingResponse{};
              drive_defaults(ctx);
              write_bits(ctx->state, OFF_SYS_RESET_I, BITS_SYS_RESET_I, 1u);
              write_bits(ctx->state, OFF_SYS_CLOCK_I, BITS_SYS_CLOCK_I, 0u);
              #{module_name}_eval(ctx->state);
            }
          CPP

          debug_copy_impl = <<~CPP
            unsigned int copy_debug_snapshot(SimContext* ctx, unsigned long long* out_words, unsigned int max_words) {
              const unsigned int count = std::min<unsigned int>(max_words, kDebugWords);
              if (count > 0) out_words[0] = ctx->cycles;
              if (count > 1) out_words[1] = read_bits(ctx->state, OFF_WBM_CYCLE_O, BITS_WBM_CYCLE_O);
              if (count > 2) out_words[2] = read_bits(ctx->state, OFF_WBM_STROBE_O, BITS_WBM_STROBE_O);
              if (count > 3) out_words[3] = read_bits(ctx->state, OFF_WBM_WE_O, BITS_WBM_WE_O);
              if (count > 4) out_words[4] = read_bits(ctx->state, OFF_WBM_ADDR_O, BITS_WBM_ADDR_O);
              if (count > 5) out_words[5] = read_bits(ctx->state, OFF_WBM_DATA_O, BITS_WBM_DATA_O);
              if (count > 6) out_words[6] = read_bits(ctx->state, OFF_WBM_SEL_O, BITS_WBM_SEL_O);
              if (count > 7) out_words[7] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_pcx_xmit_ff_q)};
              if (count > 8) out_words[8] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_pcx_atom_q)};
              if (count > 9) out_words[9] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_42)};
              if (count > 10) out_words[10] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_43)};
              if (count > 11) out_words[11] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_19)};
              if (count > 12) out_words[12] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_fifo_state)};
              if (count > 13) out_words[13] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_pcx_xmit_ff_q, 1)};
              if (count > 14) out_words[14] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_rt_tmp_42, 1)};
              if (count > 15) out_words[15] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_rt_tmp_43, 1)};
              if (count > 16) out_words[16] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_rt_tmp_19, 1)};
              if (count > 17) out_words[17] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_rt_tmp_30, 1)};
              if (count > 18) out_words[18] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_rt_tmp_42, 2)};
              if (count > 19) out_words[19] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_rt_tmp_43, 2)};
              if (count > 20) out_words[20] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_rt_tmp_19, 2)};
              if (count > 21) out_words[21] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_rt_tmp_30, 2)};
              if (count > 22) out_words[22] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_16_5)};
              if (count > 23) out_words[23] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_20_1)};
              if (count > 24) out_words[24] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_21_1)};
              if (count > 25) out_words[25] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_22_1)};
              if (count > 26) out_words[26] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_23_8)};
              if (count > 27) out_words[27] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_24_64)};
              if (count > 28) out_words[28] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_25_64)};
              if (count > 29) out_words[29] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_26_124)};
              if (count > 30) out_words[30] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_rt_tmp_26_124, 1)};
              if (count > 31) out_words[31] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_rt_tmp_38_1)};
              if (count > 32) out_words[32] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_fifo_rd_ptr)};
              if (count > 33) out_words[33] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_fifo_wr_ptr)};
              if (count > 34) out_words[34] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_fifo_slot0_meta)};
              if (count > 35) out_words[35] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_fifo_slot0_payload)};
              if (count > 36) out_words[36] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_fifo_slot0_payload, 1)};
              if (count > 37) out_words[37] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_fifo_slot1_meta)};
              if (count > 38) out_words[38] = #{read_debug_signal_expr(state_info.fetch(:signals), :os2wb_fifo_slot1_payload)};
              if (count > 39) out_words[39] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_fifo_slot1_payload, 1)};
              if (count > 40) out_words[40] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :os2wb_fifo_slot1_payload, 2)};
              if (count > 41) out_words[41] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_rdata_q)};
              if (count > 42) out_words[42] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_r0_data)};
              if (count > 43) out_words[43] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_data_local_dout)};
              if (count > 44) out_words[44] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_stb_data_local_dout, 1)};
              if (count > 45) out_words[45] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_wptr_vld_q)};
              if (count > 46) out_words[46] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_rptr_vld_q)};
              if (count > 47) out_words[47] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_rw_tid_q)};
              if (count > 48) out_words[48] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_rw_addr_q)};
              if (count > 49) out_words[49] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_r0_addr)};
              if (count > 50) out_words[50] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_wr_data_hi30_q)};
              if (count > 51) out_words[51] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_wr_data_lo15_q)};
              if (count > 52) out_words[52] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_stb_cam_alt_wsel_q)};
              if (count > 53) out_words[53] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_dtlb_bypass_e)};
              if (count > 54) out_words[54] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_dtlb_bypass_va)};
              if (count > 55) out_words[55] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_dtlb_cam_key)};
              if (count > 56) out_words[56] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_dtlb_va_tag_plus)};
              if (count > 57) out_words[57] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_dtlb_vrtl_pgnum_m)};
              if (count > 58) out_words[58] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_dtlb_bypass_d)};
              if (count > 59) out_words[59] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_dtlb_pgnum_m)};
              if (count > 60) out_words[60] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_dtlb_pgnum_crit)};
              if (count > 61) out_words[61] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_store_pkt_d1)};
              if (count > 62) out_words[62] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_store_pkt_d1, 1)};
              if (count > 63) out_words[63] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_store_pkt_d1, 2)};
              if (count > 64) out_words[64] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_dctldp_va_stgm)};
              if (count > 65) out_words[65] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_exu_rs1_data_dff)};
              if (count > 66) out_words[66] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_exu_rs2_data_dff)};
              if (count > 67) out_words[67] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_exu_c_used_dff)};
              if (count > 68) out_words[68] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_exu_sub_dff)};
              if (count > 69) out_words[69] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_exu_rd_data_e2m)};
              if (count > 70) out_words[70] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_exu_rd_data_m2w)};
              if (count > 71) out_words[71] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_exu_rd_data_g2w)};
              if (count > 72) out_words[72] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_exu_dfill_data_dff)};
              if (count > 73) out_words[73] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_tlu_stgg_eldxa)};
              if (count > 74) out_words[74] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_irf_active_win_thr_rd_w_neg)};
              if (count > 75) out_words[75] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_irf_thr_rd_w_neg)};
              if (count > 76) out_words[76] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_irf_active_win_thr_rd_w2_neg)};
              if (count > 77) out_words[77] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_irf_thr_rd_w2_neg)};
              if (count > 78) out_words[78] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_ifq_thrrdy_ctr)};
              if (count > 79) out_words[79] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_ifq_imsf_ff)};
              if (count > 80) out_words[80] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_ifq_pcxreqvd_ff)};
              if (count > 81) out_words[81] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_ifq_pcxreqve_ff)};
              if (count > 82) out_words[82] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_ifq_pcxreq_reg)};
              if (count > 83) out_words[83] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_ifqop_reg)};
              if (count > 84) out_words[84] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_ifqop_reg, 1)};
              if (count > 85) out_words[85] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_ifqop_reg, 2)};
              if (count > 86) out_words[86] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_ifq_cpxreq_reg)};
              if (count > 87) out_words[87] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_ifq_qadv_ff)};
              if (count > 88) out_words[88] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_ifq_ibuf, 2)};
              if (count > 89) out_words[89] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_ff_cpx_data_cx3, 2)};
              if (count > 90) out_words[90] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_qctl2_ifill_pkt_fwd_done_ff)};
              if (count > 91) out_words[91] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_qctl2_dfq_wptr_ff)};
              if (count > 92) out_words[92] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_qctl2_dfq_vld)};
              if (count > 93) out_words[93] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_qctl2_dfq_inv)};
              if (count > 94) out_words[94] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_qctl2_rvld_stgd1)};
              if (count > 95) out_words[95] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_qctl2_rvld_stgd1_new)};
              if (count > 96) out_words[96] = #{read_debug_signal_expr(state_info.fetch(:signals), :core0_qdp2_dfq_data_stg)};
              if (count > 97) out_words[97] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_qdp2_dfq_data_stg, 1)};
              if (count > 98) out_words[98] = #{read_debug_signal_word_expr(state_info.fetch(:signals), :core0_qdp2_dfq_data_stg, 2)};
              return count;
            }
          CPP

          wrapper = SharedRuntimeSupport.build_wrapper_cpp(
            includes: includes,
            context_fields: "std::uint8_t state[STATE_SIZE];\nPendingResponse deferred_request{};",
            backend_helpers: backend_helpers,
            sim_create_impl: sim_create_impl,
            sim_destroy_impl: sim_destroy_impl,
            sim_reset_impl: sim_reset_impl,
            include_debug_snapshot: true,
            debug_words: DEBUG_WORDS,
            debug_copy_impl: debug_copy_impl
          )
          wrapper << jit_runtime_main_cpp(module_name: module_name, signals: state_info.fetch(:signals)) if include_jit_main

          write_file_if_changed(path, wrapper)
        end

        def jit_runtime_main_cpp(module_name:, signals:)
          smoke_output_format = (['%u', '%llu'] + Array.new(6, '%llu')).join(' ')
          smoke_output_exprs = %i[wbm_cycle_o wbm_strobe_o wbm_we_o wbm_addr_o wbm_data_o wbm_sel_o].map do |key|
            macro = sanitize_macro(key)
            "static_cast<unsigned long long>(read_bits(ctx->state, OFF_#{macro}, BITS_#{macro}))"
          end.join(', ')

          <<~CPP
            #ifdef ARCI_JIT_MAIN
            namespace {
            static void write_hex_bytes(FILE* out, const unsigned char* bytes, size_t len) {
              static const char* kHex = "0123456789abcdef";
              for (size_t i = 0; i < len; ++i) {
                unsigned char byte = bytes[i];
                fputc(kHex[(byte >> 4) & 0xF], out);
                fputc(kHex[byte & 0xF], out);
              }
            }

            static bool hex_nibble(char ch, unsigned char* out) {
              if (ch >= '0' && ch <= '9') {
                *out = static_cast<unsigned char>(ch - '0');
                return true;
              }
              if (ch >= 'a' && ch <= 'f') {
                *out = static_cast<unsigned char>(10 + (ch - 'a'));
                return true;
              }
              if (ch >= 'A' && ch <= 'F') {
                *out = static_cast<unsigned char>(10 + (ch - 'A'));
                return true;
              }
              return false;
            }

            static bool decode_hex_payload(const char* hex, std::vector<unsigned char>* out) {
              out->clear();
              if (!hex) {
                return true;
              }
              while (*hex == ' ') {
                ++hex;
              }
              size_t len = strlen(hex);
              if ((len & 1u) != 0u) {
                return false;
              }
              out->reserve(len / 2u);
              for (size_t i = 0; i < len; i += 2u) {
                unsigned char hi = 0u;
                unsigned char lo = 0u;
                if (!hex_nibble(hex[i], &hi) || !hex_nibble(hex[i + 1u], &lo)) {
                  return false;
                }
                out->push_back(static_cast<unsigned char>((hi << 4) | lo));
              }
              return true;
            }

            static const char* skip_spaces(const char* text) {
              while (text && *text == ' ') {
                ++text;
              }
              return text;
            }

            static bool parse_u64_token(const char** cursor, unsigned long long* out) {
              if (!cursor || !*cursor) {
                return false;
              }
              const char* start = skip_spaces(*cursor);
              if (!start || *start == '\\0') {
                return false;
              }
              char* end = nullptr;
              *out = strtoull(start, &end, 0);
              if (end == start) {
                return false;
              }
              *cursor = skip_spaces(end);
              return true;
            }
            }  // namespace

            int main(int argc, char** argv) {
              (void)argc;
              (void)argv;
              SimContext* ctx = static_cast<SimContext*>(sim_create());
              if (!ctx) {
                return 1;
              }

              fprintf(stdout, "READY\\n");
              fflush(stdout);

              char* line = nullptr;
              size_t cap = 0u;
              while (getline(&line, &cap, stdin) != -1) {
                size_t len = strlen(line);
                while (len > 0u && (line[len - 1u] == '\\n' || line[len - 1u] == '\\r')) {
                  line[--len] = '\\0';
                }

                if (strcmp(line, "RESET") == 0) {
                  sim_reset(ctx);
                  fprintf(stdout, "OK\\n");
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "CLEAR_MEMORY") == 0) {
                  sim_clear_memory(ctx);
                  fprintf(stdout, "OK\\n");
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "LOAD_FLASH ", 11) == 0) {
                  const char* cursor = line + 11;
                  unsigned long long base = 0ULL;
                  std::vector<unsigned char> payload;
                  if (!parse_u64_token(&cursor, &base) || !decode_hex_payload(cursor, &payload)) {
                    fprintf(stdout, "ERR LOAD_FLASH\\n");
                    fflush(stdout);
                    continue;
                  }
                  sim_load_flash(ctx, payload.data(), base, static_cast<unsigned int>(payload.size()));
                  fprintf(stdout, "OK %zu\\n", payload.size());
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "LOAD_MEMORY ", 12) == 0) {
                  const char* cursor = line + 12;
                  unsigned long long base = 0ULL;
                  std::vector<unsigned char> payload;
                  if (!parse_u64_token(&cursor, &base) || !decode_hex_payload(cursor, &payload)) {
                    fprintf(stdout, "ERR LOAD_MEMORY\\n");
                    fflush(stdout);
                    continue;
                  }
                  sim_load_memory(ctx, payload.data(), base, static_cast<unsigned int>(payload.size()));
                  fprintf(stdout, "OK %zu\\n", payload.size());
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "READ_MEMORY ", 12) == 0) {
                  const char* cursor = line + 12;
                  unsigned long long addr = 0ULL;
                  unsigned long long length = 0ULL;
                  if (!parse_u64_token(&cursor, &addr) || !parse_u64_token(&cursor, &length)) {
                    fprintf(stdout, "ERR READ_MEMORY\\n");
                    fflush(stdout);
                    continue;
                  }
                  std::vector<unsigned char> buffer(static_cast<size_t>(length), 0u);
                  unsigned int copied = sim_read_memory(ctx, addr, buffer.data(), static_cast<unsigned int>(buffer.size()));
                  fputs("BYTES ", stdout);
                  write_hex_bytes(stdout, buffer.data(), copied);
                  fputc('\\n', stdout);
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "WRITE_MEMORY ", 13) == 0) {
                  const char* cursor = line + 13;
                  unsigned long long addr = 0ULL;
                  std::vector<unsigned char> payload;
                  if (!parse_u64_token(&cursor, &addr) || !decode_hex_payload(cursor, &payload)) {
                    fprintf(stdout, "ERR WRITE_MEMORY\\n");
                    fflush(stdout);
                    continue;
                  }
                  unsigned int written = sim_write_memory(ctx, addr, payload.data(), static_cast<unsigned int>(payload.size()));
                  fprintf(stdout, "WROTE %u\\n", written);
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "RUN ", 4) == 0) {
                  unsigned long requested = strtoul(line + 4, nullptr, 10);
                  unsigned int ran = sim_run_cycles(ctx, static_cast<unsigned int>(requested));
                  fprintf(stdout, "RUN %u\\n", ran);
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "TRACE") == 0) {
                  unsigned int count = sim_wishbone_trace_count(ctx);
                  std::vector<unsigned long long> words(static_cast<size_t>(count) * #{SharedRuntimeSupport::TRACE_WORDS}, 0ULL);
                  unsigned int copied = sim_copy_wishbone_trace(ctx, words.data(), count);
                  fprintf(stdout, "TRACE %u ", copied);
                  write_hex_bytes(stdout, reinterpret_cast<const unsigned char*>(words.data()), static_cast<size_t>(copied) * #{SharedRuntimeSupport::TRACE_WORDS} * sizeof(unsigned long long));
                  fputc('\\n', stdout);
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "DEBUG") == 0) {
                  unsigned long long words[kDebugWords];
                  unsigned int copied = sim_copy_debug_snapshot(ctx, words, kDebugWords);
                  fprintf(stdout, "DEBUG %u ", copied);
                  write_hex_bytes(stdout, reinterpret_cast<const unsigned char*>(words), static_cast<size_t>(copied) * sizeof(unsigned long long));
                  fputc('\\n', stdout);
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "FAULTS") == 0) {
                  unsigned int count = sim_unmapped_access_count(ctx);
                  std::vector<unsigned long long> words(static_cast<size_t>(count) * #{SharedRuntimeSupport::FAULT_WORDS}, 0ULL);
                  unsigned int copied = sim_copy_unmapped_accesses(ctx, words.data(), count);
                  fprintf(stdout, "FAULTS %u ", copied);
                  write_hex_bytes(stdout, reinterpret_cast<const unsigned char*>(words.data()), static_cast<size_t>(copied) * #{SharedRuntimeSupport::FAULT_WORDS} * sizeof(unsigned long long));
                  fputc('\\n', stdout);
                  fflush(stdout);
                  continue;
                }

                if (strncmp(line, "SMOKE ", 6) == 0) {
                  const char* cursor = line + 6;
                  unsigned long long cycles = 0ULL;
                  unsigned long long reset_cycles = 0ULL;
                  if (!parse_u64_token(&cursor, &cycles) || !parse_u64_token(&cursor, &reset_cycles)) {
                    fprintf(stdout, "ERR SMOKE\\n");
                    fflush(stdout);
                    continue;
                  }
                  sim_reset(ctx);
                  ctx->reset_cycles_remaining = static_cast<size_t>(reset_cycles);
                  unsigned int ran = sim_run_cycles(ctx, static_cast<unsigned int>(cycles));
                  fprintf(stdout, "#{smoke_output_format}\\n", ran, reset_cycles, #{smoke_output_exprs});
                  fflush(stdout);
                  continue;
                }

                if (strcmp(line, "QUIT") == 0) {
                  fprintf(stdout, "OK\\n");
                  fflush(stdout);
                  break;
                }

                fprintf(stdout, "ERR UNKNOWN\\n");
                fflush(stdout);
              }

              free(line);
              sim_destroy(ctx);
              return 0;
            }
            #endif
          CPP
        end

        def compile_wrapper_llvm_ir!(wrapper_path:, wrapper_ll_path:, jit_main: false)
          cmd = ['clang++', '-std=c++17', '-O0', '-S', '-emit-llvm']
          cmd << '-DARCI_JIT_MAIN' if jit_main
          cmd += [wrapper_path, '-o', wrapper_ll_path]
          stdout, stderr, status = Open3.capture3(*cmd)
          append_log(log_path, stdout, stderr)
          return if status.success?

          raise "SPARC64 Arcilator JIT wrapper compilation failed:\n#{stdout}\n#{stderr}"
        end

        def start_runtime_process(cmd)
          @jit_stdin, @jit_stdout, @jit_stderr, @jit_wait_thr = Open3.popen3(*cmd)
          @jit_stdin.sync = true
          @jit_stdout.sync = true
          @jit_stderr.sync = true
          @jit_log_thread = Thread.new do
            begin
              File.open(log_path, 'a') do |file|
                @jit_stderr.each_line do |line|
                  file.write(line)
                  file.flush
                end
              end
            rescue IOError
              nil
            end
          end

          ready = @jit_stdout.gets
          return if ready&.strip == 'READY'

          close_jit_process
          raise "SPARC64 Arcilator runtime process failed to start#{ready ? ": #{ready.strip}" : ''}"
        end

        def send_jit_command(command)
          raise 'SPARC64 Arcilator JIT runner is not active' unless @jit_stdin && @jit_stdout

          @jit_stdin.puts(command)
          response = @jit_stdout.gets
          raise 'SPARC64 Arcilator JIT runner exited unexpectedly' unless response

          response = response.strip
          raise "SPARC64 Arcilator JIT command failed: #{response}" if response.start_with?('ERR')

          response
        end

        def send_jit_payload_command(prefix, bytes)
          payload = pack_bytes(bytes).unpack1('H*')
          send_jit_command("#{prefix} #{payload}")
        end

        def parse_jit_hex_bytes(hex)
          return [] if hex.nil? || hex.empty?

          [hex].pack('H*').bytes
        end

        def parse_jit_u64_words(hex, expected_words)
          return [] if hex.nil? || hex.empty? || expected_words <= 0

          words = [hex].pack('H*').unpack('Q<*')
          words.first(expected_words)
        end

        def close_jit_process
          return false unless @jit_wait_thr

          begin
            send_jit_command('QUIT') if @jit_stdin && !@jit_stdin.closed?
          rescue StandardError
            nil
          end

          @jit_stdin&.close unless @jit_stdin&.closed?
          @jit_stdout&.close unless @jit_stdout&.closed?
          @jit_stderr&.close unless @jit_stderr&.closed?
          @jit_wait_thr.value
          @jit_log_thread&.join(1)
          @jit_stdin = nil
          @jit_stdout = nil
          @jit_stderr = nil
          @jit_wait_thr = nil
          @jit_log_thread = nil
          true
        end

        def link_jit_bitcode!(ll_path:, wrapper_ll_path:, jit_bc_path:)
          cmd = ['llvm-link', ll_path, wrapper_ll_path, '-o', jit_bc_path]
          stdout, stderr, status = Open3.capture3(*cmd)
          append_log(log_path, stdout, stderr)
          return if status.success?

          raise "SPARC64 Arcilator JIT bitcode link failed:\n#{stdout}\n#{stderr}"
        end

        def compile_llvm_ir_object!(ll_path:, obj_path:)
          cmd = ['llc', '-filetype=obj', '-O0', '-relocation-model=pic']
          # AArch64 O0 GlobalISel miscompiled the SPARC64 ARC runtime and
          # reintroduced the old cycle-938 packet divergence. Force the
          # SelectionDAG path for native compile mode.
          if RbConfig::CONFIG['host_cpu'] =~ /(arm64|aarch64)/i
            cmd << '--aarch64-enable-global-isel-at-O=-1'
          end
          cmd += [ll_path, '-o', obj_path]
          stdout, stderr, status = Open3.capture3(*cmd)
          append_log(log_path, stdout, stderr)
          return if status.success?

          raise "SPARC64 Arcilator object compilation failed:\n#{stdout}\n#{stderr}"
        end

        def link_shared_library!(obj_path:, lib_path:)
          cxx = if RbConfig::CONFIG['host_os'] =~ /darwin/ && command_available?('clang++')
                  'clang++'
                elsif command_available?('g++')
                  'g++'
                else
                  'c++'
                end
          cmd = if RbConfig::CONFIG['host_os'] =~ /darwin/
                  [cxx, '-shared', '-dynamiclib', '-fPIC', '-O2', '-o', lib_path, obj_path]
                else
                  [cxx, '-shared', '-fPIC', '-O2', '-o', lib_path, obj_path]
                end
          stdout, stderr, status = Open3.capture3(*cmd)
          append_log(log_path, stdout, stderr)
          return if status.success?

          raise "SPARC64 Arcilator shared library link failed:\n#{stdout}\n#{stderr}"
        end

        def link_runtime_executable!(obj_path:, exe_path:)
          cxx = if RbConfig::CONFIG['host_os'] =~ /darwin/ && command_available?('clang++')
                  'clang++'
                elsif command_available?('g++')
                  'g++'
                else
                  'c++'
                end
          cmd = [cxx, '-O0', '-o', exe_path, obj_path]
          stdout, stderr, status = Open3.capture3(*cmd)
          append_log(log_path, stdout, stderr)
          return if status.success?

          raise "SPARC64 Arcilator runtime executable link failed:\n#{stdout}\n#{stderr}"
        end

        def append_log(path, stdout, stderr)
          File.write(path, "#{stdout}#{stderr}", mode: 'a')
        end

        def jit_compile_threads
          [Etc.nprocessors, 8].compact.min
        end

        def shared_library_suffix
          RbConfig::CONFIG['host_os'] =~ /darwin/ ? 'dylib' : 'so'
        end

        def command_available?(tool)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            exe = File.join(path, tool)
            File.executable?(exe) && !File.directory?(exe)
          end
        end

        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def elapsed_ms_since(start_time)
          ((monotonic_time - start_time) * 1000).round(1)
        end

        def shell_join(cmd)
          cmd.map { |arg| Shellwords.escape(arg.to_s) }.join(' ')
        end

        def runtime_artifact_ready?
          if jit?
            build_result[:jit_bitcode_path].to_s != '' && File.exist?(build_result[:jit_bitcode_path])
          else
            build_result[:runtime_executable_path].to_s != '' && File.exist?(build_result[:runtime_executable_path])
          end
        end

        def completion_result(timeout: false)
          trace = Integration.normalize_wishbone_trace(wishbone_trace)
          faults = unmapped_accesses
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
      end
    end
  end
end
