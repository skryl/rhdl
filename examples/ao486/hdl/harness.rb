# ao486 Harness - Simulation Test Harness
# Wraps the ao486 CPU for behavior simulation and testing.
# Provides a high-level interface: reset, step, memory read/write,
# register inspection.
#
# Initially a skeleton for Phase 0 — will grow as pipeline stages
# are added in later phases.

require_relative '../../../lib/rhdl/hdl'
require_relative 'constants'

module RHDL
  module Examples
    module AO486
      class Harness
        include Constants

        attr_reader :clock_count

        def initialize
          @memory = {}  # Sparse 32-bit address space (byte-addressable)
          @clock_count = 0

          # Architectural state (will be replaced by actual CPU component in Phase 5+)
          @eip = Constants::STARTUP_EIP
          @eax = Constants::STARTUP_EAX
          @ebx = Constants::STARTUP_EBX
          @ecx = Constants::STARTUP_ECX
          @edx = Constants::STARTUP_EDX
          @esp = Constants::STARTUP_ESP
          @ebp = Constants::STARTUP_EBP
          @esi = Constants::STARTUP_ESI
          @edi = Constants::STARTUP_EDI
        end

        def reset
          @clock_count = 0
          @eip = Constants::STARTUP_EIP
          @eax = Constants::STARTUP_EAX
          @ebx = Constants::STARTUP_EBX
          @ecx = Constants::STARTUP_ECX
          @edx = Constants::STARTUP_EDX
          @esp = Constants::STARTUP_ESP
          @ebp = Constants::STARTUP_EBP
          @esi = Constants::STARTUP_ESI
          @edi = Constants::STARTUP_EDI
        end

        # Memory interface
        def read_mem(addr)
          @memory[addr & 0xFFFF_FFFF] || 0
        end

        def write_mem(addr, value)
          @memory[addr & 0xFFFF_FFFF] = value & 0xFF
        end

        # Register accessors
        def eip; @eip; end
        def eax; @eax; end
        def ebx; @ebx; end
        def ecx; @ecx; end
        def edx; @edx; end
        def esp; @esp; end
        def ebp; @ebp; end
        def esi; @esi; end
        def edi; @edi; end

        # State inspection
        def state
          {
            eip: @eip, eax: @eax, ebx: @ebx, ecx: @ecx,
            edx: @edx, esp: @esp, ebp: @ebp, esi: @esi, edi: @edi,
            cycles: @clock_count
          }
        end
      end
    end
  end
end
