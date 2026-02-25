# ao486 Prefetch FIFO
# Ported from: rtl/ao486/memory/prefetch_fifo.v
#
# 16-entry FIFO buffering instruction bytes from icache to fetch stage.
# Stores 36-bit entries {length[3:0], data[31:0]}, outputs 68-bit
# entries {length[3:0], padding[31:0], data[31:0]}.
# Has bypass path for zero-latency when FIFO is empty.
# Can inject GP_FAULT/PF_FAULT markers.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../constants'

module RHDL
  module Examples
    module AO486
      class PrefetchFifo < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst_n

        input :pr_reset  # synchronous clear

        input :prefetchfifo_signal_limit_do  # inject GP fault
        input :prefetchfifo_signal_pf_do     # inject PF fault

        input :prefetchfifo_write_do
        input :prefetchfifo_write_data, width: 36  # {length[3:0], data[31:0]}

        input :prefetchfifo_accept_do  # read/consume from FIFO

        output :prefetchfifo_used, width: 5        # bit4=full, bits3:0=count
        output :prefetchfifo_accept_data, width: 68 # {length[3:0], pad[31:0], data[31:0]}
        output :prefetchfifo_accept_empty

        FIFO_DEPTH = 16

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          @prev_clk = 0
          @fifo = []
        end

        def propagate
          clk = in_val(:clk)
          rising = (clk == 1 && @prev_clk == 0)
          @prev_clk = clk

          if rising
            rst_n = in_val(:rst_n)

            if rst_n == 0
              @fifo.clear
            elsif in_val(:pr_reset) != 0
              @fifo.clear
            else
              # Read side (consume)
              if in_val(:prefetchfifo_accept_do) != 0 && !@fifo.empty?
                @fifo.shift
              end

              # Determine write data (fault injection takes priority)
              do_write = false
              write_data = 0

              if in_val(:prefetchfifo_signal_limit_do) != 0
                do_write = true
                write_data = (Constants::PREFETCH_GP_FAULT << 32)
              elsif in_val(:prefetchfifo_signal_pf_do) != 0
                do_write = true
                write_data = (Constants::PREFETCH_PF_FAULT << 32)
              elsif in_val(:prefetchfifo_write_do) != 0
                # Only store if FIFO not empty or not simultaneously reading
                # (if empty+write, bypass path handles it combinationally)
                empty = @fifo.empty?
                accepting = in_val(:prefetchfifo_accept_do) != 0
                if !empty || !accepting
                  do_write = true
                  write_data = in_val(:prefetchfifo_write_data)
                end
              end

              if do_write && @fifo.length < FIFO_DEPTH
                @fifo.push(write_data)
              end
            end
          end

          # Combinational outputs
          empty = @fifo.empty?
          writing = in_val(:prefetchfifo_write_do) != 0
          bypass = writing && empty

          if bypass
            wd = in_val(:prefetchfifo_write_data)
            len = (wd >> 32) & 0xF
            data = wd & 0xFFFF_FFFF
            out_set(:prefetchfifo_accept_data, (len << 64) | data)
            out_set(:prefetchfifo_accept_empty, 0)
          elsif !empty
            entry = @fifo.first
            len = (entry >> 32) & 0xF
            data = entry & 0xFFFF_FFFF
            out_set(:prefetchfifo_accept_data, (len << 64) | data)
            out_set(:prefetchfifo_accept_empty, 0)
          else
            out_set(:prefetchfifo_accept_data, 0)
            out_set(:prefetchfifo_accept_empty, 1)
          end

          full = @fifo.length >= FIFO_DEPTH ? 1 : 0
          out_set(:prefetchfifo_used, (full << 4) | (@fifo.length & 0xF))
        end
      end
    end
  end
end
