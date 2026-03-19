# frozen_string_literal: true

require_relative 'ir_runner'
require_relative 'verilator_runner'
require_relative 'arcilator_runner'
require_relative '../integration/image_builder'
require_relative '../integration/programs'
require 'rhdl/sim/native/headless_trace'

module RHDL
  module Examples
      module SPARC64
      class HeadlessRunner
        include RHDL::Sim::Native::HeadlessTrace
        attr_reader :runner, :mode, :sim_backend, :builder, :fast_boot, :compile_mode,
                    :verilator_source, :arcilator_source

        def initialize(mode: :ir, sim: nil, runner: nil, ir_runner_class: IrRunner,
                       verilator_runner_class: VerilatorRunner, arcilator_runner_class: ArcilatorRunner, builder: nil,
                       builder_class: Integration::ProgramImageBuilder, fast_boot: true,
                       compile_mode: :rustc,
                       verilator_source: :staged_verilog,
                       arcilator_source: :rhdl_mlir)
          @mode = (mode || :ir).to_sym
          @sim_backend = (sim || default_backend(@mode)).to_sym
          @builder = builder || builder_class.new
          @fast_boot = !!fast_boot
          @compile_mode = normalize_compile_mode(compile_mode)
          @verilator_source = normalize_verilator_source(verilator_source)
          @arcilator_source = normalize_arcilator_source(arcilator_source)
          @runner = runner || build_runner(
            ir_runner_class: ir_runner_class,
            verilator_runner_class: verilator_runner_class,
            arcilator_runner_class: arcilator_runner_class
          )
        end

        def native?
          @runner.native?
        end

        def simulator_type
          @runner.simulator_type
        end

        def backend
          @runner.backend
        end

        def reset
          @runner.reset!
        end

        def cycle_count
          @runner.clock_count
        end

        def load_benchmark(program)
          selected = program.is_a?(Symbol) || program.is_a?(String) ? Integration::Programs.fetch(program) : program
          images = @builder.build(selected)
          @runner.load_images(
            boot_image: images.boot_bytes,
            program_image: images.program_bytes
          )
          selected
        end

        def run_until_complete(max_cycles:, batch_cycles: 1_000)
          @runner.run_until_complete(max_cycles: max_cycles, batch_cycles: batch_cycles)
        end

        def read_memory(addr, length)
          @runner.read_memory(addr, length)
        end

        def write_memory(addr, bytes)
          @runner.write_memory(addr, bytes)
        end

        def wishbone_trace
          @runner.wishbone_trace
        end

        def mailbox_status
          @runner.mailbox_status
        end

        def mailbox_value
          @runner.mailbox_value
        end

        def unmapped_accesses
          @runner.unmapped_accesses
        end

        def debug_snapshot
          return {} unless @runner.respond_to?(:debug_snapshot)

          @runner.debug_snapshot
        end

        private

        def build_runner(ir_runner_class:, verilator_runner_class:, arcilator_runner_class:)
          case @mode
          when :ir
            ir_runner_class.new(
              backend: normalize_ir_backend(@sim_backend),
              fast_boot: fast_boot,
              compiler_mode: compile_mode
            )
          when :verilog
            verilator_runner_class.new(
              fast_boot: fast_boot,
              source_kind: verilator_source
            )
          when :circt, :arcilator
            arcilator_runner_class.new(
              fast_boot: fast_boot,
              jit: arcilator_jit_mode?(@sim_backend),
              source_kind: arcilator_source
            )
          else
            raise ArgumentError, "Unsupported SPARC64 mode #{@mode.inspect}. Use :ir, :verilog, or :arcilator."
          end
        end

        def normalize_ir_backend(backend)
          case backend
          when :interpret, :interpreter
            :interpret
          when :jit
            :jit
          when :compile, :compiler
            :compile
          else
            raise ArgumentError, "Unsupported SPARC64 IR backend #{backend.inspect}. Use :interpret, :jit, or :compile."
          end
        end

        def default_backend(mode)
          case mode
          when :ir
            :compile
          when :verilog
            :verilator
          when :circt, :arcilator
            :compile
          else
            raise ArgumentError, "Unsupported SPARC64 mode #{mode.inspect}. Use :ir, :verilog, or :arcilator."
          end
        end

        def arcilator_jit_mode?(backend)
          case backend
          when :compile
            false
          when :jit
            true
          else
            raise ArgumentError, "Unsupported SPARC64 Arcilator backend #{backend.inspect}. Use :compile or :jit."
          end
        end

        def normalize_compile_mode(value)
          mode = (value || :rustc).to_sym
          return mode unless @mode == :ir && @sim_backend == :compile
          return :rustc if mode == :rustc

          raise ArgumentError,
                "Unsupported SPARC64 compiler mode #{value.inspect}. The compiler backend is rustc-only; use :jit for fallback."
        end

        def normalize_verilator_source(value)
          case (value || :staged_verilog).to_sym
          when :staged, :staged_verilog
            :staged_verilog
          when :rhdl, :rhdl_verilog
            :rhdl_verilog
          else
            raise ArgumentError,
                  "Unsupported SPARC64 Verilator source #{value.inspect}. Use :staged_verilog or :rhdl_verilog."
          end
        end

        def normalize_arcilator_source(value)
          case (value || :rhdl_mlir).to_sym
          when :staged, :staged_verilog
            :staged_verilog
          when :rhdl, :rhdl_mlir
            :rhdl_mlir
          else
            raise ArgumentError,
                  "Unsupported SPARC64 Arcilator source #{value.inspect}. Use :staged_verilog or :rhdl_mlir."
          end
        end
      end
    end
  end
end
