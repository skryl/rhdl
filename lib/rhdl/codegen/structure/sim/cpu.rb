# CPU backend for gate-level simulation

require_relative '../primitives'

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

        # Update SR latches (level-sensitive, may need iteration for stability)
        max_iterations = 10
        max_iterations.times do
          changed = false
          @ir.sr_latches.each do |latch|
            s = @nets[latch.s]
            r = @nets[latch.r]
            en = @nets[latch.en]
            q_old = @nets[latch.q]

            # SR latch truth table (when en=1):
            #   S=1, R=0: Q=1 (set)
            #   S=0, R=1: Q=0 (reset)
            #   S=0, R=0: Q=hold
            #   S=1, R=1: invalid (R wins, Q=0)
            # When en=0: Q=hold
            # Using bitwise operations for SIMD lanes:
            # q_next = mux(en, mux(r, 0, mux(s, 1, q)), q)
            #        = (en & (r ? 0 : (s ? 1 : q))) | (~en & q)
            #        = (en & ~r & (s | q)) | (~en & q)
            #        = (en & ~r & s) | (en & ~r & ~s & q) | (~en & q)
            # Simplified: q_next = (~en & q) | (en & ~r & (s | q))
            q_next = ((~en) & q_old) | (en & (~r) & (s | q_old))
            q_next &= @lane_mask

            if q_next != q_old
              @nets[latch.q] = q_next
              @nets[latch.qn] = (~q_next) & @lane_mask
              changed = true
            end
          end
          break unless changed
        end
      end

      def tick
        # First pass: evaluate combinational logic with current DFF state
        evaluate

        # Sample all DFF inputs and compute next state
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
            reset_val = dff.reset_value || 0
            # When rst is asserted, use reset_value instead of 0
            q_next = (q_next & ~rst) | (rst & (reset_val.zero? ? 0 : @lane_mask))
          end

          q_next
        end

        # Update all DFF Q outputs
        @ir.dffs.each_with_index do |dff, idx|
          @nets[dff.q] = next_q[idx]
        end

        # Second pass: re-evaluate combinational logic with new DFF state
        # This ensures outputs depending on DFF state are updated in the same cycle
        evaluate
      end

      def reset
        @nets.fill(0)
        # Apply DFF reset values (for non-zero reset)
        @ir.dffs.each do |dff|
          reset_val = dff.reset_value || 0
          @nets[dff.q] = reset_val.zero? ? 0 : @lane_mask
        end
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
