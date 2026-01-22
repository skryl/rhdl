# frozen_string_literal: true

# Cranelift-based JIT compiler for gate-level netlist simulation
#
# This module compiles gate-level netlists to native machine code at load time
# using Cranelift, eliminating interpretation dispatch overhead.

require_relative 'netlist_interpreter'

module RHDL
  module Codegen
    module Structure
      # Try to load the JIT extension
      unless const_defined?(:NETLIST_JIT_AVAILABLE)
        _jit_loaded = begin
          ext_dir = File.expand_path('netlist_jit/lib', __dir__)

          lib_name = case RbConfig::CONFIG['host_os']
          when /darwin/ then 'netlist_jit.bundle'
          when /mswin|mingw/ then 'netlist_jit.dll'
          else 'netlist_jit.so'
          end

          lib_path = File.join(ext_dir, lib_name)

          if File.exist?(lib_path)
            $LOAD_PATH.unshift(ext_dir) unless $LOAD_PATH.include?(ext_dir)
            require 'netlist_jit'
            true
          else
            false
          end
        rescue LoadError => e
          warn "NetlistJit extension not available: #{e.message}" if ENV['RHDL_DEBUG']
          false
        end

        NETLIST_JIT_AVAILABLE = _jit_loaded unless const_defined?(:NETLIST_JIT_AVAILABLE)
      end

      # Wrapper class for the JIT compiler
      class NetlistJitWrapper
        attr_reader :ir, :lanes

        def initialize(ir, lanes: 64)
          @ir = ir
          @lanes = lanes

          if NETLIST_JIT_AVAILABLE
            json = ir.is_a?(String) ? ir : ir.to_json
            @sim = NetlistJit.new(json, lanes)
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
          NETLIST_JIT_AVAILABLE && @sim.respond_to?(:native?) && @sim.native?
        end

        def stats
          @sim.stats
        end
      end
    end
  end
end
