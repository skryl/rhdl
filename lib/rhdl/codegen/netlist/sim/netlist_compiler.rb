# frozen_string_literal: true

# Rustc-based compiler for gate-level netlist simulation with SIMD support
#
# This module generates specialized Rust code for the netlist and compiles
# it with rustc for maximum simulation performance. Supports SIMD:
#   - scalar: 64 lanes (1 × u64)
#   - avx2:   256 lanes (4 × u64)
#   - avx512: 512 lanes (8 × u64)
#
# Usage:
#   sim = NetlistCompilerWrapper.new(ir, simd: :auto)  # auto-detect
#   sim = NetlistCompilerWrapper.new(ir, simd: :avx2)  # force AVX2
#   sim = NetlistCompilerWrapper.new(ir, simd: :scalar) # scalar only

require_relative 'netlist_interpreter'

module RHDL
  module Codegen
    module Netlist
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

      # Wrapper class for the Rustc-based SIMD compiler
      class NetlistCompilerWrapper
        attr_reader :ir

        # Initialize with netlist IR and SIMD mode
        # @param ir [Hash, String] Netlist IR (hash or JSON string)
        # @param simd [Symbol, String] SIMD mode: :auto, :scalar, :avx2, :avx512
        # @param lanes [Integer] Deprecated, use simd: parameter instead
        def initialize(ir, simd: :auto, lanes: nil)
          @ir = ir

          # Convert simd parameter to string for Rust
          simd_mode = simd.to_s

          if NETLIST_COMPILER_AVAILABLE
            json = ir.is_a?(String) ? ir : ir.to_json
            @sim = NetlistCompiler.new(json, simd_mode)
            @sim.compile  # Compile immediately for maximum performance
          else
            # Fall back to interpreter
            @sim = NetlistInterpreterWrapper.new(ir, lanes: lanes || 64)
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

        def simd_mode
          @sim.simd_mode if @sim.respond_to?(:simd_mode)
        end

        def lanes
          @sim.lanes if @sim.respond_to?(:lanes)
        end

        def stats
          @sim.stats
        end
      end
    end
  end
end
