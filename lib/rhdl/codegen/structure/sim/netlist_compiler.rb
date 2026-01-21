# frozen_string_literal: true

# Rustc-based compiler for gate-level netlist simulation
#
# This module generates specialized Rust code for the netlist and compiles
# it with rustc for maximum simulation performance (~3x faster than JIT).

require_relative 'netlist_interpreter'

module RHDL
  module Codegen
    module Structure
      # Try to load the compiler extension
      unless const_defined?(:NETLIST_COMPILER_AVAILABLE)
        _compiler_loaded = begin
          ext_dir = File.expand_path('netlist_compiler/lib', __dir__)

          lib_name = case RbConfig::CONFIG['host_os']
          when /darwin/ then 'netlist_compiler.bundle'
          when /mswin|mingw/ then 'netlist_compiler.dll'
          else 'netlist_compiler.so'
          end

          lib_path = File.join(ext_dir, lib_name)

          if File.exist?(lib_path)
            $LOAD_PATH.unshift(ext_dir) unless $LOAD_PATH.include?(ext_dir)
            require 'netlist_compiler'
            true
          else
            false
          end
        rescue LoadError => e
          warn "NetlistCompiler extension not available: #{e.message}" if ENV['RHDL_DEBUG']
          false
        end

        NETLIST_COMPILER_AVAILABLE = _compiler_loaded unless const_defined?(:NETLIST_COMPILER_AVAILABLE)
      end

      # Wrapper class for the Rustc-based compiler
      class NetlistCompilerWrapper
        attr_reader :ir, :lanes

        def initialize(ir, lanes: 64)
          @ir = ir
          @lanes = lanes

          if NETLIST_COMPILER_AVAILABLE
            json = ir.is_a?(String) ? ir : ir.to_json
            @sim = NetlistCompiler.new(json, lanes)
            @sim.compile  # Compile immediately for maximum performance
          else
            # Fall back to interpreter
            @sim = NetlistInterpreterWrapper.new(ir, lanes: lanes)
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

        def run_ticks(n)
          @sim.run_ticks(n)
        end

        def reset
          @sim.reset
        end

        def native?
          NETLIST_COMPILER_AVAILABLE && @sim.respond_to?(:native?) && @sim.native?
        end

        def compiled?
          NETLIST_COMPILER_AVAILABLE && @sim.respond_to?(:compiled?) && @sim.compiled?
        end

        def generated_code
          @sim.generated_code if @sim.respond_to?(:generated_code)
        end

        def stats
          @sim.stats
        end
      end
    end
  end
end
