# frozen_string_literal: true

# MOS 6502 Native ISA-Level Simulator
# High-performance instruction-level simulator implemented in Rust
# Falls back to pure Ruby implementation if native library is not available

require 'rbconfig'

module RHDL
  module Examples
    module MOS6502
      def self.native_lib_name(base)
        case RbConfig::CONFIG['host_os']
        when /darwin/ then "#{base}.dylib"
        when /mswin|mingw/ then "#{base}.dll"
        else "#{base}.so"
        end
      end

      ISA_NATIVE_EXT_DIR = File.expand_path('isa_simulator_native/lib', __dir__)
      ISA_NATIVE_LIB_NAME = native_lib_name('isa_simulator_native')
      ISA_NATIVE_LIB_PATH = File.join(ISA_NATIVE_EXT_DIR, ISA_NATIVE_LIB_NAME)

      def self.sim_backend_available?(lib_path)
        return false unless File.exist?(lib_path)

        lib = Fiddle.dlopen(lib_path)
        %w[
          sim_create sim_destroy sim_set_io_callbacks sim_reset sim_step sim_run sim_run_cycles
          sim_get_reg sim_set_reg sim_read sim_write sim_peek sim_poke sim_load_bytes sim_read_word
          sim_load_program sim_has_io_handler sim_inject_key sim_key_ready sim_speaker_toggles
          sim_reset_speaker_toggles sim_get_video_state sim_set_video_state sim_render_hires_braille
          sim_free_string
        ].each { |sym| lib[sym] }
        true
      rescue Fiddle::DLError
        false
      end

      NATIVE_AVAILABLE = begin
        require 'fiddle'
        require 'fiddle/import'
        sim_backend_available?(ISA_NATIVE_LIB_PATH)
      rescue LoadError
        false
      end

      unless NATIVE_AVAILABLE
        warn "Native ISA simulator not available at #{ISA_NATIVE_LIB_PATH}" if ENV['DEBUG']
        warn 'Falling back to pure Ruby implementation' if ENV['DEBUG']
        require_relative 'isa_simulator'
      end

      if NATIVE_AVAILABLE
        class ISASimulatorNative
          FLAG_C = 0
          FLAG_Z = 1
          FLAG_I = 2
          FLAG_D = 3
          FLAG_B = 4
          FLAG_U = 5
          FLAG_V = 6
          FLAG_N = 7

          NMI_VECTOR = 0xFFFA
          RESET_VECTOR = 0xFFFC
          IRQ_VECTOR = 0xFFFE

          VIDEO_STATE_TEXT = 1 << 0
          VIDEO_STATE_MIXED = 1 << 1
          VIDEO_STATE_PAGE2 = 1 << 2
          VIDEO_STATE_HIRES = 1 << 3

          REG_A = 0
          REG_X = 1
          REG_Y = 2
          REG_SP = 3
          REG_PC = 4
          REG_P = 5
          REG_CYCLES = 6
          REG_HALTED = 7

          class << self
            def lib
              @lib ||= Fiddle.dlopen(ISA_NATIVE_LIB_PATH)
            end

            def bind_functions
              return if defined?(@fn_create) && @fn_create

              @fn_create = Fiddle::Function.new(lib['sim_create'], [], Fiddle::TYPE_VOIDP)
              @fn_destroy = Fiddle::Function.new(lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
              @fn_set_io_callbacks = Fiddle::Function.new(
                lib['sim_set_io_callbacks'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
                Fiddle::TYPE_INT
              )
              @fn_reset = Fiddle::Function.new(lib['sim_reset'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
              @fn_step = Fiddle::Function.new(lib['sim_step'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG_LONG)
              @fn_run = Fiddle::Function.new(
                lib['sim_run'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                Fiddle::TYPE_INT
              )
              @fn_run_cycles = Fiddle::Function.new(
                lib['sim_run_cycles'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG],
                Fiddle::TYPE_LONG_LONG
              )
              @fn_get_reg = Fiddle::Function.new(
                lib['sim_get_reg'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                Fiddle::TYPE_LONG_LONG
              )
              @fn_set_reg = Fiddle::Function.new(
                lib['sim_set_reg'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG],
                Fiddle::TYPE_INT
              )
              @fn_read = Fiddle::Function.new(
                lib['sim_read'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                Fiddle::TYPE_INT
              )
              @fn_write = Fiddle::Function.new(
                lib['sim_write'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
                Fiddle::TYPE_INT
              )
              @fn_peek = Fiddle::Function.new(
                lib['sim_peek'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                Fiddle::TYPE_INT
              )
              @fn_poke = Fiddle::Function.new(
                lib['sim_poke'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
                Fiddle::TYPE_INT
              )
              @fn_load_bytes = Fiddle::Function.new(
                lib['sim_load_bytes'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT],
                Fiddle::TYPE_SIZE_T
              )
              @fn_read_word = Fiddle::Function.new(
                lib['sim_read_word'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                Fiddle::TYPE_INT
              )
              @fn_load_program = Fiddle::Function.new(
                lib['sim_load_program'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT],
                Fiddle::TYPE_SIZE_T
              )
              @fn_has_io_handler = Fiddle::Function.new(
                lib['sim_has_io_handler'],
                [Fiddle::TYPE_VOIDP],
                Fiddle::TYPE_INT
              )
              @fn_inject_key = Fiddle::Function.new(
                lib['sim_inject_key'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                Fiddle::TYPE_INT
              )
              @fn_key_ready = Fiddle::Function.new(
                lib['sim_key_ready'],
                [Fiddle::TYPE_VOIDP],
                Fiddle::TYPE_INT
              )
              @fn_speaker_toggles = Fiddle::Function.new(
                lib['sim_speaker_toggles'],
                [Fiddle::TYPE_VOIDP],
                Fiddle::TYPE_LONG_LONG
              )
              @fn_reset_speaker_toggles = Fiddle::Function.new(
                lib['sim_reset_speaker_toggles'],
                [Fiddle::TYPE_VOIDP],
                Fiddle::TYPE_INT
              )
              @fn_get_video_state = Fiddle::Function.new(
                lib['sim_get_video_state'],
                [Fiddle::TYPE_VOIDP],
                Fiddle::TYPE_INT
              )
              @fn_set_video_state = Fiddle::Function.new(
                lib['sim_set_video_state'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                Fiddle::TYPE_INT
              )
              @fn_render_hires_braille = Fiddle::Function.new(
                lib['sim_render_hires_braille'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
                Fiddle::TYPE_VOIDP
              )
              @fn_free_string = Fiddle::Function.new(
                lib['sim_free_string'],
                [Fiddle::TYPE_VOIDP],
                Fiddle::TYPE_VOID
              )
            end

            attr_reader :fn_create, :fn_destroy, :fn_set_io_callbacks,
                        :fn_reset, :fn_step, :fn_run, :fn_run_cycles,
                        :fn_get_reg, :fn_set_reg,
                        :fn_read, :fn_write, :fn_peek, :fn_poke,
                        :fn_load_bytes, :fn_read_word, :fn_load_program,
                        :fn_has_io_handler,
                        :fn_inject_key, :fn_key_ready,
                        :fn_speaker_toggles, :fn_reset_speaker_toggles,
                        :fn_get_video_state, :fn_set_video_state,
                        :fn_render_hires_braille, :fn_free_string
          end

          def initialize(io_handler = nil)
            self.class.bind_functions
            @ctx = self.class.fn_create.call
            raise LoadError, 'Failed to create native ISA simulator context' if @ctx.to_i.zero?

            @io_handler = io_handler
            @io_read_cb = nil
            @io_write_cb = nil
            configure_io_callbacks(io_handler)
          end

          def close
            return if @ctx.nil? || @ctx.to_i.zero?

            self.class.fn_destroy.call(@ctx)
            @ctx = 0
          rescue StandardError
            @ctx = 0
          end

          def reset
            self.class.fn_reset.call(@ctx)
            true
          end

          def step
            self.class.fn_step.call(@ctx).to_i
          end

          def run(max_instructions = 1000)
            self.class.fn_run.call(@ctx, max_instructions.to_i).to_i
          end

          def run_cycles(target_cycles)
            self.class.fn_run_cycles.call(@ctx, target_cycles.to_i).to_i
          end

          def a
            get_reg(REG_A) & 0xFF
          end

          def x
            get_reg(REG_X) & 0xFF
          end

          def y
            get_reg(REG_Y) & 0xFF
          end

          def sp
            get_reg(REG_SP) & 0xFF
          end

          def pc
            get_reg(REG_PC) & 0xFFFF
          end

          def p
            get_reg(REG_P) & 0xFF
          end

          def cycles
            get_reg(REG_CYCLES)
          end

          def halted
            get_reg(REG_HALTED) != 0
          end

          def halted?
            halted
          end

          def a=(v)
            set_reg(REG_A, v.to_i & 0xFF)
          end

          def x=(v)
            set_reg(REG_X, v.to_i & 0xFF)
          end

          def y=(v)
            set_reg(REG_Y, v.to_i & 0xFF)
          end

          def sp=(v)
            set_reg(REG_SP, v.to_i & 0xFF)
          end

          def pc=(v)
            set_reg(REG_PC, v.to_i & 0xFFFF)
          end

          def p=(v)
            set_reg(REG_P, (v.to_i & 0xFF) | 0x20)
          end

          def cycles=(v)
            set_reg(REG_CYCLES, v.to_i)
          end

          def halted=(v)
            set_reg(REG_HALTED, v ? 1 : 0)
          end

          def flag_c
            (p >> FLAG_C) & 1
          end

          def flag_z
            (p >> FLAG_Z) & 1
          end

          def flag_i
            (p >> FLAG_I) & 1
          end

          def flag_d
            (p >> FLAG_D) & 1
          end

          def flag_b
            (p >> FLAG_B) & 1
          end

          def flag_v
            (p >> FLAG_V) & 1
          end

          def flag_n
            (p >> FLAG_N) & 1
          end

          def set_flag(flag, value)
            if value != 0 && value != false
              self.p = p | (1 << flag)
            else
              self.p = p & ~(1 << flag)
            end
          end

          # CPU memory access (I/O aware)
          def read(addr)
            self.class.fn_read.call(@ctx, addr.to_i & 0xFFFF).to_i & 0xFF
          end

          def write(addr, value)
            self.class.fn_write.call(@ctx, addr.to_i & 0xFFFF, value.to_i & 0xFF)
            value
          end

          # Direct memory access (bypasses I/O callbacks)
          def peek(addr)
            self.class.fn_peek.call(@ctx, addr.to_i & 0xFFFF).to_i & 0xFF
          end

          def poke(addr, value)
            self.class.fn_poke.call(@ctx, addr.to_i & 0xFFFF, value.to_i & 0xFF)
            value
          end

          def load_bytes(bytes, addr)
            payload = coerce_bytes(bytes)
            ptr = payload.empty? ? 0 : Fiddle::Pointer[payload.pack('C*')]
            self.class.fn_load_bytes.call(@ctx, ptr, payload.length, addr.to_i & 0xFFFF)
            self
          end

          def read_word(addr)
            self.class.fn_read_word.call(@ctx, addr.to_i & 0xFFFF).to_i & 0xFFFF
          end

          def load_program(bytes, addr = 0x8000)
            payload = coerce_bytes(bytes)
            ptr = payload.empty? ? 0 : Fiddle::Pointer[payload.pack('C*')]
            self.class.fn_load_program.call(@ctx, ptr, payload.length, addr.to_i & 0xFFFF)
            self
          end

          def state
            {
              a: a,
              x: x,
              y: y,
              sp: sp,
              pc: pc,
              p: p,
              n: flag_n,
              v: flag_v,
              b: flag_b,
              d: flag_d,
              i: flag_i,
              z: flag_z,
              c: flag_c,
              cycles: cycles,
              halted: halted?
            }
          end

          def native?
            true
          end

          def has_io_handler?
            self.class.fn_has_io_handler.call(@ctx).to_i != 0
          end

          def inject_key(ascii)
            self.class.fn_inject_key.call(@ctx, ascii.to_i & 0xFF)
            true
          end

          def key_ready?
            self.class.fn_key_ready.call(@ctx).to_i != 0
          end

          def speaker_toggles
            self.class.fn_speaker_toggles.call(@ctx).to_i
          end

          def reset_speaker_toggles
            self.class.fn_reset_speaker_toggles.call(@ctx)
            true
          end

          def video_state
            bits = self.class.fn_get_video_state.call(@ctx).to_i
            {
              text: (bits & VIDEO_STATE_TEXT) != 0,
              mixed: (bits & VIDEO_STATE_MIXED) != 0,
              page2: (bits & VIDEO_STATE_PAGE2) != 0,
              hires: (bits & VIDEO_STATE_HIRES) != 0
            }
          end

          def set_video_state(text, mixed, page2, hires)
            bits = 0
            bits |= VIDEO_STATE_TEXT if text
            bits |= VIDEO_STATE_MIXED if mixed
            bits |= VIDEO_STATE_PAGE2 if page2
            bits |= VIDEO_STATE_HIRES if hires
            self.class.fn_set_video_state.call(@ctx, bits)
            true
          end

          def render_hires_braille(chars_wide = 140, invert = false)
            ptr = self.class.fn_render_hires_braille.call(@ctx, chars_wide.to_i, invert ? 1 : 0)
            return '' if ptr.to_i.zero?

            str_ptr = Fiddle::Pointer.new(ptr)
            output = str_ptr.to_s.force_encoding('UTF-8')
            self.class.fn_free_string.call(ptr)
            output
          rescue StandardError
            ''
          end

          private

          def get_reg(reg)
            self.class.fn_get_reg.call(@ctx, reg).to_i
          end

          def set_reg(reg, value)
            self.class.fn_set_reg.call(@ctx, reg, value.to_i)
          end

          def configure_io_callbacks(io_handler)
            return unless io_handler
            return unless io_handler.respond_to?(:io_read) && io_handler.respond_to?(:io_write)

            @io_read_cb = Fiddle::Closure::BlockCaller.new(
              Fiddle::TYPE_INT,
              [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP]
            ) do |addr, _user_data|
              io_handler.io_read(addr.to_i & 0xFFFF).to_i & 0xFF
            rescue StandardError
              0
            end

            @io_write_cb = Fiddle::Closure::BlockCaller.new(
              Fiddle::TYPE_VOID,
              [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP]
            ) do |addr, value, _user_data|
              io_handler.io_write(addr.to_i & 0xFFFF, value.to_i & 0xFF)
              nil
            rescue StandardError
              nil
            end

            self.class.fn_set_io_callbacks.call(@ctx, @io_read_cb, @io_write_cb, 0)
          end

          def coerce_bytes(source)
            return source.bytes if source.is_a?(String)
            source.to_a.map { |b| b.to_i & 0xFF }
          end
        end
      else
        ISASimulatorNative = ISASimulator

        class ISASimulatorNative
          def native?
            false
          end
        end
      end

      def self.create_fast_simulator(io_handler = nil)
        ISASimulatorNative.new(io_handler)
      end

      def self.native_available?
        NATIVE_AVAILABLE
      end
    end
  end
end
