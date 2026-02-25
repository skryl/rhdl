# ao486 Pipeline — Step-at-a-time instruction executor
# Ported from: rtl/ao486/pipeline/pipeline.v (simplified for real-mode subset)
#
# Wires together: Decode, ALU, Shift, Multiply, Divide, ConditionEval,
# ReadEffectiveAddress, and WriteRegister to execute x86 instructions
# one at a time. Non-pipelined; later phases will add pipeline stages.

require_relative '../../../../lib/rhdl'
require_relative '../constants'
require_relative 'decode'
require_relative 'read_effective_address'
require_relative 'write_register'
require_relative '../execute/alu'
require_relative '../execute/shift'
require_relative '../execute/multiply'
require_relative '../execute/divide'
require_relative '../execute/condition_eval'

module RHDL
  module Examples
    module AO486
      class Pipeline
        C = Constants

        # Raised when a memory access violates segment limits in protected mode
        class SegmentFault < StandardError; end

        # Raised when paging detects a page fault (#PF)
        class PageFault < StandardError
          attr_reader :linear_addr, :error_code
          def initialize(linear_addr, error_code)
            @linear_addr = linear_addr
            @error_code = error_code
            super("Page fault at 0x#{linear_addr.to_s(16)}")
          end
        end

        GPR_NAMES = [:eax, :ecx, :edx, :ebx, :esp, :ebp, :esi, :edi].freeze

        def initialize
          @decode = Decode.new(:decode)
          @alu = ALU.new(:alu)
          @shift = Shift.new(:shift)
          @multiply = Multiply.new(:multiply)
          @divide = Divide.new(:divide)
          @cond_eval = ConditionEval.new(:cond_eval)
          @ea_calc = ReadEffectiveAddress.new(:ea_calc)
          @regfile = WriteRegister.new(:regfile)

          # I/O callbacks
          @io_read_callback = nil
          @io_write_callback = nil

          # Interrupt state
          @pending_interrupt = nil  # { vector: N } or nil

          # TLB: hash from virtual page number (linear[31:12]) to { phys_page:, rw:, us: }
          @tlb = {}

          # Initialize register file
          clock_regfile_reset
        end

        def on_io_read(&block)
          @io_read_callback = block
        end

        def on_io_write(&block)
          @io_write_callback = block
        end

        # Raise a hardware interrupt (will be serviced on next step if IF=1)
        def raise_hw_interrupt(vector)
          @pending_interrupt = { vector: vector }
        end

        # Public accessor for EFLAGS
        def build_eflags_public
          build_eflags
        end

        # Public accessors for segment caches and descriptor base
        def seg_cache_public(name)
          seg_cache(name)
        end

        def desc_base_public(cache)
          desc_base(cache)
        end

        # Load GDTR directly (for testing)
        def load_gdtr(base, limit)
          write_regfile(write_gdtr: 1, gdtr_base_to_reg: base, gdtr_limit_to_reg: limit)
        end

        # Load IDTR directly (for testing)
        def load_idtr(base, limit)
          write_regfile(write_idtr: 1, idtr_base_to_reg: base, idtr_limit_to_reg: limit)
        end

        # Set CR0.PE directly (for testing)
        def set_cr0_pe(value)
          write_regfile(write_cr0_pe: 1, cr0_pe_to_reg: value)
        end

        # Set CR0.PG directly (for testing)
        def set_cr0_pg(value)
          write_regfile(write_cr0_pg: 1, cr0_pg_to_reg: value)
        end

        # Set CR0.WP directly (for testing)
        def set_cr0_wp(value)
          write_regfile(write_cr0_wp: 1, cr0_wp_to_reg: value)
        end

        # Set CR0.EM directly (for testing)
        def set_cr0_em(value)
          write_regfile(write_cr0_em: 1, cr0_em_to_reg: value)
        end

        # Set CR3 directly (for testing)
        def set_cr3(value)
          write_regfile(write_cr3: 1, cr3_to_reg: value)
          @tlb.clear  # CR3 write flushes TLB
        end

        # Set CS.D/B bit directly (for testing — controls 16/32-bit default)
        def set_cs_db(value)
          cs_cache = seg_cache(:cs)
          if value != 0
            cs_cache |= (1 << C::DESC_BIT_D_B)
          else
            cs_cache &= ~(1 << C::DESC_BIT_D_B)
          end
          write_regfile(write_seg: 1, wr_seg_index: C::SEGMENT_CS,
                        seg_to_reg: reg(:cs),
                        write_seg_cache: 1, seg_cache_to_reg: cs_cache,
                        write_seg_valid: 1, seg_valid_to_reg: 1)
        end

        # Set CPL directly (for testing) — CPL is derived from CS selector RPL
        def set_cpl(value)
          cs_sel = reg(:cs)
          new_sel = (cs_sel & ~3) | (value & 3)
          write_regfile(write_seg: 1, wr_seg_index: C::SEGMENT_CS, seg_to_reg: new_sel,
                        write_seg_cache: 1, seg_cache_to_reg: seg_cache(:cs),
                        write_seg_valid: 1, seg_valid_to_reg: 1)
        end

        # Set DS base directly (for testing segment overrides)
        def set_ds_base(base)
          set_seg_base(:ds, C::SEGMENT_DS, base)
        end

        # Set ES base directly (for testing segment overrides)
        def set_es_base(base)
          set_seg_base(:es, C::SEGMENT_ES, base)
        end

        # Set EFLAGS directly (for testing)
        def set_flags(value)
          write_regfile(
            write_flags: 1,
            cflag_to_reg: (value >> 0) & 1,
            pflag_to_reg: (value >> 2) & 1,
            aflag_to_reg: (value >> 4) & 1,
            zflag_to_reg: (value >> 6) & 1,
            sflag_to_reg: (value >> 7) & 1,
            tflag_to_reg: (value >> 8) & 1,
            iflag_to_reg: (value >> 9) & 1,
            dflag_to_reg: (value >> 10) & 1,
            oflag_to_reg: (value >> 11) & 1,
            iopl_to_reg: (value >> 12) & 3,
            ntflag_to_reg: (value >> 14) & 1,
            rflag_to_reg: (value >> 16) & 1,
            vmflag_to_reg: (value >> 17) & 1,
            acflag_to_reg: (value >> 18) & 1,
            idflag_to_reg: (value >> 21) & 1
          )
        end

        # Check if TLB has an entry for the given linear address
        def tlb_hit?(linear_addr)
          vpn = (linear_addr >> 12) & 0xFFFFF
          @tlb.key?(vpn)
        end

        # Set up a convenient real-mode state for testing
        def setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7000)
          # Set EIP
          write_regfile(write_eip: 1, eip_to_reg: eip)

          # Set ESP
          write_regfile(write_eax: 0, write_regrm: 1, wr_dst_is_rm: 1,
                        wr_modregrm_rm: 4, wr_operand_32bit: 0, wr_is_8bit: 0,
                        result: esp)

          # Set CS selector and descriptor cache with desired base
          # In real mode, selector = base >> 4
          cs_selector = (cs_base >> 4) & 0xFFFF
          # Build a 64-bit descriptor with the given base
          # Format: base[31:24] at bits 63:56, base[23:0] at bits 39:16
          base_hi = (cs_base >> 24) & 0xFF
          base_lo = cs_base & 0xFF_FFFF
          # Start with default CS cache and override base
          cache = C::DEFAULT_CS_CACHE
          # Clear existing base fields and set new ones
          cache = cache & ~(0xFF << 56) & ~(0xFF_FFFF << 16)
          cache = cache | (base_hi << 56) | (base_lo << 16)

          write_regfile(write_seg: 1, wr_seg_index: C::SEGMENT_CS, seg_to_reg: cs_selector,
                        write_seg_cache: 1, seg_cache_to_reg: cache,
                        write_seg_valid: 1, seg_valid_to_reg: 1)
        end

        # Execute one instruction. Returns :ok or :halt
        def step(memory)
          # 0. Check for pending hardware interrupt (IF=1 required)
          if @pending_interrupt && reg(:iflag) == 1
            int_info = @pending_interrupt
            @pending_interrupt = nil
            return dispatch_interrupt(memory, int_info[:vector], reg(:eip), :hardware)
          end

          # 1. Fetch: read up to 15 bytes at CS:EIP
          eip = reg(:eip)
          cs_cache = seg_cache(:cs)
          cs_base = desc_base(cs_cache)
          linear_eip = (cs_base + eip) & 0xFFFF_FFFF
          fetch_data = fetch_bytes(memory, linear_eip, 8)
          fetch_valid = [8, count_available(memory, linear_eip, 8)].min

          # 2. Decode
          @decode.set_input(:fetch_valid, fetch_valid)
          @decode.set_input(:fetch, fetch_data)
          # In real mode, default operand/address size depends on CS.D bit
          cs_d = (cs_cache >> C::DESC_BIT_D_B) & 1
          @decode.set_input(:operand_32bit, cs_d)
          @decode.set_input(:address_32bit, cs_d)
          @decode.propagate

          cmd = @decode.get_output(:dec_cmd)
          cmdex = @decode.get_output(:dec_cmdex)
          consumed = @decode.get_output(:dec_consumed)
          is_8bit = @decode.get_output(:dec_is_8bit) != 0
          op32 = @decode.get_output(:dec_operand_32bit) != 0
          addr32 = @decode.get_output(:dec_address_32bit) != 0
          modregrm_mod = @decode.get_output(:dec_modregrm_mod)
          modregrm_reg = @decode.get_output(:dec_modregrm_reg)
          modregrm_rm = @decode.get_output(:dec_modregrm_rm)

          if @decode.get_output(:dec_ready) == 0
            return :not_ready
          end

          rep_prefix = @decode.get_output(:dec_prefix_group_1_rep)
          seg_override = @decode.get_output(:dec_prefix_group_2_seg)

          # Get raw instruction bytes for operand resolution
          bytes = Array.new(15) { |i| (fetch_data >> (i * 8)) & 0xFF }

          # Handle REP/REPE/REPNE for string operations
          if rep_prefix != 0 && string_op?(cmd)
            return exec_string_rep(cmd, cmdex, consumed, is_8bit, op32, addr32,
                                   modregrm_mod, modregrm_reg, modregrm_rm,
                                   bytes, memory, cs_base, eip, rep_prefix, seg_override)
          end

          # 3-5: Read, Execute, Write — dispatch by command
          execute_instruction(cmd, cmdex, consumed, is_8bit, op32, addr32,
                              modregrm_mod, modregrm_reg, modregrm_rm,
                              bytes, memory, cs_base, eip, seg_override)
        end

        # Register accessors
        def reg(name)
          @regfile.get_output(name)
        end

        def set_reg(name, value)
          idx = GPR_NAMES.index(name)
          if idx
            write_regfile(write_eax: 0, write_regrm: 1, wr_dst_is_rm: 1,
                          wr_modregrm_rm: idx, wr_operand_32bit: 1, wr_is_8bit: 0,
                          result: value)
          else
            # Handle segment registers
            seg_map = { es: C::SEGMENT_ES, cs: C::SEGMENT_CS, ss: C::SEGMENT_SS,
                        ds: C::SEGMENT_DS, fs: C::SEGMENT_FS, gs: C::SEGMENT_GS }
            seg_index = seg_map[name]
            if seg_index
              write_regfile(write_seg: 1, wr_seg_index: seg_index, seg_to_reg: value & 0xFFFF,
                            write_seg_cache: 1, seg_cache_to_reg: seg_cache(name),
                            write_seg_valid: 1, seg_valid_to_reg: 1)
            end
          end
        end

        def set_flag(flag, value)
          flag_map = {
            cf: :cflag_to_reg, pf: :pflag_to_reg, af: :aflag_to_reg,
            zf: :zflag_to_reg, sf: :sflag_to_reg, of: :oflag_to_reg,
            tf: :tflag_to_reg, if: :iflag_to_reg, df: :dflag_to_reg
          }
          inputs = { write_flags: 1 }

          # Read current flag values
          flag_outputs = {
            cflag_to_reg: reg(:cflag), pflag_to_reg: reg(:pflag),
            aflag_to_reg: reg(:aflag), zflag_to_reg: reg(:zflag),
            sflag_to_reg: reg(:sflag), oflag_to_reg: reg(:oflag),
            tflag_to_reg: reg(:tflag), iflag_to_reg: reg(:iflag),
            dflag_to_reg: reg(:dflag), iopl_to_reg: reg(:iopl),
            ntflag_to_reg: reg(:ntflag), vmflag_to_reg: reg(:vmflag),
            acflag_to_reg: reg(:acflag), idflag_to_reg: reg(:idflag),
            rflag_to_reg: reg(:rflag)
          }

          target = flag_map[flag]
          flag_outputs[target] = value if target

          write_regfile(**inputs.merge(flag_outputs))
        end

        private

        def set_seg_base(name, index, base)
          cache = seg_cache(name)
          # Clear existing base fields and set new ones
          cache = cache & ~(0xFF << 56) & ~(0xFF_FFFF << 16)
          base_hi = (base >> 24) & 0xFF
          base_lo = base & 0xFF_FFFF
          cache = cache | (base_hi << 56) | (base_lo << 16)
          write_regfile(write_seg: 1, wr_seg_index: index,
                        seg_to_reg: reg(name),
                        write_seg_cache: 1, seg_cache_to_reg: cache,
                        write_seg_valid: 1, seg_valid_to_reg: 1)
        end

        # Resolve the data segment base from the segment override index
        def resolve_segment_base(seg_index)
          case seg_index
          when C::SEGMENT_ES then desc_base(seg_cache(:es))
          when C::SEGMENT_CS then desc_base(seg_cache(:cs))
          when C::SEGMENT_SS then desc_base(seg_cache(:ss))
          when C::SEGMENT_DS then desc_base(seg_cache(:ds))
          when C::SEGMENT_FS then desc_base(seg_cache(:fs))
          when C::SEGMENT_GS then desc_base(seg_cache(:gs))
          else desc_base(seg_cache(:ds))
          end
        end

        # ---------- Memory helpers ----------

        def fetch_bytes(memory, addr, count)
          val = 0
          if reg(:cr0_pg) != 0
            # With paging, translate each byte (simplification: translate per-page)
            count.times do |i|
              la = (addr + i) & 0xFFFF_FFFF
              pa = translate_linear(memory, la, :read, false)  # code fetch = supervisor read
              val |= ((memory[pa] || 0) & 0xFF) << (i * 8)
            end
          else
            count.times { |i| val |= ((memory[(addr + i) & 0xFFFF_FFFF] || 0) & 0xFF) << (i * 8) }
          end
          val
        end

        def count_available(memory, addr, max)
          max  # Simplified: assume all bytes available
        end

        def mem_read(memory, addr, size)
          addr = addr & 0xFFFF_FFFF
          if reg(:cr0_pg) != 0
            return mem_read_paged(memory, addr, size)
          end
          mem_read_phys(memory, addr, size)
        end

        def mem_write(memory, addr, value, size)
          addr = addr & 0xFFFF_FFFF
          if reg(:cr0_pg) != 0
            return mem_write_paged(memory, addr, value, size)
          end
          mem_write_phys(memory, addr, value, size)
        end

        def mem_read_phys(memory, addr, size)
          case size
          when 1 then (memory[addr] || 0) & 0xFF
          when 2 then ((memory[addr] || 0) & 0xFF) |
                      (((memory[(addr + 1) & 0xFFFF_FFFF] || 0) & 0xFF) << 8)
          when 4 then ((memory[addr] || 0) & 0xFF) |
                      (((memory[(addr + 1) & 0xFFFF_FFFF] || 0) & 0xFF) << 8) |
                      (((memory[(addr + 2) & 0xFFFF_FFFF] || 0) & 0xFF) << 16) |
                      (((memory[(addr + 3) & 0xFFFF_FFFF] || 0) & 0xFF) << 24)
          else 0
          end
        end

        def mem_write_phys(memory, addr, value, size)
          case size
          when 1
            memory[addr] = value & 0xFF
          when 2
            memory[addr] = value & 0xFF
            memory[(addr + 1) & 0xFFFF_FFFF] = (value >> 8) & 0xFF
          when 4
            memory[addr] = value & 0xFF
            memory[(addr + 1) & 0xFFFF_FFFF] = (value >> 8) & 0xFF
            memory[(addr + 2) & 0xFFFF_FFFF] = (value >> 16) & 0xFF
            memory[(addr + 3) & 0xFFFF_FFFF] = (value >> 24) & 0xFF
          end
        end

        def mem_read_paged(memory, linear, size)
          # Translate each byte through paging (handles page boundary crossings)
          is_user = reg(:cpl) == 3
          val = 0
          size.times do |i|
            la = (linear + i) & 0xFFFF_FFFF
            pa = translate_linear(memory, la, :read, is_user)
            val |= ((memory[pa] || 0) & 0xFF) << (i * 8)
          end
          val
        end

        def mem_write_paged(memory, linear, value, size)
          is_user = reg(:cpl) == 3
          size.times do |i|
            la = (linear + i) & 0xFFFF_FFFF
            pa = translate_linear(memory, la, :write, is_user)
            memory[pa] = (value >> (i * 8)) & 0xFF
          end
        end

        # Translate a linear address to a physical address using page tables.
        # access_type: :read or :write
        # is_user: true if CPL=3 (user mode)
        # Returns physical address. Raises PageFault on failure.
        def translate_linear(memory, linear, access_type, is_user)
          vpn = (linear >> 12) & 0xFFFFF
          offset = linear & 0xFFF

          # TLB lookup
          if (entry = @tlb[vpn])
            # Permission check on TLB hit
            check_page_permissions(linear, entry, access_type, is_user)
            return ((entry[:phys_page] << 12) | offset) & 0xFFFF_FFFF
          end

          # TLB miss — page walk
          cr3_val = reg(:cr3)
          pd_base = cr3_val & 0xFFFFF000

          # Read PDE
          pde_index = (linear >> 22) & 0x3FF
          pde_addr = (pd_base + pde_index * 4) & 0xFFFF_FFFF
          pde = mem_read_phys(memory, pde_addr, 4)

          # Check PDE present
          unless (pde & 1) != 0
            error_code = build_pf_error_code(false, access_type == :write, is_user)
            raise PageFault.new(linear, error_code)
          end

          # Check for 4MB page (PS bit)
          if (pde & 0x80) != 0
            # 4MB page: physical = PDE[31:22] + linear[21:0]
            phys_page = (pde >> 22) & 0x3FF  # upper 10 bits of PDE become upper 10 bits
            phys_base = (phys_page << 22) | (linear & 0x3FFFFF)
            pa = phys_base & 0xFFFF_FFFF

            # Build TLB entry for 4MB page (store as multiple 4KB entries for simplicity)
            # For TLB, store the specific 4KB page
            rw = (pde >> 1) & 1
            us = (pde >> 2) & 1
            tlb_entry = { phys_page: (pa >> 12) & 0xFFFFF, rw: rw, us: us, large: true }
            check_page_permissions(linear, tlb_entry, access_type, is_user)
            @tlb[vpn] = tlb_entry
            return pa
          end

          # Read PTE
          pt_base = pde & 0xFFFFF000
          pte_index = (linear >> 12) & 0x3FF
          pte_addr = (pt_base + pte_index * 4) & 0xFFFF_FFFF
          pte = mem_read_phys(memory, pte_addr, 4)

          # Check PTE present
          unless (pte & 1) != 0
            error_code = build_pf_error_code(false, access_type == :write, is_user)
            raise PageFault.new(linear, error_code)
          end

          # Combined permissions (PDE AND PTE)
          rw = ((pde >> 1) & 1) & ((pte >> 1) & 1)
          us = ((pde >> 2) & 1) & ((pte >> 2) & 1)

          phys_page = (pte >> 12) & 0xFFFFF
          tlb_entry = { phys_page: phys_page, rw: rw, us: us, large: false }
          check_page_permissions(linear, tlb_entry, access_type, is_user)
          @tlb[vpn] = tlb_entry

          ((phys_page << 12) | offset) & 0xFFFF_FFFF
        end

        def check_page_permissions(linear, entry, access_type, is_user)
          # User accessing supervisor page
          if is_user && entry[:us] == 0
            error_code = build_pf_error_code(true, access_type == :write, true)
            raise PageFault.new(linear, error_code)
          end

          # Write to read-only page
          if access_type == :write && entry[:rw] == 0
            if is_user
              error_code = build_pf_error_code(true, true, true)
              raise PageFault.new(linear, error_code)
            elsif reg(:cr0_wp) != 0
              # Supervisor with WP=1 can't write read-only pages
              error_code = build_pf_error_code(true, true, false)
              raise PageFault.new(linear, error_code)
            end
            # Supervisor with WP=0 can write read-only pages — no fault
          end
        end

        # Build #PF error code: bit 0=P (present), bit 1=W/R, bit 2=U/S
        def build_pf_error_code(present, is_write, is_user)
          code = 0
          code |= 1 if present
          code |= 2 if is_write
          code |= 4 if is_user
          code
        end

        # ---------- Register file helpers ----------

        def seg_cache(name)
          @regfile.get_output(:"#{name}_cache")
        end

        def desc_base(cache)
          hi = (cache >> 56) & 0xFF
          lo = (cache >> 16) & 0xFF_FFFF
          (hi << 24) | lo
        end

        def gpr(index)
          @regfile.get_output(GPR_NAMES[index])
        end

        def operand_size(is_8bit, op32)
          if is_8bit then 1
          elsif op32 then 4
          else 2
          end
        end

        def size_mask(sz)
          case sz
          when 1 then 0xFF
          when 2 then 0xFFFF
          else 0xFFFF_FFFF
          end
        end

        def sign_extend_8(val)
          val = val & 0xFF
          (val & 0x80) != 0 ? val - 0x100 : val
        end

        def sign_extend_16(val)
          val = val & 0xFFFF
          (val & 0x8000) != 0 ? val - 0x10000 : val
        end

        def clock_regfile_reset
          # Reset cycle
          @regfile.set_input(:clk, 0)
          clear_regfile_inputs
          @regfile.set_input(:rst_n, 0)
          @regfile.propagate
          @regfile.set_input(:clk, 1)
          @regfile.propagate

          # Release reset
          @regfile.set_input(:clk, 0)
          @regfile.set_input(:rst_n, 1)
          @regfile.propagate
          @regfile.set_input(:clk, 1)
          @regfile.propagate
        end

        def clear_regfile_inputs
          # Clear all write enables
          [:write_eax, :write_regrm, :wr_dst_is_rm, :wr_dst_is_reg,
           :wr_dst_is_implicit_reg, :write_flags, :write_eip,
           :write_seg, :write_seg_rpl, :write_seg_cache, :write_seg_valid,
           :write_cr0_pe, :write_cr0_mp, :write_cr0_em, :write_cr0_ts,
           :write_cr0_ne, :write_cr0_wp, :write_cr0_am, :write_cr0_nw,
           :write_cr0_cd, :write_cr0_pg, :write_cr2, :write_cr3,
           :write_gdtr, :write_idtr, :write_dr0, :write_dr1, :write_dr2,
           :write_dr3, :write_dr6, :write_dr7, :exc_restore_esp].each do |sig|
            @regfile.set_input(sig, 0)
          end

          # Set defaults for value inputs
          @regfile.set_input(:result, 0)
          @regfile.set_input(:wr_modregrm_reg, 0)
          @regfile.set_input(:wr_modregrm_rm, 0)
          @regfile.set_input(:wr_operand_32bit, 0)
          @regfile.set_input(:wr_is_8bit, 0)
          @regfile.set_input(:eip_to_reg, 0)
          @regfile.set_input(:wr_seg_index, 0)
          @regfile.set_input(:seg_to_reg, 0)
          @regfile.set_input(:seg_rpl_to_reg, 0)
          @regfile.set_input(:seg_cache_to_reg, 0)
          @regfile.set_input(:seg_valid_to_reg, 0)
        end

        def write_regfile(**inputs)
          @regfile.set_input(:clk, 0)
          clear_regfile_inputs
          @regfile.set_input(:rst_n, 1)
          inputs.each { |k, v| @regfile.set_input(k, v) }
          @regfile.propagate
          @regfile.set_input(:clk, 1)
          @regfile.propagate
        end

        # ---------- Instruction execution ----------

        def execute_instruction(cmd, cmdex, consumed, is_8bit, op32, addr32,
                                modregrm_mod, modregrm_reg, modregrm_rm,
                                bytes, memory, cs_base, eip, seg_override = C::SEGMENT_DS)
          sz = operand_size(is_8bit, op32)
          mask = size_mask(sz)
          next_eip = (eip + consumed) & 0xFFFF

          # Find prefix count: consumed - instruction_len (decode returns total)
          # We need the raw opcode to determine operand routing
          opcode, prefix_count, has_0f = find_opcode(bytes, consumed)

          # Default segment for data access — apply segment override prefix
          ss_base = desc_base(seg_cache(:ss))
          ds_base = resolve_segment_base(seg_override)
          es_base = desc_base(seg_cache(:es))

          begin
          case cmd
          when C::CMD_Arith, C::CMD_ADD, C::CMD_OR, C::CMD_ADC, C::CMD_SBB,
               C::CMD_AND, C::CMD_SUB, C::CMD_XOR, C::CMD_CMP
            exec_arith(cmd, opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                       modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                       eip, next_eip)

          when C::CMD_MOV
            exec_mov(opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)

          when C::CMD_INC_DEC
            exec_inc_dec(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                         modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                         eip, next_eip)

          when C::CMD_PUSH
            exec_push(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ss_base,
                      eip, next_eip)

          when C::CMD_POP
            exec_pop(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)

          when C::CMD_JMP
            exec_jmp(opcode, prefix_count, has_0f, op32, bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_Jcc
            exec_jcc(opcode, prefix_count, has_0f, op32, addr32, bytes, eip, next_eip)

          when C::CMD_CALL
            exec_call(opcode, prefix_count, has_0f, op32, bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_RET_near
            exec_ret_near(opcode, prefix_count, op32, bytes, memory, ss_base, eip, next_eip)

          when C::CMD_LEA
            exec_lea(opcode, prefix_count, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)

          when C::CMD_TEST
            exec_test(opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                      eip, next_eip)

          when C::CMD_XCHG
            exec_xchg(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                      eip, next_eip)

          when C::CMD_Shift
            exec_shift(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                       modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                       eip, next_eip)

          when C::CMD_NEG
            exec_neg(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)

          when C::CMD_NOT
            exec_not(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)

          when C::CMD_CLC
            set_flag(:cf, 0)
            advance_eip(next_eip)
            :ok

          when C::CMD_STC
            set_flag(:cf, 1)
            advance_eip(next_eip)
            :ok

          when C::CMD_CMC
            set_flag(:cf, reg(:cflag) ^ 1)
            advance_eip(next_eip)
            :ok

          when C::CMD_CLD
            set_flag(:df, 0)
            advance_eip(next_eip)
            :ok

          when C::CMD_STD
            set_flag(:df, 1)
            advance_eip(next_eip)
            :ok

          when C::CMD_CLI
            set_flag(:if, 0)
            advance_eip(next_eip)
            :ok

          when C::CMD_STI
            set_flag(:if, 1)
            advance_eip(next_eip)
            :ok

          when C::CMD_HLT
            advance_eip(next_eip)
            :halt

          when C::CMD_PUSHF
            exec_pushf(op32, memory, ss_base, eip, next_eip)

          when C::CMD_POPF
            exec_popf(op32, memory, ss_base, eip, next_eip)

          when C::CMD_SAHF
            exec_sahf(eip, next_eip)

          when C::CMD_LAHF
            exec_lahf(eip, next_eip)

          when C::CMD_CBW
            exec_cbw(op32, eip, next_eip)

          when C::CMD_CWD
            exec_cwd(op32, eip, next_eip)

          when C::CMD_MUL
            exec_mul(is_8bit, op32, addr32, sz, mask, modregrm_mod, modregrm_reg, modregrm_rm,
                     bytes, memory, ds_base, ss_base, prefix_count, eip, next_eip)

          when C::CMD_IMUL
            exec_imul(opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                      eip, next_eip)

          when C::CMD_DIV
            exec_div(false, is_8bit, op32, addr32, sz, mask, modregrm_mod, modregrm_reg, modregrm_rm,
                     bytes, memory, ds_base, ss_base, prefix_count, eip, next_eip)

          when C::CMD_IDIV
            exec_div(true, is_8bit, op32, addr32, sz, mask, modregrm_mod, modregrm_reg, modregrm_rm,
                     bytes, memory, ds_base, ss_base, prefix_count, eip, next_eip)

          when C::CMD_MOVZX
            exec_movzx(opcode, prefix_count, is_8bit, op32, addr32, modregrm_mod, modregrm_reg, modregrm_rm,
                       bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_MOVSX
            exec_movsx(opcode, prefix_count, is_8bit, op32, addr32, modregrm_mod, modregrm_reg, modregrm_rm,
                       bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_PUSHA
            exec_pusha(op32, memory, ss_base, eip, next_eip)

          when C::CMD_POPA
            exec_popa(op32, memory, ss_base, eip, next_eip)

          when C::CMD_MOVS
            exec_movs(is_8bit, op32, memory, ds_base, es_base, eip, next_eip)

          when C::CMD_STOS
            exec_stos(is_8bit, op32, memory, es_base, eip, next_eip)

          when C::CMD_LODS
            exec_lods(is_8bit, op32, memory, ds_base, eip, next_eip)

          when C::CMD_CMPS
            exec_cmps(is_8bit, op32, memory, ds_base, es_base, eip, next_eip)

          when C::CMD_SCAS
            exec_scas(is_8bit, op32, memory, es_base, eip, next_eip)

          when C::CMD_ENTER
            exec_enter(op32, bytes, prefix_count, memory, ss_base, eip, next_eip)

          when C::CMD_LEAVE
            exec_leave(op32, memory, ss_base, eip, next_eip)

          when C::CMD_IN
            exec_in(opcode, prefix_count, is_8bit, op32, bytes, eip, next_eip)

          when C::CMD_INS
            exec_ins(is_8bit, op32, addr32, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_OUT
            exec_out(opcode, prefix_count, is_8bit, op32, bytes, eip, next_eip)

          when C::CMD_OUTS
            exec_outs(is_8bit, op32, addr32, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_XLAT
            exec_xlat(memory, ds_base, eip, next_eip)

          when C::CMD_INT_INTO
            exec_int_into(opcode, prefix_count, bytes, memory, ss_base, eip, next_eip)

          when C::CMD_IRET
            exec_iret(op32, memory, ss_base, eip, next_eip)

          when C::CMD_LGDT
            exec_lgdt(opcode, prefix_count, addr32, bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_LIDT
            exec_lidt(opcode, prefix_count, addr32, bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_control_reg
            exec_control_reg(opcode, prefix_count, has_0f, bytes, modregrm_mod, modregrm_reg, modregrm_rm,
                             eip, next_eip)

          when C::CMD_MOV_to_seg
            exec_mov_to_seg(opcode, prefix_count, addr32, bytes, memory, ds_base, ss_base,
                            modregrm_mod, modregrm_reg, modregrm_rm, eip, next_eip)

          when C::CMD_INVLPG
            exec_invlpg(prefix_count, addr32, modregrm_mod, modregrm_rm,
                        bytes, ds_base, ss_base, eip, next_eip)

          when C::CMD_CPUID
            exec_cpuid(eip, next_eip)

          when C::CMD_BOUND
            exec_bound(opcode, prefix_count, op32, addr32, sz,
                       modregrm_mod, modregrm_reg, modregrm_rm,
                       bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_BSF
            exec_bsf_bsr(opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                         modregrm_mod, modregrm_reg, modregrm_rm,
                         bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_BT
            exec_bt(opcode, prefix_count, has_0f, op32, addr32, sz, mask,
                    modregrm_mod, modregrm_reg, modregrm_rm,
                    bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_SETcc
            exec_setcc(opcode, prefix_count, has_0f, addr32,
                       modregrm_mod, modregrm_reg, modregrm_rm,
                       bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_BSWAP
            exec_bswap(opcode, prefix_count, has_0f, bytes, eip, next_eip)

          when C::CMD_LOOP
            exec_loop(opcode, prefix_count, op32, bytes, eip, next_eip)

          when C::CMD_JCXZ
            exec_jcxz(prefix_count, op32, bytes, eip, next_eip)

          when C::CMD_SHLD, C::CMD_SHRD
            exec_shxd(opcode, prefix_count, has_0f, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm,
                      bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_AAA
            exec_aaa(eip, next_eip)

          when C::CMD_AAS
            exec_aas(eip, next_eip)

          when C::CMD_DAA
            exec_daa(eip, next_eip)

          when C::CMD_DAS
            exec_das(eip, next_eip)

          when C::CMD_AAD
            exec_aad(prefix_count, bytes, eip, next_eip)

          when C::CMD_AAM
            exec_aam(prefix_count, bytes, memory, eip, next_eip)

          when C::CMD_SALC
            exec_salc(eip, next_eip)

          when C::CMD_fpu
            exec_fpu(memory, eip, next_eip)

          when C::CMD_PUSH_MOV_SEG
            exec_push_mov_seg(opcode, prefix_count, op32, addr32, sz,
                              modregrm_mod, modregrm_reg, modregrm_rm,
                              bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_POP_seg
            exec_pop_seg(opcode, prefix_count, op32, memory, ss_base, eip, next_eip)

          when C::CMD_RET_far
            exec_ret_far(opcode, prefix_count, op32, bytes, memory, ss_base, eip, next_eip)

          when C::CMD_LxS
            exec_lxs(opcode, prefix_count, op32, addr32, sz,
                     modregrm_mod, modregrm_reg, modregrm_rm,
                     bytes, memory, ds_base, ss_base, eip, next_eip)

          when C::CMD_NULL
            # Unknown opcode: raise #UD exception
            dispatch_interrupt(memory, C::EXCEPTION_UD, eip, :fault)

          else
            # NOP or unimplemented: just advance EIP
            advance_eip(next_eip)
            :ok
          end
          rescue SegmentFault
            dispatch_interrupt(memory, C::EXCEPTION_GP, eip, :fault)
          rescue PageFault => pf
            write_regfile(write_cr2: 1, cr2_to_reg: pf.linear_addr)
            dispatch_interrupt(memory, C::EXCEPTION_PF, eip, :fault)
          end
        end

        def find_opcode(bytes, consumed)
          prefix_count = 0
          has_0f = false
          while prefix_count < consumed
            b = bytes[prefix_count]
            case b
            when 0x66, 0x67, 0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65, 0xF0, 0xF2, 0xF3
              prefix_count += 1
            when 0x0F
              has_0f = true
              prefix_count += 1
              break
            else
              break
            end
          end
          opcode = bytes[prefix_count]
          [opcode, prefix_count, has_0f]
        end

        def advance_eip(next_eip)
          write_regfile(write_eip: 1, eip_to_reg: next_eip & 0xFFFF)
        end

        # ---------- Effective address ----------

        def compute_ea(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset, ds_base, ss_base)
          disp = extract_displacement(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset)
          sib_byte = (addr32 && modregrm_rm == 4 && modregrm_mod != 3) ? bytes[mrm_offset + 1] : 0

          @ea_calc.set_input(:modregrm_mod, modregrm_mod)
          @ea_calc.set_input(:modregrm_rm, modregrm_rm)
          @ea_calc.set_input(:address_32bit, addr32 ? 1 : 0)
          @ea_calc.set_input(:sib, sib_byte)
          @ea_calc.set_input(:displacement, disp)

          # Default segment: SS for BP/ESP-based, DS otherwise
          # We'll set DS first, then EA calc tells us if we need SS
          @ea_calc.set_input(:seg_base, 0)  # compute offset first
          GPR_NAMES.each_with_index { |n, i| @ea_calc.set_input(:"reg_#{n}", gpr(i)) }
          @ea_calc.propagate

          use_ss = @ea_calc.get_output(:use_ss) != 0
          offset = @ea_calc.get_output(:address)
          seg = use_ss ? ss_base : ds_base

          (seg + offset) & 0xFFFF_FFFF
        end

        def extract_displacement(mod, rm, addr32, bytes, mrm_offset)
          if addr32
            extract_disp_32(mod, rm, bytes, mrm_offset)
          else
            extract_disp_16(mod, rm, bytes, mrm_offset)
          end
        end

        def extract_disp_16(mod, rm, bytes, off)
          case mod
          when 0
            rm == 6 ? (bytes[off + 1] | (bytes[off + 2] << 8)) : 0
          when 1
            bytes[off + 1]
          when 2
            bytes[off + 1] | (bytes[off + 2] << 8)
          else
            0
          end
        end

        def extract_disp_32(mod, rm, bytes, off)
          has_sib = (rm == 4 && mod != 3)
          disp_off = off + 1 + (has_sib ? 1 : 0)

          case mod
          when 0
            if rm == 5
              bytes[off + 1] | (bytes[off + 2] << 8) | (bytes[off + 3] << 16) | (bytes[off + 4] << 24)
            elsif has_sib && (bytes[off + 1] & 7) == 5
              bytes[disp_off] | (bytes[disp_off + 1] << 8) | (bytes[disp_off + 2] << 16) | (bytes[disp_off + 3] << 24)
            else
              0
            end
          when 1
            bytes[disp_off]
          when 2
            bytes[disp_off] | (bytes[disp_off + 1] << 8) | (bytes[disp_off + 2] << 16) | (bytes[disp_off + 3] << 24)
          else
            0
          end
        end

        # Read value from ModR/M r/m field (register or memory)
        def read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base)
          if modregrm_mod == 3
            read_gpr(modregrm_rm, is_8bit, sz)
          else
            addr = compute_ea(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset, ds_base, ss_base)
            # Check segment limit in protected mode
            if reg(:cr0_pe) == 1
              use_ss = @ea_calc.get_output(:use_ss) != 0
              seg_name = use_ss ? :ss : :ds
              seg_base = use_ss ? ss_base : ds_base
              offset = (addr - seg_base) & 0xFFFF_FFFF
              cache = seg_cache(seg_name)
              raise SegmentFault unless check_segment_limit(cache, offset, sz)
            end
            mem_read(memory, addr, sz)
          end
        end

        # Write value to ModR/M r/m field (register or memory)
        def write_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, op32, sz, value, bytes, mrm_offset, memory, ds_base, ss_base)
          if modregrm_mod == 3
            write_gpr(modregrm_rm, value, is_8bit, op32)
          else
            addr = compute_ea(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset, ds_base, ss_base)
            if reg(:cr0_pe) == 1
              use_ss = @ea_calc.get_output(:use_ss) != 0
              seg_name = use_ss ? :ss : :ds
              seg_base = use_ss ? ss_base : ds_base
              offset = (addr - seg_base) & 0xFFFF_FFFF
              cache = seg_cache(seg_name)
              raise SegmentFault unless check_segment_limit(cache, offset, sz)
            end
            mem_write(memory, addr, value, sz)
          end
        end



        def read_gpr(index, is_8bit, sz)
          val = gpr(index & 7)
          if is_8bit
            # For 8-bit: index 0-3 = AL,CL,DL,BL, 4-7 = AH,CH,DH,BH
            if index < 4
              val & 0xFF
            else
              (gpr(index - 4) >> 8) & 0xFF
            end
          elsif sz == 2
            val & 0xFFFF
          else
            val & 0xFFFF_FFFF
          end
        end

        def write_gpr(index, value, is_8bit, op32)
          if is_8bit
            if index < 4
              write_regfile(write_regrm: 1, wr_dst_is_rm: 1,
                            wr_modregrm_rm: index, wr_is_8bit: 1, wr_operand_32bit: 0,
                            result: value & 0xFF)
            else
              # AH, CH, DH, BH: write to high byte
              real_index = index - 4
              old = gpr(real_index)
              new_val = (old & 0xFFFF_00FF) | ((value & 0xFF) << 8)
              write_regfile(write_regrm: 1, wr_dst_is_rm: 1,
                            wr_modregrm_rm: real_index, wr_operand_32bit: 1, wr_is_8bit: 0,
                            result: new_val)
            end
          else
            write_regfile(write_regrm: 1, wr_dst_is_rm: 1,
                          wr_modregrm_rm: index & 7, wr_operand_32bit: op32 ? 1 : 0, wr_is_8bit: 0,
                          result: value)
          end
        end

        def write_gpr_by_reg_field(index, value, is_8bit, op32)
          if is_8bit
            if index < 4
              write_regfile(write_regrm: 1, wr_dst_is_reg: 1,
                            wr_modregrm_reg: index, wr_is_8bit: 1, wr_operand_32bit: 0,
                            result: value & 0xFF)
            else
              real_index = index - 4
              old = gpr(real_index)
              new_val = (old & 0xFFFF_00FF) | ((value & 0xFF) << 8)
              write_regfile(write_regrm: 1, wr_dst_is_reg: 1,
                            wr_modregrm_reg: real_index, wr_operand_32bit: 1, wr_is_8bit: 0,
                            result: new_val)
            end
          else
            write_regfile(write_regrm: 1, wr_dst_is_reg: 1,
                          wr_modregrm_reg: index & 7, wr_operand_32bit: op32 ? 1 : 0, wr_is_8bit: 0,
                          result: value)
          end
        end

        # Extract immediate value after ModR/M
        def extract_imm(bytes, imm_offset, sz)
          case sz
          when 1 then bytes[imm_offset] || 0
          when 2 then (bytes[imm_offset] || 0) | ((bytes[imm_offset + 1] || 0) << 8)
          when 4 then (bytes[imm_offset] || 0) | ((bytes[imm_offset + 1] || 0) << 8) |
                      ((bytes[imm_offset + 2] || 0) << 16) | ((bytes[imm_offset + 3] || 0) << 24)
          else 0
          end
        end

        # Compute ModR/M byte length (including SIB and displacement)
        def modregrm_byte_len(mod, rm, addr32, bytes, mrm_offset)
          if addr32
            modregrm_len_32(mod, rm, bytes, mrm_offset)
          else
            modregrm_len_16(mod, rm)
          end
        end

        def modregrm_len_16(mod, rm)
          case mod
          when 0 then rm == 6 ? 3 : 1
          when 1 then 2
          when 2 then 3
          when 3 then 1
          end
        end

        def modregrm_len_32(mod, rm, bytes, mrm_offset)
          has_sib = (rm == 4 && mod != 3)
          sib_base = has_sib && (mrm_offset + 1) < bytes.length ? bytes[mrm_offset + 1] & 7 : 0

          case mod
          when 0
            if rm == 5 then 5
            elsif has_sib && sib_base == 5 then 6
            elsif has_sib then 2
            else 1
            end
          when 1 then has_sib ? 3 : 2
          when 2 then has_sib ? 6 : 5
          when 3 then 1
          end
        end

        # ---------- ALU helpers ----------

        def run_alu(arith_op, src, dst, size, cf_in: 0)
          @alu.set_input(:arith_index, arith_op)
          @alu.set_input(:src, src)
          @alu.set_input(:dst, dst)
          @alu.set_input(:operand_size, size * 8)
          @alu.set_input(:cflag_in, cf_in)
          @alu.propagate
          {
            result: @alu.get_output(:result),
            cf: @alu.get_output(:cflag), pf: @alu.get_output(:pflag),
            af: @alu.get_output(:aflag), zf: @alu.get_output(:zflag),
            sf: @alu.get_output(:sflag), of: @alu.get_output(:oflag)
          }
        end

        def write_flags_from_alu(alu_result)
          write_regfile(
            write_flags: 1,
            cflag_to_reg: alu_result[:cf], pflag_to_reg: alu_result[:pf],
            aflag_to_reg: alu_result[:af], zflag_to_reg: alu_result[:zf],
            sflag_to_reg: alu_result[:sf], oflag_to_reg: alu_result[:of],
            tflag_to_reg: reg(:tflag), iflag_to_reg: reg(:iflag),
            dflag_to_reg: reg(:dflag), iopl_to_reg: reg(:iopl),
            ntflag_to_reg: reg(:ntflag), vmflag_to_reg: reg(:vmflag),
            acflag_to_reg: reg(:acflag), idflag_to_reg: reg(:idflag),
            rflag_to_reg: reg(:rflag)
          )
        end

        # ---------- Stack helpers ----------

        def push_value(memory, value, sz, ss_base, op32)
          esp = reg(:esp)
          new_esp = if op32
                      (esp - sz) & 0xFFFF_FFFF
                    else
                      (esp & 0xFFFF_0000) | ((esp - sz) & 0xFFFF)
                    end
          addr = (ss_base + (op32 ? new_esp : (new_esp & 0xFFFF))) & 0xFFFF_FFFF
          mem_write(memory, addr, value, sz)
          # Write new ESP
          write_regfile(write_regrm: 1, wr_dst_is_rm: 1,
                        wr_modregrm_rm: 4,
                        wr_operand_32bit: op32 ? 1 : 0, wr_is_8bit: 0,
                        result: new_esp)
        end

        def pop_value(memory, sz, ss_base, op32)
          esp = reg(:esp)
          addr = (ss_base + (op32 ? esp : (esp & 0xFFFF))) & 0xFFFF_FFFF
          value = mem_read(memory, addr, sz)
          new_esp = if op32
                      (esp + sz) & 0xFFFF_FFFF
                    else
                      (esp & 0xFFFF_0000) | ((esp + sz) & 0xFFFF)
                    end
          write_regfile(write_regrm: 1, wr_dst_is_rm: 1,
                        wr_modregrm_rm: 4,
                        wr_operand_32bit: op32 ? 1 : 0, wr_is_8bit: 0,
                        result: new_esp)
          value
        end

        # ========== Instruction implementations ==========

        def exec_arith(cmd, opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                       modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                       eip, next_eip)
          arith_op = cmd - C::CMD_Arith
          mrm_offset = prefix_count + 1
          cf_in = reg(:cflag)

          # Determine operands based on opcode encoding
          raw_opcode = opcode
          if (raw_opcode & 0xC6) == 0x04
            # Accumulator, immediate: AL/AX/EAX, imm
            dst = read_gpr(0, is_8bit, sz) & mask
            src = extract_imm(bytes, prefix_count + 1, sz) & mask
            result = run_alu(arith_op, src, dst, sz, cf_in: cf_in)
            write_flags_from_alu(result)
            write_gpr(0, result[:result], is_8bit, op32) unless arith_op == C::ARITH_CMP
          elsif (raw_opcode & 0xC4) == 0x00 && (raw_opcode & 0x07) <= 3
            # ModR/M forms
            direction = (raw_opcode >> 1) & 1  # 0=dst is r/m, 1=dst is reg
            if direction == 0
              dst = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
              src = read_gpr(modregrm_reg, is_8bit, sz) & mask
              result = run_alu(arith_op, src, dst, sz, cf_in: cf_in)
              write_flags_from_alu(result)
              write_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, op32, sz, result[:result], bytes, mrm_offset, memory, ds_base, ss_base) unless arith_op == C::ARITH_CMP
            else
              src = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
              dst = read_gpr(modregrm_reg, is_8bit, sz) & mask
              result = run_alu(arith_op, src, dst, sz, cf_in: cf_in)
              write_flags_from_alu(result)
              write_gpr_by_reg_field(modregrm_reg, result[:result], is_8bit, op32) unless arith_op == C::ARITH_CMP
            end
          elsif raw_opcode >= 0x80 && raw_opcode <= 0x83
            # Immediate group
            mlen = modregrm_byte_len(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset)
            imm_offset = mrm_offset + mlen
            dst = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
            if raw_opcode == 0x83
              # Sign-extend imm8 to operand size
              src = sign_extend_8(bytes[imm_offset] || 0) & mask
            elsif is_8bit
              src = (bytes[imm_offset] || 0) & 0xFF
            else
              src = extract_imm(bytes, imm_offset, sz) & mask
            end
            result = run_alu(arith_op, src, dst, sz, cf_in: cf_in)
            write_flags_from_alu(result)
            write_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, op32, sz, result[:result], bytes, mrm_offset, memory, ds_base, ss_base) unless arith_op == C::ARITH_CMP
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_mov(opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)
          mrm_offset = prefix_count + 1

          case opcode
          when 0x88, 0x89  # MOV r/m, r
            src = read_gpr(modregrm_reg, is_8bit, sz)
            write_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, op32, sz, src, bytes, mrm_offset, memory, ds_base, ss_base)

          when 0x8A, 0x8B  # MOV r, r/m
            src = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base)
            write_gpr_by_reg_field(modregrm_reg, src, is_8bit, op32)

          when 0xA0  # MOV AL, moffs
            addr_sz = addr32 ? 4 : 2
            addr = extract_imm(bytes, prefix_count + 1, addr_sz)
            value = mem_read(memory, (ds_base + addr) & 0xFFFF_FFFF, 1)
            write_gpr(0, value, true, false)

          when 0xA1  # MOV AX/EAX, moffs
            addr_sz = addr32 ? 4 : 2
            addr = extract_imm(bytes, prefix_count + 1, addr_sz)
            value = mem_read(memory, (ds_base + addr) & 0xFFFF_FFFF, sz)
            write_gpr(0, value, false, op32)

          when 0xA2  # MOV moffs, AL
            addr_sz = addr32 ? 4 : 2
            addr = extract_imm(bytes, prefix_count + 1, addr_sz)
            value = read_gpr(0, true, 1)
            mem_write(memory, (ds_base + addr) & 0xFFFF_FFFF, value, 1)

          when 0xA3  # MOV moffs, AX/EAX
            addr_sz = addr32 ? 4 : 2
            addr = extract_imm(bytes, prefix_count + 1, addr_sz)
            value = read_gpr(0, false, sz)
            mem_write(memory, (ds_base + addr) & 0xFFFF_FFFF, value, sz)

          when 0xB0..0xB7  # MOV r8, imm8
            reg_idx = opcode - 0xB0
            imm = bytes[prefix_count + 1] || 0
            write_gpr(reg_idx, imm, true, false)

          when 0xB8..0xBF  # MOV r16/r32, imm
            reg_idx = opcode - 0xB8
            imm = extract_imm(bytes, prefix_count + 1, sz)
            write_gpr(reg_idx, imm, false, op32)

          when 0xC6  # MOV r/m8, imm8
            mlen = modregrm_byte_len(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset)
            imm = bytes[mrm_offset + mlen] || 0
            write_rm(modregrm_mod, modregrm_rm, addr32, true, false, 1, imm, bytes, mrm_offset, memory, ds_base, ss_base)

          when 0xC7  # MOV r/m16/32, imm
            mlen = modregrm_byte_len(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset)
            imm = extract_imm(bytes, mrm_offset + mlen, sz)
            write_rm(modregrm_mod, modregrm_rm, addr32, false, op32, sz, imm, bytes, mrm_offset, memory, ds_base, ss_base)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_inc_dec(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                         modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                         eip, next_eip)
          mrm_offset = prefix_count + 1
          saved_cf = reg(:cflag)  # INC/DEC preserve CF

          if opcode >= 0x40 && opcode <= 0x47
            # INC r16/r32
            reg_idx = opcode - 0x40
            val = read_gpr(reg_idx, false, sz) & mask
            result = run_alu(C::ARITH_ADD, 1, val, sz)
            write_gpr(reg_idx, result[:result], false, op32)
          elsif opcode >= 0x48 && opcode <= 0x4F
            # DEC r16/r32
            reg_idx = opcode - 0x48
            val = read_gpr(reg_idx, false, sz) & mask
            result = run_alu(C::ARITH_SUB, 1, val, sz)
            write_gpr(reg_idx, result[:result], false, op32)
          elsif opcode == 0xFE || opcode == 0xFF
            val = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
            if modregrm_reg == 0  # INC
              result = run_alu(C::ARITH_ADD, 1, val, sz)
            else  # DEC
              result = run_alu(C::ARITH_SUB, 1, val, sz)
            end
            write_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, op32, sz, result[:result], bytes, mrm_offset, memory, ds_base, ss_base)
          end

          # Write flags but preserve CF
          write_regfile(
            write_flags: 1,
            cflag_to_reg: saved_cf, pflag_to_reg: result[:pf],
            aflag_to_reg: result[:af], zflag_to_reg: result[:zf],
            sflag_to_reg: result[:sf], oflag_to_reg: result[:of],
            tflag_to_reg: reg(:tflag), iflag_to_reg: reg(:iflag),
            dflag_to_reg: reg(:dflag), iopl_to_reg: reg(:iopl),
            ntflag_to_reg: reg(:ntflag), vmflag_to_reg: reg(:vmflag),
            acflag_to_reg: reg(:acflag), idflag_to_reg: reg(:idflag),
            rflag_to_reg: reg(:rflag)
          )

          advance_eip(next_eip)
          :ok
        end

        def exec_push(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ss_base,
                      eip, next_eip)
          push_sz = op32 ? 4 : 2

          case opcode
          when 0x50..0x57
            reg_idx = opcode - 0x50
            value = read_gpr(reg_idx, false, push_sz)
            push_value(memory, value, push_sz, ss_base, op32)

          when 0x68  # PUSH imm16/32
            imm = extract_imm(bytes, prefix_count + 1, push_sz)
            push_value(memory, imm, push_sz, ss_base, op32)

          when 0x6A  # PUSH imm8 (sign-extended)
            imm = sign_extend_8(bytes[prefix_count + 1] || 0)
            push_value(memory, imm & size_mask(push_sz), push_sz, ss_base, op32)

          when 0xFF  # PUSH r/m (reg_field = 6)
            mrm_offset = prefix_count + 1
            value = read_rm(modregrm_mod, modregrm_rm, addr32, false, push_sz, bytes, mrm_offset, memory, 0, ss_base)
            push_value(memory, value, push_sz, ss_base, op32)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_pop(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)
          pop_sz = op32 ? 4 : 2

          case opcode
          when 0x58..0x5F
            reg_idx = opcode - 0x58
            value = pop_value(memory, pop_sz, ss_base, op32)
            write_gpr(reg_idx, value, false, op32)
          when 0x8F  # POP r/m16/32
            value = pop_value(memory, pop_sz, ss_base, op32)
            mrm_offset = prefix_count + 1
            if modregrm_mod == 3
              write_gpr(modregrm_rm, value, false, op32)
            else
              addr = compute_ea(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset, ds_base, ss_base)
              mem_write(memory, addr, value, pop_sz)
            end
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_jmp(opcode, prefix_count, has_0f, op32, bytes, memory, ds_base, ss_base, eip, next_eip)
          case opcode
          when 0xEB  # JMP short
            offset = sign_extend_8(bytes[prefix_count + 1] || 0)
            target = (next_eip + offset) & 0xFFFF
            advance_eip(target)

          when 0xE9  # JMP near
            if op32
              offset = extract_imm(bytes, prefix_count + 1, 4)
              offset = offset & 0xFFFF_FFFF
              offset = offset >= 0x8000_0000 ? offset - 0x1_0000_0000 : offset
              target = (next_eip + offset) & 0xFFFF_FFFF
            else
              offset = extract_imm(bytes, prefix_count + 1, 2)
              offset = sign_extend_16(offset)
              target = (next_eip + offset) & 0xFFFF
            end
            advance_eip(target)

          when 0xEA  # JMP far (ptr16:16 or ptr16:32)
            off_sz = op32 ? 4 : 2
            target_offset = extract_imm(bytes, prefix_count + 1, off_sz)
            target_selector = extract_imm(bytes, prefix_count + 1 + off_sz, 2)
            exec_far_jmp(target_selector, target_offset, op32, memory)

          when 0xFF  # JMP indirect near (/4) or JMP far indirect (/5)
            mrm_offset = prefix_count + 1
            mrm = bytes[mrm_offset]
            reg_field = (mrm >> 3) & 7
            modregrm_mod = (mrm >> 6) & 3
            modregrm_rm = mrm & 7

            if reg_field == 4  # JMP near indirect
              if modregrm_mod == 3
                target = read_gpr(modregrm_rm, false, op32 ? 4 : 2) & (op32 ? 0xFFFF_FFFF : 0xFFFF)
              else
                addr = compute_ea(modregrm_mod, modregrm_rm, false, bytes, mrm_offset, ds_base, ss_base)
                target = mem_read(memory, addr, op32 ? 4 : 2) & (op32 ? 0xFFFF_FFFF : 0xFFFF)
              end
              advance_eip(target)

            elsif reg_field == 5  # JMP far indirect (m16:16 or m16:32)
              addr = compute_ea(modregrm_mod, modregrm_rm, false, bytes, mrm_offset, ds_base, ss_base)
              off_sz = op32 ? 4 : 2
              target_offset = mem_read(memory, addr, off_sz)
              target_selector = mem_read(memory, addr + off_sz, 2)
              exec_far_jmp(target_selector, target_offset, op32, memory)
            end
          end

          :ok
        end

        def exec_jcc(opcode, prefix_count, has_0f, op32, addr32, bytes, eip, next_eip)
          # Condition code is low nibble of opcode
          cc = opcode & 0x0F

          @cond_eval.set_input(:condition_index, cc)
          @cond_eval.set_input(:oflag, reg(:oflag))
          @cond_eval.set_input(:cflag, reg(:cflag))
          @cond_eval.set_input(:zflag, reg(:zflag))
          @cond_eval.set_input(:sflag, reg(:sflag))
          @cond_eval.set_input(:pflag, reg(:pflag))
          @cond_eval.propagate

          if @cond_eval.get_output(:condition_met) != 0
            if has_0f
              # Jcc near (0x0F 0x8x)
              if op32
                offset = extract_imm(bytes, prefix_count + 1, 4)
                offset = offset >= 0x8000_0000 ? offset - 0x1_0000_0000 : offset
                target = (next_eip + offset) & 0xFFFF_FFFF
              else
                offset = extract_imm(bytes, prefix_count + 1, 2)
                offset = sign_extend_16(offset)
                target = (next_eip + offset) & 0xFFFF
              end
            else
              # Jcc short (0x7x)
              offset = sign_extend_8(bytes[prefix_count + 1] || 0)
              target = (next_eip + offset) & 0xFFFF
            end
            advance_eip(target)
          else
            advance_eip(next_eip)
          end

          :ok
        end

        def exec_call(opcode, prefix_count, has_0f, op32, bytes, memory, ds_base, ss_base, eip, next_eip)
          push_sz = op32 ? 4 : 2
          mrm_offset = prefix_count + 1

          case opcode
          when 0xE8  # CALL near relative
            push_value(memory, next_eip, push_sz, ss_base, op32)
            if op32
              offset = extract_imm(bytes, prefix_count + 1, 4)
              offset = offset >= 0x8000_0000 ? offset - 0x1_0000_0000 : offset
              target = (next_eip + offset) & 0xFFFF_FFFF
            else
              offset = extract_imm(bytes, prefix_count + 1, 2)
              offset = sign_extend_16(offset)
              target = (next_eip + offset) & 0xFFFF
            end
            advance_eip(target)

          when 0xFF  # CALL indirect near (FF /2) or CALL indirect far (FF /3)
            mrm = bytes[mrm_offset]
            reg_field = (mrm >> 3) & 7
            modregrm_mod = (mrm >> 6) & 3
            modregrm_rm = mrm & 7

            if reg_field == 2  # CALL near indirect
              if modregrm_mod == 3
                target = read_gpr(modregrm_rm, false, op32 ? 4 : 2) & (op32 ? 0xFFFF_FFFF : 0xFFFF)
              else
                addr = compute_ea(modregrm_mod, modregrm_rm, false, bytes, mrm_offset, ds_base, ss_base)
                target = mem_read(memory, addr, op32 ? 4 : 2) & (op32 ? 0xFFFF_FFFF : 0xFFFF)
              end
              push_value(memory, next_eip, push_sz, ss_base, op32)
              advance_eip(target)

            elsif reg_field == 3  # CALL far indirect (m16:16 or m16:32)
              addr = compute_ea(modregrm_mod, modregrm_rm, false, bytes, mrm_offset, ds_base, ss_base)
              off_sz = op32 ? 4 : 2
              target_offset = mem_read(memory, addr, off_sz)
              target_selector = mem_read(memory, addr + off_sz, 2)
              # Push CS:IP (far return address)
              push_value(memory, reg(:cs) & 0xFFFF, push_sz, ss_base, op32)
              push_value(memory, next_eip, push_sz, ss_base, op32)
              exec_far_jmp(target_selector, target_offset, op32, memory)
            end

          when 0x9A  # CALL far direct (ptr16:16 or ptr16:32)
            off_sz = op32 ? 4 : 2
            target_offset = extract_imm(bytes, prefix_count + 1, off_sz)
            target_selector = extract_imm(bytes, prefix_count + 1 + off_sz, 2)
            # Push CS:IP (far return address)
            push_value(memory, reg(:cs) & 0xFFFF, push_sz, ss_base, op32)
            push_value(memory, next_eip, push_sz, ss_base, op32)
            exec_far_jmp(target_selector, target_offset, op32, memory)
          end

          :ok
        end

        def exec_ret_near(opcode, prefix_count, op32, bytes, memory, ss_base, eip, next_eip)
          pop_sz = op32 ? 4 : 2
          return_addr = pop_value(memory, pop_sz, ss_base, op32)
          advance_eip(return_addr & (op32 ? 0xFFFF_FFFF : 0xFFFF))

          # RET imm16 (0xC2): adjust ESP by imm16 after popping return address
          if opcode == 0xC2
            imm16 = extract_imm(bytes, prefix_count + 1, 2)
            sp = reg(:esp)
            if op32
              write_gpr(4, (sp + imm16) & 0xFFFF_FFFF, false, true)
            else
              write_gpr(4, (sp + imm16) & 0xFFFF, false, false)
            end
          end

          :ok
        end

        def exec_ret_far(opcode, prefix_count, op32, bytes, memory, ss_base, eip, next_eip)
          pop_sz = op32 ? 4 : 2
          return_ip = pop_value(memory, pop_sz, ss_base, op32)
          return_cs = pop_value(memory, pop_sz, ss_base, op32) & 0xFFFF

          # Restore CS (real mode: base = selector << 4)
          new_cs_base = (return_cs & 0xFFFF) << 4
          cache = C::DEFAULT_CS_CACHE
          base_hi = (new_cs_base >> 24) & 0xFF
          base_lo = new_cs_base & 0xFF_FFFF
          cache = cache & ~(0xFF << 56) & ~(0xFF_FFFF << 16)
          cache = cache | (base_hi << 56) | (base_lo << 16)
          write_regfile(write_seg: 1, wr_seg_index: C::SEGMENT_CS, seg_to_reg: return_cs,
                        write_seg_cache: 1, seg_cache_to_reg: cache,
                        write_seg_valid: 1, seg_valid_to_reg: 1)
          advance_eip(return_ip & (op32 ? 0xFFFF_FFFF : 0xFFFF))

          # RETF imm16 (0xCA)
          if opcode == 0xCA
            imm16 = extract_imm(bytes, prefix_count + 1, 2)
            sp = reg(:esp)
            if op32
              write_gpr(4, (sp + imm16) & 0xFFFF_FFFF, false, true)
            else
              write_gpr(4, (sp + imm16) & 0xFFFF, false, false)
            end
          end

          :ok
        end

        def exec_push_mov_seg(opcode, prefix_count, op32, addr32, sz,
                              modregrm_mod, modregrm_reg, modregrm_rm,
                              bytes, memory, ds_base, ss_base, eip, next_eip)
          push_sz = op32 ? 4 : 2

          case opcode
          when 0x06  # PUSH ES
            push_value(memory, reg(:es) & 0xFFFF, push_sz, ss_base, op32)
          when 0x0E  # PUSH CS
            push_value(memory, reg(:cs) & 0xFFFF, push_sz, ss_base, op32)
          when 0x16  # PUSH SS
            push_value(memory, reg(:ss) & 0xFFFF, push_sz, ss_base, op32)
          when 0x1E  # PUSH DS
            push_value(memory, reg(:ds) & 0xFFFF, push_sz, ss_base, op32)
          when 0x8C  # MOV r/m16, Sreg
            # reg field selects segment: 0=ES, 1=CS, 2=SS, 3=DS, 4=FS, 5=GS
            seg_names = [:es, :cs, :ss, :ds, :fs, :gs]
            seg_val = modregrm_reg < seg_names.length ? reg(seg_names[modregrm_reg]) & 0xFFFF : 0
            mrm_offset = prefix_count + 1
            if modregrm_mod == 3
              write_gpr(modregrm_rm, seg_val, false, false)
            else
              addr = compute_ea(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset, ds_base, ss_base)
              mem_write(memory, addr, seg_val, 2)
            end
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_pop_seg(opcode, prefix_count, op32, memory, ss_base, eip, next_eip)
          pop_sz = op32 ? 4 : 2
          selector = pop_value(memory, pop_sz, ss_base, op32) & 0xFFFF

          # Determine which segment to load
          seg_index, seg_name = case opcode
                                when 0x07 then [C::SEGMENT_ES, :es]
                                when 0x17 then [C::SEGMENT_SS, :ss]
                                when 0x1F then [C::SEGMENT_DS, :ds]
                                end

          if reg(:cr0_pe) == 1
            load_segment_protected(seg_index, selector, memory, eip)
          else
            # Real mode: base = selector << 4
            new_base = (selector & 0xFFFF) << 4
            cache = seg_cache(seg_name)
            cache = cache & ~(0xFF << 56) & ~(0xFF_FFFF << 16)
            base_hi = (new_base >> 24) & 0xFF
            base_lo = new_base & 0xFF_FFFF
            cache = cache | (base_hi << 56) | (base_lo << 16)
            write_regfile(write_seg: 1, wr_seg_index: seg_index, seg_to_reg: selector,
                          write_seg_cache: 1, seg_cache_to_reg: cache,
                          write_seg_valid: 1, seg_valid_to_reg: 1)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_lxs(opcode, prefix_count, op32, addr32, sz,
                     modregrm_mod, modregrm_reg, modregrm_rm,
                     bytes, memory, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1
          # LES/LDS load a far pointer (offset:segment) from memory into reg:seg
          addr = compute_ea(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset, ds_base, ss_base)
          off_sz = op32 ? 4 : 2
          offset_val = mem_read(memory, addr, off_sz)
          selector = mem_read(memory, addr + off_sz, 2) & 0xFFFF

          # Write offset to destination register
          write_gpr_by_reg_field(modregrm_reg, offset_val, false, op32)

          # Determine segment
          seg_index, seg_name = case opcode
                                when 0xC4 then [C::SEGMENT_ES, :es]  # LES
                                when 0xC5 then [C::SEGMENT_DS, :ds]  # LDS
                                end

          if reg(:cr0_pe) == 1
            load_segment_protected(seg_index, selector, memory, eip)
          else
            # Real mode: base = selector << 4
            new_base = (selector & 0xFFFF) << 4
            cache = seg_cache(seg_name)
            cache = cache & ~(0xFF << 56) & ~(0xFF_FFFF << 16)
            base_hi = (new_base >> 24) & 0xFF
            base_lo = new_base & 0xFF_FFFF
            cache = cache | (base_hi << 56) | (base_lo << 16)
            write_regfile(write_seg: 1, wr_seg_index: seg_index, seg_to_reg: selector,
                          write_seg_cache: 1, seg_cache_to_reg: cache,
                          write_seg_valid: 1, seg_valid_to_reg: 1)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_lea(opcode, prefix_count, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)
          mrm_offset = prefix_count + 1
          # LEA computes the effective address but doesn't add segment base
          @ea_calc.set_input(:modregrm_mod, modregrm_mod)
          @ea_calc.set_input(:modregrm_rm, modregrm_rm)
          @ea_calc.set_input(:address_32bit, addr32 ? 1 : 0)
          @ea_calc.set_input(:sib, (addr32 && modregrm_rm == 4 && modregrm_mod != 3) ? bytes[mrm_offset + 1] : 0)
          @ea_calc.set_input(:displacement, extract_displacement(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset))
          @ea_calc.set_input(:seg_base, 0)  # No segment for LEA
          GPR_NAMES.each_with_index { |n, i| @ea_calc.set_input(:"reg_#{n}", gpr(i)) }
          @ea_calc.propagate

          ea = @ea_calc.get_output(:address)
          write_gpr_by_reg_field(modregrm_reg, ea, false, op32)
          advance_eip(next_eip)
          :ok
        end

        def exec_test(opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                      eip, next_eip)
          mrm_offset = prefix_count + 1

          case opcode
          when 0x84, 0x85  # TEST r/m, r
            val1 = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base)
            val2 = read_gpr(modregrm_reg, is_8bit, sz)
            result = run_alu(C::ARITH_AND, val1, val2, sz)
            write_flags_from_alu(result)

          when 0xA8  # TEST AL, imm8
            val1 = read_gpr(0, true, 1)
            val2 = bytes[prefix_count + 1] || 0
            result = run_alu(C::ARITH_AND, val1, val2, 1)
            write_flags_from_alu(result)

          when 0xA9  # TEST AX/EAX, imm
            val1 = read_gpr(0, false, sz)
            val2 = extract_imm(bytes, prefix_count + 1, sz)
            result = run_alu(C::ARITH_AND, val1, val2, sz)
            write_flags_from_alu(result)

          when 0xF6, 0xF7  # TEST r/m, imm (F6/F7 /0)
            val1 = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base)
            imm_offset = mrm_offset + modregrm_byte_len(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset)
            val2 = extract_imm(bytes, imm_offset, sz) & mask
            result = run_alu(C::ARITH_AND, val1, val2, sz)
            write_flags_from_alu(result)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_xchg(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                      eip, next_eip)
          if opcode >= 0x90 && opcode <= 0x97
            reg_idx = opcode - 0x90
            if reg_idx == 0
              # NOP (XCHG EAX, EAX)
            else
              val_eax = read_gpr(0, false, sz)
              val_reg = read_gpr(reg_idx, false, sz)
              write_gpr(0, val_reg, false, op32)
              write_gpr(reg_idx, val_eax, false, op32)
            end
          elsif opcode == 0x86 || opcode == 0x87
            # XCHG r, r/m (ModR/M form)
            mrm_offset = prefix_count + 1
            val_reg = read_gpr(modregrm_reg, is_8bit, sz)
            val_rm = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz,
                             bytes, mrm_offset, memory, ds_base, ss_base)
            write_gpr_by_reg_field(modregrm_reg, val_rm, is_8bit, op32)
            write_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, op32, sz, val_reg,
                     bytes, mrm_offset, memory, ds_base, ss_base)
          end
          advance_eip(next_eip)
          :ok
        end

        def exec_shift(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                       modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                       eip, next_eip)
          mrm_offset = prefix_count + 1
          val = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask

          # Determine shift count
          count = case opcode
                  when 0xC0, 0xC1  # shift r/m, imm8
                    mlen = modregrm_byte_len(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset)
                    bytes[mrm_offset + mlen] || 0
                  when 0xD0, 0xD1  # shift r/m, 1
                    1
                  when 0xD2, 0xD3  # shift r/m, CL
                    gpr(1) & 0x1F  # CL
                  else
                    0
                  end

          @shift.set_input(:shift_op, modregrm_reg)
          @shift.set_input(:value, val)
          @shift.set_input(:count, count & 0x1F)
          @shift.set_input(:operand_size, sz * 8)
          @shift.set_input(:cflag_in, reg(:cflag))
          @shift.propagate

          result = @shift.get_output(:result) & mask
          write_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, op32, sz, result, bytes, mrm_offset, memory, ds_base, ss_base)

          # Update flags (CF and OF from shift, compute SF/ZF/PF)
          cf = @shift.get_output(:cflag)
          of = @shift.get_output(:oflag)
          msb_pos = sz * 8 - 1
          sf = (result >> msb_pos) & 1
          zf = (result & mask) == 0 ? 1 : 0
          pf = ((0..7).count { |i| (result >> i) & 1 == 1 }).even? ? 1 : 0

          if (count & 0x1F) != 0
            write_regfile(
              write_flags: 1,
              cflag_to_reg: cf, pflag_to_reg: pf,
              aflag_to_reg: reg(:aflag), zflag_to_reg: zf,
              sflag_to_reg: sf, oflag_to_reg: of,
              tflag_to_reg: reg(:tflag), iflag_to_reg: reg(:iflag),
              dflag_to_reg: reg(:dflag), iopl_to_reg: reg(:iopl),
              ntflag_to_reg: reg(:ntflag), vmflag_to_reg: reg(:vmflag),
              acflag_to_reg: reg(:acflag), idflag_to_reg: reg(:idflag),
              rflag_to_reg: reg(:rflag)
            )
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_neg(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)
          mrm_offset = prefix_count + 1
          val = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
          result = run_alu(C::ARITH_SUB, val, 0, sz)
          write_flags_from_alu(result)
          write_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, op32, sz, result[:result], bytes, mrm_offset, memory, ds_base, ss_base)
          advance_eip(next_eip)
          :ok
        end

        def exec_not(opcode, prefix_count, is_8bit, op32, addr32, sz, mask,
                     modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                     eip, next_eip)
          mrm_offset = prefix_count + 1
          val = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
          result = (~val) & mask
          write_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, op32, sz, result, bytes, mrm_offset, memory, ds_base, ss_base)
          advance_eip(next_eip)
          :ok
        end

        def exec_pushf(op32, memory, ss_base, eip, next_eip)
          flags = build_eflags
          push_sz = op32 ? 4 : 2
          push_value(memory, flags & size_mask(push_sz), push_sz, ss_base, op32)
          advance_eip(next_eip)
          :ok
        end

        def exec_popf(op32, memory, ss_base, eip, next_eip)
          pop_sz = op32 ? 4 : 2
          flags = pop_value(memory, pop_sz, ss_base, op32)
          load_eflags(flags, op32)
          advance_eip(next_eip)
          :ok
        end

        def build_eflags
          reg(:cflag) |
            (1 << 1) |
            (reg(:pflag) << 2) |
            (reg(:aflag) << 4) |
            (reg(:zflag) << 6) |
            (reg(:sflag) << 7) |
            (reg(:tflag) << 8) |
            (reg(:iflag) << 9) |
            (reg(:dflag) << 10) |
            (reg(:iopl) << 12) |
            (reg(:ntflag) << 14) |
            (reg(:rflag) << 16) |
            (reg(:vmflag) << 17) |
            (reg(:acflag) << 18) |
            (reg(:idflag) << 21)
        end

        def load_eflags(val, op32)
          write_regfile(
            write_flags: 1,
            cflag_to_reg: val & 1,
            pflag_to_reg: (val >> 2) & 1,
            aflag_to_reg: (val >> 4) & 1,
            zflag_to_reg: (val >> 6) & 1,
            sflag_to_reg: (val >> 7) & 1,
            tflag_to_reg: (val >> 8) & 1,
            iflag_to_reg: (val >> 9) & 1,
            dflag_to_reg: (val >> 10) & 1,
            iopl_to_reg: (val >> 12) & 3,
            ntflag_to_reg: (val >> 14) & 1,
            vmflag_to_reg: op32 ? ((val >> 17) & 1) : reg(:vmflag),
            acflag_to_reg: op32 ? ((val >> 18) & 1) : reg(:acflag),
            idflag_to_reg: op32 ? ((val >> 21) & 1) : reg(:idflag),
            rflag_to_reg: op32 ? ((val >> 16) & 1) : reg(:rflag),
            oflag_to_reg: (val >> 11) & 1
          )
        end

        def exec_sahf(eip, next_eip)
          ah = (gpr(0) >> 8) & 0xFF
          write_regfile(
            write_flags: 1,
            cflag_to_reg: ah & 1,
            pflag_to_reg: (ah >> 2) & 1,
            aflag_to_reg: (ah >> 4) & 1,
            zflag_to_reg: (ah >> 6) & 1,
            sflag_to_reg: (ah >> 7) & 1,
            oflag_to_reg: reg(:oflag),
            tflag_to_reg: reg(:tflag), iflag_to_reg: reg(:iflag),
            dflag_to_reg: reg(:dflag), iopl_to_reg: reg(:iopl),
            ntflag_to_reg: reg(:ntflag), vmflag_to_reg: reg(:vmflag),
            acflag_to_reg: reg(:acflag), idflag_to_reg: reg(:idflag),
            rflag_to_reg: reg(:rflag)
          )
          advance_eip(next_eip)
          :ok
        end

        def exec_lahf(eip, next_eip)
          ah = reg(:sflag) << 7 | reg(:zflag) << 6 | reg(:aflag) << 4 |
               reg(:pflag) << 2 | 0x02 | reg(:cflag)
          old_eax = gpr(0)
          new_eax = (old_eax & 0xFFFF_00FF) | ((ah & 0xFF) << 8)
          write_regfile(write_regrm: 1, wr_dst_is_rm: 1,
                        wr_modregrm_rm: 0, wr_operand_32bit: 1, wr_is_8bit: 0,
                        result: new_eax)
          advance_eip(next_eip)
          :ok
        end

        def exec_cbw(op32, eip, next_eip)
          if op32
            # CWDE: sign-extend AX to EAX
            ax = gpr(0) & 0xFFFF
            eax = (ax & 0x8000) != 0 ? ax | 0xFFFF_0000 : ax
            write_gpr(0, eax, false, true)
          else
            # CBW: sign-extend AL to AX
            al = gpr(0) & 0xFF
            ax = (al & 0x80) != 0 ? al | 0xFF00 : al
            write_gpr(0, ax, false, false)
          end
          advance_eip(next_eip)
          :ok
        end

        def exec_cwd(op32, eip, next_eip)
          if op32
            # CDQ: sign-extend EAX to EDX:EAX
            eax = gpr(0)
            edx = (eax & 0x8000_0000) != 0 ? 0xFFFF_FFFF : 0
            write_gpr(2, edx, false, true)
          else
            # CWD: sign-extend AX to DX:AX
            ax = gpr(0) & 0xFFFF
            dx = (ax & 0x8000) != 0 ? 0xFFFF : 0
            write_gpr(2, dx, false, false)
          end
          advance_eip(next_eip)
          :ok
        end

        def exec_mul(is_8bit, op32, addr32, sz, mask, modregrm_mod, modregrm_reg, modregrm_rm,
                     bytes, memory, ds_base, ss_base, prefix_count, eip, next_eip)
          mrm_offset = prefix_count + 1
          src = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
          dst = read_gpr(0, is_8bit, sz) & mask

          @multiply.set_input(:src, src)
          @multiply.set_input(:dst, dst)
          @multiply.set_input(:operand_size, sz * 8)
          @multiply.set_input(:is_signed, 0)
          @multiply.propagate

          lo = @multiply.get_output(:result_lo)
          hi = @multiply.get_output(:result_hi)
          of = @multiply.get_output(:overflow)

          case sz
          when 1  # AX = AL * src
            write_gpr(0, (hi << 8) | (lo & 0xFF), false, false)
          when 2  # DX:AX = AX * src
            write_gpr(0, lo & 0xFFFF, false, false)
            write_gpr(2, hi & 0xFFFF, false, false)
          else    # EDX:EAX = EAX * src
            write_gpr(0, lo, false, true)
            write_gpr(2, hi, false, true)
          end

          write_regfile(
            write_flags: 1,
            cflag_to_reg: of, oflag_to_reg: of,
            pflag_to_reg: reg(:pflag), aflag_to_reg: reg(:aflag),
            zflag_to_reg: reg(:zflag), sflag_to_reg: reg(:sflag),
            tflag_to_reg: reg(:tflag), iflag_to_reg: reg(:iflag),
            dflag_to_reg: reg(:dflag), iopl_to_reg: reg(:iopl),
            ntflag_to_reg: reg(:ntflag), vmflag_to_reg: reg(:vmflag),
            acflag_to_reg: reg(:acflag), idflag_to_reg: reg(:idflag),
            rflag_to_reg: reg(:rflag)
          )

          advance_eip(next_eip)
          :ok
        end

        def exec_imul(opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm, bytes, memory, ds_base, ss_base,
                      eip, next_eip)
          mrm_offset = prefix_count + 1

          if opcode == 0xF7 || opcode == 0xF6
            # One-operand IMUL: same as MUL but signed
            src = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
            dst = read_gpr(0, is_8bit, sz) & mask

            @multiply.set_input(:src, src)
            @multiply.set_input(:dst, dst)
            @multiply.set_input(:operand_size, sz * 8)
            @multiply.set_input(:is_signed, 1)
            @multiply.propagate

            lo = @multiply.get_output(:result_lo)
            hi = @multiply.get_output(:result_hi)
            of = @multiply.get_output(:overflow)

            case sz
            when 1
              write_gpr(0, (hi << 8) | (lo & 0xFF), false, false)
            when 2
              write_gpr(0, lo & 0xFFFF, false, false)
              write_gpr(2, hi & 0xFFFF, false, false)
            else
              write_gpr(0, lo, false, true)
              write_gpr(2, hi, false, true)
            end

            write_imul_flags(of)

          elsif has_0f && opcode == 0xAF
            # Two-operand IMUL r, r/m (0x0F AF)
            src = read_rm(modregrm_mod, modregrm_rm, addr32, false, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
            dst = read_gpr(modregrm_reg, false, sz) & mask

            @multiply.set_input(:src, src)
            @multiply.set_input(:dst, dst)
            @multiply.set_input(:operand_size, sz * 8)
            @multiply.set_input(:is_signed, 1)
            @multiply.propagate

            lo = @multiply.get_output(:result_lo) & mask
            of = @multiply.get_output(:overflow)

            write_gpr_by_reg_field(modregrm_reg, lo, false, op32)
            write_imul_flags(of)

          elsif opcode == 0x69 || opcode == 0x6B
            # Three-operand IMUL r, r/m, imm
            src = read_rm(modregrm_mod, modregrm_rm, addr32, false, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
            mlen = modregrm_byte_len(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset)
            imm_offset = mrm_offset + mlen

            if opcode == 0x6B
              # imm8 sign-extended to operand size
              imm = sign_extend_8(bytes[imm_offset] || 0) & mask
            else
              # imm16/32
              imm = extract_imm(bytes, imm_offset, sz) & mask
            end

            @multiply.set_input(:src, src)
            @multiply.set_input(:dst, imm)
            @multiply.set_input(:operand_size, sz * 8)
            @multiply.set_input(:is_signed, 1)
            @multiply.propagate

            lo = @multiply.get_output(:result_lo) & mask
            of = @multiply.get_output(:overflow)

            write_gpr_by_reg_field(modregrm_reg, lo, false, op32)
            write_imul_flags(of)
          end

          advance_eip(next_eip)
          :ok
        end

        def write_imul_flags(of)
          write_regfile(
            write_flags: 1,
            cflag_to_reg: of, oflag_to_reg: of,
            pflag_to_reg: reg(:pflag), aflag_to_reg: reg(:aflag),
            zflag_to_reg: reg(:zflag), sflag_to_reg: reg(:sflag),
            tflag_to_reg: reg(:tflag), iflag_to_reg: reg(:iflag),
            dflag_to_reg: reg(:dflag), iopl_to_reg: reg(:iopl),
            ntflag_to_reg: reg(:ntflag), vmflag_to_reg: reg(:vmflag),
            acflag_to_reg: reg(:acflag), idflag_to_reg: reg(:idflag),
            rflag_to_reg: reg(:rflag)
          )
        end

        def exec_div(is_signed, is_8bit, op32, addr32, sz, mask, modregrm_mod, modregrm_reg, modregrm_rm,
                     bytes, memory, ds_base, ss_base, prefix_count, eip, next_eip)
          mrm_offset = prefix_count + 1
          denom = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask

          numer = case sz
                  when 1 then gpr(0) & 0xFFFF          # AX
                  when 2 then (gpr(2) << 16) | (gpr(0) & 0xFFFF)  # DX:AX
                  else (gpr(2) << 32) | gpr(0)          # EDX:EAX
                  end

          @divide.set_input(:numer, numer)
          @divide.set_input(:denom, denom)
          @divide.set_input(:operand_size, sz * 8)
          @divide.set_input(:is_signed, is_signed ? 1 : 0)
          @divide.propagate

          if @divide.get_output(:exception) != 0
            # #DE exception — dispatch through IVT (fault: save faulting EIP)
            return dispatch_interrupt(memory, C::EXCEPTION_DE, eip, :fault)
          end

          quot = @divide.get_output(:quotient)
          rem = @divide.get_output(:remainder)

          case sz
          when 1  # AL=quotient, AH=remainder
            old_eax = gpr(0)
            new_eax = (old_eax & 0xFFFF_0000) | ((rem & 0xFF) << 8) | (quot & 0xFF)
            write_gpr(0, new_eax, false, true)
          when 2  # AX=quotient, DX=remainder
            write_gpr(0, quot & 0xFFFF, false, false)
            write_gpr(2, rem & 0xFFFF, false, false)
          else    # EAX=quotient, EDX=remainder
            write_gpr(0, quot, false, true)
            write_gpr(2, rem, false, true)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_movzx(opcode, prefix_count, is_8bit, op32, addr32, modregrm_mod, modregrm_reg, modregrm_rm,
                       bytes, memory, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1
          src_sz = is_8bit ? 1 : 2
          src = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, src_sz, bytes, mrm_offset, memory, ds_base, ss_base)
          src = src & size_mask(src_sz)
          write_gpr_by_reg_field(modregrm_reg, src, false, op32)
          advance_eip(next_eip)
          :ok
        end

        def exec_movsx(opcode, prefix_count, is_8bit, op32, addr32, modregrm_mod, modregrm_reg, modregrm_rm,
                       bytes, memory, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1
          src_sz = is_8bit ? 1 : 2
          src = read_rm(modregrm_mod, modregrm_rm, addr32, is_8bit, src_sz, bytes, mrm_offset, memory, ds_base, ss_base)
          # Sign-extend
          if src_sz == 1
            src = sign_extend_8(src)
          else
            src = sign_extend_16(src)
          end
          dst_mask = op32 ? 0xFFFF_FFFF : 0xFFFF
          write_gpr_by_reg_field(modregrm_reg, src & dst_mask, false, op32)
          advance_eip(next_eip)
          :ok
        end

        # ---------- Phase 6: Microcode & Complex Instructions ----------

        def string_op?(cmd)
          [C::CMD_MOVS, C::CMD_STOS, C::CMD_LODS, C::CMD_CMPS, C::CMD_SCAS].include?(cmd)
        end

        def exec_string_rep(cmd, cmdex, consumed, is_8bit, op32, addr32,
                            modregrm_mod, modregrm_reg, modregrm_rm,
                            bytes, memory, cs_base, eip, rep_prefix, seg_override = C::SEGMENT_DS)
          sz = is_8bit ? 1 : (op32 ? 4 : 2)
          ds_base = resolve_segment_base(seg_override)
          es_base = desc_base(seg_cache(:es))
          next_eip = (eip + consumed) & 0xFFFF

          cx_mask = op32 ? 0xFFFF_FFFF : 0xFFFF
          cx = reg(:ecx) & cx_mask

          # If CX == 0, skip the instruction entirely
          if cx == 0
            advance_eip(next_eip)
            return :ok
          end

          # Execute one iteration at a time for step-at-a-time execution
          # The caller (run_until_halt) will keep calling step()
          loop do
            cx = reg(:ecx) & cx_mask
            break if cx == 0

            case cmd
            when C::CMD_MOVS then exec_movs(is_8bit, op32, memory, ds_base, es_base, eip, next_eip, advance: false)
            when C::CMD_STOS then exec_stos(is_8bit, op32, memory, es_base, eip, next_eip, advance: false)
            when C::CMD_LODS then exec_lods(is_8bit, op32, memory, ds_base, eip, next_eip, advance: false)
            when C::CMD_CMPS then exec_cmps(is_8bit, op32, memory, ds_base, es_base, eip, next_eip, advance: false)
            when C::CMD_SCAS then exec_scas(is_8bit, op32, memory, es_base, eip, next_eip, advance: false)
            end

            # Decrement CX
            new_cx = (cx - 1) & cx_mask
            write_gpr(1, new_cx, false, op32)

            # Check termination conditions
            if new_cx == 0
              break
            end

            # For REPE (rep_prefix=2) with CMPS/SCAS: stop if ZF=0
            if rep_prefix == 2 && (cmd == C::CMD_CMPS || cmd == C::CMD_SCAS)
              break if reg(:zflag) == 0
            end

            # For REPNE (rep_prefix=1) with CMPS/SCAS: stop if ZF=1
            if rep_prefix == 1 && (cmd == C::CMD_CMPS || cmd == C::CMD_SCAS)
              break if reg(:zflag) == 1
            end
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_pusha(op32, memory, ss_base, eip, next_eip)
          push_sz = op32 ? 4 : 2
          mask = op32 ? 0xFFFF_FFFF : 0xFFFF

          # Save original SP/ESP before any pushes
          orig_sp = reg(:esp) & mask

          # Push order: AX, CX, DX, BX, SP(original), BP, SI, DI
          push_value(memory, reg(:eax) & mask, push_sz, ss_base, op32)
          push_value(memory, reg(:ecx) & mask, push_sz, ss_base, op32)
          push_value(memory, reg(:edx) & mask, push_sz, ss_base, op32)
          push_value(memory, reg(:ebx) & mask, push_sz, ss_base, op32)
          push_value(memory, orig_sp, push_sz, ss_base, op32)
          push_value(memory, reg(:ebp) & mask, push_sz, ss_base, op32)
          push_value(memory, reg(:esi) & mask, push_sz, ss_base, op32)
          push_value(memory, reg(:edi) & mask, push_sz, ss_base, op32)

          advance_eip(next_eip)
          :ok
        end

        def exec_popa(op32, memory, ss_base, eip, next_eip)
          pop_sz = op32 ? 4 : 2

          # Pop order: DI, SI, BP, (skip SP), BX, DX, CX, AX
          di = pop_value(memory, pop_sz, ss_base, op32)
          si = pop_value(memory, pop_sz, ss_base, op32)
          bp = pop_value(memory, pop_sz, ss_base, op32)
          _sp = pop_value(memory, pop_sz, ss_base, op32)  # popped but discarded
          bx = pop_value(memory, pop_sz, ss_base, op32)
          dx = pop_value(memory, pop_sz, ss_base, op32)
          cx = pop_value(memory, pop_sz, ss_base, op32)
          ax = pop_value(memory, pop_sz, ss_base, op32)

          write_gpr(7, di, false, op32)   # EDI
          write_gpr(6, si, false, op32)   # ESI
          write_gpr(5, bp, false, op32)   # EBP
          # ESP is NOT restored (already updated by pop_value calls)
          write_gpr(3, bx, false, op32)   # EBX
          write_gpr(2, dx, false, op32)   # EDX
          write_gpr(1, cx, false, op32)   # ECX
          write_gpr(0, ax, false, op32)   # EAX

          advance_eip(next_eip)
          :ok
        end

        def exec_movs(is_8bit, op32, memory, ds_base, es_base, eip, next_eip, advance: true)
          sz = is_8bit ? 1 : (op32 ? 4 : 2)
          addr_mask = op32 ? 0xFFFF_FFFF : 0xFFFF
          df = reg(:dflag)
          delta = df == 0 ? sz : -sz

          si = reg(:esi) & addr_mask
          di = reg(:edi) & addr_mask

          # Read from DS:SI, write to ES:DI
          val = mem_read(memory, (ds_base + si) & 0xFFFF_FFFF, sz)
          mem_write(memory, (es_base + di) & 0xFFFF_FFFF, val, sz)

          write_gpr(6, (si + delta) & addr_mask, false, op32)  # ESI
          write_gpr(7, (di + delta) & addr_mask, false, op32)  # EDI

          advance_eip(next_eip) if advance
          :ok
        end

        def exec_stos(is_8bit, op32, memory, es_base, eip, next_eip, advance: true)
          sz = is_8bit ? 1 : (op32 ? 4 : 2)
          addr_mask = op32 ? 0xFFFF_FFFF : 0xFFFF
          df = reg(:dflag)
          delta = df == 0 ? sz : -sz

          di = reg(:edi) & addr_mask
          val = is_8bit ? (reg(:eax) & 0xFF) : (reg(:eax) & size_mask(sz))

          mem_write(memory, (es_base + di) & 0xFFFF_FFFF, val, sz)

          write_gpr(7, (di + delta) & addr_mask, false, op32)  # EDI

          advance_eip(next_eip) if advance
          :ok
        end

        def exec_lods(is_8bit, op32, memory, ds_base, eip, next_eip, advance: true)
          sz = is_8bit ? 1 : (op32 ? 4 : 2)
          addr_mask = op32 ? 0xFFFF_FFFF : 0xFFFF
          df = reg(:dflag)
          delta = df == 0 ? sz : -sz

          si = reg(:esi) & addr_mask
          val = mem_read(memory, (ds_base + si) & 0xFFFF_FFFF, sz)

          if is_8bit
            # Only write AL
            old_eax = gpr(0)
            new_eax = (old_eax & 0xFFFF_FF00) | (val & 0xFF)
            write_gpr(0, new_eax, false, true)
          else
            write_gpr(0, val, false, op32)
          end

          write_gpr(6, (si + delta) & addr_mask, false, op32)  # ESI

          advance_eip(next_eip) if advance
          :ok
        end

        def exec_cmps(is_8bit, op32, memory, ds_base, es_base, eip, next_eip, advance: true)
          sz = is_8bit ? 1 : (op32 ? 4 : 2)
          addr_mask = op32 ? 0xFFFF_FFFF : 0xFFFF
          df = reg(:dflag)
          delta = df == 0 ? sz : -sz

          si = reg(:esi) & addr_mask
          di = reg(:edi) & addr_mask

          val_src = mem_read(memory, (ds_base + si) & 0xFFFF_FFFF, sz)
          val_dst = mem_read(memory, (es_base + di) & 0xFFFF_FFFF, sz)

          # CMP: dst - src (SI data - DI data)
          result = run_alu(C::ARITH_SUB, val_dst, val_src, sz)
          write_flags_from_alu(result)

          write_gpr(6, (si + delta) & addr_mask, false, op32)  # ESI
          write_gpr(7, (di + delta) & addr_mask, false, op32)  # EDI

          advance_eip(next_eip) if advance
          :ok
        end

        def exec_scas(is_8bit, op32, memory, es_base, eip, next_eip, advance: true)
          sz = is_8bit ? 1 : (op32 ? 4 : 2)
          addr_mask = op32 ? 0xFFFF_FFFF : 0xFFFF
          df = reg(:dflag)
          delta = df == 0 ? sz : -sz

          di = reg(:edi) & addr_mask
          al_val = is_8bit ? (reg(:eax) & 0xFF) : (reg(:eax) & size_mask(sz))

          val_mem = mem_read(memory, (es_base + di) & 0xFFFF_FFFF, sz)

          # CMP AL/AX/EAX with ES:DI
          result = run_alu(C::ARITH_SUB, val_mem, al_val, sz)
          write_flags_from_alu(result)

          write_gpr(7, (di + delta) & addr_mask, false, op32)  # EDI

          advance_eip(next_eip) if advance
          :ok
        end

        def exec_enter(op32, bytes, prefix_count, memory, ss_base, eip, next_eip)
          push_sz = op32 ? 4 : 2
          # ENTER imm16, imm8 — opcode C8
          # imm16 is the frame size, imm8 is the nesting level
          imm_offset = prefix_count + 1
          frame_size = (bytes[imm_offset] || 0) | ((bytes[imm_offset + 1] || 0) << 8)
          _nesting = bytes[imm_offset + 2] || 0

          # For level 0: PUSH BP, BP = SP, SP -= frame_size
          bp = reg(:ebp) & (op32 ? 0xFFFF_FFFF : 0xFFFF)
          push_value(memory, bp, push_sz, ss_base, op32)

          new_bp = reg(:esp) & (op32 ? 0xFFFF_FFFF : 0xFFFF)
          write_gpr(5, new_bp, false, op32)  # EBP = ESP (frame pointer)

          # Allocate local space
          new_sp = if op32
                     (new_bp - frame_size) & 0xFFFF_FFFF
                   else
                     (new_bp - frame_size) & 0xFFFF
                   end
          write_gpr(4, new_sp, false, op32)  # ESP -= frame_size

          advance_eip(next_eip)
          :ok
        end

        def exec_leave(op32, memory, ss_base, eip, next_eip)
          pop_sz = op32 ? 4 : 2

          # LEAVE: SP = BP, POP BP
          bp = reg(:ebp) & (op32 ? 0xFFFF_FFFF : 0xFFFF)
          write_gpr(4, bp, false, op32)  # ESP = EBP

          new_bp = pop_value(memory, pop_sz, ss_base, op32)
          write_gpr(5, new_bp, false, op32)  # EBP = popped value

          advance_eip(next_eip)
          :ok
        end

        def exec_in(opcode, prefix_count, is_8bit, op32, bytes, eip, next_eip)
          case opcode
          when 0xE4  # IN AL, imm8
            port = bytes[prefix_count + 1] || 0
            value = @io_read_callback ? @io_read_callback.call(port, 1) : 0
            old_eax = gpr(0)
            write_gpr(0, (old_eax & 0xFFFF_FF00) | (value & 0xFF), false, true)

          when 0xE5  # IN AX/EAX, imm8
            port = bytes[prefix_count + 1] || 0
            sz = op32 ? 4 : 2
            value = @io_read_callback ? @io_read_callback.call(port, sz) : 0
            write_gpr(0, value, false, op32)

          when 0xEC  # IN AL, DX
            port = reg(:edx) & 0xFFFF
            value = @io_read_callback ? @io_read_callback.call(port, 1) : 0
            old_eax = gpr(0)
            write_gpr(0, (old_eax & 0xFFFF_FF00) | (value & 0xFF), false, true)

          when 0xED  # IN AX/EAX, DX
            port = reg(:edx) & 0xFFFF
            sz = op32 ? 4 : 2
            value = @io_read_callback ? @io_read_callback.call(port, sz) : 0
            write_gpr(0, value, false, op32)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_out(opcode, prefix_count, is_8bit, op32, bytes, eip, next_eip)
          case opcode
          when 0xE6  # OUT imm8, AL
            port = bytes[prefix_count + 1] || 0
            value = reg(:eax) & 0xFF
            @io_write_callback&.call(port, value, 1)

          when 0xE7  # OUT imm8, AX/EAX
            port = bytes[prefix_count + 1] || 0
            sz = op32 ? 4 : 2
            value = reg(:eax) & size_mask(sz)
            @io_write_callback&.call(port, value, sz)

          when 0xEE  # OUT DX, AL
            port = reg(:edx) & 0xFFFF
            value = reg(:eax) & 0xFF
            @io_write_callback&.call(port, value, 1)

          when 0xEF  # OUT DX, AX/EAX
            port = reg(:edx) & 0xFFFF
            sz = op32 ? 4 : 2
            value = reg(:eax) & size_mask(sz)
            @io_write_callback&.call(port, value, sz)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_ins(is_8bit, op32, addr32, memory, ds_base, ss_base, eip, next_eip)
          sz = is_8bit ? 1 : (op32 ? 4 : 2)
          addr_mask = addr32 ? 0xFFFF_FFFF : 0xFFFF
          port = reg(:edx) & 0xFFFF
          value = @io_read_callback ? @io_read_callback.call(port, sz) : 0

          es_base = desc_base_public(seg_cache_public(:es))
          di = reg(:edi) & addr_mask
          mem_write(memory, (es_base + di) & 0xFFFF_FFFF, value, sz)

          df = reg(:dflag)
          delta = df == 0 ? sz : -sz
          write_gpr(7, (di + delta) & addr_mask, false, addr32)

          advance_eip(next_eip)
          :ok
        end

        def exec_outs(is_8bit, op32, addr32, memory, ds_base, ss_base, eip, next_eip)
          sz = is_8bit ? 1 : (op32 ? 4 : 2)
          addr_mask = addr32 ? 0xFFFF_FFFF : 0xFFFF
          port = reg(:edx) & 0xFFFF

          si = reg(:esi) & addr_mask
          value = mem_read(memory, (ds_base + si) & 0xFFFF_FFFF, sz)
          @io_write_callback&.call(port, value, sz)

          df = reg(:dflag)
          delta = df == 0 ? sz : -sz
          write_gpr(6, (si + delta) & addr_mask, false, addr32)

          advance_eip(next_eip)
          :ok
        end

        def exec_xlat(memory, ds_base, eip, next_eip)
          bx = reg(:ebx) & 0xFFFF
          al = reg(:eax) & 0xFF
          addr = (ds_base + bx + al) & 0xFFFF_FFFF
          value = mem_read(memory, addr, 1)

          old_eax = gpr(0)
          write_gpr(0, (old_eax & 0xFFFF_FF00) | (value & 0xFF), false, true)

          advance_eip(next_eip)
          :ok
        end

        # ---------- Phase 7: Exception & Interrupt Handling ----------

        # Dispatch an interrupt/exception through the real-mode IVT.
        # type: :software (INT), :hardware (IRQ), :fault (#DE, #UD, etc.)
        # For :fault, return_eip points to the faulting instruction.
        # For :software, return_eip points to the instruction AFTER INT.
        def dispatch_interrupt(memory, vector, return_eip, type)
          ss_base = desc_base(seg_cache(:ss))
          op32 = false  # Real mode uses 16-bit frames

          # Push FLAGS, CS, IP (each 16-bit, total 6 bytes)
          flags = build_eflags & 0xFFFF
          cs_val = reg(:cs) & 0xFFFF
          push_value(memory, flags, 2, ss_base, op32)
          push_value(memory, cs_val, 2, ss_base, op32)
          push_value(memory, return_eip & 0xFFFF, 2, ss_base, op32)

          # Clear IF and TF
          set_flag(:if, 0)
          set_flag(:tf, 0)

          # Load new CS:IP from IVT (at linear address vector * 4)
          ivt_addr = (vector & 0xFF) * 4
          new_ip = mem_read(memory, ivt_addr, 2)
          new_cs = mem_read(memory, ivt_addr + 2, 2)

          # Update CS selector and descriptor cache with new base (new_cs << 4 for real mode)
          new_cs_base = (new_cs & 0xFFFF) << 4
          cache = C::DEFAULT_CS_CACHE
          base_hi = (new_cs_base >> 24) & 0xFF
          base_lo = new_cs_base & 0xFF_FFFF
          cache = cache & ~(0xFF << 56) & ~(0xFF_FFFF << 16)
          cache = cache | (base_hi << 56) | (base_lo << 16)
          write_regfile(write_seg: 1, wr_seg_index: C::SEGMENT_CS, seg_to_reg: new_cs,
                        write_seg_cache: 1, seg_cache_to_reg: cache,
                        write_seg_valid: 1, seg_valid_to_reg: 1)

          # Set new EIP
          advance_eip(new_ip & 0xFFFF)

          :ok
        end

        def exec_int_into(opcode, prefix_count, bytes, memory, ss_base, eip, next_eip)
          case opcode
          when 0xCD  # INT imm8
            vector = bytes[prefix_count + 1] || 0
            dispatch_interrupt(memory, vector, next_eip, :software)

          when 0xCC  # INT3
            dispatch_interrupt(memory, C::EXCEPTION_BP, next_eip, :software)

          when 0xCE  # INTO
            if reg(:oflag) == 1
              dispatch_interrupt(memory, C::EXCEPTION_OF, next_eip, :software)
            else
              advance_eip(next_eip)
              :ok
            end
          end
        end

        def exec_iret(op32, memory, ss_base, eip, next_eip)
          pop_sz = op32 ? 4 : 2

          # Pop IP, CS, FLAGS (in this order)
          new_ip = pop_value(memory, pop_sz, ss_base, op32)
          new_cs = pop_value(memory, pop_sz, ss_base, op32)
          new_flags = pop_value(memory, pop_sz, ss_base, op32)

          # Update CS selector and descriptor cache
          new_cs_base = (new_cs & 0xFFFF) << 4
          cache = C::DEFAULT_CS_CACHE
          base_hi = (new_cs_base >> 24) & 0xFF
          base_lo = new_cs_base & 0xFF_FFFF
          cache = cache & ~(0xFF << 56) & ~(0xFF_FFFF << 16)
          cache = cache | (base_hi << 56) | (base_lo << 16)
          write_regfile(write_seg: 1, wr_seg_index: C::SEGMENT_CS, seg_to_reg: new_cs,
                        write_seg_cache: 1, seg_cache_to_reg: cache,
                        write_seg_valid: 1, seg_valid_to_reg: 1)

          # Restore flags
          load_eflags(new_flags, op32)

          # Set new EIP
          advance_eip(new_ip & (op32 ? 0xFFFF_FFFF : 0xFFFF))

          :ok
        end

        # ---------- Phase 8: Protected Mode & Segmentation ----------

        def exec_lgdt(opcode, prefix_count, addr32, bytes, memory, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1
          addr = compute_ea(
            (bytes[mrm_offset] >> 6) & 3,
            bytes[mrm_offset] & 7,
            addr32, bytes, mrm_offset, ds_base, ss_base
          )
          limit = mem_read(memory, addr, 2)
          base = mem_read(memory, addr + 2, 4)
          write_regfile(write_gdtr: 1, gdtr_base_to_reg: base, gdtr_limit_to_reg: limit)
          advance_eip(next_eip)
          :ok
        end

        def exec_lidt(opcode, prefix_count, addr32, bytes, memory, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1
          addr = compute_ea(
            (bytes[mrm_offset] >> 6) & 3,
            bytes[mrm_offset] & 7,
            addr32, bytes, mrm_offset, ds_base, ss_base
          )
          limit = mem_read(memory, addr, 2)
          base = mem_read(memory, addr + 2, 4)
          write_regfile(write_idtr: 1, idtr_base_to_reg: base, idtr_limit_to_reg: limit)
          advance_eip(next_eip)
          :ok
        end

        def exec_invlpg(prefix_count, addr32, modregrm_mod, modregrm_rm,
                        bytes, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1
          # INVLPG takes a memory operand — compute the effective address
          addr = compute_ea(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset, ds_base, ss_base)
          vpn = (addr >> 12) & 0xFFFFF
          @tlb.delete(vpn)
          advance_eip(next_eip)
          :ok
        end

        def exec_control_reg(opcode, prefix_count, has_0f, bytes, modregrm_mod, modregrm_reg, modregrm_rm,
                             eip, next_eip)
          cr_index = modregrm_reg  # CR number (0-4)
          gpr_index = modregrm_rm  # GPR index

          if opcode == 0x20
            # MOV r32, CRx — read from control register
            value = case cr_index
                    when 0
                      cr0_val = 0
                      cr0_val |= 1 if reg(:cr0_pe) != 0
                      cr0_val |= (1 << 1) if reg(:cr0_mp) != 0
                      cr0_val |= (1 << 2) if reg(:cr0_em) != 0
                      cr0_val |= (1 << 3) if reg(:cr0_ts) != 0
                      cr0_val |= (1 << 5) if reg(:cr0_ne) != 0
                      cr0_val |= (1 << 16) if reg(:cr0_wp) != 0
                      cr0_val |= (1 << 18) if reg(:cr0_am) != 0
                      cr0_val |= (1 << 29) if reg(:cr0_nw) != 0
                      cr0_val |= (1 << 30) if reg(:cr0_cd) != 0
                      cr0_val |= (1 << 31) if reg(:cr0_pg) != 0
                      cr0_val
                    when 2 then reg(:cr2)
                    when 3 then reg(:cr3)
                    else 0
                    end
            write_gpr(gpr_index, value, false, true)  # always 32-bit
          elsif opcode == 0x22
            # MOV CRx, r32 — write to control register
            value = gpr(gpr_index)
            case cr_index
            when 0
              write_regfile(
                write_cr0_pe: 1, cr0_pe_to_reg: value & 1,
                write_cr0_mp: 1, cr0_mp_to_reg: (value >> 1) & 1,
                write_cr0_em: 1, cr0_em_to_reg: (value >> 2) & 1,
                write_cr0_ts: 1, cr0_ts_to_reg: (value >> 3) & 1,
                write_cr0_ne: 1, cr0_ne_to_reg: (value >> 5) & 1,
                write_cr0_wp: 1, cr0_wp_to_reg: (value >> 16) & 1,
                write_cr0_am: 1, cr0_am_to_reg: (value >> 18) & 1,
                write_cr0_nw: 1, cr0_nw_to_reg: (value >> 29) & 1,
                write_cr0_cd: 1, cr0_cd_to_reg: (value >> 30) & 1,
                write_cr0_pg: 1, cr0_pg_to_reg: (value >> 31) & 1
              )
            when 2
              write_regfile(write_cr2: 1, cr2_to_reg: value)
            when 3
              write_regfile(write_cr3: 1, cr3_to_reg: value)
              @tlb.clear  # CR3 write flushes TLB
            end
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_mov_to_seg(opcode, prefix_count, addr32, bytes, memory, ds_base, ss_base,
                            modregrm_mod, modregrm_reg, modregrm_rm, eip, next_eip)
          mrm_offset = prefix_count + 1
          seg_index = modregrm_reg  # 0=ES, 1=CS, 2=SS, 3=DS, 4=FS, 5=GS

          # Read selector from r/m
          selector = read_rm(modregrm_mod, modregrm_rm, addr32, false, 2, bytes, mrm_offset, memory, ds_base, ss_base) & 0xFFFF

          if reg(:cr0_pe) == 1
            # Protected mode: load descriptor from GDT/LDT
            exception = load_segment_protected(seg_index, selector, memory, eip)
            return :ok if exception  # Exception dispatched, don't advance EIP
          else
            # Real mode: base = selector << 4
            new_base = (selector & 0xFFFF) << 4
            cache = C::DEFAULT_SEG_CACHE
            base_hi = (new_base >> 24) & 0xFF
            base_lo = new_base & 0xFF_FFFF
            cache = cache & ~(0xFF << 56) & ~(0xFF_FFFF << 16)
            cache = cache | (base_hi << 56) | (base_lo << 16)
            write_regfile(write_seg: 1, wr_seg_index: seg_index, seg_to_reg: selector,
                          write_seg_cache: 1, seg_cache_to_reg: cache,
                          write_seg_valid: 1, seg_valid_to_reg: 1)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_far_jmp(selector, offset, op32, memory)
          if reg(:cr0_pe) == 1
            # Protected mode: load CS descriptor from GDT
            load_segment_protected(C::SEGMENT_CS, selector, memory, reg(:eip))
          else
            # Real mode: CS base = selector << 4
            new_base = (selector & 0xFFFF) << 4
            cache = C::DEFAULT_CS_CACHE
            base_hi = (new_base >> 24) & 0xFF
            base_lo = new_base & 0xFF_FFFF
            cache = cache & ~(0xFF << 56) & ~(0xFF_FFFF << 16)
            cache = cache | (base_hi << 56) | (base_lo << 16)
            write_regfile(write_seg: 1, wr_seg_index: C::SEGMENT_CS, seg_to_reg: selector,
                          write_seg_cache: 1, seg_cache_to_reg: cache,
                          write_seg_valid: 1, seg_valid_to_reg: 1)
          end
          advance_eip(offset & (op32 ? 0xFFFF_FFFF : 0xFFFF))
        end

        # Load a segment in protected mode from GDT/LDT.
        # Returns true if an exception was raised, false otherwise.
        def load_segment_protected(seg_index, selector, memory, fault_eip)
          # Null selector check
          if (selector >> 3) == 0 && (selector & 4) == 0
            # Null selector — allowed for DS/ES/FS/GS, not for CS/SS
            if seg_index == C::SEGMENT_CS || seg_index == C::SEGMENT_SS
              dispatch_interrupt(memory, C::EXCEPTION_GP, fault_eip, :fault)
              return true
            end
            # Load null descriptor
            write_regfile(write_seg: 1, wr_seg_index: seg_index, seg_to_reg: selector,
                          write_seg_cache: 1, seg_cache_to_reg: 0,
                          write_seg_valid: 1, seg_valid_to_reg: 0)
            return false
          end

          # Determine table base (TI bit: 0=GDT, 1=LDT)
          ti = (selector >> 2) & 1
          index = (selector >> 3) & 0x1FFF
          if ti == 0
            table_base = reg(:gdtr_base)
            table_limit = reg(:gdtr_limit)
          else
            # LDT — not yet implemented, use 0
            table_base = 0
            table_limit = 0
          end

          # Check bounds
          desc_addr = table_base + index * 8
          if (index * 8 + 7) > table_limit
            dispatch_interrupt(memory, C::EXCEPTION_GP, fault_eip, :fault)
            return true
          end

          # Fetch 8-byte descriptor from memory
          desc_lo = mem_read(memory, desc_addr, 4)
          desc_hi = mem_read(memory, desc_addr + 4, 4)
          desc = (desc_hi << 32) | desc_lo

          # Check present bit
          present = (desc >> C::DESC_BIT_P) & 1
          if present == 0
            dispatch_interrupt(memory, C::EXCEPTION_NP, fault_eip, :fault)
            return true
          end

          # Store descriptor cache and selector
          write_regfile(write_seg: 1, wr_seg_index: seg_index, seg_to_reg: selector,
                        write_seg_cache: 1, seg_cache_to_reg: desc,
                        write_seg_valid: 1, seg_valid_to_reg: 1)
          false
        end

        # ---------- Phase 10: Extended instruction set ----------

        def exec_cpuid(eip, next_eip)
          leaf = gpr(0)  # EAX = leaf
          case leaf
          when 0
            # Max leaf + vendor string "GenuineIntel"
            write_gpr(0, 1, false, true)      # EAX = max supported leaf
            write_gpr(3, 0x756E6547, false, true)  # EBX = "Genu"
            write_gpr(2, 0x49656E69, false, true)  # EDX = "ineI"
            write_gpr(1, 0x6C65746E, false, true)  # ECX = "ntel"
          when 1
            write_gpr(0, C::CPUID_MODEL_FAMILY_STEPPING, false, true)
            write_gpr(3, 0, false, true)  # EBX
            write_gpr(1, 0, false, true)  # ECX
            write_gpr(2, 0x00000001, false, true)  # EDX = FPU present (bit 0)
          else
            write_gpr(0, 0, false, true)
            write_gpr(3, 0, false, true)
            write_gpr(1, 0, false, true)
            write_gpr(2, 0, false, true)
          end
          advance_eip(next_eip)
          :ok
        end

        def exec_bound(opcode, prefix_count, op32, addr32, sz,
                       modregrm_mod, modregrm_reg, modregrm_rm,
                       bytes, memory, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1
          # Read index from register
          index = read_gpr(modregrm_reg, false, sz)
          index = op32 ? sign_extend_32(index) : sign_extend_16(index)

          # Read bounds from memory
          addr = compute_ea(modregrm_mod, modregrm_rm, addr32, bytes, mrm_offset, ds_base, ss_base)
          lower = mem_read(memory, addr, sz)
          upper = mem_read(memory, addr + sz, sz)
          lower = op32 ? sign_extend_32(lower) : sign_extend_16(lower)
          upper = op32 ? sign_extend_32(upper) : sign_extend_16(upper)

          if index < lower || index > upper
            dispatch_interrupt(memory, C::EXCEPTION_BR, eip, :fault)
          else
            advance_eip(next_eip)
            :ok
          end
        end

        def sign_extend_32(val)
          val = val & 0xFFFF_FFFF
          (val & 0x8000_0000) != 0 ? val - 0x1_0000_0000 : val
        end

        def exec_bsf_bsr(opcode, prefix_count, has_0f, is_8bit, op32, addr32, sz, mask,
                         modregrm_mod, modregrm_reg, modregrm_rm,
                         bytes, memory, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1
          src = read_rm(modregrm_mod, modregrm_rm, addr32, false, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask

          if src == 0
            set_flag(:zf, 1)
          else
            set_flag(:zf, 0)
            if opcode == 0xBC  # BSF
              bit = 0
              bit += 1 while (src & (1 << bit)) == 0
            else  # BSR (0xBD)
              bit = (sz * 8) - 1
              bit -= 1 while (src & (1 << bit)) == 0
            end
            write_gpr(modregrm_reg, bit, false, op32)
          end
          advance_eip(next_eip)
          :ok
        end

        def exec_bt(opcode, prefix_count, has_0f, op32, addr32, sz, mask,
                    modregrm_mod, modregrm_reg, modregrm_rm,
                    bytes, memory, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1

          # Determine the bit operation variant and bit offset source
          if opcode == 0xBA
            # Immediate form: 0F BA /4-7 imm8
            src = read_rm(modregrm_mod, modregrm_rm, addr32, false, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
            bit_offset = bytes[mrm_offset + modregrm_len_value(modregrm_mod, modregrm_rm, addr32)] & ((sz * 8) - 1)
            reg_field = modregrm_reg
          else
            # Register form: 0F A3/AB/B3/BB
            src = read_rm(modregrm_mod, modregrm_rm, addr32, false, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
            bit_offset = read_gpr(modregrm_reg, false, sz) & ((sz * 8) - 1)
            reg_field = case opcode
                        when 0xA3 then 4  # BT
                        when 0xAB then 5  # BTS
                        when 0xB3 then 6  # BTR
                        when 0xBB then 7  # BTC
                        end
          end

          # Test the bit
          old_bit = (src >> bit_offset) & 1
          set_flag(:cf, old_bit)

          # Modify the bit based on operation
          case reg_field
          when 4  # BT — test only
            # no modification
          when 5  # BTS — set
            src |= (1 << bit_offset)
          when 6  # BTR — reset
            src &= ~(1 << bit_offset)
          when 7  # BTC — complement
            src ^= (1 << bit_offset)
          end

          # Write back if modified (BTS/BTR/BTC)
          if reg_field != 4
            write_rm(modregrm_mod, modregrm_rm, addr32, false, op32, sz, src & mask,
                     bytes, mrm_offset, memory, ds_base, ss_base)
          end

          advance_eip(next_eip)
          :ok
        end

        # Helper: get ModR/M length value for imm8 offset calculation
        def modregrm_len_value(mod_val, rm_val, addr32)
          if addr32
            if mod_val == 3
              1
            elsif mod_val == 0 && rm_val == 5
              5
            elsif rm_val == 4  # SIB
              if mod_val == 0 then 2
              elsif mod_val == 1 then 3
              else 6
              end
            elsif mod_val == 1 then 2
            elsif mod_val == 2 then 5
            else 1
            end
          else
            if mod_val == 3 then 1
            elsif mod_val == 0 && rm_val == 6 then 3
            elsif mod_val == 1 then 2
            elsif mod_val == 2 then 3
            else 1
            end
          end
        end

        def exec_setcc(opcode, prefix_count, has_0f, addr32,
                       modregrm_mod, modregrm_reg, modregrm_rm,
                       bytes, memory, ds_base, ss_base, eip, next_eip)
          # Evaluate condition (opcode & 0x0F gives condition code, like Jcc)
          cc = opcode & 0x0F
          @cond_eval.set_input(:condition_index, cc)
          @cond_eval.set_input(:cflag, reg(:cflag))
          @cond_eval.set_input(:zflag, reg(:zflag))
          @cond_eval.set_input(:sflag, reg(:sflag))
          @cond_eval.set_input(:oflag, reg(:oflag))
          @cond_eval.set_input(:pflag, reg(:pflag))
          @cond_eval.propagate
          result = @cond_eval.get_output(:condition_met)

          mrm_offset = prefix_count + 1
          write_rm(modregrm_mod, modregrm_rm, addr32, true, false, 1, result,
                   bytes, mrm_offset, memory, ds_base, ss_base)
          advance_eip(next_eip)
          :ok
        end

        def exec_bswap(opcode, prefix_count, has_0f, bytes, eip, next_eip)
          # Register encoded in low 3 bits of opcode (0xC8-0xCF → reg 0-7)
          reg_index = opcode & 7
          val = gpr(reg_index)
          swapped = ((val >> 24) & 0xFF) |
                    (((val >> 16) & 0xFF) << 8) |
                    (((val >> 8) & 0xFF) << 16) |
                    ((val & 0xFF) << 24)
          write_gpr(reg_index, swapped & 0xFFFF_FFFF, false, true)
          advance_eip(next_eip)
          :ok
        end

        def exec_loop(opcode, prefix_count, op32, bytes, eip, next_eip)
          # Decrement CX (or ECX)
          cx = gpr(1)  # ECX
          cx = op32 ? (cx - 1) & 0xFFFF_FFFF : (cx - 1) & 0xFFFF
          if op32
            write_gpr(1, cx, false, true)
          else
            write_gpr(1, (gpr(1) & 0xFFFF0000) | cx, false, true)
          end

          rel = sign_extend_8(bytes[prefix_count + 1])
          take = case opcode
                 when 0xE2  # LOOP
                   cx != 0
                 when 0xE1  # LOOPE/LOOPZ
                   cx != 0 && reg(:zflag) == 1
                 when 0xE0  # LOOPNE/LOOPNZ
                   cx != 0 && reg(:zflag) == 0
                 end

          if take
            target = (next_eip + rel) & (op32 ? 0xFFFF_FFFF : 0xFFFF)
            advance_eip(target)
          else
            advance_eip(next_eip)
          end
          :ok
        end

        def exec_jcxz(prefix_count, op32, bytes, eip, next_eip)
          cx = op32 ? gpr(1) : gpr(1) & 0xFFFF
          rel = sign_extend_8(bytes[prefix_count + 1])

          if cx == 0
            target = (next_eip + rel) & (op32 ? 0xFFFF_FFFF : 0xFFFF)
            advance_eip(target)
          else
            advance_eip(next_eip)
          end
          :ok
        end

        def exec_shxd(opcode, prefix_count, has_0f, op32, addr32, sz, mask,
                      modregrm_mod, modregrm_reg, modregrm_rm,
                      bytes, memory, ds_base, ss_base, eip, next_eip)
          mrm_offset = prefix_count + 1
          dst = read_rm(modregrm_mod, modregrm_rm, addr32, false, sz, bytes, mrm_offset, memory, ds_base, ss_base) & mask
          src = read_gpr(modregrm_reg, false, sz) & mask
          bits = sz * 8

          # Shift count: imm8 or CL
          if opcode == 0xA4 || opcode == 0xAC  # imm8
            count = bytes[mrm_offset + modregrm_len_value(modregrm_mod, modregrm_rm, addr32)] & 0x1F
          else  # CL
            count = gpr(1) & 0x1F  # CL
          end

          if count > 0 && count <= bits
            if opcode == 0xA4 || opcode == 0xA5  # SHLD
              result = ((dst << count) | (src >> (bits - count))) & mask
            else  # SHRD (0xAC, 0xAD)
              result = ((dst >> count) | (src << (bits - count))) & mask
            end
            write_rm(modregrm_mod, modregrm_rm, addr32, false, op32, sz, result,
                     bytes, mrm_offset, memory, ds_base, ss_base)
            update_flags_szp(result, sz)
          end

          advance_eip(next_eip)
          :ok
        end

        def exec_aaa(eip, next_eip)
          al = gpr(0) & 0xFF
          ah = (gpr(0) >> 8) & 0xFF
          if (al & 0x0F) > 9 || reg(:aflag) == 1
            al = (al + 6) & 0xFF
            ah = (ah + 1) & 0xFF
            set_flag(:af, 1)
            set_flag(:cf, 1)
          else
            set_flag(:af, 0)
            set_flag(:cf, 0)
          end
          al = al & 0x0F
          write_gpr(0, (gpr(0) & 0xFFFF0000) | (ah << 8) | al, false, true)
          advance_eip(next_eip)
          :ok
        end

        def exec_aas(eip, next_eip)
          al = gpr(0) & 0xFF
          ah = (gpr(0) >> 8) & 0xFF
          if (al & 0x0F) > 9 || reg(:aflag) == 1
            al = (al - 6) & 0xFF
            ah = (ah - 1) & 0xFF
            set_flag(:af, 1)
            set_flag(:cf, 1)
          else
            set_flag(:af, 0)
            set_flag(:cf, 0)
          end
          al = al & 0x0F
          write_gpr(0, (gpr(0) & 0xFFFF0000) | (ah << 8) | al, false, true)
          advance_eip(next_eip)
          :ok
        end

        def exec_daa(eip, next_eip)
          al = gpr(0) & 0xFF
          old_cf = reg(:cflag)
          set_flag(:cf, 0)

          if (al & 0x0F) > 9 || reg(:aflag) == 1
            al = (al + 6) & 0xFF
            set_flag(:cf, old_cf == 1 || al < 6 ? 1 : 0)
            set_flag(:af, 1)
          else
            set_flag(:af, 0)
          end

          if (gpr(0) & 0xFF) > 0x99 || old_cf == 1
            al = (al + 0x60) & 0xFF
            set_flag(:cf, 1)
          end

          write_gpr(0, (gpr(0) & 0xFFFF_FF00) | al, false, true)
          update_flags_szp(al, 1)
          advance_eip(next_eip)
          :ok
        end

        def exec_das(eip, next_eip)
          al = gpr(0) & 0xFF
          old_cf = reg(:cflag)
          set_flag(:cf, 0)

          if (al & 0x0F) > 9 || reg(:aflag) == 1
            al = (al - 6) & 0xFF
            set_flag(:cf, old_cf == 1 || (gpr(0) & 0xFF) < 6 ? 1 : 0)
            set_flag(:af, 1)
          else
            set_flag(:af, 0)
          end

          if (gpr(0) & 0xFF) > 0x99 || old_cf == 1
            al = (al - 0x60) & 0xFF
            set_flag(:cf, 1)
          end

          write_gpr(0, (gpr(0) & 0xFFFF_FF00) | al, false, true)
          update_flags_szp(al, 1)
          advance_eip(next_eip)
          :ok
        end

        def exec_aad(prefix_count, bytes, eip, next_eip)
          base = bytes[prefix_count + 1]  # usually 0x0A
          al = gpr(0) & 0xFF
          ah = (gpr(0) >> 8) & 0xFF
          al = (al + ah * base) & 0xFF
          write_gpr(0, (gpr(0) & 0xFFFF0000) | al, false, true)
          update_flags_szp(al, 1)
          advance_eip(next_eip)
          :ok
        end

        def exec_aam(prefix_count, bytes, memory, eip, next_eip)
          base = bytes[prefix_count + 1]  # usually 0x0A
          if base == 0
            dispatch_interrupt(memory, C::EXCEPTION_DE, eip, :fault)
            return :ok
          end
          al = gpr(0) & 0xFF
          ah = al / base
          al = al % base
          write_gpr(0, (gpr(0) & 0xFFFF0000) | ((ah & 0xFF) << 8) | (al & 0xFF), false, true)
          update_flags_szp(al, 1)
          advance_eip(next_eip)
          :ok
        end

        def exec_salc(eip, next_eip)
          val = reg(:cflag) == 1 ? 0xFF : 0x00
          write_gpr(0, (gpr(0) & 0xFFFF_FF00) | val, false, true)
          advance_eip(next_eip)
          :ok
        end

        def exec_fpu(memory, eip, next_eip)
          # If CR0.EM=1, raise #NM (no math coprocessor)
          if reg(:cr0_em) != 0
            dispatch_interrupt(memory, C::EXCEPTION_NM, eip, :fault)
          else
            # FPU not implemented — just advance past the instruction
            advance_eip(next_eip)
            :ok
          end
        end

        # Helper: update SZP flags only (no CF/OF/AF)
        def update_flags_szp(result, sz)
          mask = size_mask(sz)
          result = result & mask
          set_flag(:zf, result == 0 ? 1 : 0)
          set_flag(:sf, (result >> (sz * 8 - 1)) & 1)
          # Parity of low byte
          pb = result & 0xFF
          pb ^= (pb >> 4)
          pb ^= (pb >> 2)
          pb ^= (pb >> 1)
          set_flag(:pf, (pb & 1) == 0 ? 1 : 0)
        end

        # Check if a memory access is within segment limit
        def check_segment_limit(seg_cache, offset, size)
          return true if reg(:cr0_pe) == 0  # No limit checking in real mode

          limit_lo = seg_cache & 0xFFFF
          limit_hi = (seg_cache >> 48) & 0xF
          g = (seg_cache >> C::DESC_BIT_G) & 1
          limit = (limit_hi << 16) | limit_lo
          limit = g == 1 ? (limit << 12) | 0xFFF : limit

          (offset + size - 1) <= limit
        end
      end
    end
  end
end
