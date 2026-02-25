# ao486 Instruction Cache
# Ported from: rtl/ao486/memory/icache.v
#
# Simplified for simulation: models the icache wrapper state machine
# (IDLE → READ) with burst length calculation and barrel-shifted FIFO writes.
# The L1 cache backing store is modeled as pass-through to memory
# (readcode_do/readcode_done interface).

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../constants'

module RHDL
  module Examples
    module AO486
      class ICache < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst_n

        input :cache_disable

        input :pr_reset
        input :prefetch_address, width: 32
        input :delivered_eip, width: 32

        # From prefetch_control
        input :icacheread_do
        input :icacheread_address, width: 32
        input :icacheread_length, width: 5

        # Memory interface
        output :readcode_do
        output :readcode_address, width: 32
        input :readcode_done
        input :readcode_partial, width: 32

        # To prefetch FIFO
        output :prefetchfifo_write_do
        output :prefetchfifo_write_data, width: 36  # {length[3:0], data[31:0]}

        # To prefetch module
        output :prefetched_do
        output :prefetched_length, width: 5

        # Snoop interface
        input :snoop_addr, width: 26   # [27:2]
        input :snoop_data, width: 32
        input :snoop_be, width: 4
        input :snoop_we

        output :reset_prefetch

        STATE_IDLE = 0
        STATE_READ = 1

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          @prev_clk = 0
          @state = STATE_IDLE
          @length = 0          # remaining bytes to fetch
          @partial_length = 0  # 12-bit shift register: {burst3, burst2, burst1, burst0} x 3 bits each
          @reset_waiting = false
          @reset_prefetch = false
          @reset_prefetch_count = 0
          @read_address = 0

          # Snoop detection
          @prefetch_checknext = false
          @prefetch_checkaddr = 0
          @min_check = 0
          @max_check = 0
        end

        def propagate
          clk = in_val(:clk)
          rising = (clk == 1 && @prev_clk == 0)
          @prev_clk = clk

          rst_n = in_val(:rst_n)
          reset_combined = @reset_prefetch || (in_val(:pr_reset) != 0)

          # --- Combinational outputs (use CURRENT state, before clock edge) ---

          # readcode_do: active in READ state when still needing data
          needs_data = rst_n != 0 && @state == STATE_READ && !reset_combined && !@reset_waiting
          out_set(:readcode_do, needs_data ? 1 : 0)
          out_set(:readcode_address, @read_address & 0xFFFF_FFFC)

          # FIFO write: in READ state when data arrives and no reset
          data_valid = @state == STATE_READ && !reset_combined && !@reset_waiting &&
                       in_val(:readcode_done) != 0
          out_set(:prefetchfifo_write_do, data_valid ? 1 : 0)
          out_set(:prefetched_do, data_valid ? 1 : 0)

          if data_valid
            pl = @partial_length & 0x7
            mem_data = in_val(:readcode_partial)
            pl_cur = partial_length_current

            # Barrel-shift data based on partial_length
            case pl
            when 1
              write_data = (1 << 32) | ((mem_data >> 24) & 0xFF)
            when 2
              len = @length > 2 ? 2 : @length
              write_data = (len << 32) | ((mem_data >> 16) & 0xFFFF)
            when 3
              len = @length > 3 ? 3 : @length
              write_data = (len << 32) | ((mem_data >> 8) & 0xFFFFFF)
            else # 4 or more
              len = @length > 4 ? 4 : @length
              write_data = (len << 32) | (mem_data & 0xFFFF_FFFF)
            end

            out_set(:prefetchfifo_write_data, write_data & 0xF_FFFF_FFFF)
            out_set(:prefetched_length, pl_cur)
          else
            out_set(:prefetchfifo_write_data, 0)
            out_set(:prefetched_length, 0)
          end

          out_set(:reset_prefetch, @reset_prefetch ? 1 : 0)

          # --- Sequential update (on rising clock edge) ---

          if rising
            if rst_n == 0
              @state = STATE_IDLE
              @length = 0
              @partial_length = 0
              @reset_waiting = false
              @reset_prefetch = false
              @reset_prefetch_count = 0
              @prefetch_checknext = false
            else
              # Snoop detection (simplified)
              old_checknext = @prefetch_checknext
              old_checkaddr = @prefetch_checkaddr

              @prefetch_checknext = in_val(:snoop_we) != 0
              @prefetch_checkaddr = (in_val(:snoop_addr) & 0x3FFFFFF) << 2
              @min_check = in_val(:delivered_eip)
              @max_check = in_val(:prefetch_address) + 20

              if old_checknext && old_checkaddr >= @min_check && old_checkaddr <= @max_check
                @reset_prefetch = true
                @reset_prefetch_count = 2
              end

              if @reset_prefetch_count > 0
                @reset_prefetch_count -= 1
                @reset_prefetch = false if @reset_prefetch_count == 0
              end

              reset_combined = @reset_prefetch || (in_val(:pr_reset) != 0)

              # Reset waiting flag
              if reset_combined && @state != STATE_IDLE
                @reset_waiting = true
              elsif @state == STATE_IDLE
                @reset_waiting = false
              end

              # State machine
              if @state == STATE_IDLE
                if !reset_combined && in_val(:icacheread_do) != 0 && in_val(:icacheread_length) > 0
                  @state = STATE_READ
                  @partial_length = compute_length_burst(in_val(:icacheread_address))
                  @length = in_val(:icacheread_length)
                  @read_address = in_val(:icacheread_address)
                end
              elsif @state == STATE_READ
                if !reset_combined && !@reset_waiting
                  if in_val(:readcode_done) != 0
                    pl_current = partial_length_current
                    if (@partial_length & 0x7) > 0 && @length > 0
                      @length -= pl_current
                      @partial_length = (@partial_length >> 3) & 0x1FF
                    end
                  end
                end
                @state = STATE_IDLE if in_val(:readcode_done) != 0
              end
            end
          end
        end

        private

        # Compute burst lengths based on address alignment
        # Returns 12-bit packed value: {burst3[2:0], burst2[2:0], burst1[2:0], burst0[2:0]}
        def compute_length_burst(addr)
          case addr & 0x3
          when 0 then (4 << 9) | (4 << 6) | (4 << 3) | 4  # 4,4,4,4
          when 1 then (4 << 9) | (4 << 6) | (4 << 3) | 3  # 3,4,4,4
          when 2 then (4 << 9) | (4 << 6) | (4 << 3) | 2  # 2,4,4,4
          when 3 then (4 << 9) | (4 << 6) | (4 << 3) | 1  # 1,4,4,4
          end
        end

        # MIN(partial_length[2:0], length)
        def partial_length_current
          pl = @partial_length & 0x7
          pl > @length ? @length : pl
        end
      end
    end
  end
end
