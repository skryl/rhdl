# frozen_string_literal: true

# MOS 6502 ISA-Level Simulator
# Fast instruction-level simulator for performance-critical applications
# Executes instructions directly without HDL simulation overhead

module MOS6502
  class ISASimulator
    # Status flag bit positions
    FLAG_C = 0  # Carry
    FLAG_Z = 1  # Zero
    FLAG_I = 2  # Interrupt Disable
    FLAG_D = 3  # Decimal Mode
    FLAG_B = 4  # Break
    FLAG_U = 5  # Unused (always 1)
    FLAG_V = 6  # Overflow
    FLAG_N = 7  # Negative

    # Interrupt vectors
    NMI_VECTOR   = 0xFFFA
    RESET_VECTOR = 0xFFFC
    IRQ_VECTOR   = 0xFFFE

    attr_reader :a, :x, :y, :sp, :pc, :p, :cycles, :halted
    attr_accessor :memory

    def initialize(memory = nil)
      @memory = memory || Array.new(0x10000, 0)
      reset
    end

    def reset
      @a = 0
      @x = 0
      @y = 0
      @sp = 0xFD
      @p = 0x24  # Unused flag set, Interrupt disable set
      @pc = read_word(RESET_VECTOR)
      @cycles = 0
      @halted = false
    end

    # Execute one instruction and return cycles taken
    def step
      return 0 if @halted

      opcode = fetch_byte
      execute(opcode)
    end

    # Execute multiple instructions
    def run(max_instructions = 1000)
      count = 0
      while count < max_instructions && !@halted
        step
        count += 1
      end
      count
    end

    # Execute for a number of cycles (approximate - will complete current instruction)
    def run_cycles(target_cycles)
      start_cycles = @cycles
      while (@cycles - start_cycles) < target_cycles && !@halted
        step
      end
      @cycles - start_cycles
    end

    # Register accessors (write)
    def a=(v); @a = v & 0xFF; end
    def x=(v); @x = v & 0xFF; end
    def y=(v); @y = v & 0xFF; end
    def sp=(v); @sp = v & 0xFF; end
    def pc=(v); @pc = v & 0xFFFF; end
    def p=(v); @p = (v & 0xFF) | 0x20; end  # Unused flag always 1

    # Flag accessors
    def flag_c; (@p >> FLAG_C) & 1; end
    def flag_z; (@p >> FLAG_Z) & 1; end
    def flag_i; (@p >> FLAG_I) & 1; end
    def flag_d; (@p >> FLAG_D) & 1; end
    def flag_b; (@p >> FLAG_B) & 1; end
    def flag_v; (@p >> FLAG_V) & 1; end
    def flag_n; (@p >> FLAG_N) & 1; end

    def set_flag(flag, value)
      if value != 0
        @p |= (1 << flag)
      else
        @p &= ~(1 << flag)
      end
    end

    # Memory operations
    def read(addr)
      addr &= 0xFFFF
      if @memory.is_a?(Array)
        @memory[addr] || 0
      else
        @memory.read(addr)
      end
    end

    def write(addr, value)
      addr &= 0xFFFF
      value &= 0xFF
      if @memory.is_a?(Array)
        @memory[addr] = value
      else
        @memory.write(addr, value)
      end
    end

    def read_word(addr)
      lo = read(addr)
      hi = read(addr + 1)
      (hi << 8) | lo
    end

    def load_program(bytes, addr = 0x8000)
      bytes.each_with_index do |byte, i|
        write(addr + i, byte)
      end
      # Set reset vector
      write(RESET_VECTOR, addr & 0xFF)
      write(RESET_VECTOR + 1, (addr >> 8) & 0xFF)
    end

    # State inspection
    def state
      {
        a: @a, x: @x, y: @y, sp: @sp, pc: @pc, p: @p,
        n: flag_n, v: flag_v, b: flag_b, d: flag_d,
        i: flag_i, z: flag_z, c: flag_c,
        cycles: @cycles, halted: @halted
      }
    end

    def halted?
      @halted
    end

    private

    def fetch_byte
      byte = read(@pc)
      @pc = (@pc + 1) & 0xFFFF
      byte
    end

    def fetch_word
      lo = fetch_byte
      hi = fetch_byte
      (hi << 8) | lo
    end

    # Stack operations
    def push_byte(value)
      write(0x100 + @sp, value)
      @sp = (@sp - 1) & 0xFF
    end

    def pull_byte
      @sp = (@sp + 1) & 0xFF
      read(0x100 + @sp)
    end

    def push_word(value)
      push_byte((value >> 8) & 0xFF)
      push_byte(value & 0xFF)
    end

    def pull_word
      lo = pull_byte
      hi = pull_byte
      (hi << 8) | lo
    end

    # Flag helpers
    def set_nz(value)
      set_flag(FLAG_Z, (value & 0xFF) == 0 ? 1 : 0)
      set_flag(FLAG_N, (value & 0x80) != 0 ? 1 : 0)
      value & 0xFF
    end

    # Addressing modes - return address
    def addr_immediate
      addr = @pc
      @pc = (@pc + 1) & 0xFFFF
      addr
    end

    def addr_zero_page
      fetch_byte
    end

    def addr_zero_page_x
      (fetch_byte + @x) & 0xFF
    end

    def addr_zero_page_y
      (fetch_byte + @y) & 0xFF
    end

    def addr_absolute
      fetch_word
    end

    def addr_absolute_x(check_page_cross = true)
      base = fetch_word
      addr = (base + @x) & 0xFFFF
      @cycles += 1 if check_page_cross && (base & 0xFF00) != (addr & 0xFF00)
      addr
    end

    def addr_absolute_y(check_page_cross = true)
      base = fetch_word
      addr = (base + @y) & 0xFFFF
      @cycles += 1 if check_page_cross && (base & 0xFF00) != (addr & 0xFF00)
      addr
    end

    def addr_indirect
      ptr = fetch_word
      # 6502 indirect JMP bug: if ptr is at xxFF, high byte comes from xx00
      lo = read(ptr)
      hi_addr = (ptr & 0xFF) == 0xFF ? (ptr & 0xFF00) : (ptr + 1)
      hi = read(hi_addr)
      (hi << 8) | lo
    end

    def addr_indexed_indirect  # (zp,X)
      ptr = (fetch_byte + @x) & 0xFF
      lo = read(ptr)
      hi = read((ptr + 1) & 0xFF)
      (hi << 8) | lo
    end

    def addr_indirect_indexed(check_page_cross = true)  # (zp),Y
      ptr = fetch_byte
      lo = read(ptr)
      hi = read((ptr + 1) & 0xFF)
      base = (hi << 8) | lo
      addr = (base + @y) & 0xFFFF
      @cycles += 1 if check_page_cross && (base & 0xFF00) != (addr & 0xFF00)
      addr
    end

    def addr_relative
      offset = fetch_byte
      offset = offset - 256 if offset > 127
      (@pc + offset) & 0xFFFF
    end

    # ALU operations
    def do_adc(value)
      if flag_d == 1
        # Decimal mode
        lo = (@a & 0x0F) + (value & 0x0F) + flag_c
        hi = (@a >> 4) + (value >> 4)
        hi += 1 if lo > 9
        lo -= 10 if lo > 9
        hi += 1 if hi > 9
        set_flag(FLAG_C, hi > 9 ? 1 : 0)
        hi -= 10 if hi > 9
        result = ((hi << 4) | (lo & 0x0F)) & 0xFF
        set_flag(FLAG_Z, result == 0 ? 1 : 0)
        set_flag(FLAG_N, (result & 0x80) != 0 ? 1 : 0)
        # V flag in decimal mode is undefined on NMOS 6502
        @a = result
      else
        # Binary mode
        sum = @a + value + flag_c
        overflow = (~(@a ^ value) & (@a ^ sum) & 0x80) != 0
        set_flag(FLAG_C, sum > 0xFF ? 1 : 0)
        set_flag(FLAG_V, overflow ? 1 : 0)
        @a = set_nz(sum)
      end
    end

    def do_sbc(value)
      if flag_d == 1
        # Decimal mode
        lo = (@a & 0x0F) - (value & 0x0F) - (1 - flag_c)
        hi = (@a >> 4) - (value >> 4)
        if lo < 0
          lo += 10
          hi -= 1
        end
        if hi < 0
          hi += 10
          set_flag(FLAG_C, 0)
        else
          set_flag(FLAG_C, 1)
        end
        result = ((hi << 4) | (lo & 0x0F)) & 0xFF
        set_flag(FLAG_Z, result == 0 ? 1 : 0)
        set_flag(FLAG_N, (result & 0x80) != 0 ? 1 : 0)
        @a = result
      else
        # Binary mode (SBC is ADC with inverted operand)
        do_adc(value ^ 0xFF)
      end
    end

    def do_cmp(reg_value, mem_value)
      result = reg_value - mem_value
      set_flag(FLAG_C, reg_value >= mem_value ? 1 : 0)
      set_nz(result)
    end

    def do_asl(value)
      set_flag(FLAG_C, (value & 0x80) != 0 ? 1 : 0)
      set_nz(value << 1)
    end

    def do_lsr(value)
      set_flag(FLAG_C, value & 1)
      set_nz(value >> 1)
    end

    def do_rol(value)
      carry = flag_c
      set_flag(FLAG_C, (value & 0x80) != 0 ? 1 : 0)
      set_nz((value << 1) | carry)
    end

    def do_ror(value)
      carry = flag_c
      set_flag(FLAG_C, value & 1)
      set_nz((value >> 1) | (carry << 7))
    end

    # Branch helper
    def branch_if(condition)
      target = addr_relative
      if condition
        @cycles += 1
        @cycles += 1 if (@pc & 0xFF00) != (target & 0xFF00)
        @pc = target
      end
    end

    # Main instruction executor
    def execute(opcode)
      case opcode
      # ADC - Add with Carry
      when 0x69 then @cycles += 2; do_adc(read(addr_immediate))
      when 0x65 then @cycles += 3; do_adc(read(addr_zero_page))
      when 0x75 then @cycles += 4; do_adc(read(addr_zero_page_x))
      when 0x6D then @cycles += 4; do_adc(read(addr_absolute))
      when 0x7D then @cycles += 4; do_adc(read(addr_absolute_x))
      when 0x79 then @cycles += 4; do_adc(read(addr_absolute_y))
      when 0x61 then @cycles += 6; do_adc(read(addr_indexed_indirect))
      when 0x71 then @cycles += 5; do_adc(read(addr_indirect_indexed))

      # SBC - Subtract with Carry
      when 0xE9 then @cycles += 2; do_sbc(read(addr_immediate))
      when 0xE5 then @cycles += 3; do_sbc(read(addr_zero_page))
      when 0xF5 then @cycles += 4; do_sbc(read(addr_zero_page_x))
      when 0xED then @cycles += 4; do_sbc(read(addr_absolute))
      when 0xFD then @cycles += 4; do_sbc(read(addr_absolute_x))
      when 0xF9 then @cycles += 4; do_sbc(read(addr_absolute_y))
      when 0xE1 then @cycles += 6; do_sbc(read(addr_indexed_indirect))
      when 0xF1 then @cycles += 5; do_sbc(read(addr_indirect_indexed))

      # AND - Logical AND
      when 0x29 then @cycles += 2; @a = set_nz(@a & read(addr_immediate))
      when 0x25 then @cycles += 3; @a = set_nz(@a & read(addr_zero_page))
      when 0x35 then @cycles += 4; @a = set_nz(@a & read(addr_zero_page_x))
      when 0x2D then @cycles += 4; @a = set_nz(@a & read(addr_absolute))
      when 0x3D then @cycles += 4; @a = set_nz(@a & read(addr_absolute_x))
      when 0x39 then @cycles += 4; @a = set_nz(@a & read(addr_absolute_y))
      when 0x21 then @cycles += 6; @a = set_nz(@a & read(addr_indexed_indirect))
      when 0x31 then @cycles += 5; @a = set_nz(@a & read(addr_indirect_indexed))

      # ORA - Logical OR
      when 0x09 then @cycles += 2; @a = set_nz(@a | read(addr_immediate))
      when 0x05 then @cycles += 3; @a = set_nz(@a | read(addr_zero_page))
      when 0x15 then @cycles += 4; @a = set_nz(@a | read(addr_zero_page_x))
      when 0x0D then @cycles += 4; @a = set_nz(@a | read(addr_absolute))
      when 0x1D then @cycles += 4; @a = set_nz(@a | read(addr_absolute_x))
      when 0x19 then @cycles += 4; @a = set_nz(@a | read(addr_absolute_y))
      when 0x01 then @cycles += 6; @a = set_nz(@a | read(addr_indexed_indirect))
      when 0x11 then @cycles += 5; @a = set_nz(@a | read(addr_indirect_indexed))

      # EOR - Exclusive OR
      when 0x49 then @cycles += 2; @a = set_nz(@a ^ read(addr_immediate))
      when 0x45 then @cycles += 3; @a = set_nz(@a ^ read(addr_zero_page))
      when 0x55 then @cycles += 4; @a = set_nz(@a ^ read(addr_zero_page_x))
      when 0x4D then @cycles += 4; @a = set_nz(@a ^ read(addr_absolute))
      when 0x5D then @cycles += 4; @a = set_nz(@a ^ read(addr_absolute_x))
      when 0x59 then @cycles += 4; @a = set_nz(@a ^ read(addr_absolute_y))
      when 0x41 then @cycles += 6; @a = set_nz(@a ^ read(addr_indexed_indirect))
      when 0x51 then @cycles += 5; @a = set_nz(@a ^ read(addr_indirect_indexed))

      # CMP - Compare Accumulator
      when 0xC9 then @cycles += 2; do_cmp(@a, read(addr_immediate))
      when 0xC5 then @cycles += 3; do_cmp(@a, read(addr_zero_page))
      when 0xD5 then @cycles += 4; do_cmp(@a, read(addr_zero_page_x))
      when 0xCD then @cycles += 4; do_cmp(@a, read(addr_absolute))
      when 0xDD then @cycles += 4; do_cmp(@a, read(addr_absolute_x))
      when 0xD9 then @cycles += 4; do_cmp(@a, read(addr_absolute_y))
      when 0xC1 then @cycles += 6; do_cmp(@a, read(addr_indexed_indirect))
      when 0xD1 then @cycles += 5; do_cmp(@a, read(addr_indirect_indexed))

      # CPX - Compare X Register
      when 0xE0 then @cycles += 2; do_cmp(@x, read(addr_immediate))
      when 0xE4 then @cycles += 3; do_cmp(@x, read(addr_zero_page))
      when 0xEC then @cycles += 4; do_cmp(@x, read(addr_absolute))

      # CPY - Compare Y Register
      when 0xC0 then @cycles += 2; do_cmp(@y, read(addr_immediate))
      when 0xC4 then @cycles += 3; do_cmp(@y, read(addr_zero_page))
      when 0xCC then @cycles += 4; do_cmp(@y, read(addr_absolute))

      # BIT - Bit Test
      when 0x24
        @cycles += 3
        value = read(addr_zero_page)
        set_flag(FLAG_Z, (@a & value) == 0 ? 1 : 0)
        set_flag(FLAG_N, (value & 0x80) != 0 ? 1 : 0)
        set_flag(FLAG_V, (value & 0x40) != 0 ? 1 : 0)
      when 0x2C
        @cycles += 4
        value = read(addr_absolute)
        set_flag(FLAG_Z, (@a & value) == 0 ? 1 : 0)
        set_flag(FLAG_N, (value & 0x80) != 0 ? 1 : 0)
        set_flag(FLAG_V, (value & 0x40) != 0 ? 1 : 0)

      # LDA - Load Accumulator
      when 0xA9 then @cycles += 2; @a = set_nz(read(addr_immediate))
      when 0xA5 then @cycles += 3; @a = set_nz(read(addr_zero_page))
      when 0xB5 then @cycles += 4; @a = set_nz(read(addr_zero_page_x))
      when 0xAD then @cycles += 4; @a = set_nz(read(addr_absolute))
      when 0xBD then @cycles += 4; @a = set_nz(read(addr_absolute_x))
      when 0xB9 then @cycles += 4; @a = set_nz(read(addr_absolute_y))
      when 0xA1 then @cycles += 6; @a = set_nz(read(addr_indexed_indirect))
      when 0xB1 then @cycles += 5; @a = set_nz(read(addr_indirect_indexed))

      # LDX - Load X Register
      when 0xA2 then @cycles += 2; @x = set_nz(read(addr_immediate))
      when 0xA6 then @cycles += 3; @x = set_nz(read(addr_zero_page))
      when 0xB6 then @cycles += 4; @x = set_nz(read(addr_zero_page_y))
      when 0xAE then @cycles += 4; @x = set_nz(read(addr_absolute))
      when 0xBE then @cycles += 4; @x = set_nz(read(addr_absolute_y))

      # LDY - Load Y Register
      when 0xA0 then @cycles += 2; @y = set_nz(read(addr_immediate))
      when 0xA4 then @cycles += 3; @y = set_nz(read(addr_zero_page))
      when 0xB4 then @cycles += 4; @y = set_nz(read(addr_zero_page_x))
      when 0xAC then @cycles += 4; @y = set_nz(read(addr_absolute))
      when 0xBC then @cycles += 4; @y = set_nz(read(addr_absolute_x))

      # STA - Store Accumulator
      when 0x85 then @cycles += 3; write(addr_zero_page, @a)
      when 0x95 then @cycles += 4; write(addr_zero_page_x, @a)
      when 0x8D then @cycles += 4; write(addr_absolute, @a)
      when 0x9D then @cycles += 5; write(addr_absolute_x(false), @a)
      when 0x99 then @cycles += 5; write(addr_absolute_y(false), @a)
      when 0x81 then @cycles += 6; write(addr_indexed_indirect, @a)
      when 0x91 then @cycles += 6; write(addr_indirect_indexed(false), @a)

      # STX - Store X Register
      when 0x86 then @cycles += 3; write(addr_zero_page, @x)
      when 0x96 then @cycles += 4; write(addr_zero_page_y, @x)
      when 0x8E then @cycles += 4; write(addr_absolute, @x)

      # STY - Store Y Register
      when 0x84 then @cycles += 3; write(addr_zero_page, @y)
      when 0x94 then @cycles += 4; write(addr_zero_page_x, @y)
      when 0x8C then @cycles += 4; write(addr_absolute, @y)

      # Register Transfers
      when 0xAA then @cycles += 2; @x = set_nz(@a)  # TAX
      when 0x8A then @cycles += 2; @a = set_nz(@x)  # TXA
      when 0xA8 then @cycles += 2; @y = set_nz(@a)  # TAY
      when 0x98 then @cycles += 2; @a = set_nz(@y)  # TYA
      when 0xBA then @cycles += 2; @x = set_nz(@sp) # TSX
      when 0x9A then @cycles += 2; @sp = @x        # TXS (doesn't affect flags)

      # Increment/Decrement Register
      when 0xE8 then @cycles += 2; @x = set_nz(@x + 1)  # INX
      when 0xCA then @cycles += 2; @x = set_nz(@x - 1)  # DEX
      when 0xC8 then @cycles += 2; @y = set_nz(@y + 1)  # INY
      when 0x88 then @cycles += 2; @y = set_nz(@y - 1)  # DEY

      # Increment Memory
      when 0xE6
        @cycles += 5; addr = addr_zero_page
        write(addr, set_nz(read(addr) + 1))
      when 0xF6
        @cycles += 6; addr = addr_zero_page_x
        write(addr, set_nz(read(addr) + 1))
      when 0xEE
        @cycles += 6; addr = addr_absolute
        write(addr, set_nz(read(addr) + 1))
      when 0xFE
        @cycles += 7; addr = addr_absolute_x(false)
        write(addr, set_nz(read(addr) + 1))

      # Decrement Memory
      when 0xC6
        @cycles += 5; addr = addr_zero_page
        write(addr, set_nz(read(addr) - 1))
      when 0xD6
        @cycles += 6; addr = addr_zero_page_x
        write(addr, set_nz(read(addr) - 1))
      when 0xCE
        @cycles += 6; addr = addr_absolute
        write(addr, set_nz(read(addr) - 1))
      when 0xDE
        @cycles += 7; addr = addr_absolute_x(false)
        write(addr, set_nz(read(addr) - 1))

      # ASL - Arithmetic Shift Left
      when 0x0A then @cycles += 2; @a = do_asl(@a)
      when 0x06
        @cycles += 5; addr = addr_zero_page
        write(addr, do_asl(read(addr)))
      when 0x16
        @cycles += 6; addr = addr_zero_page_x
        write(addr, do_asl(read(addr)))
      when 0x0E
        @cycles += 6; addr = addr_absolute
        write(addr, do_asl(read(addr)))
      when 0x1E
        @cycles += 7; addr = addr_absolute_x(false)
        write(addr, do_asl(read(addr)))

      # LSR - Logical Shift Right
      when 0x4A then @cycles += 2; @a = do_lsr(@a)
      when 0x46
        @cycles += 5; addr = addr_zero_page
        write(addr, do_lsr(read(addr)))
      when 0x56
        @cycles += 6; addr = addr_zero_page_x
        write(addr, do_lsr(read(addr)))
      when 0x4E
        @cycles += 6; addr = addr_absolute
        write(addr, do_lsr(read(addr)))
      when 0x5E
        @cycles += 7; addr = addr_absolute_x(false)
        write(addr, do_lsr(read(addr)))

      # ROL - Rotate Left
      when 0x2A then @cycles += 2; @a = do_rol(@a)
      when 0x26
        @cycles += 5; addr = addr_zero_page
        write(addr, do_rol(read(addr)))
      when 0x36
        @cycles += 6; addr = addr_zero_page_x
        write(addr, do_rol(read(addr)))
      when 0x2E
        @cycles += 6; addr = addr_absolute
        write(addr, do_rol(read(addr)))
      when 0x3E
        @cycles += 7; addr = addr_absolute_x(false)
        write(addr, do_rol(read(addr)))

      # ROR - Rotate Right
      when 0x6A then @cycles += 2; @a = do_ror(@a)
      when 0x66
        @cycles += 5; addr = addr_zero_page
        write(addr, do_ror(read(addr)))
      when 0x76
        @cycles += 6; addr = addr_zero_page_x
        write(addr, do_ror(read(addr)))
      when 0x6E
        @cycles += 6; addr = addr_absolute
        write(addr, do_ror(read(addr)))
      when 0x7E
        @cycles += 7; addr = addr_absolute_x(false)
        write(addr, do_ror(read(addr)))

      # Branches
      when 0x10 then @cycles += 2; branch_if(flag_n == 0)  # BPL
      when 0x30 then @cycles += 2; branch_if(flag_n == 1)  # BMI
      when 0x50 then @cycles += 2; branch_if(flag_v == 0)  # BVC
      when 0x70 then @cycles += 2; branch_if(flag_v == 1)  # BVS
      when 0x90 then @cycles += 2; branch_if(flag_c == 0)  # BCC
      when 0xB0 then @cycles += 2; branch_if(flag_c == 1)  # BCS
      when 0xD0 then @cycles += 2; branch_if(flag_z == 0)  # BNE
      when 0xF0 then @cycles += 2; branch_if(flag_z == 1)  # BEQ

      # JMP - Jump
      when 0x4C then @cycles += 3; @pc = addr_absolute
      when 0x6C then @cycles += 5; @pc = addr_indirect

      # JSR - Jump to Subroutine
      when 0x20
        @cycles += 6
        target = addr_absolute
        push_word(@pc - 1)
        @pc = target

      # RTS - Return from Subroutine
      when 0x60
        @cycles += 6
        @pc = (pull_word + 1) & 0xFFFF

      # RTI - Return from Interrupt
      when 0x40
        @cycles += 6
        @p = pull_byte | 0x20  # Unused flag always 1
        @pc = pull_word

      # Stack Operations
      when 0x48 then @cycles += 3; push_byte(@a)  # PHA
      when 0x08 then @cycles += 3; push_byte(@p | 0x10)  # PHP (B flag set when pushed)
      when 0x68 then @cycles += 4; @a = set_nz(pull_byte)  # PLA
      when 0x28 then @cycles += 4; @p = pull_byte | 0x20  # PLP

      # Flag Operations
      when 0x18 then @cycles += 2; set_flag(FLAG_C, 0)  # CLC
      when 0x38 then @cycles += 2; set_flag(FLAG_C, 1)  # SEC
      when 0x58 then @cycles += 2; set_flag(FLAG_I, 0)  # CLI
      when 0x78 then @cycles += 2; set_flag(FLAG_I, 1)  # SEI
      when 0xB8 then @cycles += 2; set_flag(FLAG_V, 0)  # CLV
      when 0xD8 then @cycles += 2; set_flag(FLAG_D, 0)  # CLD
      when 0xF8 then @cycles += 2; set_flag(FLAG_D, 1)  # SED

      # NOP
      when 0xEA then @cycles += 2

      # BRK - Break
      when 0x00
        @cycles += 7
        @pc = (@pc + 1) & 0xFFFF  # BRK skips a byte
        push_word(@pc)
        push_byte(@p | 0x10)  # B flag set when pushed
        set_flag(FLAG_I, 1)
        @pc = read_word(IRQ_VECTOR)

      else
        # Illegal opcode - halt
        @halted = true
        @cycles += 2
      end

      @cycles
    end
  end
end
