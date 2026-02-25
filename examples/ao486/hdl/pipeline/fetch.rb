# ao486 Fetch Pipeline Stage
# Ported from: rtl/ao486/pipeline/fetch.v
#
# Sits between prefetch FIFO and decode stage.
# Barrel-shifts 64-bit instruction window based on fetch_count offset.
# Detects GP fault and page fault markers in FIFO data.
# Controls FIFO accept and partial consumption flow.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../constants'

module RHDL
  module Examples
    module AO486
      class Fetch < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst_n

        input :pr_reset

        # EIP from write-back
        input :wr_eip, width: 32

        output :prefetch_eip, width: 32

        # Prefetch FIFO interface
        output :prefetchfifo_accept_do
        input :prefetchfifo_accept_data, width: 68  # {length[3:0], pad[31:0], data[31:0]}
        input :prefetchfifo_accept_empty

        # Fetch output to decode
        output :fetch_valid, width: 4
        output :fetch, width: 64
        output :fetch_limit
        output :fetch_page_fault

        # Feedback from decode
        input :dec_acceptable, width: 4

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          @prev_clk = 0
          @fetch_count = 0
        end

        def propagate
          clk = in_val(:clk)
          rising = (clk == 1 && @prev_clk == 0)
          @prev_clk = clk

          # Combinational: EIP passthrough
          out_set(:prefetch_eip, in_val(:wr_eip))

          # Read FIFO data
          empty = in_val(:prefetchfifo_accept_empty) != 0
          data = in_val(:prefetchfifo_accept_data)
          data_len = (data >> 64) & 0xF
          data_64 = data & 0xFFFF_FFFF_FFFF_FFFF

          # Fault detection
          is_gp_fault = !empty && data_len == Constants::PREFETCH_GP_FAULT
          is_pf_fault = !empty && data_len == Constants::PREFETCH_PF_FAULT
          is_fault = !empty && data_len >= Constants::PREFETCH_MIN_FAULT

          out_set(:fetch_limit, is_gp_fault ? 1 : 0)
          out_set(:fetch_page_fault, is_pf_fault ? 1 : 0)

          # fetch_valid: bytes available after fetch_count offset
          if empty || is_fault
            fv = 0
          else
            fv = data_len - @fetch_count
            fv = 0 if fv < 0
          end
          out_set(:fetch_valid, fv & 0xF)

          # Barrel shift: shift data right by fetch_count bytes
          if empty
            out_set(:fetch, 0)
          else
            shifted = case @fetch_count
                      when 0 then data_64
                      when 1 then data_64 >> 8
                      when 2 then data_64 >> 16
                      when 3 then data_64 >> 24
                      when 4 then data_64 >> 32
                      when 5 then data_64 >> 40
                      when 6 then data_64 >> 48
                      when 7 then data_64 >> 56
                      else 0
                      end
            out_set(:fetch, shifted & 0xFFFF_FFFF_FFFF_FFFF)
          end

          # FIFO accept control
          dec_acc = in_val(:dec_acceptable)
          accept_do = dec_acc >= fv && !empty && !is_fault
          partial = dec_acc < fv && !empty && !is_fault

          out_set(:prefetchfifo_accept_do, accept_do ? 1 : 0)

          # Sequential: update fetch_count
          if rising
            rst_n = in_val(:rst_n)
            if rst_n == 0
              @fetch_count = 0
            elsif in_val(:pr_reset) != 0
              @fetch_count = 0
            elsif accept_do
              @fetch_count = 0
            elsif partial
              @fetch_count = (@fetch_count + dec_acc) & 0xF
            end
          end
        end
      end
    end
  end
end
