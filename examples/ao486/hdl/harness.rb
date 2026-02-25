# ao486 Harness - Simulation Test Harness
# Wraps the ao486 Pipeline for behavior simulation and testing.
# Provides a high-level interface: load binary, run, step, memory,
# register inspection, I/O callbacks.

require_relative '../../../lib/rhdl/hdl'
require_relative 'constants'
require_relative 'pipeline/pipeline'

module RHDL
  module Examples
    module AO486
      class Harness
        include Constants

        attr_reader :clock_count

        def initialize
          @pipeline = Pipeline.new
          @memory = {}  # Sparse 32-bit address space (byte-addressable)
          @clock_count = 0
        end

        def reset
          @pipeline = Pipeline.new
          @memory = {}
          @clock_count = 0
        end

        # Load a .COM binary at CS:0100h (standard DOS load point)
        def load_com(bytes)
          @pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
          bytes.each_with_index { |b, i| @memory[0x0100 + i] = b & 0xFF }
        end

        # Load raw bytes at a specific address
        def load_at(addr, bytes)
          bytes.each_with_index { |b, i| @memory[(addr + i) & 0xFFFF_FFFF] = b & 0xFF }
        end

        # Run until halt or max_steps exceeded
        def run(max_steps: 1000)
          max_steps.times do
            result = step
            return result if result == :halt
          end
          :timeout
        end

        # Execute one instruction
        def step
          result = @pipeline.step(@memory)
          @clock_count += 1
          result
        end

        # Memory interface
        def read_mem(addr)
          @memory[addr & 0xFFFF_FFFF] || 0
        end

        def write_mem(addr, value)
          @memory[addr & 0xFFFF_FFFF] = value & 0xFF
        end

        # Register access (delegates to Pipeline)
        def reg(name)
          @pipeline.reg(name)
        end

        def set_reg(name, value)
          @pipeline.set_reg(name, value)
        end

        # Legacy register accessors for backwards compatibility
        def eip; @pipeline.reg(:eip); end
        def eax; @pipeline.reg(:eax); end
        def ebx; @pipeline.reg(:ebx); end
        def ecx; @pipeline.reg(:ecx); end
        def edx; @pipeline.reg(:edx); end
        def esp; @pipeline.reg(:esp); end
        def ebp; @pipeline.reg(:ebp); end
        def esi; @pipeline.reg(:esi); end
        def edi; @pipeline.reg(:edi); end

        # I/O callbacks
        def on_io_write(&block)
          @pipeline.on_io_write(&block)
        end

        def on_io_read(&block)
          @pipeline.on_io_read(&block)
        end

        # State inspection
        def state
          {
            eip: eip, eax: eax, ebx: ebx, ecx: ecx,
            edx: edx, esp: esp, ebp: ebp, esi: esi, edi: edi,
            cycles: @clock_count
          }
        end

        # Access to underlying pipeline for advanced use
        attr_reader :pipeline
      end
    end
  end
end
