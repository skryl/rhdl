# frozen_string_literal: true

# FIRRTL JIT Compiler with Rust backend
#
# This simulator generates specialized Rust code for the circuit and compiles
# it at runtime for maximum simulation performance. Unlike the interpreter,
# this approach eliminates all interpretation overhead.

require 'json'
require_relative 'firrtl_interpreter'  # For IRToJson module

module RHDL
  module Codegen
    module CIRCT
      # Try to load compiler extension
      FIRRTL_COMPILER_AVAILABLE = begin
        require_relative 'firrtl_compiler/lib/firrtl_compiler'
        true
      rescue LoadError
        false
      end

      # Wrapper class that uses Rust JIT compiler if available
      class FirrtlCompilerWrapper
        attr_reader :ir_json

        def initialize(ir_json)
          @ir_json = ir_json

          unless FIRRTL_COMPILER_AVAILABLE
            raise LoadError, "FIRRTL Compiler native extension not available. Run 'rake native:build' to build it."
          end

          @sim = ::FirrtlCompiler.new(ir_json)
        end

        def native?
          true
        end

        def compiled?
          @sim.compiled?
        end

        def compile
          @sim.compile
        end

        def generated_code
          @sim.generated_code
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
          @sim.load_rom(data)
        end

        def load_ram(data, offset)
          @sim.load_ram(data, offset)
        end

        def run_cpu_cycles(n, key_data, key_ready)
          @sim.run_cpu_cycles(n, key_data, key_ready)
        end

        def read_ram(start, length)
          @sim.read_ram(start, length)
        end

        def write_ram(start, data)
          @sim.write_ram(start, data)
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
