# frozen_string_literal: true

require 'json'
require 'rbconfig'
require_relative '../primitives'

module RHDL
  module Codegen
    module Netlist
      class << self
        def native_lib_name(base)
          case RbConfig::CONFIG['host_os']
          when /darwin/ then "#{base}.bundle"
          when /mswin|mingw/ then "#{base}.dll"
          else "#{base}.so"
          end
        end

        def try_load_native_extension(ext_dir:, require_name:)
          lib_path = File.join(ext_dir, native_lib_name(require_name))
          return false unless File.exist?(lib_path)

          $LOAD_PATH.unshift(ext_dir) unless $LOAD_PATH.include?(ext_dir)
          require require_name
          true
        rescue LoadError => e
          warn "#{require_name} extension not available: #{e.message}" if ENV['RHDL_DEBUG']
          false
        end
      end

      unless const_defined?(:NETLIST_INTERPRETER_AVAILABLE)
        NETLIST_INTERPRETER_EXT_DIR = File.expand_path('netlist_interpreter/lib', __dir__)
        NETLIST_INTERPRETER_LIB_NAME = native_lib_name('netlist_interpreter')
        NETLIST_INTERPRETER_LIB_PATH = File.join(NETLIST_INTERPRETER_EXT_DIR, NETLIST_INTERPRETER_LIB_NAME)
        _interpreter_loaded = try_load_native_extension(
          ext_dir: NETLIST_INTERPRETER_EXT_DIR,
          require_name: 'netlist_interpreter'
        )
        NETLIST_INTERPRETER_AVAILABLE = _interpreter_loaded unless const_defined?(:NETLIST_INTERPRETER_AVAILABLE)
      end

      unless const_defined?(:NETLIST_JIT_AVAILABLE)
        NETLIST_JIT_EXT_DIR = File.expand_path('netlist_jit/lib', __dir__)
        NETLIST_JIT_LIB_NAME = native_lib_name('netlist_jit')
        NETLIST_JIT_LIB_PATH = File.join(NETLIST_JIT_EXT_DIR, NETLIST_JIT_LIB_NAME)
        _jit_loaded = try_load_native_extension(
          ext_dir: NETLIST_JIT_EXT_DIR,
          require_name: 'netlist_jit'
        )
        NETLIST_JIT_AVAILABLE = _jit_loaded unless const_defined?(:NETLIST_JIT_AVAILABLE)
      end

      unless const_defined?(:NETLIST_COMPILER_AVAILABLE)
        NETLIST_COMPILER_EXT_DIR = File.expand_path('netlist_compiler/lib', __dir__)
        NETLIST_COMPILER_LIB_NAME = native_lib_name('netlist_compiler')
        NETLIST_COMPILER_LIB_PATH = File.join(NETLIST_COMPILER_EXT_DIR, NETLIST_COMPILER_LIB_NAME)
        _compiler_loaded = try_load_native_extension(
          ext_dir: NETLIST_COMPILER_EXT_DIR,
          require_name: 'netlist_compiler'
        )
        NETLIST_COMPILER_AVAILABLE = _compiler_loaded unless const_defined?(:NETLIST_COMPILER_AVAILABLE)
      end

      # Pure Ruby fallback implementation.
      class RubyNetlistSimulator
        attr_reader :ir, :lanes

        def initialize(ir, lanes: 64)
          @ir = ir.is_a?(String) ? JSON.parse(ir, symbolize_names: true) : ir
          @lanes = lanes
          @lane_mask = (1 << lanes) - 1
          @nets = Array.new(ir_get(:net_count), 0)
          parse_ir
        end

        def parse_ir
          @gates = ir_get(:gates)
          @dffs = ir_get(:dffs)
          @sr_latches = ir_get(:sr_latches) || []
          @inputs = ir_get(:inputs)
          @outputs = ir_get(:outputs)
          @schedule = ir_get(:schedule)
        end

        private

        def ir_get(key)
          if @ir.respond_to?(key)
            @ir.send(key)
          elsif @ir.respond_to?(:[])
            @ir[key] || @ir[key.to_s]
          end
        end

        public

        def poke(name, value)
          nets = @inputs[name.to_s] || @inputs[name.to_sym]
          raise "Unknown input: #{name}" unless nets

          val = value.is_a?(Array) ? value.first : value
          val = val.to_i & @lane_mask

          if nets.length == 1
            @nets[nets.first] = val
          else
            nets.each_with_index { |net, i| @nets[net] = ((val >> i) & 1) == 1 ? @lane_mask : 0 }
          end
        end

        def peek(name)
          nets = @outputs[name.to_s] || @outputs[name.to_sym]
          raise "Unknown output: #{name}" unless nets

          nets.length == 1 ? @nets[nets.first] : nets.map { |net| @nets[net] }
        end

        def evaluate
          @schedule.each do |gate_idx|
            gate = @gates[gate_idx]
            eval_gate(gate)
          end

          # Iterate latches to a fixed point.
          10.times do
            changed = false
            @sr_latches.each do |latch|
              s = @nets[latch[:s]]
              r = @nets[latch[:r]]
              en = @nets[latch[:en]]
              q_old = @nets[latch[:q]]
              q_next = ((~en) & q_old) | (en & (~r) & (s | q_old)) & @lane_mask
              next if q_next == q_old

              @nets[latch[:q]] = q_next
              @nets[latch[:qn]] = (~q_next) & @lane_mask
              changed = true
            end
            break unless changed
          end
        end

        def tick
          evaluate
          next_q = @dffs.map do |dff|
            q = @nets[dff[:q]]
            d = @nets[dff[:d]]
            q_next = d
            if dff[:en]
              en = @nets[dff[:en]]
              q_next = (q & ~en) | (d & en)
            end
            if dff[:rst]
              rst = @nets[dff[:rst]]
              reset_val = dff[:reset_value] || 0
              q_next = (q_next & ~rst) | (rst & (reset_val.zero? ? 0 : @lane_mask))
            end
            q_next
          end
          @dffs.each_with_index { |dff, idx| @nets[dff[:q]] = next_q[idx] }
          evaluate
        end

        def reset
          @nets.fill(0)
          @dffs.each do |dff|
            reset_val = dff[:reset_value] || 0
            @nets[dff[:q]] = reset_val.zero? ? 0 : @lane_mask
          end
        end

        def run_ticks(n)
          n.times { tick }
        end

        def net_count
          @nets.length
        end

        def gate_count
          @gates.length
        end

        def dff_count
          @dffs.length
        end

        def input_names
          @inputs.keys
        end

        def output_names
          @outputs.keys
        end

        def stats
          {
            net_count: @nets.length,
            gate_count: @gates.length,
            dff_count: @dffs.length,
            lanes: @lanes,
            input_count: @inputs.length,
            output_count: @outputs.length,
            backend: 'ruby'
          }
        end

        def native?
          false
        end

        private

        def eval_gate(gate)
          type = gate[:type]&.to_sym || gate.type
          inputs = gate[:inputs] || gate.inputs
          output = gate[:output] || gate.output

          case type
          when :and then @nets[output] = @nets[inputs[0]] & @nets[inputs[1]]
          when :or then @nets[output] = @nets[inputs[0]] | @nets[inputs[1]]
          when :xor then @nets[output] = @nets[inputs[0]] ^ @nets[inputs[1]]
          when :not then @nets[output] = (~@nets[inputs[0]]) & @lane_mask
          when :mux
            sel = @nets[inputs[2]]
            @nets[output] = (@nets[inputs[0]] & ~sel) | (@nets[inputs[1]] & sel)
          when :buf then @nets[output] = @nets[inputs[0]]
          when :const
            val = gate[:value] || gate.value
            @nets[output] = val.to_i.zero? ? 0 : @lane_mask
          end
        end
      end

      # Unified wrapper for interpreter, JIT, compiler, and Ruby fallback.
      class NetlistSimulator
        attr_reader :ir, :lanes

        BACKEND_CONFIGS = {
          interpreter: {
            available: NETLIST_INTERPRETER_AVAILABLE,
            class_name: 'NetlistInterpreter',
            type: :interpret,
            lib_path: NETLIST_INTERPRETER_LIB_PATH
          },
          jit: {
            available: NETLIST_JIT_AVAILABLE,
            class_name: 'NetlistJit',
            type: :jit,
            lib_path: NETLIST_JIT_LIB_PATH
          },
          compiler: {
            available: NETLIST_COMPILER_AVAILABLE,
            class_name: 'NetlistCompiler',
            type: :compile,
            lib_path: NETLIST_COMPILER_LIB_PATH
          }
        }.freeze

        def initialize(ir, backend: :interpreter, lanes: 64, simd: :auto, allow_fallback: true)
          @ir = ir
          @lanes = lanes
          @simd = simd
          @requested_backend = normalize_backend(backend)
          @fallback = false
          @native_error = nil

          native_loaded = false
          backend_candidates(@requested_backend, allow_fallback: allow_fallback).each do |candidate|
            next unless BACKEND_CONFIGS[candidate][:available]

            begin
              create_native_sim(candidate)
              native_loaded = true
              break
            rescue StandardError => e
              @native_error = e
            end
          end

          return if native_loaded

          if allow_fallback
            @sim = RubyNetlistSimulator.new(ir, lanes: lanes)
            @backend = :ruby
            @fallback = true
          else
            raise LoadError, unavailable_backend_error_message(@requested_backend, allow_fallback: false)
          end
        end

        def simulator_type
          :"netlist_#{@backend}"
        end

        def backend
          @backend
        end

        def native?
          !@fallback && @sim.respond_to?(:native?) && @sim.native?
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
          if @sim.respond_to?(:run_ticks)
            @sim.run_ticks(n)
          else
            n.times { @sim.tick }
          end
        end

        def reset
          @sim.reset
        end

        def compile
          return true unless @sim.respond_to?(:compile)

          @sim.compile
        end

        def compiled?
          return false unless @sim.respond_to?(:compiled?)

          @sim.compiled?
        end

        def generated_code
          return nil unless @sim.respond_to?(:generated_code)

          @sim.generated_code
        end

        def simd_mode
          return nil unless @sim.respond_to?(:simd_mode)

          @sim.simd_mode
        end

        def net_count
          return @sim.net_count if @sim.respond_to?(:net_count)

          @sim.stats[:net_count]
        end

        def gate_count
          return @sim.gate_count if @sim.respond_to?(:gate_count)

          @sim.stats[:gate_count]
        end

        def dff_count
          return @sim.dff_count if @sim.respond_to?(:dff_count)

          @sim.stats[:dff_count]
        end

        def input_names
          return @sim.input_names if @sim.respond_to?(:input_names)

          []
        end

        def output_names
          return @sim.output_names if @sim.respond_to?(:output_names)

          []
        end

        def stats
          @sim.stats
        end

        private

        def normalize_backend(backend)
          case backend.to_sym
          when :interpreter, :interpret then :interpreter
          when :jit then :jit
          when :compiler, :compile then :compiler
          when :auto then :auto
          else
            raise ArgumentError, "Unknown backend: #{backend}. Valid: :interpreter, :jit, :compiler, :auto"
          end
        end

        def backend_candidates(backend, allow_fallback:)
          case backend
          when :auto then [:compiler, :jit, :interpreter]
          when :compiler then allow_fallback ? [:compiler, :jit, :interpreter] : [:compiler]
          when :jit then allow_fallback ? [:jit, :interpreter] : [:jit]
          when :interpreter then [:interpreter]
          else
            [backend]
          end
        end

        def create_native_sim(backend)
          config = BACKEND_CONFIGS.fetch(backend)
          json = @ir.is_a?(String) ? @ir : @ir.to_json
          klass = RHDL::Codegen::Netlist.const_get(config[:class_name])

          @sim = case backend
                 when :compiler
                   compiler = klass.new(json, @simd.to_s)
                   compiler.compile if compiler.respond_to?(:compile)
                   compiler
                 else
                   klass.new(json, @lanes)
                 end

          @backend = config[:type]
        end

        def unavailable_backend_error_message(backend, allow_fallback:)
          candidates = backend_candidates(backend, allow_fallback: allow_fallback)
          missing = candidates.reject { |candidate| BACKEND_CONFIGS[candidate][:available] }
          hint_paths = missing.map { |candidate| BACKEND_CONFIGS[candidate][:lib_path] }

          message = +"Netlist #{backend} backend is not available."
          unless hint_paths.empty?
            message << "\nMissing native library: #{hint_paths.join(', ')}"
          end
          message << "\nRun 'rake native:build' to build native extensions."
          message << "\nLast native error: #{@native_error.message}" if @native_error
          message
        end
      end

      # Backward compatibility aliases retained for native-vs-Ruby test helpers.
      SimCPU = RubyNetlistSimulator
      SimCPUNative = NetlistInterpreter if const_defined?(:NetlistInterpreter)
      NATIVE_SIM_AVAILABLE = NETLIST_INTERPRETER_AVAILABLE
    end
  end
end
