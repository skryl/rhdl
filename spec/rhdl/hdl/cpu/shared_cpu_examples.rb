# Shared examples for CPU behavior
# These can be run against both behavior and HDL CPU implementations

RSpec.shared_examples 'a CPU implementation' do
  include CpuTestHelper

  before(:each) do
    @memory = MemorySimulator::Memory.new
    setup_cpu
  end

  describe 'basic instructions' do
    it 'executes NOP instruction' do
      load_program([[:NOP]])
      @cpu.step
      verify_cpu_state(acc: 0x00, pc: 1, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes LDA instruction' do
      @memory.write(0x0F, 0x42)
      load_program([[:LDA, 0xF]])
      @cpu.step
      verify_cpu_state(acc: 0x42, pc: 1, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes LDI instruction' do
      load_program([[:LDI, 0x20]])
      @cpu.step
      verify_cpu_state(acc: 0x20, pc: 2, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes STA instruction' do
      load_program([[:LDI, 0x20], [:STA, 0xE]])
      2.times { @cpu.step }
      verify_memory(0xE, 0x20)
      verify_cpu_state(acc: 0x20, pc: 3, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes ADD instruction' do
      @memory.write(0x0E, 0x24)
      load_program([[:LDI, 0x20], [:ADD, 0xE]])
      2.times { @cpu.step }
      verify_cpu_state(acc: 0x44, pc: 3, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes SUB instruction' do
      load_program([[:LDI, 0x20], [:SUB, 0xE]])  # Memory at 0xE contains 0x24
      2.times { @cpu.step }
      verify_cpu_state(acc: 0xFC, pc: 3, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes AND instruction' do
      load_program([[:LDI, 0x2A], [:AND, 0xE]])  # Memory at 0xE contains 0x24
      2.times { @cpu.step }
      verify_cpu_state(acc: 0x20 & 0x24, pc: 3, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes OR instruction' do
      load_program([[:LDI, 0x20], [:OR, 0xE]])  # Memory at 0xE contains 0x24
      2.times { @cpu.step }
      verify_cpu_state(acc: 0x20 | 0x24, pc: 3, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes XOR instruction' do
      load_program([[:LDI, 0x3F], [:XOR, 0xE]])
      2.times { @cpu.step }
      verify_cpu_state(acc: 0x3F ^ 0x24, pc: 3, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes NOT instruction' do
      load_program([[:LDI, 0x2A], [:NOT]])
      2.times { @cpu.step }
      verify_cpu_state(acc: (~0x2A) & 0xFF, pc: 3, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes MUL instruction' do
      load_program([[:LDI, 0x03], [:MUL, 0xE]])
      2.times { @cpu.step }
      verify_cpu_state(acc: 0x6C, pc: 4, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes DIV instruction' do
      load_program([[:LDI, 0x30], [:DIV, 0xE]])  # 0x30 / 0x24 = 1
      2.times { @cpu.step }
      verify_cpu_state(acc: (0x30 / 0x24) & 0xFF, pc: 3, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'handles division by zero' do
      load_program([[:LDI, 0x30], [:DIV, 0xC]])
      2.times { @cpu.step }
      verify_cpu_state(acc: 0x00, pc: 3, halted: false, zero_flag: true, sp: 0xFF)
    end
  end

  describe 'control flow instructions' do
    it 'executes JMP instruction' do
      load_program([[:JMP, 0x5], [:NOP], [:NOP], [:NOP], [:NOP], [:HLT]])
      @cpu.step
      verify_cpu_state(acc: 0x00, pc: 0x5, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes JZ instruction when zero flag is set' do
      load_program([[:LDI, 0x0], [:JZ, 0x5], [:NOP], [:NOP], [:NOP], [:HLT]])
      2.times { @cpu.step }
      verify_cpu_state(acc: 0x00, pc: 0x5, halted: false, zero_flag: true, sp: 0xFF)
    end

    it 'executes JNZ instruction when zero flag is clear' do
      load_program([[:LDI, 0x1], [:JNZ, 0x5], [:NOP], [:NOP], [:NOP], [:HLT]])
      2.times { @cpu.step }
      verify_cpu_state(acc: 0x01, pc: 0x5, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes HLT instruction' do
      load_program([[:HLT]])
      @cpu.step
      verify_cpu_state(acc: 0x00, pc: 0, halted: true, zero_flag: false, sp: 0xFF)
    end
  end

  describe 'CALL and RET instructions' do
    it 'executes CALL and RET sequence' do
      program = [
        [:LDI, 0x5],
        [:CALL, 0x4],
        [:HLT],
        [:ADD, 0xE],
        [:RET]
      ]

      load_program(program)
      run_program
      verify_cpu_state(acc: 0x29, pc: 3, halted: true, zero_flag: false, sp: 0xFF)
    end

    it 'handles nested CALL instructions' do
      program = [
        [:LDI, 0x5],
        [:CALL, 0x5],
        [:HLT],
        [:NOP],
        [:ADD, 0xE],
        [:CALL, 0x8],
        [:RET],
        [:ADD, 0xE],
        [:RET]
      ]

      load_program(program)
      run_program
      verify_cpu_state(acc: 0x4D, pc: 3, halted: true, zero_flag: false, sp: 0xFF)
    end

    it 'preserves CPU state during CALL/RET' do
      program = [
        [:LDI, 0x3],
        [:CALL, 0x4],
        [:HLT],
        [:STA, 0xE],
        [:LDI, 0x2],
        [:RET],
        [:HLT]
      ]

      load_program(program)
      run_program
      verify_memory(0xE, 0x3)
      verify_cpu_state(acc: 0x2, pc: 3, halted: true, zero_flag: false, sp: 0xFF)
    end

    it 'handles stack underflow correctly' do
      load_program([[:RET]])
      @cpu.step
      verify_cpu_state(acc: 0x00, pc: 0, halted: true, zero_flag: false, sp: 0xFF)
    end
  end

  describe 'flag handling' do
    it 'sets zero flag correctly after arithmetic operations' do
      load_program([
        [:LDI, 0x24],
        [:SUB, 0xE],
        [:HLT]
      ])
      run_program
      verify_cpu_state(acc: 0x00, pc: 3, halted: true, zero_flag: true, sp: 0xFF)
    end

    it 'sets zero flag correctly after logical operations' do
      load_program([
        [:LDI, 0xFF],
        [:AND, 0xC],
        [:HLT]
      ])
      run_program
      verify_cpu_state(acc: 0x00, pc: 3, halted: true, zero_flag: true, sp: 0xFF)
    end

    it 'handles zero flag in conditional jumps' do
      program = [
        [:LDI, 0x0],
        [:JZ, 0x5],
        [:LDI, 0x1],
        [:JNZ, 0x6],
        [:HLT],
        [:HLT]
      ]

      load_program(program)
      run_program
      verify_cpu_state(acc: 0x00, pc: 6, halted: true, zero_flag: true, sp: 0xFF)
    end
  end

  describe 'STA instruction variants' do
    it 'executes direct STA instruction' do
      load_program([[:LDI, 0x20], [:STA, 0xE]])
      2.times { @cpu.step }
      verify_memory(0xE, 0x20)
      verify_cpu_state(acc: 0x20, pc: 3, halted: false, zero_flag: false, sp: 0xFF)
    end

    it 'executes indirect STA instruction' do
      load_program([
        [:LDI, 0x08],
        [:STA, 0x20],
        [:LDI, 0x00],
        [:STA, 0x21],
        [:LDI, 0x42],
        [:STA, 0x20, 0x21],
        [:HLT]
      ])

      run_program
      verify_memory(0x800, 0x42)
      verify_cpu_state(acc: 0x42, pc: 13, halted: true, zero_flag: false, sp: 0xFF)
    end
  end
end
