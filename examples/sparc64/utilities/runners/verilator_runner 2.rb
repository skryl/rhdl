# frozen_string_literal: true

require_relative '../integration/constants'

module RHDL
  module Examples
    module SPARC64
      class VerilogRunner
        include Integration

        class DefaultAdapter
          def initialize(*)
            raise NotImplementedError,
                  'SPARC64 Verilator harness build is not implemented in this slice; inject an adapter or extend this runner next'
          end
        end

        attr_reader :clock_count

        def initialize(adapter: nil, adapter_factory: nil)
          factory = adapter_factory || -> { DefaultAdapter.new }
          @adapter = adapter || factory.call
          @clock_count = 0
        end

        def native?
          true
        end

        def simulator_type
          @adapter.respond_to?(:simulator_type) ? @adapter.simulator_type : :hdl_verilator
        end

        def backend
          :verilator
        end

        def reset!
          @clock_count = 0
          @adapter.reset!
          self
        end

        def run_cycles(n)
          ran = @adapter.run_cycles(n.to_i)
          @clock_count += n.to_i if ran.nil?
          @clock_count += ran.to_i if ran
          ran
        end

        def load_images(boot_image:, program_image:)
          @adapter.load_images(boot_image: boot_image, program_image: program_image)
          self
        end

        def read_memory(addr, length)
          @adapter.read_memory(addr.to_i, length.to_i)
        end

        def write_memory(addr, bytes)
          @adapter.write_memory(addr.to_i, bytes)
        end

        def mailbox_status
          @adapter.mailbox_status
        end

        def mailbox_value
          @adapter.mailbox_value
        end

        def wishbone_trace
          Integration.normalize_wishbone_trace(@adapter.wishbone_trace)
        end

        def unmapped_accesses
          Array(@adapter.unmapped_accesses)
        end

        def completed?
          mailbox_status != 0
        end

        def run_until_complete(max_cycles:, batch_cycles: 1_000)
          while clock_count < max_cycles.to_i
            run_cycles([batch_cycles.to_i, max_cycles.to_i - clock_count].min)
            return completion_result if completed? || unmapped_accesses.any?
          end

          completion_result(timeout: true)
        end

        private

        def completion_result(timeout: false)
          trace = wishbone_trace
          faults = unmapped_accesses
          {
            completed: completed?,
            timeout: timeout,
            cycles: clock_count,
            boot_handoff_seen: trace.any? { |event| event.addr.to_i >= Integration::PROGRAM_BASE },
            secondary_core_parked: faults.empty?,
            mailbox_status: mailbox_status,
            mailbox_value: mailbox_value,
            unmapped_accesses: faults,
            wishbone_trace: trace
          }
        end
      end

      VerilatorRunner = VerilogRunner
    end
  end
end
