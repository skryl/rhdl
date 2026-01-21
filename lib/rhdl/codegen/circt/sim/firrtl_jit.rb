# frozen_string_literal: true

# FIRRTL/RTL-level JIT compiler with Cranelift backend
#
# This simulator generates native machine code at load time using Cranelift,
# eliminating all interpretation dispatch overhead. The generated code
# directly computes signal values with no runtime type checking.
#
# Performance target: ~4M cycles/sec (80x faster than interpreter)

require 'json'

module RHDL
  module Codegen
    module CIRCT
      # Try to load JIT extension
      FIRRTL_JIT_AVAILABLE = begin
        require_relative 'firrtl_jit/lib/firrtl_jit'
        true
      rescue LoadError
        false
      end

      # Wrapper class that uses Cranelift JIT if available
      class FirrtlJitWrapper
        attr_reader :ir_json

        def initialize(ir_json)
          @ir_json = ir_json

          if FIRRTL_JIT_AVAILABLE
            @sim = FirrtlJit.new(ir_json)
          else
            # Fallback to interpreter
            require_relative 'firrtl_interpreter'
            @sim = FirrtlInterpreterWrapper.new(ir_json)
          end
        end

        def native?
          FIRRTL_JIT_AVAILABLE
        end

        def backend
          FIRRTL_JIT_AVAILABLE ? :cranelift_jit : :interpreter
        end

        def poke(name, value)
          @sim.poke(name, value)
        end

        def peek(name)
          @sim.peek(name)
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

        def signal_count
          @sim.signal_count
        end

        def reg_count
          @sim.reg_count
        end

        def input_names
          @sim.input_names
        end

        def output_names
          @sim.output_names
        end

        def stats
          @sim.stats
        end

        # Batched execution methods
        def load_rom(data)
          @sim.load_rom(data) if @sim.respond_to?(:load_rom)
        end

        def load_ram(data, offset)
          @sim.load_ram(data, offset) if @sim.respond_to?(:load_ram)
        end

        def run_cpu_cycles(n, key_data, key_ready)
          if @sim.respond_to?(:run_cpu_cycles)
            @sim.run_cpu_cycles(n, key_data, key_ready)
          else
            { cycles_run: 0, text_dirty: false, key_cleared: false }
          end
        end

        def read_ram(start, length)
          if @sim.respond_to?(:read_ram)
            @sim.read_ram(start, length)
          else
            []
          end
        end

        def write_ram(start, data)
          @sim.write_ram(start, data) if @sim.respond_to?(:write_ram)
        end

        def respond_to_missing?(method_name, include_private = false)
          @sim.respond_to?(method_name) || super
        end

        def method_missing(method_name, *args, &block)
          if @sim.respond_to?(method_name)
            @sim.send(method_name, *args, &block)
          else
            super
          end
        end
      end
    end
  end
end
