# frozen_string_literal: true

# Cranelift-based JIT compiler for gate-level netlist simulation
#
# This module compiles gate-level netlists to native machine code at load time
# using Cranelift, eliminating interpretation dispatch overhead.

require_relative 'netlist_interpreter'

module RHDL
  module Codegen
    module Netlist
      # Try to load the JIT extension
      unless const_defined?(:NETLIST_JIT_AVAILABLE)
        # Determine library path based on platform
        NETLIST_JIT_EXT_DIR = File.expand_path('netlist_jit/lib', __dir__)
        NETLIST_JIT_LIB_NAME = case RbConfig::CONFIG['host_os']
        when /darwin/ then 'netlist_jit.bundle'
        when /mswin|mingw/ then 'netlist_jit.dll'
        else 'netlist_jit.so'
        end
        NETLIST_JIT_LIB_PATH = File.join(NETLIST_JIT_EXT_DIR, NETLIST_JIT_LIB_NAME)

        _jit_loaded = begin
          if File.exist?(NETLIST_JIT_LIB_PATH)
            $LOAD_PATH.unshift(NETLIST_JIT_EXT_DIR) unless $LOAD_PATH.include?(NETLIST_JIT_EXT_DIR)
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

        def initialize(ir, lanes: 64, allow_fallback: false)
          @ir = ir
          @lanes = lanes

          if NETLIST_JIT_AVAILABLE
            json = ir.is_a?(String) ? ir : ir.to_json
            @sim = NetlistJit.new(json, lanes)
            @backend = :jit
          elsif allow_fallback
            @sim = NetlistInterpreterWrapper.new(ir, lanes: lanes, allow_fallback: true)
            @backend = @sim.simulator_type.to_s.split('_').last.to_sym
          else
            raise LoadError, "Netlist JIT extension not found at: #{NETLIST_JIT_LIB_PATH}\nRun 'rake native:build' to build it."
          end
        end

        def simulator_type
          :"netlist_#{@backend}"
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
