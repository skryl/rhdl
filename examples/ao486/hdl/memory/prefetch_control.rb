# ao486 Prefetch Control
# Ported from: rtl/ao486/memory/prefetch_control.v + autogen/prefetch_control.v
#
# Two-state controller: TLB_REQUEST → ICACHE.
# Handles TLB address translation requests, page-boundary-aware length
# limiting, and icache read request generation with FIFO backpressure.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../constants'

module RHDL
  module Examples
    module AO486
      class PrefetchControl < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst_n

        input :pr_reset

        # From prefetch module
        input :prefetch_address, width: 32
        input :prefetch_length, width: 5
        input :prefetch_su

        # From prefetch FIFO
        input :prefetchfifo_used, width: 5

        # TLB request outputs
        output :tlbcoderequest_do
        output :tlbcoderequest_address, width: 32
        output :tlbcoderequest_su

        # TLB response inputs
        input :tlbcode_do
        input :tlbcode_linear, width: 32
        input :tlbcode_physical, width: 32
        input :tlbcode_cache_disable

        # ICache read outputs
        output :icacheread_do
        output :icacheread_address, width: 32
        output :icacheread_length, width: 5
        output :icacheread_cache_disable

        STATE_TLB_REQUEST = 0
        STATE_ICACHE      = 1

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          @prev_clk = 0
          @state = STATE_TLB_REQUEST
          @linear = 0
          @physical = 0
          @cache_disable = 0
        end

        def propagate
          clk = in_val(:clk)
          rising = (clk == 1 && @prev_clk == 0)
          @prev_clk = clk

          if rising
            rst_n = in_val(:rst_n)

            if rst_n == 0
              @state = STATE_TLB_REQUEST
              @linear = 0
              @physical = 0
              @cache_disable = 0
            else
              pf_addr = in_val(:prefetch_address)
              pf_len = in_val(:prefetch_length)
              fifo_used = in_val(:prefetchfifo_used)
              pr_reset = in_val(:pr_reset) != 0

              # Page-aware length calculation
              left_in_page = 4096 - (pf_addr & 0xFFF)
              length = left_in_page < pf_len ? (left_in_page & 0x1F) : pf_len

              # Page crossing detection
              offset_update = (pf_addr >> 12) == (@linear >> 12) && (pf_addr & 0xFFF) != (@linear & 0xFFF)
              page_cross = (pf_addr >> 12) != (@linear >> 12)

              # State machine (from autogen/prefetch_control.v)
              state_next = @state
              linear_next = @linear
              physical_next = @physical
              cd_next = @cache_disable

              if @state == STATE_TLB_REQUEST
                if !pr_reset && pf_len > 0 && fifo_used < 3
                  if in_val(:tlbcode_do) != 0
                    linear_next = in_val(:tlbcode_linear)
                    physical_next = in_val(:tlbcode_physical)
                    cd_next = in_val(:tlbcode_cache_disable)
                    state_next = STATE_ICACHE
                  end
                end
              elsif @state == STATE_ICACHE
                if page_cross || pr_reset || fifo_used >= 8
                  state_next = STATE_TLB_REQUEST
                end
                if offset_update
                  linear_next = (@linear & 0xFFFFF000) | (pf_addr & 0xFFF)
                  physical_next = (@physical & 0xFFFFF000) | (pf_addr & 0xFFF)
                end
              end

              @state = state_next
              @linear = linear_next
              @physical = physical_next
              @cache_disable = cd_next
            end
          end

          # Combinational outputs
          pf_addr = in_val(:prefetch_address)
          pf_len = in_val(:prefetch_length)
          fifo_used = in_val(:prefetchfifo_used)
          pr_reset = in_val(:pr_reset) != 0

          left_in_page = 4096 - (pf_addr & 0xFFF)
          length = left_in_page < pf_len ? (left_in_page & 0x1F) : pf_len

          offset_update = (pf_addr >> 12) == (@linear >> 12) && (pf_addr & 0xFFF) != (@linear & 0xFFF)
          page_cross = (pf_addr >> 12) != (@linear >> 12)

          out_set(:tlbcoderequest_address, pf_addr)
          out_set(:tlbcoderequest_su, in_val(:prefetch_su))

          # TLB request: in TLB_REQUEST state, length>0, FIFO<3, not resetting
          tlb_req = (@state == STATE_TLB_REQUEST && !pr_reset && pf_len > 0 && fifo_used < 3) ? 1 : 0
          out_set(:tlbcoderequest_do, tlb_req)

          # ICache read
          if @state == STATE_TLB_REQUEST && !pr_reset && pf_len > 0 && fifo_used < 3 && in_val(:tlbcode_do) != 0
            out_set(:icacheread_do, 1)
            out_set(:icacheread_address, in_val(:tlbcode_physical))
            out_set(:icacheread_length, length)
            out_set(:icacheread_cache_disable, in_val(:tlbcode_cache_disable))
          elsif @state == STATE_ICACHE && !(page_cross || pr_reset || fifo_used >= 8)
            out_set(:icacheread_do, 1)
            addr = offset_update ? ((@physical & 0xFFFFF000) | (pf_addr & 0xFFF)) : @physical
            out_set(:icacheread_address, addr)
            out_set(:icacheread_length, length)
            out_set(:icacheread_cache_disable, @cache_disable)
          else
            out_set(:icacheread_do, 0)
            out_set(:icacheread_address, 0)
            out_set(:icacheread_length, 0)
            out_set(:icacheread_cache_disable, 0)
          end
        end
      end
    end
  end
end
