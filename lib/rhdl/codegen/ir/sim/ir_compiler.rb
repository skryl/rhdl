# frozen_string_literal: true

# IR Compiler with Rust backend
#
# This simulator generates specialized Rust code for the circuit and compiles
# it at runtime for maximum simulation performance. Unlike the interpreter,
# this approach eliminates all interpretation overhead.

require 'json'
require_relative 'ir_interpreter'  # For IRToJson module

module RHDL
  module Codegen
    module IR
      # Determine library path based on platform
      IR_COMPILER_EXT_DIR = File.expand_path('ir_compiler/lib', __dir__)
      IR_COMPILER_LIB_NAME = case RbConfig::CONFIG['host_os']
      when /darwin/ then 'ir_compiler.bundle'
      when /mswin|mingw/ then 'ir_compiler.dll'
      else 'ir_compiler.so'
      end
      IR_COMPILER_LIB_PATH = File.join(IR_COMPILER_EXT_DIR, IR_COMPILER_LIB_NAME)

      # Try to load compiler extension
      IR_COMPILER_AVAILABLE = begin
        if File.exist?(IR_COMPILER_LIB_PATH)
          $LOAD_PATH.unshift(IR_COMPILER_EXT_DIR) unless $LOAD_PATH.include?(IR_COMPILER_EXT_DIR)
          require 'ir_compiler'
          true
        else
          false
        end
      rescue LoadError => e
        warn "IrCompiler extension not available: #{e.message}" if ENV['RHDL_DEBUG']
        false
      end

      # Backwards compatibility alias
      RTL_COMPILER_AVAILABLE = IR_COMPILER_AVAILABLE

      # Wrapper class that uses Rust AOT compiler if available
      class IrCompilerWrapper
        attr_reader :ir_json

        def initialize(ir_json)
          @ir_json = ir_json

          unless IR_COMPILER_AVAILABLE
            raise LoadError, "IR Compiler extension not found at: #{IR_COMPILER_LIB_PATH}\nRun 'rake native:build' to build it."
          end

          @sim = IrCompiler.new(ir_json)
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

      # Backwards compatibility alias
      RtlCompilerWrapper = IrCompilerWrapper
    end
  end
end
