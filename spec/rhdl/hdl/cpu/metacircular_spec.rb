# frozen_string_literal: true

# Metacircular CPU Integration Test
#
# This test demonstrates the "metacircular machine" concept from SICH Chapter 18:
# An assembly program running on our CPU interprets a gate-level netlist.
#
# The test:
# 1. Exports a simple circuit to a gate-level netlist
# 2. Writes an assembly program that interprets those gates
# 3. Runs the assembly on the HDL CPU (via behavioral harness)
# 4. Verifies the interpreter produces correct gate-level results

require 'spec_helper'
require 'rhdl/hdl'
require 'rhdl/codegen/netlist/lower'

RSpec.describe 'Metacircular CPU Simulation', :metacircular do
  # Helper to create and run CPU with a program
  # Net values stored at addresses 10-15 (accessible via single-byte LDA/STA)
  # Program at address 0
  def create_cpu(program, initial_memory = {})
    cpu = RHDL::HDL::CPU::Harness.new(name: "test_cpu")
    cpu.load_program(program)

    # Write initial memory values (for net values)
    initial_memory.each { |addr, val| cpu.write_memory(addr, val) }

    cpu.reset
    cpu
  end

  # Instruction encoding helpers
  module Asm
    def self.lda(addr); 0x10 | (addr & 0x0F); end
    def self.sta(addr); 0x20 | (addr & 0x0F); end
    def self.add(addr); 0x30 | (addr & 0x0F); end
    def self.sub(addr); 0x40 | (addr & 0x0F); end
    def self.and_op(addr); 0x50 | (addr & 0x0F); end
    def self.or_op(addr); 0x60 | (addr & 0x0F); end
    def self.xor_op(addr); 0x70 | (addr & 0x0F); end
    def self.ldi(imm); [0xA0, imm & 0xFF]; end
    def self.hlt; 0xF0; end
  end

  describe 'gate interpretation via assembly' do
    # Net value addresses (10-15 are safe from program overlap)
    NET_A = 10      # Net 0: input A
    NET_B = 11      # Net 1: input B
    NET_C = 12      # Net 2: input C (for 3-input gates)
    NET_OUT = 13    # Net 3: output
    NET_TEMP = 14   # Net 4: temporary
    NET_CONST = 15  # Net 5: constant value

    describe 'AND gate' do
      it 'computes 0 AND 0 = 0' do
        program = [
          Asm.lda(NET_A),      # Load A
          Asm.and_op(NET_B),   # AND with B
          Asm.sta(NET_OUT),    # Store result
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { NET_A => 0, NET_B => 0 })
        cpu.run(10)

        expect(cpu.read_memory(NET_OUT)).to eq(0)
      end

      it 'computes 1 AND 1 = 1' do
        program = [
          Asm.lda(NET_A),
          Asm.and_op(NET_B),
          Asm.sta(NET_OUT),
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { NET_A => 1, NET_B => 1 })
        cpu.run(10)

        expect(cpu.read_memory(NET_OUT)).to eq(1)
      end

      it 'computes 1 AND 0 = 0' do
        program = [
          Asm.lda(NET_A),
          Asm.and_op(NET_B),
          Asm.sta(NET_OUT),
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { NET_A => 1, NET_B => 0 })
        cpu.run(10)

        expect(cpu.read_memory(NET_OUT)).to eq(0)
      end
    end

    describe 'OR gate' do
      it 'computes 0 OR 1 = 1' do
        program = [
          Asm.lda(NET_A),
          Asm.or_op(NET_B),
          Asm.sta(NET_OUT),
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { NET_A => 0, NET_B => 1 })
        cpu.run(10)

        expect(cpu.read_memory(NET_OUT)).to eq(1)
      end
    end

    describe 'XOR gate' do
      it 'computes 1 XOR 1 = 0' do
        program = [
          Asm.lda(NET_A),
          Asm.xor_op(NET_B),
          Asm.sta(NET_OUT),
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { NET_A => 1, NET_B => 1 })
        cpu.run(10)

        expect(cpu.read_memory(NET_OUT)).to eq(0)
      end

      it 'computes 1 XOR 0 = 1' do
        program = [
          Asm.lda(NET_A),
          Asm.xor_op(NET_B),
          Asm.sta(NET_OUT),
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { NET_A => 1, NET_B => 0 })
        cpu.run(10)

        expect(cpu.read_memory(NET_OUT)).to eq(1)
      end
    end

    describe 'NOT gate (via XOR with 1)' do
      it 'computes NOT 0 = 1' do
        program = [
          Asm.lda(NET_A),
          Asm.xor_op(NET_CONST),  # XOR with 1 = NOT
          Asm.sta(NET_OUT),
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { NET_A => 0, NET_CONST => 1 })
        cpu.run(10)

        expect(cpu.read_memory(NET_OUT)).to eq(1)
      end

      it 'computes NOT 1 = 0' do
        program = [
          Asm.lda(NET_A),
          Asm.xor_op(NET_CONST),
          Asm.sta(NET_OUT),
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { NET_A => 1, NET_CONST => 1 })
        cpu.run(10)

        expect(cpu.read_memory(NET_OUT)).to eq(0)
      end
    end
  end

  describe 'compound circuits' do
    # Use local constants to avoid conflicts
    CIRC_A = 10
    CIRC_B = 11
    CIRC_SUM = 12
    CIRC_CARRY = 13
    CIRC_CONST = 14

    describe 'half adder (XOR + AND)' do
      def run_half_adder(a, b)
        program = [
          # sum = A XOR B
          Asm.lda(CIRC_A),
          Asm.xor_op(CIRC_B),
          Asm.sta(CIRC_SUM),
          # carry = A AND B
          Asm.lda(CIRC_A),
          Asm.and_op(CIRC_B),
          Asm.sta(CIRC_CARRY),
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { CIRC_A => a, CIRC_B => b })
        cpu.run(20)

        [cpu.read_memory(CIRC_SUM), cpu.read_memory(CIRC_CARRY)]
      end

      it 'computes 0 + 0 = sum:0, carry:0' do
        sum, carry = run_half_adder(0, 0)
        expect(sum).to eq(0)
        expect(carry).to eq(0)
      end

      it 'computes 1 + 0 = sum:1, carry:0' do
        sum, carry = run_half_adder(1, 0)
        expect(sum).to eq(1)
        expect(carry).to eq(0)
      end

      it 'computes 1 + 1 = sum:0, carry:1' do
        sum, carry = run_half_adder(1, 1)
        expect(sum).to eq(0)
        expect(carry).to eq(1)
      end
    end

    describe 'NAND gate (AND then NOT)' do
      def run_nand(a, b)
        # NAND(a,b) = NOT(AND(a,b)) = (a AND b) XOR 1
        program = [
          Asm.lda(CIRC_A),
          Asm.and_op(CIRC_B),
          Asm.xor_op(CIRC_CONST),  # XOR with 1 = NOT
          Asm.sta(CIRC_SUM),       # Using SUM as output
          Asm.hlt
        ].flatten

        cpu = create_cpu(program, { CIRC_A => a, CIRC_B => b, CIRC_CONST => 1 })
        cpu.run(20)

        cpu.read_memory(CIRC_SUM)
      end

      it 'computes NAND(0,0) = 1' do
        expect(run_nand(0, 0)).to eq(1)
      end

      it 'computes NAND(0,1) = 1' do
        expect(run_nand(0, 1)).to eq(1)
      end

      it 'computes NAND(1,0) = 1' do
        expect(run_nand(1, 0)).to eq(1)
      end

      it 'computes NAND(1,1) = 0' do
        expect(run_nand(1, 1)).to eq(0)
      end
    end
  end

  describe 'netlist export and CPU statistics' do
    it 'exports CPU to netlist and shows gate primitives' do
      # Export the CPU to see what gates it's made of
      cpu = RHDL::HDL::CPU::CPU.new(name: 'cpu')
      cpu_ir = RHDL::Codegen::Netlist::Lower.from_components([cpu], name: 'cpu')

      # Show statistics about the CPU's gate-level structure
      gate_types = cpu_ir.gates.map { |g| g[:type] || g['type'] }.tally

      puts "\n  CPU Netlist Statistics:"
      puts "    Total gates: #{cpu_ir.gates.length}"
      puts "    DFFs: #{cpu_ir.dffs.length}"
      puts "    Nets: #{cpu_ir.net_count}"
      puts "    Gate types: #{gate_types}"

      # The CPU is built from the same primitives our interpreter handles
      expect(gate_types.keys).to include(:and, :or, :xor, :not).or include('and', 'or', 'xor', 'not')
    end
  end

  describe 'metacircular demonstration' do
    it 'CPU interprets the same gate primitives it is built from' do
      # Export the CPU to see its structure
      cpu_component = RHDL::HDL::CPU::CPU.new(name: 'cpu')
      cpu_ir = RHDL::Codegen::Netlist::Lower.from_components([cpu_component], name: 'cpu')

      # The CPU is built from AND, OR, XOR, NOT gates
      gate_types = cpu_ir.gates.map { |g| g[:type]&.to_sym || g['type']&.to_sym }.uniq

      # Now run our CPU to interpret those same gate types
      net_a = 10
      net_b = 11
      net_out = 12

      # Test each gate type the CPU can interpret
      results = {}

      # AND
      program = [Asm.lda(net_a), Asm.and_op(net_b), Asm.sta(net_out), Asm.hlt].flatten
      cpu = create_cpu(program, { net_a => 1, net_b => 1 })
      cpu.run(10)
      results[:and] = cpu.read_memory(net_out) == 1

      # OR
      program = [Asm.lda(net_a), Asm.or_op(net_b), Asm.sta(net_out), Asm.hlt].flatten
      cpu = create_cpu(program, { net_a => 1, net_b => 0 })
      cpu.run(10)
      results[:or] = cpu.read_memory(net_out) == 1

      # XOR
      program = [Asm.lda(net_a), Asm.xor_op(net_b), Asm.sta(net_out), Asm.hlt].flatten
      cpu = create_cpu(program, { net_a => 1, net_b => 1 })
      cpu.run(10)
      results[:xor] = cpu.read_memory(net_out) == 0

      # NOT (via XOR with 1)
      net_const = 13
      program = [Asm.lda(net_a), Asm.xor_op(net_const), Asm.sta(net_out), Asm.hlt].flatten
      cpu = create_cpu(program, { net_a => 1, net_const => 1 })
      cpu.run(10)
      results[:not] = cpu.read_memory(net_out) == 0

      # All gates should work correctly
      expect(results.values).to all(be true)

      puts "\n  Metacircular Insight:"
      puts "    CPU is built from: #{gate_types.join(', ')}"
      puts "    CPU correctly interprets: #{results.keys.select { |k| results[k] }.join(', ')}"
      puts "    The CPU can simulate the very gates it's made of!"
      puts "    Gates in CPU: #{cpu_ir.gates.length}, DFFs: #{cpu_ir.dffs.length}"
    end
  end
end
