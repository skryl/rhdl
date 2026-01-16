# Example: ALU using Extended Behavior DSL
#
# This demonstrates how to convert complex propagate logic to synthesizable DSL.
# Compare with examples/mos6502/alu.rb which uses manual propagate.

require_relative '../lib/rhdl'
require_relative '../lib/rhdl/dsl/extended_behavior'

module Examples
  # Simple ALU demonstrating extended behavior DSL
  # (Simplified version without BCD for clarity)
  class ALUSimple < RHDL::HDL::SimComponent
    include RHDL::DSL::ExtendedBehavior

    # Operations
    OP_ADD = 0x00
    OP_SUB = 0x01
    OP_AND = 0x02
    OP_OR  = 0x03
    OP_XOR = 0x04
    OP_SHL = 0x05
    OP_SHR = 0x06
    OP_INC = 0x07
    OP_DEC = 0x08
    OP_CMP = 0x09
    OP_TST = 0x0A

    port_input :a, width: 8
    port_input :b, width: 8
    port_input :c_in
    port_input :op, width: 4

    port_output :result, width: 8
    port_output :n
    port_output :z
    port_output :c
    port_output :v

    # Extended behavior with case_of
    # Simplified version without local variables for now
    extended_behavior do
      # Case statement with multiple outputs
      # Note: use 'cs' for case builder to avoid collision with output 'c'
      case_of op do |cs|
        cs.when(OP_ADD) do
          result <= (a + b + c_in)[7..0]
          c <= (a + b + c_in)[8]
          v <= lit(0, width: 1)
        end

        cs.when(OP_SUB) do
          result <= (a - b)[7..0]
          c <= if_else(a >= b, lit(1, width: 1), lit(0, width: 1))
          v <= lit(0, width: 1)
        end

        cs.when(OP_AND) do
          result <= a & b
          c <= c_in
          v <= lit(0, width: 1)
        end

        cs.when(OP_OR) do
          result <= a | b
          c <= c_in
          v <= lit(0, width: 1)
        end

        cs.when(OP_XOR) do
          result <= a ^ b
          c <= c_in
          v <= lit(0, width: 1)
        end

        cs.when(OP_SHL) do
          result <= (a << 1)[7..0]
          c <= a[7]
          v <= lit(0, width: 1)
        end

        cs.when(OP_SHR) do
          result <= a >> 1
          c <= a[0]
          v <= lit(0, width: 1)
        end

        cs.when(OP_INC) do
          result <= (a + 1)[7..0]
          c <= c_in
          v <= lit(0, width: 1)
        end

        cs.when(OP_DEC) do
          result <= (a - 1)[7..0]
          c <= c_in
          v <= lit(0, width: 1)
        end

        cs.when(OP_CMP) do
          result <= (a - b)[7..0]
          c <= if_else(a >= b, lit(1, width: 1), lit(0, width: 1))
          v <= lit(0, width: 1)
        end

        cs.when(OP_TST) do
          result <= a
          c <= c_in
          v <= lit(0, width: 1)
        end

        cs.default do
          result <= a
          c <= c_in
          v <= lit(0, width: 1)
        end
      end

      # N and Z flags derived from result
      n <= result[7]
      z <= if_else(result == 0, lit(1, width: 1), lit(0, width: 1))
    end
  end
end

# Test the ALU if run directly
if __FILE__ == $0
  require 'rspec'

  RSpec.describe Examples::ALUSimple do
    let(:alu) { Examples::ALUSimple.new('test_alu') }

    def set_inputs(a:, b:, c_in: 0, op:)
      alu.inputs[:a].set(a)
      alu.inputs[:b].set(b)
      alu.inputs[:c_in].set(c_in)
      alu.inputs[:op].set(op)
      alu.propagate
    end

    describe 'ADD' do
      it 'adds two numbers' do
        set_inputs(a: 10, b: 20, op: Examples::ALUSimple::OP_ADD)
        expect(alu.outputs[:result].get).to eq(30)
        expect(alu.outputs[:c].get).to eq(0)
      end

      it 'sets carry on overflow' do
        set_inputs(a: 200, b: 100, op: Examples::ALUSimple::OP_ADD)
        expect(alu.outputs[:result].get).to eq(44)  # (300 & 0xFF)
        expect(alu.outputs[:c].get).to eq(1)
      end
    end

    describe 'SUB' do
      it 'subtracts two numbers' do
        set_inputs(a: 30, b: 10, c_in: 1, op: Examples::ALUSimple::OP_SUB)
        expect(alu.outputs[:result].get).to eq(20)
        expect(alu.outputs[:c].get).to eq(1)  # No borrow
      end
    end

    describe 'AND' do
      it 'performs bitwise AND' do
        set_inputs(a: 0b11110000, b: 0b10101010, op: Examples::ALUSimple::OP_AND)
        expect(alu.outputs[:result].get).to eq(0b10100000)
      end
    end

    describe 'flags' do
      it 'sets Z flag when result is zero' do
        set_inputs(a: 10, b: 10, op: Examples::ALUSimple::OP_SUB, c_in: 1)
        expect(alu.outputs[:z].get).to eq(1)
      end

      it 'sets N flag when result is negative' do
        set_inputs(a: 0x80, b: 0, op: Examples::ALUSimple::OP_TST)
        expect(alu.outputs[:n].get).to eq(1)
      end
    end
  end

  RSpec::Core::Runner.run([$0])
end
