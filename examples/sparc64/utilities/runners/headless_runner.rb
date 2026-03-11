# frozen_string_literal: true

require_relative 'ir_runner'
require_relative 'verilator_runner'
require_relative '../integration/image_builder'
require_relative '../integration/programs'

module RHDL
  module Examples
    module SPARC64
      class HeadlessRunner
        attr_reader :runner, :mode, :sim_backend, :builder, :fast_boot, :compile_mode

        def initialize(mode: :ir, sim: nil, runner: nil, ir_runner_class: IrRunner,
                       verilator_runner_class: VerilogRunner, builder: nil,
                       builder_class: Integration::ProgramImageBuilder, fast_boot: true,
                       compile_mode: :auto)
          @mode = (mode || :ir).to_sym
          @sim_backend = (sim || default_backend(@mode)).to_sym
          @builder = builder || builder_class.new
          @fast_boot = !!fast_boot
          @compile_mode = (compile_mode || :auto).to_sym
          @runner = runner || build_runner(ir_runner_class: ir_runner_class, verilator_runner_class: verilator_runner_class)
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

        private

        def build_runner(ir_runner_class:, verilator_runner_class:)
          case @mode
          when :ir
            ir_runner_class.new(
              backend: normalize_ir_backend(@sim_backend),
              fast_boot: fast_boot,
              compiler_mode: compile_mode
            )
          when :verilog
            verilator_runner_class.new(fast_boot: fast_boot)
          else
            raise ArgumentError, "Unsupported SPARC64 mode #{@mode.inspect}. Use :ir or :verilog."
          end
        end

        def normalize_ir_backend(backend)
          case backend
          when :compile, :compiler
            :compile
          else
            raise ArgumentError, "Unsupported SPARC64 IR backend #{backend.inspect}. Use :compile."
          end
        end

        def default_backend(mode)
          case mode
          when :ir
            :compile
          when :verilog
            :verilator
          else
            raise ArgumentError, "Unsupported SPARC64 mode #{mode.inspect}. Use :ir or :verilog."
          end
        end
      end
    end
  end
end
