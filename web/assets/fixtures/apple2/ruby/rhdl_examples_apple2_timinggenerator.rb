# frozen_string_literal: true

# Apple II Timing Generator
# Based on Stephen A. Edwards' neoapple2 implementation
#
# This module takes a 14.31818 MHz master clock and divides it down to generate
# the various lower-frequency signals (7M, phase 0, colorburst) as well as
# horizontal and vertical blanking and sync signals for video and video addresses.
#
# Clock domains:
# - CLK_14M: 14.31818 MHz master clock
# - CLK_7M: 7.15909 MHz (CLK_14M / 2)
# - Q3: ~2 MHz signal in phase with PHI0
# - PHI0: 1.0 MHz processor clock
# - COLOR_REF: 3.579545 MHz colorburst

require 'rhdl/hdl'

module RHDL
  module Examples
    module Apple2
      class TimingGenerator < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      # Master clock input
      input :clk_14m

      # Mode inputs
      input :text_mode
      input :page2
      input :hires

      # Clock outputs
      output :clk_7m
      output :q3                           # 2 MHz signal in phase with PHI0
      output :ras_n                        # DRAM row address strobe (active low)
      output :cas_n                        # DRAM column address strobe (active low)
      output :ax                           # Address multiplexer select
      output :phi0                         # 1.0 MHz processor clock
      output :pre_phi0                     # One 14M cycle before PHI0
      output :color_ref                    # 3.579545 MHz colorburst

      # Video address output
      output :video_address, width: 16

      # Horizontal counter signals
      output :h0                           # H counter bit 0
      output :va                           # Character row address
      output :vb
      output :vc
      output :v2
      output :v4

      # Blanking signals
      output :hbl                          # Horizontal blanking
      output :vbl                          # Vertical blanking
      output :blank                        # Composite blanking
      output :ldps_n                       # Load parallel shift
      output :ld194                        # Load 194

      # Internal registers (declared as wires for sequential access)
      # H counter: 7 bits (0, 40-127 = 65 states)
      # V counter: 9 bits ($FA-$1FF = 262 states)
      wire :h, width: 7
      wire :v, width: 9

      # DRAM signal generator (74S195 shift register)
      # State format: {q3, cas_n, ax, ras_n}
      sequential clock: :clk_14m, reset_values: {
        clk_7m: 0, q3: 0, cas_n: 0, ax: 0, ras_n: 0,
        phi0: 0, pre_phi0: 0, color_ref: 0,
        h: 0, v: 0b011111010  # V starts at $FA
      } do
        # Color delay for once-a-line hiccup
        color_delay_n = ~(~color_ref & (~ax & ~cas_n) & phi0 & ~h[6])

        # DRAM timing state machine (74S195)
        # When Q3=1: shift left (q3,cas_n,ax,ras_n) <= (cas_n,ax,ras_n,0)
        # When Q3=0: load (q3,cas_n,ax,ras_n) <= (ras_n,ax,color_delay_n,ax)
        next_q3 = mux(q3, cas_n, ras_n)
        next_cas_n = mux(q3, ax, ax)
        next_ax = mux(q3, ras_n, color_delay_n)
        next_ras_n = mux(q3, lit(0, width: 1), ax)

        q3 <= next_q3
        cas_n <= next_cas_n
        ax <= next_ax
        ras_n <= next_ras_n

        # Main clock signal generator (74S175)
        color_ref <= clk_7m ^ color_ref
        clk_7m <= ~clk_7m
        phi0 <= pre_phi0

        # Update pre_phi0 when ax is high
        pre_phi0 <= mux(ax, ~(q3 ^ phi0), pre_phi0)

        # Horizontal counter (65 states: 0, 40-127)
        # Vertical counter (262 states: $FA-$1FF)
        # Increment on specific phase of LDPS_N
        ldps_condition = phi0 & ~ax & ((q3 & ras_n) | (~q3 & color_delay_n))

        # Horizontal counter update
        h_next = mux(h[6],
          h + lit(1, width: 7),   # If H(6)=1, increment
          lit(0b1000000, width: 7)  # If H(6)=0, reset to 64
        )

        # Check if H wraps (H = 127)
        h_wrapped = (h == lit(0b1111111, width: 7))

        # Vertical counter update
        v_next = mux(h_wrapped,
          mux(v == lit(0b111111111, width: 9),
            lit(0b011111010, width: 9),  # Wrap to $FA
            v + lit(1, width: 9)         # Increment
          ),
          v
        )

        h <= mux(ldps_condition, h_next, h)
        v <= mux(ldps_condition, v_next, v)
      end

      # Combinational logic for output signals
      behavior do
        # LDPS_N and LD194 generation
        ldps_n <= ~(phi0 & ~ax & ~cas_n)
        ld194 <= ~(phi0 & ~ax & ~cas_n & ~clk_7m)

        # Horizontal counter output bits
        h0 <= h[0]

        # Vertical counter output bits
        va <= v[0]
        vb <= v[1]
        vc <= v[2]
        v2 <= v[5]
        v4 <= v[7]

        # Blanking signals
        # HBL = NOT (H(5) OR (H(3) AND H(4)))
        hbl_i = ~(h[5] | (h[3] & h[4]))
        hbl <= hbl_i

        # VBL = V(6) AND V(7)
        vbl_i = v[6] & v[7]
        vbl <= vbl_i

        # Composite blanking
        blank <= hbl_i | vbl_i

        # Video address calculation
        # Bits 2:0 = H(2:0)
        # Bits 6:3 = computed from H and V
        # Bits 9:7 = V(5:3)
        # Bits 14:10 = mode-dependent

        video_address <= cat(
          lit(0, width: 1),                                    # Bit 15 = 0
          mux(hires,                                           # Bits 14:10
            cat(page2, ~page2, v[2..0]),
            cat(lit(0, width: 2), hbl_i, page2, ~page2)
          ),
          v[5..3],                                             # Bits 9:7
          # Bits 6:3: complex address generation
          (cat(~h[5], v[6], h[4], h[3]) +
           cat(v[7], ~h[5], v[7], lit(1, width: 1)) +
           cat(lit(0, width: 3), v[6]))[3..0],
          h[2..0]                                              # Bits 2:0
        )
      end
    end
  end
  end
end
