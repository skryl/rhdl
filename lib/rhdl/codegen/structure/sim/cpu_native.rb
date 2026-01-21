# frozen_string_literal: true

# Native Rust CPU backend for gate-level simulation
#
# This module provides a high-performance Rust implementation of the gate-level
# simulator. If the native extension is not available, it falls back to the
# pure Ruby implementation (SimCPU).
#
# Usage:
#   # Direct instantiation with IR
#   sim = RHDL::Codegen::Structure::SimCPUNative.new(ir.to_json, 64)
#
#   # Or use the wrapper that accepts IR directly
#   sim = RHDL::Codegen::Structure::SimCPUNativeWrapper.new(ir, lanes: 64)

require_relative 'cpu'

module RHDL
  module Codegen
    module Structure
      # Try to load the native extension
      unless const_defined?(:NATIVE_SIM_AVAILABLE)
        _native_loaded = begin
          ext_dir = File.expand_path('cpu_native/lib', __dir__)

          # Determine library name based on platform
          lib_name = case RbConfig::CONFIG['host_os']
          when /darwin/
            'sim_cpu_native.bundle'
          when /mswin|mingw/
            'sim_cpu_native.dll'
          else
            'sim_cpu_native.so'
          end

          lib_path = File.join(ext_dir, lib_name)

          if File.exist?(lib_path)
            $LOAD_PATH.unshift(ext_dir) unless $LOAD_PATH.include?(ext_dir)
            require 'sim_cpu_native'
            true
          else
            false
          end
        rescue LoadError => e
          warn "Native sim_cpu extension not available: #{e.message}" if ENV['RHDL_DEBUG']
          false
        end

        # Only set if not already defined by native extension
        NATIVE_SIM_AVAILABLE = _native_loaded unless const_defined?(:NATIVE_SIM_AVAILABLE)
      end

      # Wrapper class that provides the same interface as SimCPU but uses
      # the native Rust implementation when available
      class SimCPUNativeWrapper
        attr_reader :ir, :lanes

        def initialize(ir, lanes: 64)
          @ir = ir
          @lanes = lanes

          if NATIVE_SIM_AVAILABLE
            @native = SimCPUNative.new(ir.to_json, lanes)
          else
            @fallback = SimCPU.new(ir, lanes: lanes)
          end
        end

        def poke(name, value)
          if @native
            @native.poke(name, value)
          else
            @fallback.poke(name, value)
          end
        end

        def peek(name)
          if @native
            @native.peek(name)
          else
            @fallback.peek(name)
          end
        end

        def evaluate
          if @native
            @native.evaluate
          else
            @fallback.evaluate
          end
        end

        def tick
          if @native
            @native.tick
          else
            @fallback.tick
          end
        end

        def reset
          if @native
            @native.reset
          else
            @fallback.reset
          end
        end

        def native?
          !@native.nil?
        end

        def stats
          if @native
            @native.stats
          else
            {
              net_count: @ir.net_count,
              gate_count: @ir.gates.length,
              dff_count: @ir.dffs.length,
              lanes: @lanes,
              input_count: @ir.inputs.length,
              output_count: @ir.outputs.length
            }
          end
        end
      end
    end
  end
end
