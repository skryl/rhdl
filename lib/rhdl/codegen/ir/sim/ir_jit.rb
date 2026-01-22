# frozen_string_literal: true

# IR-level JIT compiler with Cranelift backend
#
# This simulator generates native machine code at load time using Cranelift,
# eliminating all interpretation dispatch overhead. The generated code
# directly computes signal values with no runtime type checking.
#
# Performance target: ~4M cycles/sec (80x faster than interpreter)

require 'json'

module RHDL
  module Codegen
    module IR
      # Determine library path based on platform
      IR_JIT_EXT_DIR = File.expand_path('ir_jit/lib', __dir__)
      IR_JIT_LIB_NAME = case RbConfig::CONFIG['host_os']
      when /darwin/ then 'ir_jit.bundle'
      when /mswin|mingw/ then 'ir_jit.dll'
      else 'ir_jit.so'
      end
      IR_JIT_LIB_PATH = File.join(IR_JIT_EXT_DIR, IR_JIT_LIB_NAME)

      # Try to load JIT extension
      IR_JIT_AVAILABLE = begin
        if File.exist?(IR_JIT_LIB_PATH)
          $LOAD_PATH.unshift(IR_JIT_EXT_DIR) unless $LOAD_PATH.include?(IR_JIT_EXT_DIR)
          require 'ir_jit'
          true
        else
          false
        end
      rescue LoadError => e
        warn "IrJit extension not available: #{e.message}" if ENV['RHDL_DEBUG']
        false
      end

      # Backwards compatibility alias
      RTL_JIT_AVAILABLE = IR_JIT_AVAILABLE

      # Wrapper class that uses Cranelift JIT if available
      class IrJitWrapper
        attr_reader :ir_json

        def initialize(ir_json, allow_fallback: true)
          @ir_json = ir_json

          if IR_JIT_AVAILABLE
            @sim = ::RHDL::Codegen::CIRCT::RtlJit.new(ir_json)
            @backend = :jit
          elsif allow_fallback
            require_relative 'ir_interpreter'
            @sim = IrInterpreterWrapper.new(ir_json, allow_fallback: true)
            @backend = @sim.native? ? :interpret : :ruby
          else
            raise LoadError, "IR JIT extension not found at: #{IR_JIT_LIB_PATH}\nRun 'rake native:build' to build it."
          end
        end

        def simulator_type
          :"hdl_#{@backend}"
        end

        def native?
          IR_JIT_AVAILABLE && @backend == :jit
        end

        def backend
          @backend
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

        # Batched tick execution - eliminates FFI overhead for bulk simulation
        def run_ticks(n)
          if @sim.respond_to?(:run_ticks)
            @sim.run_ticks(n)
          else
            n.times { @sim.tick }
          end
        end

        # Get signal index by name (for caching)
        def get_signal_idx(name)
          @sim.get_signal_idx(name) if @sim.respond_to?(:get_signal_idx)
        end

        # Poke by index - faster than by name when index is cached
        def poke_by_idx(idx, value)
          @sim.poke_by_idx(idx, value) if @sim.respond_to?(:poke_by_idx)
        end

        # Peek by index - faster than by name when index is cached
        def peek_by_idx(idx)
          @sim.peek_by_idx(idx) if @sim.respond_to?(:peek_by_idx)
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
      RtlJitWrapper = IrJitWrapper
    end
  end
end
