# frozen_string_literal: true

# RV32I IR Runner - Batched native IR simulation
#
# Wraps IRHarness (single-cycle) or Pipeline::IRHarness (pipelined) with native
# batching enabled. Uses the Rust native runner for fast cycle execution.

require_relative '../../hdl/ir_harness'
require_relative '../../hdl/pipeline/ir_harness'

module RHDL
  module Examples
    module RISCV
      class IrRunner
        attr_reader :clock_count

        def initialize(core: :single, mem_size: Memory::DEFAULT_SIZE, backend: :jit)
          @core = core

          @harness = case core
                     when :single
                       IRHarness.new(mem_size: mem_size, backend: backend)
                     when :pipeline
                       Pipeline::IRHarness.new('riscv_pipeline_ir', mem_size: mem_size, backend: backend)
                     else
                       raise ArgumentError, "Unsupported core: #{core.inspect}"
                     end
        end

        def native?
          @harness.native?
        end

        def simulator_type
          @harness.simulator_type
        end

        def backend
          @harness.backend
        end

        def sim
          @harness.sim
        end

        def reset!
          @harness.reset!
        end

        def clock_cycle
          @harness.clock_cycle
        end

        def run_cycles(n)
          @harness.run_cycles(n)
        end

        def clock_count
          @harness.clock_count
        end

        def read_reg(index)
          @harness.read_reg(index)
        end

        def write_reg(index, value)
          @harness.write_reg(index, value)
        end

        def read_pc
          @harness.read_pc
        end

        def write_pc(value)
          @harness.write_pc(value)
        end

        def load_program(program, start_addr = 0)
          @harness.load_program(program, start_addr)
        end

        def load_data(data, start_addr = 0)
          if @harness.respond_to?(:load_data)
            @harness.load_data(data, start_addr)
          else
            # Pipeline harness uses write_data for word-level writes
            data.each_with_index do |word, i|
              @harness.write_data(start_addr + i * 4, word)
            end
          end
        end

        def read_inst_word(addr)
          if @harness.respond_to?(:read_inst_word)
            @harness.read_inst_word(addr)
          else
            # Pipeline harness: read directly from inst_mem
            @harness.instance_variable_get(:@inst_mem).read_word(addr)
          end
        end

        def read_data_word(addr)
          if @harness.respond_to?(:read_data_word)
            @harness.read_data_word(addr)
          else
            @harness.read_data(addr)
          end
        end

        def write_data_word(addr, value)
          if @harness.respond_to?(:write_data_word)
            @harness.write_data_word(addr, value)
          else
            @harness.write_data(addr, value)
          end
        end

        def set_interrupts(software: nil, timer: nil, external: nil)
          @harness.set_interrupts(software: software, timer: timer, external: external)
        end

        def set_plic_sources(source1: nil, source10: nil)
          @harness.set_plic_sources(source1: source1, source10: source10)
        end

        def uart_receive_byte(byte)
          @harness.uart_receive_byte(byte)
        end

        def uart_receive_bytes(bytes)
          @harness.uart_receive_bytes(bytes)
        end

        def uart_receive_text(text)
          @harness.uart_receive_text(text)
        end

        def uart_tx_bytes
          @harness.uart_tx_bytes
        end

        def clear_uart_tx_bytes
          @harness.clear_uart_tx_bytes
        end

        def load_virtio_disk(bytes, offset: 0)
          @harness.load_virtio_disk(bytes, offset: offset)
        end

        def read_virtio_disk_byte(offset)
          @harness.read_virtio_disk_byte(offset)
        end

        def state
          @harness.state
        end
      end
    end
  end
end
