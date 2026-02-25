# Differential tests: single-cycle vs pipelined RISC-V CPU
# OS-boot critical scenarios: interrupt handling, privilege transitions,
# CSR read-modify-write with interrupts, Sv32 translation, and
# load-store sequences interleaved with interrupts.

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/ir_harness'
require_relative '../../../examples/riscv/hdl/pipeline/ir_harness'
require_relative '../../../examples/riscv/utilities/assembler'

RSpec.describe 'RISC-V pipeline differential: OS-boot critical scenarios', timeout: 60 do
  let(:asm) { RHDL::Examples::RISCV::Assembler }

  before(:each) do
    skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
  end

  # -- Harness construction helpers ------------------------------------------

  def build_single
    RHDL::Examples::RISCV::IRHarness.new(mem_size: 65_536, backend: :jit, allow_fallback: false)
  end

  def build_pipeline
    RHDL::Examples::RISCV::Pipeline::IRHarness.new('diff_test', mem_size: 65_536, backend: :jit, allow_fallback: false)
  end

  # Polymorphic data-memory helpers (the two harnesses expose different names).
  def write_data_word(cpu, addr, value)
    if cpu.respond_to?(:write_data_word)
      cpu.write_data_word(addr, value)
    else
      cpu.write_data(addr, value)
    end
  end

  def read_data_word(cpu, addr)
    if cpu.respond_to?(:read_data_word)
      cpu.read_data_word(addr)
    else
      cpu.read_data(addr)
    end
  end

  # Compare all 32 integer registers between two harness instances.
  def expect_regs_match(single, pipeline, label: '')
    (0..31).each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)),
        "#{label}register x#{idx} mismatch: " \
        "single=0x#{single.read_reg(idx).to_s(16)} " \
        "pipeline=0x#{pipeline.read_reg(idx).to_s(16)}"
    end
  end

  # Compare a specific subset of registers.
  def expect_subset_match(single, pipeline, regs, label: '')
    regs.each do |idx|
      expect(pipeline.read_reg(idx)).to eq(single.read_reg(idx)),
        "#{label}register x#{idx} mismatch: " \
        "single=0x#{single.read_reg(idx).to_s(16)} " \
        "pipeline=0x#{pipeline.read_reg(idx).to_s(16)}"
    end
  end

  # -----------------------------------------------------------------------
  # Test 1 -- Timer interrupt fires mid-computation, handler reads mepc and
  #           returns via MRET.  Verify all registers match.
  # -----------------------------------------------------------------------
  describe 'timer interrupt with MRET return' do
    it 'matches register state after timer interrupt fires during sequential execution' do
      # Main program:
      #   0x000: Setup mtvec, enable MIE + MTIE, then execute a sequence of
      #          ADDI instructions that build up register state.  The timer
      #          interrupt will fire somewhere during these ADDIs.
      #
      # Trap handler at 0x400:
      #   Reads mepc into x28, clears MIE so we do not re-enter, writes
      #   back mepc (no skip -- the interrupted instruction will re-execute),
      #   then MRET.
      #
      # After handler return, all ADDIs must eventually commit.

      main_program = [
        # -- Setup trap vector --
        asm.addi(1, 0, 0x400),        # 0x00: x1 = handler address
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),       # 0x0C: mtvec = 0x400

        # -- Enable timer interrupt --
        asm.addi(1, 0, 0x80),         # 0x10: MTIE bit
        asm.csrrw(0, 0x304, 1),       # 0x14: mie = MTIE
        asm.addi(1, 0, 0x8),          # 0x18: MIE bit
        asm.csrrw(0, 0x300, 1),       # 0x1C: mstatus = MIE

        # -- Sequential computation that the interrupt will cut into --
        asm.addi(10, 0, 1),           # 0x20: x10 = 1
        asm.addi(11, 0, 2),           # 0x24: x11 = 2
        asm.addi(12, 0, 3),           # 0x28: x12 = 3
        asm.addi(13, 0, 4),           # 0x2C: x13 = 4
        asm.addi(14, 0, 5),           # 0x30: x14 = 5
        asm.add(15, 10, 11),          # 0x34: x15 = x10 + x11 = 3
        asm.add(16, 12, 13),          # 0x38: x16 = x12 + x13 = 7
        asm.add(17, 14, 15),          # 0x3C: x17 = x14 + x15 = 8
        asm.add(18, 16, 17),          # 0x40: x18 = x16 + x17 = 15
        asm.nop,                      # 0x44
        asm.nop,                      # 0x48
        asm.nop,                      # 0x4C
        asm.jal(0, 0),               # 0x50: spin
      ]

      trap_handler = [
        asm.csrrs(28, 0x341, 0),     # x28 = mepc (save for verification)
        asm.csrrs(29, 0x342, 0),     # x29 = mcause
        # Disable MIE to prevent re-entry
        asm.csrrw(30, 0x300, 0),     # x30 = old mstatus; mstatus = 0
        # Do not advance mepc -- the interrupted instruction re-executes
        asm.mret,
        asm.nop,
        asm.nop,
      ]

      # -- Single-cycle CPU --
      single = build_single
      single.load_program(main_program, 0)
      single.load_program(trap_handler, 0x400)
      single.reset!
      # Run past setup, into the computation
      single.run_cycles(12)
      single.set_interrupts(timer: true)
      # Let handler execute and return, then finish computation
      single.run_cycles(30)

      # -- Pipeline CPU (3x cycles) --
      pipeline = build_pipeline
      pipeline.load_program(main_program, 0)
      pipeline.load_program(trap_handler, 0x400)
      pipeline.reset!
      pipeline.run_cycles(30)
      pipeline.set_interrupts(timer: true)
      pipeline.run_cycles(80)

      # Computation registers must match (the interrupt fires at different
      # program points due to cycle-count differences, so mepc (x28) and
      # old mstatus (x30) naturally differ -- only compare results).
      computation_regs = [10, 11, 12, 13, 14, 15, 16, 17, 18]
      expect_subset_match(single, pipeline, computation_regs,
                          label: 'timer_mret: ')

      # Sanity: mcause should be machine timer interrupt
      expect(single.read_reg(29)).to eq(0x80000007)
      expect(pipeline.read_reg(29)).to eq(0x80000007)

      # The computation should have completed (x18 = 15)
      expect(single.read_reg(18)).to eq(15)
      expect(pipeline.read_reg(18)).to eq(15)
    end
  end

  # -----------------------------------------------------------------------
  # Test 2 -- Nested privilege mode transitions:
  #           M-mode -> S-mode (via MRET), ECALL in S-mode delegated to
  #           S-mode trap handler (via medeleg), SRET back to S-mode.
  # -----------------------------------------------------------------------
  describe 'nested privilege mode transitions M->S->ecall->S' do
    it 'matches register state after M->S via MRET, delegated ECALL, and SRET' do
      # M-mode setup at 0x000:
      #   - Set stvec to S-mode handler at 0x600
      #   - Delegate environment-call-from-S (code 9) to S-mode via medeleg
      #   - Set mstatus.MPP = S (01), set mepc = 0x100 (S-mode entry)
      #   - MRET -> drops to S-mode at 0x100
      #
      # S-mode code at 0x100:
      #   - Sets up registers, then ECALL (which is delegated to stvec)
      #   - After SRET, checks final register state
      #
      # S-mode trap handler at 0x600:
      #   - Reads scause, sepc, stval
      #   - Advances sepc by 4, then SRET

      m_mode_setup = [
        # Set stvec = 0x600 (S-mode trap handler)
        asm.addi(1, 0, 0x600),        # 0x00
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x105, 1),       # 0x0C: stvec = 0x600

        # Delegate ECALL from S-mode (exception code 9) to S-mode
        # medeleg bit 9 = 0x200
        asm.addi(1, 0, 0x200),        # 0x10
        asm.csrrw(0, 0x302, 1),       # 0x14: medeleg = 0x200

        # Set mstatus.MPP = S (bit 12:11 = 01 -> 0x800)
        asm.lui(1, 0x1),              # 0x18: x1 = 0x1000
        asm.addi(1, 1, -2048),        # 0x1C: x1 = 0x800
        asm.csrrw(0, 0x300, 1),       # 0x20: mstatus = 0x800

        # Set mepc = 0x100 (S-mode entry point)
        asm.addi(1, 0, 0x100),        # 0x24
        asm.csrrw(0, 0x341, 1),       # 0x28: mepc = 0x100

        # Drop to S-mode
        asm.mret,                     # 0x2C
        asm.nop,
        asm.nop,
      ]

      # S-mode code at 0x100
      s_mode_code = [
        asm.addi(10, 0, 42),          # 0x100: x10 = 42
        asm.addi(11, 0, 7),           # 0x104: x11 = 7
        asm.add(12, 10, 11),          # 0x108: x12 = 49
        asm.ecall,                    # 0x10C: delegated to stvec (S-mode handler)
        # -- resume here after SRET --
        asm.addi(13, 12, 1),          # 0x110: x13 = 50
        asm.add(14, 13, 11),          # 0x114: x14 = 57
        asm.nop,
        asm.nop,
        asm.nop,
        asm.jal(0, 0),               # spin
      ]

      # S-mode trap handler at 0x600
      s_trap_handler = [
        asm.csrrs(20, 0x142, 0),     # 0x600: x20 = scause
        asm.csrrs(21, 0x141, 0),     # 0x604: x21 = sepc
        asm.csrrs(22, 0x143, 0),     # 0x608: x22 = stval
        asm.csrrs(23, 0x100, 0),     # 0x60C: x23 = sstatus (in handler)
        asm.addi(21, 21, 4),         # 0x610: advance sepc past ECALL
        asm.csrrw(0, 0x141, 21),     # 0x614: sepc = sepc + 4
        asm.sret,                    # 0x618
        asm.nop,
        asm.nop,
      ]

      # -- Single-cycle CPU --
      single = build_single
      single.load_program(m_mode_setup, 0)
      single.load_program(s_mode_code, 0x100)
      single.load_program(s_trap_handler, 0x600)
      single.reset!
      single.run_cycles(30)

      # -- Pipeline CPU --
      pipeline = build_pipeline
      pipeline.load_program(m_mode_setup, 0)
      pipeline.load_program(s_mode_code, 0x100)
      pipeline.load_program(s_trap_handler, 0x600)
      pipeline.reset!
      pipeline.run_cycles(90)

      # Verify key registers match
      check_regs = [10, 11, 12, 13, 14, 20, 21, 22, 23]
      expect_subset_match(single, pipeline, check_regs,
                          label: 'priv_transition: ')

      # Sanity checks on the single-cycle result
      expect(single.read_reg(10)).to eq(42)
      expect(single.read_reg(12)).to eq(49)
      expect(single.read_reg(13)).to eq(50)
      expect(single.read_reg(14)).to eq(57)
      expect(single.read_reg(20)).to eq(9)    # scause = ecall from S-mode
      expect(single.read_reg(21)).to eq(0x110) # sepc was 0x10C, advanced by 4
    end
  end

  # -----------------------------------------------------------------------
  # Test 3 -- CSR read-modify-write (CSRRW/CSRRS) followed by timer
  #           interrupt.  Verify the interrupt sees the updated CSR values
  #           and all register state matches.
  # -----------------------------------------------------------------------
  describe 'CSR read-modify-write with timer interrupt' do
    it 'matches after CSRRW/CSRRS sequence interrupted by timer' do
      # Main program:
      #   - Write a known pattern to mscratch via CSRRW
      #   - Set bits in mscratch via CSRRS
      #   - Enable timer interrupt
      #   - Timer fires; handler reads mscratch to verify the CSR state
      #   - Handler disables MIE and returns via MRET
      #
      # Key CSR: mscratch = 0x340

      main_program = [
        # Set up mtvec
        asm.addi(1, 0, 0x400),        # 0x00
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),       # 0x0C: mtvec = 0x400

        # CSRRW: mscratch = 0xAA
        asm.addi(1, 0, 0xAA),         # 0x10: x1 = 0xAA
        asm.nop,
        asm.nop,
        asm.csrrw(2, 0x340, 1),       # 0x1C: x2 = old mscratch (0), mscratch = 0xAA

        # CSRRS: mscratch |= 0x55 -> mscratch = 0xFF
        asm.addi(3, 0, 0x55),         # 0x20: x3 = 0x55
        asm.nop,
        asm.nop,
        asm.csrrs(4, 0x340, 3),       # 0x2C: x4 = 0xAA (old), mscratch = 0xFF

        # Read back mscratch to confirm
        asm.csrrs(5, 0x340, 0),       # 0x30: x5 = 0xFF

        # Enable MTIE + MIE
        asm.addi(6, 0, 0x80),         # 0x34
        asm.csrrw(0, 0x304, 6),       # 0x38: mie = MTIE
        asm.addi(6, 0, 0x8),          # 0x3C
        asm.csrrw(0, 0x300, 6),       # 0x40: mstatus = MIE

        # Wait for interrupt
        asm.nop,                      # 0x44
        asm.nop,                      # 0x48
        asm.nop,                      # 0x4C
        asm.nop,                      # 0x50
        asm.jal(0, 0),               # 0x54: spin
      ]

      trap_handler = [
        # In handler: read mcause and mscratch
        asm.csrrs(20, 0x342, 0),     # x20 = mcause
        asm.csrrs(21, 0x340, 0),     # x21 = mscratch (should be 0xFF)
        asm.csrrs(22, 0x341, 0),     # x22 = mepc

        # Disable MIE to prevent re-entry
        asm.csrrw(23, 0x300, 0),     # x23 = old mstatus; mstatus = 0
        asm.mret,
        asm.nop,
        asm.nop,
      ]

      # -- Single-cycle --
      single = build_single
      single.load_program(main_program, 0)
      single.load_program(trap_handler, 0x400)
      single.reset!
      single.run_cycles(20)
      single.set_interrupts(timer: true)
      single.run_cycles(20)

      # -- Pipeline --
      pipeline = build_pipeline
      pipeline.load_program(main_program, 0)
      pipeline.load_program(trap_handler, 0x400)
      pipeline.reset!
      pipeline.run_cycles(50)
      pipeline.set_interrupts(timer: true)
      pipeline.run_cycles(60)

      # Compare CSR-result and interrupt-handler registers.  mepc (x22)
      # and old mstatus (x23) depend on interrupt timing and naturally differ
      # since the two CPUs run different cycle counts before the timer fires.
      csr_regs = [2, 3, 4, 5, 20, 21]
      expect_subset_match(single, pipeline, csr_regs, label: 'csr_rmw_irq: ')

      # Sanity: mscratch reads correct in both pre-interrupt and handler
      expect(single.read_reg(2)).to eq(0)       # old mscratch was 0
      expect(single.read_reg(4)).to eq(0xAA)    # before CSRRS set bits
      expect(single.read_reg(5)).to eq(0xFF)    # after CSRRS
      expect(single.read_reg(21)).to eq(0xFF)   # handler sees updated mscratch
      expect(single.read_reg(20)).to eq(0x80000007) # machine timer interrupt
    end
  end

  # -----------------------------------------------------------------------
  # Test 4 -- Load-store loop with a single-pulse timer interrupt.
  #           Accumulates values from memory while one interrupt fires.
  #           Both CPUs must produce identical final sums.
  # -----------------------------------------------------------------------
  describe 'load-store loop with single-pulse timer interrupt' do
    it 'matches accumulated sum when a timer interrupt fires during loop' do
      data_base = 0x1000
      array = [10, 20, 30, 40, 50, 60]
      expected_sum = array.sum  # 210

      main_program = [
        # -- Setup --
        asm.addi(1, 0, 0x400),        # 0x00: x1 = trap handler
        asm.nop,
        asm.nop,
        asm.csrrw(0, 0x305, 1),       # 0x0C: mtvec = 0x400
        asm.addi(1, 0, 0x80),         # 0x10: MTIE
        asm.csrrw(0, 0x304, 1),       # 0x14: mie = MTIE
        asm.addi(1, 0, 0x8),          # 0x18: MIE
        asm.csrrw(0, 0x300, 1),       # 0x1C: mstatus = MIE

        # x20 = sum (accumulator)
        # x21 = base address of data array
        # x23 = current index (0-based, scaled by 4)
        # x24 = array length * 4 (limit)
        asm.addi(20, 0, 0),           # 0x20: sum = 0
        asm.lui(21, 0x1),             # 0x24: x21 = 0x1000
        asm.addi(23, 0, 0),           # 0x28: index = 0
        asm.addi(24, 0, 24),          # 0x2C: limit = 6 * 4 = 24

        # -- Loop --
        # loop_top at 0x30:
        asm.beq(23, 24, 24),          # 0x30: if index == limit, goto done (+24 = 0x48)
        asm.add(25, 21, 23),          # 0x34: x25 = base + index
        asm.lw(26, 25, 0),            # 0x38: x26 = mem[x25]
        asm.add(20, 20, 26),          # 0x3C: sum += x26
        asm.addi(23, 23, 4),          # 0x40: index += 4
        asm.jal(0, -20),              # 0x44: jump back to loop_top (-20 = 0x30)
        # done at 0x48:
        asm.nop,                      # 0x48
        asm.nop,                      # 0x4C
        asm.jal(0, 0),               # 0x50: spin
      ]

      trap_handler = [
        # Count interrupts, read mcause, disable MIE, MRET.
        # MRET restores MPIE -> MIE; since MPIE was saved as 1 (MIE was
        # enabled when the trap was taken), MIE will be re-enabled after
        # MRET.  This is safe because the timer pin is cleared externally
        # before MRET executes.
        asm.addi(29, 29, 1),          # x29 += 1
        asm.csrrs(30, 0x342, 0),      # x30 = mcause
        asm.mret,
        asm.nop, asm.nop,
      ]

      # -- Single-cycle CPU --
      single = build_single
      single.load_program(main_program, 0)
      single.load_program(trap_handler, 0x400)
      single.reset!
      array.each_with_index { |val, i| write_data_word(single, data_base + i * 4, val) }

      # Setup phase, then pulse timer for 1 cycle during loop
      single.run_cycles(10)
      single.set_interrupts(timer: true)
      single.run_cycles(1)
      single.set_interrupts(timer: false)
      single.run_cycles(50)

      # -- Pipeline CPU (generous cycles) --
      pipeline = build_pipeline
      pipeline.load_program(main_program, 0)
      pipeline.load_program(trap_handler, 0x400)
      pipeline.reset!
      array.each_with_index { |val, i| write_data_word(pipeline, data_base + i * 4, val) }

      # Setup phase, then pulse timer for 1 cycle during loop
      pipeline.run_cycles(28)
      pipeline.set_interrupts(timer: true)
      pipeline.run_cycles(1)
      pipeline.set_interrupts(timer: false)
      pipeline.run_cycles(120)

      # The final sum must match
      expect(single.read_reg(20)).to eq(expected_sum)
      expect(pipeline.read_reg(20)).to eq(expected_sum),
        "sum mismatch: single=#{single.read_reg(20)} pipeline=#{pipeline.read_reg(20)}"

      # Both should have taken exactly 1 interrupt
      expect(single.read_reg(29)).to eq(1)
      expect(pipeline.read_reg(29)).to eq(1)

      # mcause should be machine timer interrupt
      expect(single.read_reg(30)).to eq(0x80000007)
    end
  end
end
