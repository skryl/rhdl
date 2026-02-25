# ao486 Prefetch Module
# Ported from: rtl/ao486/memory/prefetch.v
#
# Tracks code segment linear address and segment limit.
# Coordinates with prefetch_control and icache to fill the prefetch FIFO.
# Computes CS base/limit from descriptor cache, manages delivered_eip.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../constants'

module RHDL
  module Examples
    module AO486
      class Prefetch < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst_n

        input :pr_reset
        input :reset_prefetch

        input :prefetch_cpl, width: 2
        input :prefetch_eip, width: 32
        input :cs_cache, width: 64

        # From icache
        input :prefetched_do
        input :prefetched_length, width: 5

        # From fetch (via FIFO accept)
        input :prefetched_accept_do
        input :prefetched_accept_length, width: 4

        # To prefetch_control/TLB
        output :prefetch_address, width: 32
        output :prefetch_length, width: 5
        output :prefetch_su

        # To prefetch FIFO
        output :prefetchfifo_signal_limit_do

        # To fetch
        output :delivered_eip, width: 32

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          @prev_clk = 0
          @linear = Constants::STARTUP_PREFETCH_LINEAR
          @limit = Constants::STARTUP_PREFETCH_LIMIT
          @limit_signaled = false
          @delivered_eip = Constants::STARTUP_PREFETCH_LINEAR
          @prefetched_accept_do_1 = 0
          @prefetched_accept_length_1 = 0
          @limit_signal_pending = false
        end

        def propagate
          clk = in_val(:clk)
          rising = (clk == 1 && @prev_clk == 0)
          @prev_clk = clk

          if rising
            rst_n = in_val(:rst_n)

            if rst_n == 0
              @linear = Constants::STARTUP_PREFETCH_LINEAR
              @limit = Constants::STARTUP_PREFETCH_LIMIT
              @limit_signaled = false
              @limit_signal_pending = false
              @delivered_eip = Constants::STARTUP_PREFETCH_LINEAR
              @prefetched_accept_do_1 = 0
              @prefetched_accept_length_1 = 0
            else
              cs = in_val(:cs_cache)
              eip = in_val(:prefetch_eip)
              cs_base = ((cs >> 56) & 0xFF) << 24 | ((cs >> 16) & 0xFFFFFF)
              g_bit = (cs >> Constants::DESC_BIT_G) & 1
              cs_limit = if g_bit == 1
                           ((cs >> 48) & 0xF) << 28 | ((cs & 0xFFFF) << 12) | 0xFFF
                         else
                           ((cs >> 48) & 0xF) << 16 | (cs & 0xFFFF)
                         end

              pr_reset = in_val(:pr_reset) != 0
              reset_pf = in_val(:reset_prefetch) != 0

              # Limit register
              if pr_reset || reset_pf
                @limit = cs_limit >= eip ? (cs_limit - eip + 1) : 0
              elsif in_val(:prefetched_do) != 0
                length = compute_length
                @limit = (@limit >= length) ? @limit - length : 0
              end

              # Delayed accept signals
              prev_accept_do = @prefetched_accept_do_1
              prev_accept_len = @prefetched_accept_length_1
              @prefetched_accept_do_1 = in_val(:prefetched_accept_do)
              @prefetched_accept_length_1 = in_val(:prefetched_accept_length)

              # Linear address and delivered_eip
              if pr_reset
                @linear = (cs_base + eip) & 0xFFFF_FFFF
                @delivered_eip = (cs_base + eip) & 0xFFFF_FFFF
              else
                if reset_pf
                  @linear = if prev_accept_do != 0
                              (@delivered_eip + prev_accept_len) & 0xFFFF_FFFF
                            else
                              @delivered_eip
                            end
                elsif in_val(:prefetched_do) != 0
                  length = compute_length
                  @linear = (@linear + length) & 0xFFFF_FFFF
                end

                if prev_accept_do != 0
                  @delivered_eip = (@delivered_eip + prev_accept_len) & 0xFFFF_FFFF
                end
              end

              # Limit signaled flag: latches on the cycle AFTER the
              # combinational signal fires (Verilog: responds to
              # prefetchfifo_signal_limit_do which is the output)
              if pr_reset
                @limit_signaled = false
              elsif @limit_signal_pending
                @limit_signaled = true
              end
              # Compute what the combinational output will be this cycle
              @limit_signal_pending = (@limit == 0 && !@limit_signaled)
            end
          end

          # Combinational outputs
          out_set(:prefetch_address, @linear & 0xFFFF_FFFF)
          pf_len = @limit > 16 ? 16 : (@limit & 0x1F)
          out_set(:prefetch_length, pf_len)
          out_set(:prefetch_su, in_val(:prefetch_cpl) == 3 ? 1 : 0)
          out_set(:prefetchfifo_signal_limit_do,
                  @limit == 0 && !@limit_signaled ? 1 : 0)
          out_set(:delivered_eip, @delivered_eip & 0xFFFF_FFFF)
        end

        private

        def compute_length
          pf_len = in_val(:prefetched_length)
          if @limit < pf_len
            @limit & 0x1F
          else
            pf_len
          end
        end
      end
    end
  end
end
