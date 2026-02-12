require 'spec_helper'

RSpec.describe 'HDL CPU' do
  describe RHDL::HDL::CPU::Harness do
    def create_cpu(program = [])
      cpu = RHDL::HDL::CPU::Harness.new(name: "test_cpu")
      cpu.load_program(program)
      cpu.reset
      cpu
    end

    describe 'LDI instruction' do
      it 'loads immediate value into accumulator' do
        # LDI 42 (0xA0, 0x2A)
        cpu = create_cpu([0xA0, 0x2A, 0xF0])
        cpu.step
        expect(cpu.acc_value).to eq(42)
      end
    end

    describe 'LDA instruction' do
      it 'loads value from memory' do
        # LDA 5 (0x15) - load from address 5
        # Memory[5] = 0x99
        cpu = create_cpu([0x15, 0xF0])
        cpu.write_memory(5, 0x99)
        cpu.step
        expect(cpu.acc_value).to eq(0x99)
      end
    end

    describe 'STA instruction' do
      it 'stores accumulator to memory' do
        # LDI 42, STA 3
        cpu = create_cpu([0xA0, 0x2A, 0x23, 0xF0])
        cpu.step  # LDI
        cpu.step  # STA
        expect(cpu.read_memory(3)).to eq(42)
      end
    end

    describe 'ADD instruction' do
      it 'adds memory to accumulator' do
        # LDI 10, ADD 5 (mem[5]=20)
        cpu = create_cpu([0xA0, 0x0A, 0x35, 0xF0])
        cpu.write_memory(5, 20)
        cpu.step  # LDI 10
        cpu.step  # ADD 5
        expect(cpu.acc_value).to eq(30)
      end
    end

    describe 'SUB instruction' do
      it 'subtracts memory from accumulator' do
        # LDI 50, SUB 5 (mem[5]=20)
        cpu = create_cpu([0xA0, 0x32, 0x45, 0xF0])
        cpu.write_memory(5, 20)
        cpu.step  # LDI 50
        cpu.step  # SUB 5
        expect(cpu.acc_value).to eq(30)
      end
    end

    describe 'AND instruction' do
      it 'ANDs memory with accumulator' do
        # LDI 0xFF, AND 5 (mem[5]=0x0F)
        cpu = create_cpu([0xA0, 0xFF, 0x55, 0xF0])
        cpu.write_memory(5, 0x0F)
        cpu.step  # LDI
        cpu.step  # AND
        expect(cpu.acc_value).to eq(0x0F)
      end
    end

    describe 'OR instruction' do
      it 'ORs memory with accumulator' do
        # LDI 0xF0, OR 5 (mem[5]=0x0F)
        cpu = create_cpu([0xA0, 0xF0, 0x65, 0xF0])
        cpu.write_memory(5, 0x0F)
        cpu.step  # LDI
        cpu.step  # OR
        expect(cpu.acc_value).to eq(0xFF)
      end
    end

    describe 'XOR instruction' do
      it 'XORs memory with accumulator' do
        # LDI 0xFF, XOR 5 (mem[5]=0x0F)
        cpu = create_cpu([0xA0, 0xFF, 0x75, 0xF0])
        cpu.write_memory(5, 0x0F)
        cpu.step  # LDI
        cpu.step  # XOR
        expect(cpu.acc_value).to eq(0xF0)
      end
    end

    describe 'NOT instruction' do
      it 'inverts accumulator' do
        # LDI 0xF0, NOT
        cpu = create_cpu([0xA0, 0xF0, 0xF2, 0xF0])
        cpu.step  # LDI
        cpu.step  # NOT
        expect(cpu.acc_value).to eq(0x0F)
      end
    end

    describe 'JMP instruction' do
      it 'jumps unconditionally' do
        # JMP 0xA (0xBA)
        cpu = create_cpu([0xBA, 0xF0])
        cpu.step
        expect(cpu.pc_value).to eq(0x0A)
      end
    end

    describe 'JZ instruction' do
      it 'jumps when zero flag is set' do
        # LDI 0, JZ 0xA
        cpu = create_cpu([0xA0, 0x00, 0x8A, 0xF0])
        cpu.step  # LDI 0 (sets zero flag)
        cpu.step  # JZ
        expect(cpu.pc_value).to eq(0x0A)
      end

      it 'does not jump when zero flag is clear' do
        # LDI 1, JZ 0xA
        cpu = create_cpu([0xA0, 0x01, 0x8A, 0xF0])
        cpu.step  # LDI 1 (clears zero flag)
        cpu.step  # JZ (should not jump)
        expect(cpu.pc_value).to eq(3)  # Next instruction
      end
    end

    describe 'JNZ instruction' do
      it 'jumps when zero flag is clear' do
        # LDI 1, JNZ 0xA
        cpu = create_cpu([0xA0, 0x01, 0x9A, 0xF0])
        cpu.step  # LDI 1
        cpu.step  # JNZ
        expect(cpu.pc_value).to eq(0x0A)
      end
    end

    describe 'HLT instruction' do
      it 'halts the CPU' do
        cpu = create_cpu([0xF0])
        cpu.step
        expect(cpu.halted).to be true
      end
    end

    describe 'MUL instruction' do
      it 'multiplies accumulator by memory' do
        # LDI 5, MUL 10 (mem[10]=3)
        cpu = create_cpu([0xA0, 0x05, 0xF1, 0x0A, 0xF0])
        cpu.write_memory(10, 3)
        cpu.step  # LDI
        cpu.step  # MUL
        expect(cpu.acc_value).to eq(15)
      end
    end

    describe 'DIV instruction' do
      it 'divides accumulator by memory' do
        # LDI 20, DIV 5 (mem[5]=4)
        cpu = create_cpu([0xA0, 0x14, 0xE5, 0xF0])
        cpu.write_memory(5, 4)
        cpu.step  # LDI
        cpu.step  # DIV
        expect(cpu.acc_value).to eq(5)
      end
    end

    describe 'CMP instruction' do
      it 'sets zero flag when equal' do
        # LDI 42, CMP 5 (mem[5]=42)
        cpu = create_cpu([0xA0, 0x2A, 0xF3, 0x05, 0xF0])
        cpu.write_memory(5, 42)
        cpu.step  # LDI
        cpu.step  # CMP
        expect(cpu.zero_flag_value).to eq(1)
        expect(cpu.acc_value).to eq(42)  # ACC unchanged
      end

      it 'clears zero flag when not equal' do
        # LDI 42, CMP 5 (mem[5]=10)
        cpu = create_cpu([0xA0, 0x2A, 0xF3, 0x05, 0xF0])
        cpu.write_memory(5, 10)
        cpu.step  # LDI
        cpu.step  # CMP
        expect(cpu.zero_flag_value).to eq(0)
      end
    end

    describe 'Program execution' do
      it 'runs a simple counter program' do
        # Count from 0 to 5 and store in memory
        # 0: LDI 0
        # 2: STA 10
        # 3: ADD 11 (mem[11]=1)
        # 4: STA 10
        # 5: ADD 11
        # 6: STA 10
        # ...repeat...
        # 7: HLT

        # Simpler: just add 3 + 5
        # LDI 3, STA 10, LDI 5, ADD 10, STA 11, HLT
        program = [
          0xA0, 0x03,  # LDI 3
          0x2A,        # STA 10
          0xA0, 0x05,  # LDI 5
          0x3A,        # ADD 10
          0x2B,        # STA 11
          0xF0         # HLT
        ]

        cpu = create_cpu(program)
        cycles = cpu.run(100)

        expect(cpu.read_memory(10)).to eq(3)
        expect(cpu.read_memory(11)).to eq(8)  # 3 + 5
        expect(cpu.halted).to be true
      end

      it 'runs a loop program' do
        # Count down from 3 to 0
        # 0: LDI 3
        # 2: STA 15
        # 3: SUB 14 (mem[14]=1)
        # 4: JNZ 2 (back to STA)
        # 5: HLT

        # Set up decrement value
        program = [
          0xA0, 0x03,  # 0: LDI 3
          0x2F,        # 2: STA 15
          0x4E,        # 3: SUB 14
          0x92,        # 4: JNZ 2
          0xF0         # 5: HLT
        ]

        cpu = create_cpu(program)
        cpu.write_memory(14, 1)  # Decrement value

        cycles = cpu.run(100)

        expect(cpu.acc_value).to eq(0)
        expect(cpu.halted).to be true
      end
    end
  end
end
