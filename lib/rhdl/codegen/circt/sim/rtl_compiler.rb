# frozen_string_literal: true

# RTL Compiler with Rust backend
#
# This simulator generates specialized Rust code for the circuit and compiles
# it at runtime for maximum simulation performance. Unlike the interpreter,
# this approach eliminates all interpretation overhead.

require 'json'
require_relative 'rtl_interpreter'  # For IRToJson module

module RHDL
  module Codegen
    module CIRCT
      # Determine library path based on platform
      RTL_COMPILER_EXT_DIR = File.expand_path('rtl_compiler/lib', __dir__)
      RTL_COMPILER_LIB_NAME = case RbConfig::CONFIG['host_os']
      when /darwin/ then 'rtl_compiler.bundle'
      when /mswin|mingw/ then 'rtl_compiler.dll'
      else 'rtl_compiler.so'
      end
      RTL_COMPILER_LIB_PATH = File.join(RTL_COMPILER_EXT_DIR, RTL_COMPILER_LIB_NAME)

      # Try to load compiler extension
      RTL_COMPILER_AVAILABLE = begin
        if File.exist?(RTL_COMPILER_LIB_PATH)
          $LOAD_PATH.unshift(RTL_COMPILER_EXT_DIR) unless $LOAD_PATH.include?(RTL_COMPILER_EXT_DIR)
          require 'rtl_compiler'
          true
        else
          false
        end
      rescue LoadError => e
        warn "RtlCompiler extension not available: #{e.message}" if ENV['RHDL_DEBUG']
        false
      end

      # Wrapper class that uses Rust AOT compiler if available
      class RtlCompilerWrapper
        attr_reader :ir_json

        def initialize(ir_json)
          @ir_json = ir_json

          unless RTL_COMPILER_AVAILABLE
            raise LoadError, "RTL Compiler extension not found at: #{RTL_COMPILER_LIB_PATH}\nRun 'rake native:build' to build it."
          end

          @sim = ::RtlCompiler.new(ir_json)
        end

        def simulator_type
          :hdl_compile
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
