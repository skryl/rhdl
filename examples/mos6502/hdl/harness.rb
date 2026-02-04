# MOS 6502 Harness - Simulation Test Harness
# Wraps the synthesizable CPU for behavior simulation and testing
# Interacts with CPU only through ports - no direct access to internals
# Provides high-level methods for stepping, running, and debugging

require_relative '../../../lib/rhdl/hdl'
require_relative 'cpu'
require_relative 'memory'
require_relative '../../../spec/support/mos6502_assembler'

module RHDL
  module Examples
    module MOS6502
      # Simulation harness for the synthesizable CPU
      # All interaction with CPU is through ports only
      class Harness
    attr_reader :memory, :clock_count

    def initialize(memory = nil)
      @memory = memory || Memory.new("mem")
      @cpu = CPU.new("cpu")
      @clock_count = 0
      @halted = false
      @breakpoints = []

      reset
    end

    def reset
      @clock_count = 0
      @halted = false

      # Clear all external load enables
      clear_ext_loads

      # Pulse reset
      clock_cycle(rst: 1)
      # Need 6 cycles for reset_step to reach 5 and state to transition to FETCH
      5.times { clock_cycle(rst: 0) }

      # Now CPU is in STATE_FETCH. Load PC with reset vector value.
      # This clock cycle will:
      # 1. Load PC with the new address (via external load)
      # 2. Advance from FETCH to DECODE, but with opcode from new address
      lo = @memory.read(Memory::RESET_VECTOR)
      hi = @memory.read(Memory::RESET_VECTOR + 1)
      target_addr = (hi << 8) | lo

      @cpu.set_input(:ext_pc_load_data, target_addr)
      @cpu.set_input(:ext_pc_load_en, 1)

      # Do just the low phase to set up PC, then high phase will latch it
      # along with fetching the first opcode from the new address
      @cpu.set_input(:clk, 0)
      @cpu.propagate

      # Now set address bus to PC (target_addr) and provide correct data
      @memory.set_input(:addr, target_addr)
      @memory.set_input(:rw, 1)
      @memory.set_input(:cs, 1)
      @memory.propagate
      @cpu.set_input(:data_in, @memory.get_output(:data_out))

      @cpu.set_input(:clk, 1)
      @cpu.propagate
      @memory.propagate

      @clock_count += 1
      clear_ext_loads
    end

    def clock_cycle(rst: 0, rdy: 1, irq: 1, nmi: 1)
      # Get address from CPU (before clock)
      @cpu.set_input(:rst, rst)
      @cpu.set_input(:rdy, rdy)
      @cpu.set_input(:irq, irq)
      @cpu.set_input(:nmi, nmi)

      # Low clock phase
      @cpu.set_input(:clk, 0)
      @cpu.propagate

      addr = @cpu.get_output(:addr)
      rw = @cpu.get_output(:rw)

      # Memory operation
      @memory.set_input(:clk, 0)
      @memory.set_input(:addr, addr)
      @memory.set_input(:rw, rw)
      @memory.set_input(:cs, 1)

      if rw == 0  # Write
        data_out = @cpu.get_output(:data_out)
        @memory.set_input(:data_in, data_out)
      end

      @memory.propagate

      # High clock phase
      @cpu.set_input(:clk, 1)
      @memory.set_input(:clk, 1)

      # Read data from memory into CPU
      data_in = @memory.get_output(:data_out)
      @cpu.set_input(:data_in, data_in)

      @cpu.propagate
      @memory.propagate

      @clock_count += 1
      @halted = @cpu.get_output(:halted) == 1

      # Clear external load enables after the cycle completes
      clear_ext_loads
    end

    def step
      # Execute until instruction complete
      cycles = 0
      max_cycles = 20  # Safety limit
      prev_state = @cpu.get_output(:state)

      loop do
        clock_cycle
        cycles += 1

        state = @cpu.get_output(:state)

        # Instruction is complete when we transition TO FETCH from another state
        # (not when we're already in FETCH from the start)
        if state == ControlUnit::STATE_FETCH && prev_state != ControlUnit::STATE_FETCH
          break
        end

        prev_state = state
        break if cycles >= max_cycles || halted?
      end

      # Extra propagate to ensure output ports reflect final register values
      # (register writes happen during propagate, but outputs read pre-write values)
      @cpu.propagate

      cycles
    end

    def run(max_instructions = 1000)
      count = 0
      while count < max_instructions && !halted?
        step
        count += 1

        # Check breakpoints
        if @breakpoints.include?(pc)
          puts "Breakpoint hit at $#{format('%04X', pc)}"
          break
        end
      end
      count
    end

    def run_until(condition_proc, max_cycles = 100_000)
      cycles = 0
      while cycles < max_cycles && !halted?
        clock_cycle
        cycles += 1
        break if condition_proc.call(self)
      end
      cycles
    end

    def halted?
      @halted
    end

    # Register accessors - read through output ports
    def a; @cpu.get_output(:reg_a); end
    def x; @cpu.get_output(:reg_x); end
    def y; @cpu.get_output(:reg_y); end
    def sp; @cpu.get_output(:reg_sp); end
    def pc; @cpu.get_output(:reg_pc); end
    def p; @cpu.get_output(:reg_p); end

    # Register setters - use external load ports
    def a=(v)
      @cpu.set_input(:ext_a_load_data, v & 0xFF)
      @cpu.set_input(:ext_a_load_en, 1)
      clock_cycle
    end

    def x=(v)
      @cpu.set_input(:ext_x_load_data, v & 0xFF)
      @cpu.set_input(:ext_x_load_en, 1)
      clock_cycle
    end

    def y=(v)
      @cpu.set_input(:ext_y_load_data, v & 0xFF)
      @cpu.set_input(:ext_y_load_en, 1)
      clock_cycle
    end

    def sp=(v)
      @cpu.set_input(:ext_sp_load_data, v & 0xFF)
      @cpu.set_input(:ext_sp_load_en, 1)
      clock_cycle
    end

    def pc=(v)
      load_pc(v)
    end

    # Status flag accessors
    def flag_n; (p >> 7) & 1; end
    def flag_v; (p >> 6) & 1; end
    def flag_b; (p >> 4) & 1; end
    def flag_d; (p >> 3) & 1; end
    def flag_i; (p >> 2) & 1; end
    def flag_z; (p >> 1) & 1; end
    def flag_c; p & 1; end

    # Memory accessors
    def read_mem(addr)
      @memory.read(addr)
    end

    def write_mem(addr, value)
      @memory.write(addr, value)
    end

    def load_program(bytes, addr = 0x8000)
      @memory.load_program(bytes, addr)
      @memory.set_reset_vector(addr)
      # Do a full reset to properly initialize PC from reset vector
      reset
    end

    def assemble_and_load(source, addr = 0x8000)
      asm = Assembler.new
      bytes = asm.assemble(source, addr)
      load_program(bytes, addr)
      bytes
    end

    # Breakpoint support
    def add_breakpoint(addr)
      @breakpoints << addr unless @breakpoints.include?(addr)
    end

    def remove_breakpoint(addr)
      @breakpoints.delete(addr)
    end

    def clear_breakpoints
      @breakpoints.clear
    end

    # Debug output
    def state
      {
        a: a,
        x: x,
        y: y,
        sp: sp,
        pc: pc,
        p: p,
        n: flag_n,
        v: flag_v,
        b: flag_b,
        d: flag_d,
        i: flag_i,
        z: flag_z,
        c: flag_c,
        cycles: @clock_count,
        halted: halted?
      }
    end

    def status_string
      flags = ''
      flags += flag_n == 1 ? 'N' : 'n'
      flags += flag_v == 1 ? 'V' : 'v'
      flags += '-'
      flags += flag_b == 1 ? 'B' : 'b'
      flags += flag_d == 1 ? 'D' : 'd'
      flags += flag_i == 1 ? 'I' : 'i'
      flags += flag_z == 1 ? 'Z' : 'z'
      flags += flag_c == 1 ? 'C' : 'c'

      format("A:%02X X:%02X Y:%02X SP:%02X PC:%04X P:%02X [%s] Cycles:%d",
             a, x, y, sp, pc, p, flags, @clock_count)
    end

    def disassemble(addr, count = 1)
      Disassembler.disassemble(@memory, addr, count)
    end

    private

    def clear_ext_loads
      @cpu.set_input(:ext_pc_load_en, 0)
      @cpu.set_input(:ext_a_load_en, 0)
      @cpu.set_input(:ext_x_load_en, 0)
      @cpu.set_input(:ext_y_load_en, 0)
      @cpu.set_input(:ext_sp_load_en, 0)
    end

    def load_pc(addr)
      # Use external PC load port to set PC
      @cpu.set_input(:ext_pc_load_data, addr & 0xFFFF)
      @cpu.set_input(:ext_pc_load_en, 1)
      clock_cycle
    end
  end

    # Simple disassembler for debugging
    module Disassembler
    MNEMONICS = {
      0x00 => ['BRK', :imp], 0x01 => ['ORA', :indx], 0x05 => ['ORA', :zp],
      0x06 => ['ASL', :zp], 0x08 => ['PHP', :imp], 0x09 => ['ORA', :imm],
      0x0A => ['ASL', :acc], 0x0D => ['ORA', :abs], 0x0E => ['ASL', :abs],
      0x10 => ['BPL', :rel], 0x11 => ['ORA', :indy], 0x15 => ['ORA', :zpx],
      0x16 => ['ASL', :zpx], 0x18 => ['CLC', :imp], 0x19 => ['ORA', :absy],
      0x1D => ['ORA', :absx], 0x1E => ['ASL', :absx],
      0x20 => ['JSR', :abs], 0x21 => ['AND', :indx], 0x24 => ['BIT', :zp],
      0x25 => ['AND', :zp], 0x26 => ['ROL', :zp], 0x28 => ['PLP', :imp],
      0x29 => ['AND', :imm], 0x2A => ['ROL', :acc], 0x2C => ['BIT', :abs],
      0x2D => ['AND', :abs], 0x2E => ['ROL', :abs], 0x30 => ['BMI', :rel],
      0x31 => ['AND', :indy], 0x35 => ['AND', :zpx], 0x36 => ['ROL', :zpx],
      0x38 => ['SEC', :imp], 0x39 => ['AND', :absy], 0x3D => ['AND', :absx],
      0x3E => ['ROL', :absx],
      0x40 => ['RTI', :imp], 0x41 => ['EOR', :indx], 0x45 => ['EOR', :zp],
      0x46 => ['LSR', :zp], 0x48 => ['PHA', :imp], 0x49 => ['EOR', :imm],
      0x4A => ['LSR', :acc], 0x4C => ['JMP', :abs], 0x4D => ['EOR', :abs],
      0x4E => ['LSR', :abs], 0x50 => ['BVC', :rel], 0x51 => ['EOR', :indy],
      0x55 => ['EOR', :zpx], 0x56 => ['LSR', :zpx], 0x58 => ['CLI', :imp],
      0x59 => ['EOR', :absy], 0x5D => ['EOR', :absx], 0x5E => ['LSR', :absx],
      0x60 => ['RTS', :imp], 0x61 => ['ADC', :indx], 0x65 => ['ADC', :zp],
      0x66 => ['ROR', :zp], 0x68 => ['PLA', :imp], 0x69 => ['ADC', :imm],
      0x6A => ['ROR', :acc], 0x6C => ['JMP', :ind], 0x6D => ['ADC', :abs],
      0x6E => ['ROR', :abs], 0x70 => ['BVS', :rel], 0x71 => ['ADC', :indy],
      0x75 => ['ADC', :zpx], 0x76 => ['ROR', :zpx], 0x78 => ['SEI', :imp],
      0x79 => ['ADC', :absy], 0x7D => ['ADC', :absx], 0x7E => ['ROR', :absx],
      0x81 => ['STA', :indx], 0x84 => ['STY', :zp], 0x85 => ['STA', :zp],
      0x86 => ['STX', :zp], 0x88 => ['DEY', :imp], 0x8A => ['TXA', :imp],
      0x8C => ['STY', :abs], 0x8D => ['STA', :abs], 0x8E => ['STX', :abs],
      0x90 => ['BCC', :rel], 0x91 => ['STA', :indy], 0x94 => ['STY', :zpx],
      0x95 => ['STA', :zpx], 0x96 => ['STX', :zpy], 0x98 => ['TYA', :imp],
      0x99 => ['STA', :absy], 0x9A => ['TXS', :imp], 0x9D => ['STA', :absx],
      0xA0 => ['LDY', :imm], 0xA1 => ['LDA', :indx], 0xA2 => ['LDX', :imm],
      0xA4 => ['LDY', :zp], 0xA5 => ['LDA', :zp], 0xA6 => ['LDX', :zp],
      0xA8 => ['TAY', :imp], 0xA9 => ['LDA', :imm], 0xAA => ['TAX', :imp],
      0xAC => ['LDY', :abs], 0xAD => ['LDA', :abs], 0xAE => ['LDX', :abs],
      0xB0 => ['BCS', :rel], 0xB1 => ['LDA', :indy], 0xB4 => ['LDY', :zpx],
      0xB5 => ['LDA', :zpx], 0xB6 => ['LDX', :zpy], 0xB8 => ['CLV', :imp],
      0xB9 => ['LDA', :absy], 0xBA => ['TSX', :imp], 0xBC => ['LDY', :absx],
      0xBD => ['LDA', :absx], 0xBE => ['LDX', :absy],
      0xC0 => ['CPY', :imm], 0xC1 => ['CMP', :indx], 0xC4 => ['CPY', :zp],
      0xC5 => ['CMP', :zp], 0xC6 => ['DEC', :zp], 0xC8 => ['INY', :imp],
      0xC9 => ['CMP', :imm], 0xCA => ['DEX', :imp], 0xCC => ['CPY', :abs],
      0xCD => ['CMP', :abs], 0xCE => ['DEC', :abs], 0xD0 => ['BNE', :rel],
      0xD1 => ['CMP', :indy], 0xD5 => ['CMP', :zpx], 0xD6 => ['DEC', :zpx],
      0xD8 => ['CLD', :imp], 0xD9 => ['CMP', :absy], 0xDD => ['CMP', :absx],
      0xDE => ['DEC', :absx],
      0xE0 => ['CPX', :imm], 0xE1 => ['SBC', :indx], 0xE4 => ['CPX', :zp],
      0xE5 => ['SBC', :zp], 0xE6 => ['INC', :zp], 0xE8 => ['INX', :imp],
      0xE9 => ['SBC', :imm], 0xEA => ['NOP', :imp], 0xEC => ['CPX', :abs],
      0xED => ['SBC', :abs], 0xEE => ['INC', :abs], 0xF0 => ['BEQ', :rel],
      0xF1 => ['SBC', :indy], 0xF5 => ['SBC', :zpx], 0xF6 => ['INC', :zpx],
      0xF8 => ['SED', :imp], 0xF9 => ['SBC', :absy], 0xFD => ['SBC', :absx],
      0xFE => ['INC', :absx]
    }

    def self.disassemble(memory, addr, count)
      lines = []
      current_addr = addr

      count.times do
        opcode = memory.read(current_addr)
        info = MNEMONICS[opcode]

        if info
          mnemonic, mode = info
          bytes, operand_str = format_operand(memory, current_addr, mode)
          hex = (0...bytes).map { |i| format('%02X', memory.read(current_addr + i)) }.join(' ')
          lines << format('%04X: %-9s %s %s', current_addr, hex, mnemonic, operand_str)
          current_addr += bytes
        else
          lines << format('%04X: %02X        ???', current_addr, opcode)
          current_addr += 1
        end
      end

      lines.join("\n")
    end

    def self.format_operand(memory, addr, mode)
      case mode
      when :imp then [1, '']
      when :acc then [1, 'A']
      when :imm then [2, format('#$%02X', memory.read(addr + 1))]
      when :zp then [2, format('$%02X', memory.read(addr + 1))]
      when :zpx then [2, format('$%02X,X', memory.read(addr + 1))]
      when :zpy then [2, format('$%02X,Y', memory.read(addr + 1))]
      when :abs
        lo = memory.read(addr + 1)
        hi = memory.read(addr + 2)
        [3, format('$%04X', (hi << 8) | lo)]
      when :absx
        lo = memory.read(addr + 1)
        hi = memory.read(addr + 2)
        [3, format('$%04X,X', (hi << 8) | lo)]
      when :absy
        lo = memory.read(addr + 1)
        hi = memory.read(addr + 2)
        [3, format('$%04X,Y', (hi << 8) | lo)]
      when :ind
        lo = memory.read(addr + 1)
        hi = memory.read(addr + 2)
        [3, format('($%04X)', (hi << 8) | lo)]
      when :indx then [2, format('($%02X,X)', memory.read(addr + 1))]
      when :indy then [2, format('($%02X),Y', memory.read(addr + 1))]
      when :rel
        offset = memory.read(addr + 1)
        offset = offset - 256 if offset > 127
        target = (addr + 2 + offset) & 0xFFFF
        [2, format('$%04X', target)]
      else [1, '']
      end
    end
    end
  end
end
end
