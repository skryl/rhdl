# ao486 Write Register File
# Ported from: rtl/ao486/pipeline/write_register.v
#
# Contains:
# - 8 x 32-bit GPRs (EAX-EDI) with 8/16/32-bit write support
# - EFLAGS (individual flag bits)
# - CR0 (mode bits), CR2, CR3
# - GDTR, IDTR (base + limit)
# - DR0-DR3, DR6, DR7
# - 8 segment selectors + RPL + 64-bit descriptor caches + valid bits
# - EIP
# - Derived mode outputs (real_mode, protected_mode, v8086_mode, cpl)

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../constants'

module RHDL
  module Examples
    module AO486
      class WriteRegister < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential
        include Constants

        input :clk
        input :rst_n

        # --- Write-back control ---
        input :result, width: 32
        input :write_eax
        input :write_regrm
        input :wr_dst_is_rm
        input :wr_dst_is_reg
        input :wr_dst_is_implicit_reg
        input :wr_modregrm_reg, width: 3
        input :wr_modregrm_rm, width: 3
        input :wr_operand_32bit
        input :wr_is_8bit

        # --- Flag write-back ---
        input :write_flags
        input :cflag_to_reg
        input :pflag_to_reg
        input :aflag_to_reg
        input :zflag_to_reg
        input :sflag_to_reg
        input :oflag_to_reg
        input :tflag_to_reg
        input :iflag_to_reg
        input :dflag_to_reg
        input :iopl_to_reg, width: 2
        input :ntflag_to_reg
        input :vmflag_to_reg
        input :acflag_to_reg
        input :idflag_to_reg
        input :rflag_to_reg

        # --- CR0 write-back ---
        input :write_cr0_pe
        input :cr0_pe_to_reg
        input :write_cr0_mp
        input :cr0_mp_to_reg
        input :write_cr0_em
        input :cr0_em_to_reg
        input :write_cr0_ts
        input :cr0_ts_to_reg
        input :write_cr0_ne
        input :cr0_ne_to_reg
        input :write_cr0_wp
        input :cr0_wp_to_reg
        input :write_cr0_am
        input :cr0_am_to_reg
        input :write_cr0_nw
        input :cr0_nw_to_reg
        input :write_cr0_cd
        input :cr0_cd_to_reg
        input :write_cr0_pg
        input :cr0_pg_to_reg

        # --- CR2, CR3 ---
        input :write_cr2
        input :cr2_to_reg, width: 32
        input :write_cr3
        input :cr3_to_reg, width: 32

        # --- EIP ---
        input :write_eip
        input :eip_to_reg, width: 32

        # --- Segment registers ---
        input :write_seg
        input :wr_seg_index, width: 3
        input :seg_to_reg, width: 16
        input :write_seg_rpl
        input :seg_rpl_to_reg, width: 2
        input :write_seg_cache
        input :seg_cache_to_reg, width: 64
        input :write_seg_valid
        input :seg_valid_to_reg

        # --- GDTR, IDTR ---
        input :write_gdtr
        input :gdtr_base_to_reg, width: 32
        input :gdtr_limit_to_reg, width: 16
        input :write_idtr
        input :idtr_base_to_reg, width: 32
        input :idtr_limit_to_reg, width: 16

        # --- Debug registers ---
        input :write_dr0
        input :dr0_to_reg, width: 32
        input :write_dr1
        input :dr1_to_reg, width: 32
        input :write_dr2
        input :dr2_to_reg, width: 32
        input :write_dr3
        input :dr3_to_reg, width: 32
        input :write_dr6
        input :dr6_breakpoints_to_reg, width: 4
        input :dr6_b12_to_reg
        input :dr6_bd_to_reg
        input :dr6_bs_to_reg
        input :dr6_bt_to_reg
        input :write_dr7
        input :dr7_to_reg, width: 32

        # --- Exception ESP restore ---
        input :exc_restore_esp
        input :exc_restore_esp_value, width: 32

        # --- GPR outputs ---
        output :eax, width: 32
        output :ebx, width: 32
        output :ecx, width: 32
        output :edx, width: 32
        output :esp, width: 32
        output :ebp, width: 32
        output :esi, width: 32
        output :edi, width: 32

        # --- EFLAGS outputs ---
        output :cflag
        output :pflag
        output :aflag
        output :zflag
        output :sflag
        output :oflag
        output :tflag
        output :iflag
        output :dflag
        output :iopl, width: 2
        output :ntflag
        output :vmflag
        output :acflag
        output :idflag
        output :rflag

        # --- CR outputs ---
        output :cr0_pe
        output :cr0_mp
        output :cr0_em
        output :cr0_ts
        output :cr0_ne
        output :cr0_wp
        output :cr0_am
        output :cr0_nw
        output :cr0_cd
        output :cr0_pg
        output :cr2, width: 32
        output :cr3, width: 32

        # --- EIP ---
        output :eip, width: 32

        # --- Mode outputs ---
        output :real_mode
        output :protected_mode
        output :v8086_mode
        output :cpl, width: 2

        # --- Segment outputs ---
        output :es, width: 16
        output :cs, width: 16
        output :ss, width: 16
        output :ds, width: 16
        output :fs, width: 16
        output :gs, width: 16
        output :ldtr, width: 16
        output :tr, width: 16

        output :es_rpl, width: 2
        output :cs_rpl, width: 2
        output :ss_rpl, width: 2
        output :ds_rpl, width: 2
        output :fs_rpl, width: 2
        output :gs_rpl, width: 2
        output :ldtr_rpl, width: 2
        output :tr_rpl, width: 2

        output :es_cache, width: 64
        output :cs_cache, width: 64
        output :ss_cache, width: 64
        output :ds_cache, width: 64
        output :fs_cache, width: 64
        output :gs_cache, width: 64
        output :ldtr_cache, width: 64
        output :tr_cache, width: 64

        output :es_cache_valid
        output :cs_cache_valid
        output :ss_cache_valid
        output :ds_cache_valid
        output :fs_cache_valid
        output :gs_cache_valid
        output :ldtr_cache_valid
        output :tr_cache_valid

        # --- GDTR, IDTR ---
        output :gdtr_base, width: 32
        output :gdtr_limit, width: 16
        output :idtr_base, width: 32
        output :idtr_limit, width: 16

        # --- Debug registers ---
        output :dr0, width: 32
        output :dr1, width: 32
        output :dr2, width: 32
        output :dr3, width: 32
        output :dr6_breakpoints, width: 4
        output :dr6_b12
        output :dr6_bd
        output :dr6_bs
        output :dr6_bt
        output :dr7, width: 32

        # GPR name/index mapping
        GPR_NAMES = [:eax, :ecx, :edx, :ebx, :esp, :ebp, :esi, :edi].freeze
        GPR_STARTUP = [STARTUP_EAX, STARTUP_ECX, STARTUP_EDX, STARTUP_EBX,
                       STARTUP_ESP, STARTUP_EBP, STARTUP_ESI, STARTUP_EDI].freeze

        SEG_NAMES = [:es, :cs, :ss, :ds, :fs, :gs, :ldtr, :tr].freeze
        SEG_STARTUP = [STARTUP_ES, STARTUP_CS, STARTUP_SS, STARTUP_DS,
                       STARTUP_FS, STARTUP_GS, STARTUP_LDTR, STARTUP_TR].freeze
        SEG_RPL_STARTUP = [STARTUP_ES_RPL, STARTUP_CS_RPL, STARTUP_SS_RPL, STARTUP_DS_RPL,
                           STARTUP_FS_RPL, STARTUP_GS_RPL, STARTUP_LDTR_RPL, STARTUP_TR_RPL].freeze
        SEG_CACHE_STARTUP = [DEFAULT_SEG_CACHE, DEFAULT_CS_CACHE, DEFAULT_SEG_CACHE, DEFAULT_SEG_CACHE,
                             DEFAULT_SEG_CACHE, DEFAULT_SEG_CACHE, DEFAULT_LDTR_CACHE, DEFAULT_TR_CACHE].freeze

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          @prev_clk = 0
          init_regs
        end

        def propagate
          clk = in_val(:clk)
          rising = (clk == 1 && @prev_clk == 0)
          @prev_clk = clk

          if rising
            if in_val(:rst_n) == 0
              init_regs
            else
              update_gprs
              update_eflags
              update_cr0
              update_cr2_cr3
              update_eip
              update_segments
              update_gdtr_idtr
              update_debug_regs
            end
          end

          drive_outputs
        end

        private

        def init_regs
          @gpr = GPR_STARTUP.dup
          @flags = {
            cf: STARTUP_CFLAG, pf: STARTUP_PFLAG, af: STARTUP_AFLAG,
            zf: STARTUP_ZFLAG, sf: STARTUP_SFLAG, of: STARTUP_OFLAG,
            tf: STARTUP_TFLAG, if: STARTUP_IFLAG, df: STARTUP_DFLAG,
            iopl: STARTUP_IOPL, nt: STARTUP_NTFLAG, vm: STARTUP_VMFLAG,
            ac: STARTUP_ACFLAG, id: STARTUP_IDFLAG, rf: STARTUP_RFLAG
          }
          @cr0 = {
            pe: STARTUP_CR0_PE ? 1 : 0, mp: STARTUP_CR0_MP ? 1 : 0,
            em: STARTUP_CR0_EM ? 1 : 0, ts: STARTUP_CR0_TS ? 1 : 0,
            ne: STARTUP_CR0_NE ? 1 : 0, wp: STARTUP_CR0_WP ? 1 : 0,
            am: STARTUP_CR0_AM ? 1 : 0, nw: STARTUP_CR0_NW ? 1 : 0,
            cd: STARTUP_CR0_CD ? 1 : 0, pg: STARTUP_CR0_PG ? 1 : 0
          }
          @cr2 = STARTUP_CR2
          @cr3 = STARTUP_CR3
          @eip = STARTUP_EIP
          @seg = SEG_STARTUP.dup
          @seg_rpl = SEG_RPL_STARTUP.dup
          @seg_cache = SEG_CACHE_STARTUP.dup
          @seg_valid = Array.new(8, 1)
          @gdtr_base = STARTUP_GDTR_BASE
          @gdtr_limit = STARTUP_GDTR_LIMIT
          @idtr_base = STARTUP_IDTR_BASE
          @idtr_limit = STARTUP_IDTR_LIMIT
          @dr = [STARTUP_DR0, STARTUP_DR1, STARTUP_DR2, STARTUP_DR3]
          @dr6 = {
            breakpoints: STARTUP_DR6_BREAKPOINTS,
            b12: STARTUP_DR6_B12 ? 1 : 0,
            bd: STARTUP_DR6_BD ? 1 : 0,
            bs: STARTUP_DR6_BS ? 1 : 0,
            bt: STARTUP_DR6_BT ? 1 : 0
          }
          @dr7 = STARTUP_DR7
        end

        def update_gprs
          result = in_val(:result)

          # Determine destination index
          dst_index = nil
          if in_val(:write_eax) != 0
            dst_index = 0  # EAX
          elsif in_val(:write_regrm) != 0
            if in_val(:wr_dst_is_rm) != 0
              dst_index = in_val(:wr_modregrm_rm)
            elsif in_val(:wr_dst_is_reg) != 0
              dst_index = in_val(:wr_modregrm_reg)
            elsif in_val(:wr_dst_is_implicit_reg) != 0
              dst_index = in_val(:wr_modregrm_rm)
            end
          end

          if dst_index
            old = @gpr[dst_index]
            if in_val(:wr_operand_32bit) != 0
              @gpr[dst_index] = result & 0xFFFF_FFFF
            elsif in_val(:wr_is_8bit) != 0
              @gpr[dst_index] = (old & 0xFFFF_FF00) | (result & 0xFF)
            else
              @gpr[dst_index] = (old & 0xFFFF_0000) | (result & 0xFFFF)
            end
          end

          # Exception ESP restore
          if in_val(:exc_restore_esp) != 0
            @gpr[4] = in_val(:exc_restore_esp_value) & 0xFFFF_FFFF
          end
        end

        def update_eflags
          return unless in_val(:write_flags) != 0

          @flags[:cf] = in_val(:cflag_to_reg)
          @flags[:pf] = in_val(:pflag_to_reg)
          @flags[:af] = in_val(:aflag_to_reg)
          @flags[:zf] = in_val(:zflag_to_reg)
          @flags[:sf] = in_val(:sflag_to_reg)
          @flags[:of] = in_val(:oflag_to_reg)
          @flags[:tf] = in_val(:tflag_to_reg)
          @flags[:if] = in_val(:iflag_to_reg)
          @flags[:df] = in_val(:dflag_to_reg)
          @flags[:iopl] = in_val(:iopl_to_reg)
          @flags[:nt] = in_val(:ntflag_to_reg)
          @flags[:vm] = in_val(:vmflag_to_reg)
          @flags[:ac] = in_val(:acflag_to_reg)
          @flags[:id] = in_val(:idflag_to_reg)
          @flags[:rf] = in_val(:rflag_to_reg)
        end

        def update_cr0
          cr0_writes = {
            pe: :write_cr0_pe, mp: :write_cr0_mp, em: :write_cr0_em,
            ts: :write_cr0_ts, ne: :write_cr0_ne, wp: :write_cr0_wp,
            am: :write_cr0_am, nw: :write_cr0_nw, cd: :write_cr0_cd,
            pg: :write_cr0_pg
          }
          cr0_writes.each do |bit, write_sig|
            if in_val(write_sig) != 0
              @cr0[bit] = in_val(:"cr0_#{bit}_to_reg")
            end
          end
        end

        def update_cr2_cr3
          @cr2 = in_val(:cr2_to_reg) & 0xFFFF_FFFF if in_val(:write_cr2) != 0
          @cr3 = in_val(:cr3_to_reg) & 0xFFFF_FFFF if in_val(:write_cr3) != 0
        end

        def update_eip
          @eip = in_val(:eip_to_reg) & 0xFFFF_FFFF if in_val(:write_eip) != 0
        end

        def update_segments
          if in_val(:write_seg) != 0
            idx = in_val(:wr_seg_index)
            @seg[idx] = in_val(:seg_to_reg) & 0xFFFF
          end
          if in_val(:write_seg_rpl) != 0
            idx = in_val(:wr_seg_index)
            @seg_rpl[idx] = in_val(:seg_rpl_to_reg) & 0x3
          end
          if in_val(:write_seg_cache) != 0
            idx = in_val(:wr_seg_index)
            @seg_cache[idx] = in_val(:seg_cache_to_reg)
          end
          if in_val(:write_seg_valid) != 0
            idx = in_val(:wr_seg_index)
            @seg_valid[idx] = in_val(:seg_valid_to_reg)
          end
        end

        def update_gdtr_idtr
          if in_val(:write_gdtr) != 0
            @gdtr_base = in_val(:gdtr_base_to_reg) & 0xFFFF_FFFF
            @gdtr_limit = in_val(:gdtr_limit_to_reg) & 0xFFFF
          end
          if in_val(:write_idtr) != 0
            @idtr_base = in_val(:idtr_base_to_reg) & 0xFFFF_FFFF
            @idtr_limit = in_val(:idtr_limit_to_reg) & 0xFFFF
          end
        end

        def update_debug_regs
          @dr[0] = in_val(:dr0_to_reg) & 0xFFFF_FFFF if in_val(:write_dr0) != 0
          @dr[1] = in_val(:dr1_to_reg) & 0xFFFF_FFFF if in_val(:write_dr1) != 0
          @dr[2] = in_val(:dr2_to_reg) & 0xFFFF_FFFF if in_val(:write_dr2) != 0
          @dr[3] = in_val(:dr3_to_reg) & 0xFFFF_FFFF if in_val(:write_dr3) != 0

          if in_val(:write_dr6) != 0
            @dr6[:breakpoints] = in_val(:dr6_breakpoints_to_reg) & 0xF
            @dr6[:b12] = in_val(:dr6_b12_to_reg)
            @dr6[:bd] = in_val(:dr6_bd_to_reg)
            @dr6[:bs] = in_val(:dr6_bs_to_reg)
            @dr6[:bt] = in_val(:dr6_bt_to_reg)
          end

          @dr7 = in_val(:dr7_to_reg) & 0xFFFF_FFFF if in_val(:write_dr7) != 0
        end

        def drive_outputs
          # GPRs
          GPR_NAMES.each_with_index { |name, i| out_set(name, @gpr[i]) }

          # EFLAGS
          out_set(:cflag, @flags[:cf])
          out_set(:pflag, @flags[:pf])
          out_set(:aflag, @flags[:af])
          out_set(:zflag, @flags[:zf])
          out_set(:sflag, @flags[:sf])
          out_set(:oflag, @flags[:of])
          out_set(:tflag, @flags[:tf])
          out_set(:iflag, @flags[:if])
          out_set(:dflag, @flags[:df])
          out_set(:iopl, @flags[:iopl])
          out_set(:ntflag, @flags[:nt])
          out_set(:vmflag, @flags[:vm])
          out_set(:acflag, @flags[:ac])
          out_set(:idflag, @flags[:id])
          out_set(:rflag, @flags[:rf])

          # CR0
          @cr0.each { |bit, val| out_set(:"cr0_#{bit}", val) }
          out_set(:cr2, @cr2)
          out_set(:cr3, @cr3)

          # Mode outputs (combinational)
          pe = @cr0[:pe]
          vm = @flags[:vm]
          out_set(:real_mode, pe == 0 ? 1 : 0)
          out_set(:protected_mode, (pe == 1 && vm == 0) ? 1 : 0)
          out_set(:v8086_mode, (pe == 1 && vm == 1) ? 1 : 0)
          out_set(:cpl, @seg_rpl[SEGMENT_CS])

          # EIP
          out_set(:eip, @eip)

          # Segments
          SEG_NAMES.each_with_index do |name, i|
            out_set(name, @seg[i])
            out_set(:"#{name}_rpl", @seg_rpl[i])
            out_set(:"#{name}_cache", @seg_cache[i])
            out_set(:"#{name}_cache_valid", @seg_valid[i])
          end

          # GDTR, IDTR
          out_set(:gdtr_base, @gdtr_base)
          out_set(:gdtr_limit, @gdtr_limit)
          out_set(:idtr_base, @idtr_base)
          out_set(:idtr_limit, @idtr_limit)

          # Debug registers
          @dr.each_with_index { |v, i| out_set(:"dr#{i}", v) }
          out_set(:dr6_breakpoints, @dr6[:breakpoints])
          out_set(:dr6_b12, @dr6[:b12])
          out_set(:dr6_bd, @dr6[:bd])
          out_set(:dr6_bs, @dr6[:bs])
          out_set(:dr6_bt, @dr6[:bt])
          out_set(:dr7, @dr7)
        end
      end
    end
  end
end
