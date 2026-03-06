# frozen_string_literal: true

require 'json'
require 'fiddle'
require 'fiddle/import'
require 'rbconfig'
require_relative '../../../codegen/netlist/primitives'

module RHDL
  module Sim
    module Native
      module Netlist
        class << self
          def native_lib_candidates(base)
            case RbConfig::CONFIG['host_os']
            when /darwin/ then ["#{base}.bundle", "#{base}.dylib"]
            when /mswin|mingw/ then ["#{base}.dll"]
            else ["#{base}.so"]
            end
          end

          def native_lib_name(base)
            native_lib_candidates(base).first
          end

          def resolve_native_lib_path(ext_dir, base)
            native_lib_candidates(base)
              .map { |name| [name, File.join(ext_dir, name)] }
              .find { |_name, path| File.exist?(path) }
          end

          def sim_backend_available?(lib_path)
            return false unless File.exist?(lib_path)

            lib = Fiddle.dlopen(lib_path)
            lib['sim_create']
            lib['sim_destroy']
            lib['sim_poke_bus']
            lib['sim_peek_bus']
            lib['sim_exec']
            lib['sim_query']
            lib['sim_blob']
            true
          rescue Fiddle::DLError
            false
          end
        end


      INTERPRETER_EXT_DIR = File.expand_path('netlist_interpreter/lib', __dir__)
      INTERPRETER_LIB_NAME, INTERPRETER_LIB_PATH = resolve_native_lib_path(INTERPRETER_EXT_DIR, 'netlist_interpreter')
      INTERPRETER_AVAILABLE = sim_backend_available?(INTERPRETER_LIB_PATH)

      JIT_EXT_DIR = File.expand_path('netlist_jit/lib', __dir__)
      JIT_LIB_NAME, JIT_LIB_PATH = resolve_native_lib_path(JIT_EXT_DIR, 'netlist_jit')
      JIT_AVAILABLE = sim_backend_available?(JIT_LIB_PATH)

      COMPILER_EXT_DIR = File.expand_path('netlist_compiler/lib', __dir__)
      COMPILER_LIB_NAME, COMPILER_LIB_PATH = resolve_native_lib_path(COMPILER_EXT_DIR, 'netlist_compiler')
      COMPILER_AVAILABLE = sim_backend_available?(COMPILER_LIB_PATH)

      # Common Fiddle wrapper shared by netlist native backends.
      class NativeBackend
        SIM_EXEC_EVALUATE = 0
        SIM_EXEC_TICK = 1
        SIM_EXEC_RUN_TICKS = 2
        SIM_EXEC_RESET = 3
        SIM_EXEC_COMPILE = 4
        SIM_EXEC_IS_COMPILED = 5

        SIM_QUERY_NET_COUNT = 0
        SIM_QUERY_GATE_COUNT = 1
        SIM_QUERY_DFF_COUNT = 2
        SIM_QUERY_LANES = 3

        SIM_BLOB_INPUT_NAMES = 0
        SIM_BLOB_OUTPUT_NAMES = 1
        SIM_BLOB_GENERATED_CODE = 2
        SIM_BLOB_SIMD_MODE = 3

        U64_PACK = 'Q'
        SIZE_T_PACK = Fiddle::SIZEOF_VOIDP == 8 ? 'Q' : 'L'

        def initialize(lib_path, json, config)
          @lib = Fiddle.dlopen(lib_path)
          bind_functions

          error_ptr = alloc_error_ptr
          @ctx = @fn_create.call(json.to_s, config&.to_s, error_ptr)
          if @ctx.to_i.zero?
            raise LoadError, error_from_ptr(error_ptr)
          end
        end

        def close
          return if @ctx.nil? || @ctx.to_i.zero?

          @fn_destroy.call(@ctx)
          @ctx = 0
        rescue StandardError
          @ctx = 0
        end

        def native?
          true
        end

        def poke(name, value)
          if value.is_a?(Array)
            values = value.map { |v| v.to_i & 0xFFFFFFFFFFFFFFFF }
            buf = Fiddle::Pointer[values.pack("#{U64_PACK}*")]
            exec_with_error do |error_ptr|
              @fn_poke_bus.call(@ctx, name.to_s, buf, values.length, error_ptr)
            end
          else
            raw = value.to_i & 0xFFFFFFFFFFFFFFFF
            signed = raw >= 0x8000000000000000 ? raw - 0x1_0000_0000_0000_0000 : raw
            exec_with_error do |error_ptr|
              @fn_poke_scalar.call(@ctx, name.to_s, signed, error_ptr)
            end
          end
          true
        end

        def peek(name)
          values = peek_bus(name)
          values.length <= 1 ? (values[0] || 0) : values
        end

        def evaluate
          exec_with_error do |error_ptr|
            @fn_exec.call(@ctx, SIM_EXEC_EVALUATE, 0, error_ptr)
          end
          true
        end

        def tick
          exec_with_error do |error_ptr|
            @fn_exec.call(@ctx, SIM_EXEC_TICK, 0, error_ptr)
          end
          true
        end

        def run_ticks(n)
          exec_with_error do |error_ptr|
            @fn_exec.call(@ctx, SIM_EXEC_RUN_TICKS, n.to_i, error_ptr)
          end
          true
        end

        def reset
          exec_with_error do |error_ptr|
            @fn_exec.call(@ctx, SIM_EXEC_RESET, 0, error_ptr)
          end
          true
        end

        def compile
          exec_with_error do |error_ptr|
            @fn_exec.call(@ctx, SIM_EXEC_COMPILE, 0, error_ptr)
          end
          true
        end

        def compiled?
          @fn_exec.call(@ctx, SIM_EXEC_IS_COMPILED, 0, 0).to_i != 0
        end

        def generated_code
          blob(SIM_BLOB_GENERATED_CODE)
        end

        def simd_mode
          blob(SIM_BLOB_SIMD_MODE)
        end

        def net_count
          @fn_query.call(@ctx, SIM_QUERY_NET_COUNT).to_i
        end

        def gate_count
          @fn_query.call(@ctx, SIM_QUERY_GATE_COUNT).to_i
        end

        def dff_count
          @fn_query.call(@ctx, SIM_QUERY_DFF_COUNT).to_i
        end

        def lanes
          @fn_query.call(@ctx, SIM_QUERY_LANES).to_i
        end

        def input_names
          csv = blob(SIM_BLOB_INPUT_NAMES)
          csv.empty? ? [] : csv.split(',')
        end

        def output_names
          csv = blob(SIM_BLOB_OUTPUT_NAMES)
          csv.empty? ? [] : csv.split(',')
        end

        def stats
          {
            net_count: net_count,
            gate_count: gate_count,
            dff_count: dff_count,
            lanes: lanes,
            input_count: input_names.length,
            output_count: output_names.length
          }
        end

        private

        def bind_functions
          @fn_create = Fiddle::Function.new(
            @lib['sim_create'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOIDP
          )
          @fn_destroy = Fiddle::Function.new(
            @lib['sim_destroy'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )
          @fn_free_error = Fiddle::Function.new(
            @lib['sim_free_error'],
            [Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_VOID
          )
          @fn_poke_bus = Fiddle::Function.new(
            @lib['sim_poke_bus'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @fn_poke_scalar = Fiddle::Function.new(
            @lib['sim_poke_scalar'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @fn_peek_bus = Fiddle::Function.new(
            @lib['sim_peek_bus'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @fn_exec = Fiddle::Function.new(
            @lib['sim_exec'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
          @fn_query = Fiddle::Function.new(
            @lib['sim_query'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_SIZE_T
          )
          @fn_blob = Fiddle::Function.new(
            @lib['sim_blob'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T],
            Fiddle::TYPE_SIZE_T
          )
        end

        def peek_bus(name)
          out_len_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          out_len_ptr[0, Fiddle::SIZEOF_VOIDP] = [0].pack(SIZE_T_PACK)

          exec_with_error do |error_ptr|
            @fn_peek_bus.call(@ctx, name.to_s, 0, 0, out_len_ptr, error_ptr)
          end

          len = out_len_ptr[0, Fiddle::SIZEOF_VOIDP].unpack1(SIZE_T_PACK)
          return [] if len.zero?

          out_buf = Fiddle::Pointer.malloc(len * 8)
          out_len_ptr[0, Fiddle::SIZEOF_VOIDP] = [0].pack(SIZE_T_PACK)

          exec_with_error do |error_ptr|
            @fn_peek_bus.call(@ctx, name.to_s, out_buf, len, out_len_ptr, error_ptr)
          end

          out_buf[0, len * 8].unpack("#{U64_PACK}*")
        end

        def blob(op)
          size = @fn_blob.call(@ctx, op, 0, 0).to_i
          return '' if size <= 0

          buf = Fiddle::Pointer.malloc(size)
          written = @fn_blob.call(@ctx, op, buf, size).to_i
          return '' if written <= 0

          buf.to_s(written)
        end

        def exec_with_error
          error_ptr = alloc_error_ptr
          result = yield(error_ptr)
          return result if result.to_i != 0

          raise RuntimeError, error_from_ptr(error_ptr)
        end

        def alloc_error_ptr
          ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
          ptr[0, Fiddle::SIZEOF_VOIDP] = [0].pack(SIZE_T_PACK)
          ptr
        end

        def error_from_ptr(error_ptr)
          error_str_ptr = error_ptr[0, Fiddle::SIZEOF_VOIDP].unpack1(SIZE_T_PACK)
          return 'native netlist backend operation failed' if error_str_ptr.zero?

          error_msg = Fiddle::Pointer.new(error_str_ptr).to_s
          @fn_free_error.call(error_str_ptr)
          error_msg
        rescue StandardError
          'native netlist backend operation failed'
        end
      end

      class Interpreter < NativeBackend
        def initialize(json, lanes = 64)
          super(INTERPRETER_LIB_PATH, json, lanes)
        end
      end

      class Jit < NativeBackend
        def initialize(json, lanes = 64)
          super(JIT_LIB_PATH, json, lanes)
        end
      end

      class Compiler < NativeBackend
        def initialize(json, simd_mode = 'auto')
          super(COMPILER_LIB_PATH, json, simd_mode)
        end

        def compile
          super
        end

        def simd_mode
          mode = super
          mode.empty? ? 'scalar' : mode
        end

        def stats
          super.merge(
            simd_mode: simd_mode,
            compiled: compiled?,
            backend: 'rustc_compiler_simd'
          )
        end
      end

      # Pure Ruby netlist simulator implementation.
      class RubySimulator
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

      # Unified wrapper for native netlist backends (interpreter, JIT, compiler).
      class Simulator
        attr_reader :ir, :lanes

        BACKEND_CONFIGS = {
          interpreter: {
            available: INTERPRETER_AVAILABLE,
            class_name: 'Interpreter',
            type: :interpret,
            lib_path: INTERPRETER_LIB_PATH
          },
          jit: {
            available: JIT_AVAILABLE,
            class_name: 'Jit',
            type: :jit,
            lib_path: JIT_LIB_PATH
          },
          compiler: {
            available: COMPILER_AVAILABLE,
            class_name: 'Compiler',
            type: :compile,
            lib_path: COMPILER_LIB_PATH
          }
        }.freeze

        def initialize(ir, backend: :interpreter, lanes: 64, simd: :auto)
          @ir = ir
          @lanes = lanes
          @simd = simd
          @requested_backend = normalize_backend(backend)
          @native_error = nil

          native_loaded = false
          backend_candidates(@requested_backend).each do |candidate|
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

          raise LoadError, unavailable_backend_error_message(@requested_backend)
        end

        def simulator_type
          :"netlist_#{@backend}"
        end

        def backend
          @backend
        end

        def native?
          @sim.respond_to?(:native?) && @sim.native?
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

        def backend_candidates(backend)
          case backend
          when :auto then [:compiler, :jit, :interpreter]
          when :compiler then [:compiler]
          when :jit then [:jit]
          when :interpreter then [:interpreter]
          else
            [backend]
          end
        end

        def create_native_sim(backend)
          config = BACKEND_CONFIGS.fetch(backend)
          json = @ir.is_a?(String) ? @ir : @ir.to_json
          klass = RHDL::Sim::Native::Netlist.const_get(config[:class_name])

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

        def unavailable_backend_error_message(backend)
          candidates = backend_candidates(backend)
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
    end
  end
end
end
