# ao486 Global Registers
# Ported from: rtl/ao486/global_regs.v
#
# 5 x 32-bit parameter registers and 2 x 64-bit descriptor registers
# with computed base/limit outputs for descriptors.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'

module RHDL
  module Examples
    module AO486
      class GlobalRegs < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst_n

        # Parameter set/value pairs
        input :glob_param_1_set
        input :glob_param_1_value, width: 32
        input :glob_param_2_set
        input :glob_param_2_value, width: 32
        input :glob_param_3_set
        input :glob_param_3_value, width: 32
        input :glob_param_4_set
        input :glob_param_4_value, width: 32
        input :glob_param_5_set
        input :glob_param_5_value, width: 32

        # Descriptor set/value pairs
        input :glob_descriptor_set
        input :glob_descriptor_value, width: 64
        input :glob_descriptor_2_set
        input :glob_descriptor_2_value, width: 64

        # Parameter outputs
        output :glob_param_1, width: 32
        output :glob_param_2, width: 32
        output :glob_param_3, width: 32
        output :glob_param_4, width: 32
        output :glob_param_5, width: 32

        # Descriptor outputs
        output :glob_descriptor, width: 64
        output :glob_descriptor_2, width: 64

        # Computed descriptor fields
        output :glob_desc_base, width: 32
        output :glob_desc_limit, width: 32
        output :glob_desc_2_limit, width: 32

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          @prev_clk = 0
          @regs = {
            glob_param_1: 0, glob_param_2: 0, glob_param_3: 0,
            glob_param_4: 0, glob_param_5: 0,
            glob_descriptor: 0, glob_descriptor_2: 0
          }
        end

        def propagate
          clk = in_val(:clk)
          rising = (clk == 1 && @prev_clk == 0)
          @prev_clk = clk

          if rising
            rst_n = in_val(:rst_n)

            if rst_n == 0
              @regs.each_key { |k| @regs[k] = 0 }
            else
              (1..5).each do |i|
                if in_val(:"glob_param_#{i}_set") != 0
                  @regs[:"glob_param_#{i}"] = in_val(:"glob_param_#{i}_value")
                end
              end
              if in_val(:glob_descriptor_set) != 0
                @regs[:glob_descriptor] = in_val(:glob_descriptor_value)
              end
              if in_val(:glob_descriptor_2_set) != 0
                @regs[:glob_descriptor_2] = in_val(:glob_descriptor_2_value)
              end
            end
          end

          # Drive outputs from register state
          @regs.each { |k, v| out_set(k, v) }

          # Combinational: compute descriptor base and limit
          desc = @regs[:glob_descriptor]
          desc2 = @regs[:glob_descriptor_2]

          # Base = { desc[63:56], desc[39:16] }
          base_hi = (desc >> 56) & 0xFF
          base_lo = (desc >> 16) & 0xFF_FFFF
          out_set(:glob_desc_base, ((base_hi << 24) | base_lo) & 0xFFFF_FFFF)

          # Limit with granularity
          limit_hi = (desc >> 48) & 0xF
          limit_lo = desc & 0xFFFF
          g_bit = (desc >> 55) & 1
          limit = if g_bit == 1
                    (limit_hi << 28) | (limit_lo << 12) | 0xFFF
                  else
                    (limit_hi << 16) | limit_lo
                  end
          out_set(:glob_desc_limit, limit & 0xFFFF_FFFF)

          # Descriptor 2 limit
          limit2_hi = (desc2 >> 48) & 0xF
          limit2_lo = desc2 & 0xFFFF
          g2_bit = (desc2 >> 55) & 1
          limit2 = if g2_bit == 1
                     (limit2_hi << 28) | (limit2_lo << 12) | 0xFFF
                   else
                     (limit2_hi << 16) | limit2_lo
                   end
          out_set(:glob_desc_2_limit, limit2 & 0xFFFF_FFFF)
        end
      end
    end
  end
end
