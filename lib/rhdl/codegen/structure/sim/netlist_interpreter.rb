# frozen_string_literal: true

# Native Rust interpreter for gate-level netlist simulation
#
# This module provides a high-performance Rust implementation of the gate-level
# simulator. It supports AND, OR, XOR, NOT, MUX, BUF, CONST gates and DFFs.
#
# The simulator uses a SIMD-style "lanes" approach where each signal
# is represented as a u64 bitmask, allowing parallel simulation of
# up to 64 test vectors simultaneously.
#
# Usage:
#   sim = RHDL::Codegen::Structure::NetlistInterpreter.new(ir.to_json, 64)
#   sim = RHDL::Codegen::Structure::NetlistInterpreterWrapper.new(ir, lanes: 64)

require_relative '../primitives'

module RHDL
  module Codegen
    module Structure
      # Try to load the native extension
      unless const_defined?(:NETLIST_INTERPRETER_AVAILABLE)
        _native_loaded = begin
          ext_dir = File.expand_path('netlist_interpreter/lib', __dir__)

          # Determine library name based on platform
          lib_name = case RbConfig::CONFIG['host_os']
          when /darwin/
            'netlist_interpreter.bundle'
          when /mswin|mingw/
            'netlist_interpreter.dll'
          else
            'netlist_interpreter.so'
          end

          lib_path = File.join(ext_dir, lib_name)

          if File.exist?(lib_path)
            $LOAD_PATH.unshift(ext_dir) unless $LOAD_PATH.include?(ext_dir)
            require 'netlist_interpreter'
            true
          else
            false
          end
        rescue LoadError => e
          warn "NetlistInterpreter extension not available: #{e.message}" if ENV['RHDL_DEBUG']
          false
        end

        NETLIST_INTERPRETER_AVAILABLE = _native_loaded unless const_defined?(:NETLIST_INTERPRETER_AVAILABLE)
      end

      # Pure Ruby fallback implementation
      class RubyNetlistSimulator
        attr_reader :ir, :lanes

        def initialize(ir, lanes: 64)
          @ir = ir.is_a?(String) ? JSON.parse(ir, symbolize_names: true) : ir
          @lanes = lanes
          @lane_mask = (1 << lanes) - 1
          @nets = Array.new(@ir[:net_count] || @ir.net_count, 0)
          parse_ir
        end

        def parse_ir
          @gates = @ir[:gates] || @ir.gates
          @dffs = @ir[:dffs] || @ir.dffs
          @sr_latches = @ir[:sr_latches] || []
          @inputs = @ir[:inputs] || @ir.inputs
          @outputs = @ir[:outputs] || @ir.outputs
          @schedule = @ir[:schedule] || @ir.schedule
        end

        def poke(name, value)
          nets = @inputs[name.to_s] || @inputs[name.to_sym]
          raise "Unknown input: #{name}" unless nets

          if nets.length == 1
            @nets[nets.first] = value & @lane_mask
          else
            nets.each { |net| @nets[net] = value & @lane_mask }
          end
        end

        def peek(name)
          nets = @outputs[name.to_s] || @outputs[name.to_sym]
          raise "Unknown output: #{name}" unless nets

          nets.length == 1 ? @nets[nets.first] : nets.map { |net| @nets[net] }
        end

        def evaluate
          @schedule.each do |gate_idx|
            gate = @gates[gate_idx]
            eval_gate(gate)
          end

          # Update SR latches
          10.times do
            changed = false
            @sr_latches.each do |latch|
              s = @nets[latch[:s]]
              r = @nets[latch[:r]]
              en = @nets[latch[:en]]
              q_old = @nets[latch[:q]]
              q_next = ((~en) & q_old) | (en & (~r) & (s | q_old)) & @lane_mask
              if q_next != q_old
                @nets[latch[:q]] = q_next
                @nets[latch[:qn]] = (~q_next) & @lane_mask
                changed = true
              end
            end
            break unless changed
          end
        end

        def tick
          evaluate
          next_q = @dffs.map do |dff|
            q = @nets[dff[:q]]
            d = @nets[dff[:d]]
            q_next = d
            if dff[:en]
              en = @nets[dff[:en]]
              q_next = (q & ~en) | (d & en)
            end
            if dff[:rst]
              rst = @nets[dff[:rst]]
              reset_val = dff[:reset_value] || 0
              q_next = (q_next & ~rst) | (rst & (reset_val.zero? ? 0 : @lane_mask))
            end
            q_next
          end
          @dffs.each_with_index { |dff, idx| @nets[dff[:q]] = next_q[idx] }
          evaluate
        end

        def reset
          @nets.fill(0)
          @dffs.each do |dff|
            reset_val = dff[:reset_value] || 0
            @nets[dff[:q]] = reset_val.zero? ? 0 : @lane_mask
          end
        end

        def run_ticks(n)
          n.times { tick }
        end

        def stats
          {
            net_count: @nets.length,
            gate_count: @gates.length,
            dff_count: @dffs.length,
            lanes: @lanes,
            input_count: @inputs.length,
            output_count: @outputs.length,
            backend: 'ruby'
          }
        end

        def native?
          false
        end

        private

        def eval_gate(gate)
          type = gate[:type]&.to_sym || gate.type
          inputs = gate[:inputs] || gate.inputs
          output = gate[:output] || gate.output

          case type
          when :and then @nets[output] = @nets[inputs[0]] & @nets[inputs[1]]
          when :or  then @nets[output] = @nets[inputs[0]] | @nets[inputs[1]]
          when :xor then @nets[output] = @nets[inputs[0]] ^ @nets[inputs[1]]
          when :not then @nets[output] = (~@nets[inputs[0]]) & @lane_mask
          when :mux
            sel = @nets[inputs[2]]
            @nets[output] = (@nets[inputs[0]] & ~sel) | (@nets[inputs[1]] & sel)
          when :buf then @nets[output] = @nets[inputs[0]]
          when :const
            val = gate[:value] || gate.value
            @nets[output] = val.to_i.zero? ? 0 : @lane_mask
          end
        end
      end

      # Wrapper class that uses native Rust implementation when available
      class NetlistInterpreterWrapper
        attr_reader :ir, :lanes

        def initialize(ir, lanes: 64)
          @ir = ir
          @lanes = lanes

          if NETLIST_INTERPRETER_AVAILABLE
            json = ir.is_a?(String) ? ir : ir.to_json
            @sim = NetlistInterpreter.new(json, lanes)
          else
            @sim = RubyNetlistSimulator.new(ir, lanes: lanes)
          end
        end

        def poke(name, value)
          @sim.poke(name.to_s, value)
        end

        def peek(name)
          @sim.peek(name.to_s)
        end

        def evaluate
          @sim.evaluate
        end

        def tick
          @sim.tick
        end

        def reset
          @sim.reset
        end

        def run_ticks(n)
          if @sim.respond_to?(:run_ticks)
            @sim.run_ticks(n)
          else
            n.times { @sim.tick }
          end
        end

        def native?
          NETLIST_INTERPRETER_AVAILABLE && @sim.respond_to?(:native?) && @sim.native?
        end

        def stats
          @sim.stats
        end
      end
    end
  end
end
