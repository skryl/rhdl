# CPU backend for gate-level simulation

require_relative 'primitives'

module RHDL
  module Codegen
    module Structure
      class SimCPU
      attr_reader :ir, :lanes

      def initialize(ir, lanes: 64)
        @ir = ir
        @lanes = lanes
        @lane_mask = (1 << lanes) - 1
        @nets = Array.new(@ir.net_count, 0)
      end

      def poke(name, value)
        nets = @ir.inputs.fetch(name)
        if nets.length == 1
          @nets[nets.first] = value & @lane_mask
        else
          values = normalize_bus_values(value, nets.length)
          nets.each_with_index do |net, idx|
            @nets[net] = values[idx] & @lane_mask
          end
        end
      end

      def peek(name)
        nets = @ir.outputs.fetch(name)
        if nets.length == 1
          @nets[nets.first]
        else
          nets.map { |net| @nets[net] }
        end
      end

      def evaluate
        @ir.schedule.each do |gate_idx|
          gate = @ir.gates[gate_idx]
          eval_gate(gate)
        end
      end

      def tick
        evaluate
        next_q = @ir.dffs.map do |dff|
          q = @nets[dff.q]
          d = @nets[dff.d]
          q_next = d

          if dff.en
            en = @nets[dff.en]
            q_next = (q & ~en) | (d & en)
          end

          if dff.rst
            rst = @nets[dff.rst]
            q_next &= ~rst
          end

          q_next
        end

        @ir.dffs.each_with_index do |dff, idx|
          @nets[dff.q] = next_q[idx]
        end
      end

      def reset
        @nets.fill(0)
      end

      private

      def normalize_bus_values(value, width)
        if value.is_a?(Array)
          lane_values_to_masks(value, width)
        else
          Array.new(width, value)
        end
      end

      def lane_values_to_masks(values, width)
        masks = Array.new(width, 0)
        values.each_with_index do |lane_value, lane|
          width.times do |bit|
            masks[bit] |= (1 << lane) if ((lane_value >> bit) & 1) == 1
          end
        end
        masks
      end

      def eval_gate(gate)
        case gate.type
        when Primitives::AND
          @nets[gate.output] = @nets[gate.inputs[0]] & @nets[gate.inputs[1]]
        when Primitives::OR
          @nets[gate.output] = @nets[gate.inputs[0]] | @nets[gate.inputs[1]]
        when Primitives::XOR
          @nets[gate.output] = @nets[gate.inputs[0]] ^ @nets[gate.inputs[1]]
        when Primitives::NOT
          @nets[gate.output] = (~@nets[gate.inputs[0]]) & @lane_mask
        when Primitives::MUX
          sel = @nets[gate.inputs[2]]
          a = @nets[gate.inputs[0]]
          b = @nets[gate.inputs[1]]
          @nets[gate.output] = (a & ~sel) | (b & sel)
        when Primitives::BUF
          @nets[gate.output] = @nets[gate.inputs[0]]
        when Primitives::CONST
          @nets[gate.output] = gate.value.to_i.zero? ? 0 : @lane_mask
        else
          raise ArgumentError, "Unknown gate type: #{gate.type}"
        end
      end
      end
    end
  end
end
