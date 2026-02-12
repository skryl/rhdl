require_relative '../../examples/8bit/utilities/isa_simulator'

module CpuTestHelper
  # Set this to switch between behavior and HDL CPU implementations
  # Override in specific test files or use shared examples
  def cpu_class
    @cpu_class || RHDL::HDL::CPU::Harness
  end

  def use_hdl_cpu!
    @cpu_class = RHDL::HDL::CPU::Harness
  end

  def use_behavior_cpu!
    @cpu_class = RHDL::Components::CPU::CPU
  end

  def create_test_program(instructions)
    instructions.flat_map do |instr|
      if instr.is_a?(Array)
        opcode = instr[0]
        operand1 = instr[1] || 0
        operand2 = instr[2] || 0
        if opcode == :STA && instr[2]
          [0x20, operand1, operand2]  # 3-byte STA instruction
        else
          encode_instruction(opcode, operand1)
        end
      else
        encode_instruction(instr, 0)
      end
    end
  end

  def encode_instruction(opcode, operand)
    # Handle indirect addressing for STA
    if opcode == :STA && operand.is_a?(Array)
      return [0x20, operand[0], operand[1]]  # 3-byte indirect STA
    end

    # Handle STA specially: 0x20 is indirect, 0x21 is 2-byte direct
    # Only addresses 2-15 can use nibble encoding (0x22-0x2F)
    if opcode == :STA
      if operand.is_a?(Integer) && operand >= 2 && operand <= 0x0F
        # Nibble-encoded: 0x22-0x2F
        return 0x20 | (operand & 0x0F)
      else
        # 2-byte direct STA: 0x21 + operand
        return [0x21, operand & 0xFF]
      end
    end

    opcode_value = case opcode
    when :NOP  then 0x00
    when :LDA  then 0x10
    when :STA  then 0x20  # Direct STA (nibble-encoded)
    when :ADD  then 0x30
    when :SUB  then 0x40
    when :AND  then 0x50
    when :OR   then 0x60
    when :XOR  then 0x70
    when :JZ   then 0x80
    when :JNZ  then 0x90
    when :LDI  then 0xA0
    when :JMP  then 0xB0
    when :CALL then 0xC0
    when :RET  then 0xD0
    when :DIV  then 0xE0
    when :HLT  then 0xF0
    when :MUL  then 0xF1
    when :NOT  then 0xF2
    when :JZ_LONG   then 0xF8
    when :JMP_LONG  then 0xF9
    when :JNZ_LONG  then 0xFA
    when :CMP  then 0xF3
    else
      raise "Unknown opcode: #{opcode}"
    end

    if [:LDI, :MUL, :JZ_LONG, :JMP_LONG, :JNZ_LONG].include?(opcode)
      [opcode_value, operand & 0xFF]
    else
      opcode_value | (operand & 0x0F)
    end
  end

  def load_program(program, start_addr = 0)
    @cpu = cpu_class.new(@memory)
    # Clear any previous memory values
    (0..0xFFF).each { |addr| @memory.write(addr, 0x00) }
    setup_test_values

    instructions = if program.first.is_a?(Array) || program.first.is_a?(Symbol)
                    create_test_program(program)
                  else
                    program
                  end

    Debug.log("Loading instructions at 0x#{start_addr.to_s(16)}:")
    Debug.log("        #{instructions.map { |b| '0x' + b.to_s(16).rjust(2, '0') }.join(' ')}")

    @cpu.memory.load(instructions, start_addr)
  end

  def setup_test_values
    # Common test values
    # First clear the memory locations we'll use
    @cpu.memory.write(0x0F, 0x00)
    @cpu.memory.write(0x0E, 0x00)
    @cpu.memory.write(0x0D, 0x00)
    @cpu.memory.write(0x0C, 0x00)

    # Then set up test values only for instructions that need them
    @cpu.memory.write(0x0F, 0x42) # Test value for LDA
    @cpu.memory.write(0x0E, 0x24) # Test value for arithmetic operations
    @cpu.memory.write(0x0D, 0xFF) # Test value for logical operations
    @cpu.memory.write(0x0C, 0x00) # Zero value for testing
  end

  def run_program
    while !@cpu.halted
      @cpu.step
    end
  end

  def simulate_cycles(cycles)
    cycles.times do
      break if @cpu.halted
      @cpu.step
    end
  end

  def cpu_state
    {
      acc: @cpu.acc,
      pc: @cpu.pc,
      halted: @cpu.halted,
      zero_flag: @cpu.zero_flag,
      sp: @cpu.sp
    }
  end

  def verify_memory(address, expected_value)
    actual = @cpu.memory.read(address)
    expect(actual).to eq(expected_value),
      "Memory at 0x#{address.to_s(16)} expected 0x#{expected_value.to_s(16)}, got 0x#{actual.to_s(16)}"
  end

  def verify_cpu_state(expected_state)
    actual_state = cpu_state
    expect(actual_state).to eq(expected_state),
      "CPU state mismatch:\nExpected: #{expected_state}\nGot: #{actual_state}"
  end
end
