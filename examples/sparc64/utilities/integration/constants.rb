# frozen_string_literal: true

module RHDL
  module Examples
    module SPARC64
      module Integration
        REQUESTER_TAG_SHIFT = 59
        PHYSICAL_ADDR_MASK = (1 << REQUESTER_TAG_SHIFT) - 1
        FLASH_BOOT_BASE = 0x3_FFFF_C000
        PROGRAM_BASE = 0x0000_4000
        STACK_TOP = 0x0002_0000
        MAILBOX_STATUS = 0x0000_1000
        MAILBOX_VALUE = 0x0000_1008
        SUCCESS_STATUS = 0x0000_0000_0000_0001
        FAILURE_STATUS = 0xFFFF_FFFF_FFFF_FFFF

        WishboneEvent = Struct.new(
          :cycle,
          :op,
          :addr,
          :sel,
          :write_data,
          :read_data,
          keyword_init: true
        )

        class << self
          def canonical_bus_addr(addr)
            addr.to_i & PHYSICAL_ADDR_MASK
          end

          def normalize_wishbone_trace(events)
            Array(events).map { |event| normalize_wishbone_event(event) }
          end

          def normalize_wishbone_event(event)
            if event.respond_to?(:to_h)
              data = event.to_h
              return WishboneEvent.new(
                cycle: value_for(data, :cycle),
                op: value_for(data, :op),
                addr: canonical_bus_addr(value_for(data, :addr)),
                sel: value_for(data, :sel),
                write_data: value_for(data, :write_data),
                read_data: value_for(data, :read_data)
              )
            end

            raise ArgumentError, "Unsupported SPARC64 Wishbone event payload: #{event.inspect}"
          end

          private

          def value_for(data, key)
            data[key] || data[key.to_s]
          end
        end
      end
    end
  end
end
