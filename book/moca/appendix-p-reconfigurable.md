# Appendix P: FPGA Implementation

*Companion appendix to [Chapter 16: Reconfigurable Computing](16-reconfigurable-computing.md)*

## Overview

This appendix provides RHDL models of FPGA primitives and demonstrates how designs map to reconfigurable fabric.

---

## LUT Implementations

### Generic LUT

```ruby
module RHDL::FPGA
  # N-input Lookup Table
  class LUT < SimComponent
    parameter :n, default: 4  # Number of inputs
    parameter :init, default: 0  # Truth table contents (2^n bits)

    input :inputs, width: n
    output :out

    behavior do
      # LUT is just a memory read
      out <= (init >> inputs) & 1
    end
  end

  # 4-input LUT (most common)
  class LUT4 < SimComponent
    parameter :init, default: 0x0000  # 16-bit truth table

    input :a, :b, :c, :d
    output :out

    behavior do
      addr = (d << 3) | (c << 2) | (b << 1) | a
      out <= (init >> addr) & 1
    end
  end

  # 6-input LUT (modern FPGAs)
  class LUT6 < SimComponent
    parameter :init, default: 0  # 64-bit truth table

    input :i, width: 6
    output :o

    behavior do
      o <= (init >> i) & 1
    end

    # Can also be used as two 5-LUTs sharing inputs
    output :o5  # Output when i[5]=0

    behavior do
      o <= (init >> i) & 1
      o5 <= (init >> (i & 0x1F)) & 1
    end
  end
end
```

### LUT as Logic Gates

```ruby
module RHDL::FPGA
  # Create LUT4 configured as specific gates
  class LUT4Gates
    # LUT4 configured as 4-input AND
    def self.and4
      LUT4.new(init: 0x8000)  # Only output 1 when all inputs are 1
    end

    # LUT4 configured as 4-input OR
    def self.or4
      LUT4.new(init: 0xFFFE)  # Output 1 unless all inputs are 0
    end

    # LUT4 configured as 4-input XOR
    def self.xor4
      # XOR: output 1 when odd number of inputs are 1
      init = 0
      16.times do |i|
        ones = i.to_s(2).count('1')
        init |= (ones.odd? ? 1 : 0) << i
      end
      LUT4.new(init: init)  # 0x6996
    end

    # LUT4 configured as 2:1 MUX
    # out = sel ? b : a
    def self.mux2
      # a=i0, b=i1, sel=i2
      # When sel=0, out=a (bits 0,2,4,6 of truth table = a)
      # When sel=1, out=b (bits 1,3,5,7 of truth table = b)
      LUT4.new(init: 0xCACA)
    end

    # LUT4 configured as full adder sum output
    def self.fa_sum
      # sum = a ^ b ^ cin (i0, i1, i2)
      LUT4.new(init: 0x9696)  # XOR pattern
    end

    # LUT4 configured as full adder carry output
    def self.fa_carry
      # cout = (a & b) | (a & cin) | (b & cin)
      LUT4.new(init: 0xE8E8)  # Majority function
    end
  end
end
```

### LUT Initialization

```ruby
module RHDL::FPGA
  # Helper to generate LUT init values from boolean expressions
  class LUTInit
    def self.from_function(n_inputs, &block)
      init = 0
      (2**n_inputs).times do |i|
        inputs = n_inputs.times.map { |j| (i >> j) & 1 }
        output = block.call(*inputs)
        init |= (output ? 1 : 0) << i
      end
      init
    end

    # Examples:
    # AND:  from_function(4) { |a,b,c,d| a & b & c & d }
    # OR:   from_function(4) { |a,b,c,d| a | b | c | d }
    # XOR:  from_function(4) { |a,b,c,d| [a,b,c,d].count(1).odd? }
    # MUX:  from_function(3) { |a,b,sel| sel == 1 ? b : a }
  end
end
```

---

## Configurable Logic Block

### Basic Slice

```ruby
module RHDL::FPGA
  # Simplified FPGA Slice (part of a CLB)
  class Slice < SimComponent
    parameter :lut_init, default: 0

    # LUT inputs
    input :a, :b, :c, :d
    output :comb_out   # Combinational output
    output :reg_out    # Registered output

    # Clock and control
    input :clk
    input :ce          # Clock enable
    input :sr          # Set/reset

    # Output selection
    input :use_reg     # 1 = use registered output

    output :out

    # Internal components
    instance :lut, LUT4, init: lut_init
    instance :ff, DFlipFlop

    wire :lut_out

    port :a => [:lut, :a]
    port :b => [:lut, :b]
    port :c => [:lut, :c]
    port :d => [:lut, :d]
    port [:lut, :out] => :lut_out
    port :lut_out => :comb_out

    port :clk => [:ff, :clk]
    port :lut_out => [:ff, :d]
    port [:ff, :q] => :reg_out

    behavior do
      # Output mux: combinational or registered
      out <= use_reg == 1 ? reg_out : comb_out
    end
  end

  # Full slice with multiple LUTs and carry chain
  class FullSlice < SimComponent
    parameter :n_luts, default: 4

    input :inputs, width: 4 * n_luts  # 4 inputs per LUT
    input :clk
    input :ce, width: n_luts
    input :sr, width: n_luts
    input :use_reg, width: n_luts

    output :comb_out, width: n_luts
    output :reg_out, width: n_luts
    output :out, width: n_luts

    # Carry chain
    input :cin
    output :cout

    # LUT instances (simplified)
    behavior do
      n_luts.times do |i|
        lut_in = (inputs >> (i * 4)) & 0xF
        # Each LUT computes its function
        # Results go to comb_out, can be registered
      end

      # Carry chain
      cout <= cin  # Simplified; real carry chain is complex
    end
  end
end
```

### Carry Chain

```ruby
module RHDL::FPGA
  # Fast carry chain for arithmetic
  class CarryChain < SimComponent
    parameter :width, default: 4

    input :g, width: width   # Generate: a & b
    input :p, width: width   # Propagate: a ^ b
    input :cin

    output :c, width: width  # Carry at each position
    output :cout

    # Dedicated carry logic (much faster than LUT routing)
    behavior do
      carry = cin

      width.times do |i|
        c[i] <= carry
        # carry = g[i] | (p[i] & carry)
        carry = g[i] | (p[i] & carry)
      end

      cout <= carry
    end
  end

  # Slice with integrated carry for addition
  class SliceWithCarry < SimComponent
    input :a, :b
    input :cin
    output :sum
    output :cout

    # LUT computes propagate (XOR) and generate (AND)
    # Dedicated carry mux computes final carry

    wire :p  # Propagate: a ^ b
    wire :g  # Generate: a & b

    behavior do
      p <= a ^ b
      g <= a & b
      sum <= p ^ cin
      cout <= g | (p & cin)
    end
  end
end
```

---

## Switch Box and Routing

```ruby
module RHDL::FPGA
  # Programmable Interconnect Point (PIP)
  class PIP < SimComponent
    input :a
    input :b
    output :out

    parameter :select, default: 0  # Configuration bit

    behavior do
      out <= select == 0 ? a : b
    end
  end

  # Switch Box: connects routing channels
  class SwitchBox < SimComponent
    # 4 directions: North, East, South, West
    input :n_in, width: 4
    input :e_in, width: 4
    input :s_in, width: 4
    input :w_in, width: 4

    output :n_out, width: 4
    output :e_out, width: 4
    output :s_out, width: 4
    output :w_out, width: 4

    # Configuration: which inputs connect to which outputs
    # Simplified: each output can select from any input
    parameter :config, default: 0  # 64 bits of configuration

    behavior do
      # Each output selects from one of 16 inputs (4 per direction)
      all_inputs = (w_in << 12) | (s_in << 8) | (e_in << 4) | n_in

      4.times do |i|
        n_sel = (config >> (i * 4)) & 0xF
        n_out[i] <= (all_inputs >> n_sel) & 1

        e_sel = (config >> (16 + i * 4)) & 0xF
        e_out[i] <= (all_inputs >> e_sel) & 1

        s_sel = (config >> (32 + i * 4)) & 0xF
        s_out[i] <= (all_inputs >> s_sel) & 1

        w_sel = (config >> (48 + i * 4)) & 0xF
        w_out[i] <= (all_inputs >> w_sel) & 1
      end
    end
  end

  # Connection Box: connects CLB to routing
  class ConnectionBox < SimComponent
    input :clb_out, width: 4      # Outputs from CLB
    input :routing_in, width: 8   # Inputs from routing

    output :clb_in, width: 4      # Inputs to CLB
    output :routing_out, width: 8 # Outputs to routing

    parameter :config, default: 0

    behavior do
      # CLB inputs select from routing
      4.times do |i|
        sel = (config >> (i * 3)) & 0x7
        clb_in[i] <= (routing_in >> sel) & 1
      end

      # Routing outputs can come from CLB or pass through
      8.times do |i|
        sel = (config >> (12 + i * 2)) & 0x3
        routing_out[i] <= case sel
                          when 0 then (routing_in >> i) & 1
                          when 1 then (clb_out >> (i % 4)) & 1
                          else 0
                          end
      end
    end
  end
end
```

---

## Block RAM

```ruby
module RHDL::FPGA
  # Block RAM (BRAM) primitive
  class BRAM < SimComponent
    parameter :width, default: 18
    parameter :depth, default: 1024  # 18Kb typical

    # Port A
    input :clk_a
    input :en_a
    input :we_a
    input :addr_a, width: 10  # log2(depth)
    input :din_a, width: width
    output :dout_a, width: width

    # Port B (true dual-port)
    input :clk_b
    input :en_b
    input :we_b
    input :addr_b, width: 10
    input :din_b, width: width
    output :dout_b, width: width

    # Memory array
    memory :mem, depth: depth, width: width

    behavior do
      # Port A - synchronous read/write
      on_rising_edge(:clk_a) do
        if en_a == 1
          if we_a == 1
            mem[addr_a] <= din_a
          end
          dout_a <= mem[addr_a]  # Read-first mode
        end
      end

      # Port B - synchronous read/write
      on_rising_edge(:clk_b) do
        if en_b == 1
          if we_b == 1
            mem[addr_b] <= din_b
          end
          dout_b <= mem[addr_b]
        end
      end
    end
  end

  # Configurable BRAM (width/depth tradeoff)
  class ConfigurableBRAM < SimComponent
    parameter :total_bits, default: 18432  # 18Kb

    # Can be configured as:
    # 16K x 1, 8K x 2, 4K x 4, 2K x 9, 1K x 18, 512 x 36

    parameter :configured_width, default: 18
    parameter :configured_depth, default: 1024

    input :clk
    input :en
    input :we
    input :addr, width: Math.log2(configured_depth).ceil
    input :din, width: configured_width
    output :dout, width: configured_width

    memory :mem, depth: configured_depth, width: configured_width

    behavior do
      on_rising_edge(:clk) do
        if en == 1
          if we == 1
            mem[addr] <= din
          end
          dout <= mem[addr]
        end
      end
    end
  end
end
```

---

## DSP Block

```ruby
module RHDL::FPGA
  # DSP48 style multiply-accumulate block
  class DSPBlock < SimComponent
    parameter :a_width, default: 25
    parameter :b_width, default: 18
    parameter :p_width, default: 48

    input :clk
    input :ce

    # Data inputs
    input :a, width: a_width
    input :b, width: b_width
    input :c, width: p_width
    input :d, width: a_width  # Pre-adder input

    # Cascade inputs
    input :acin, width: 30
    input :bcin, width: 18
    input :pcin, width: 48

    # Control
    input :opmode, width: 7
    input :alumode, width: 4

    # Outputs
    output :p, width: p_width
    output :acout, width: 30
    output :bcout, width: 18
    output :pcout, width: 48

    # Internal registers
    wire :a_reg, width: a_width
    wire :b_reg, width: b_width
    wire :m_reg, width: 43  # Multiplier output
    wire :p_reg, width: p_width

    behavior do
      on_rising_edge(:clk) do
        next unless ce == 1

        # Pre-adder (optional): D + A or D - A
        pre_add = d + a  # Simplified

        # Multiplier
        m_reg <= a_reg * b_reg

        # Post-adder/accumulator based on opmode
        case opmode
        when 0b0000101  # P = (A * B)
          p_reg <= m_reg
        when 0b0100101  # P = P + (A * B)
          p_reg <= p_reg + m_reg
        when 0b0110101  # P = C + (A * B)
          p_reg <= c + m_reg
        else
          p_reg <= m_reg
        end

        a_reg <= a
        b_reg <= b
        p <= p_reg
      end
    end
  end
end
```

---

## I/O Block

```ruby
module RHDL::FPGA
  # I/O Block (IOB)
  class IOBlock < SimComponent
    # Bidirectional I/O
    inout :pad

    # Internal signals
    input :out_data
    input :out_en      # Tristate control
    output :in_data

    # Clock and registers
    input :clk
    input :use_in_reg
    input :use_out_reg

    wire :in_raw
    wire :out_raw
    wire :in_reg_q
    wire :out_reg_q

    instance :in_ff, DFlipFlop
    instance :out_ff, DFlipFlop

    behavior do
      # Input path
      in_raw <= pad
      in_data <= use_in_reg == 1 ? in_reg_q : in_raw

      # Output path
      out_raw <= use_out_reg == 1 ? out_reg_q : out_data

      # Tristate buffer
      if out_en == 1
        pad <= out_raw
      else
        pad <= 'Z'  # High impedance
      end
    end

    port :clk => [:in_ff, :clk]
    port :in_raw => [:in_ff, :d]
    port [:in_ff, :q] => :in_reg_q

    port :clk => [:out_ff, :clk]
    port :out_data => [:out_ff, :d]
    port [:out_ff, :q] => :out_reg_q
  end

  # DDR I/O (Double Data Rate)
  class DDRIO < SimComponent
    input :clk
    input :d_rise   # Data for rising edge
    input :d_fall   # Data for falling edge
    output :q_rise  # Captured on rising edge
    output :q_fall  # Captured on falling edge
    inout :pad

    behavior do
      on_rising_edge(:clk) do
        pad <= d_rise
        q_rise <= pad
      end

      on_falling_edge(:clk) do
        pad <= d_fall
        q_fall <= pad
      end
    end
  end
end
```

---

## Configuration Controller

```ruby
module RHDL::FPGA
  # Simplified configuration controller
  class ConfigController < SimComponent
    input :clk
    input :reset

    # Configuration interface
    input :cfg_data, width: 32
    input :cfg_valid
    output :cfg_ready

    # To fabric
    output :frame_addr, width: 24
    output :frame_data, width: 32
    output :frame_write

    # State machine
    IDLE = 0
    HEADER = 1
    DATA = 2
    CRC = 3

    wire :state, width: 2
    wire :frame_count, width: 16
    wire :word_count, width: 8

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          state <= IDLE
          cfg_ready <= 1
          frame_write <= 0
        else
          case state
          when IDLE
            if cfg_valid == 1
              # Parse configuration header
              state <= HEADER
            end

          when HEADER
            if cfg_valid == 1
              frame_addr <= cfg_data[23:0]
              frame_count <= cfg_data[31:24]
              state <= DATA
              word_count <= 0
            end

          when DATA
            if cfg_valid == 1
              frame_data <= cfg_data
              frame_write <= 1
              word_count <= word_count + 1

              if word_count == 100  # Frame size
                frame_addr <= frame_addr + 1
                frame_count <= frame_count - 1
                word_count <= 0

                if frame_count == 1
                  state <= CRC
                end
              end
            else
              frame_write <= 0
            end

          when CRC
            # Verify CRC
            state <= IDLE
          end
        end
      end
    end
  end
end
```

---

## Partial Reconfiguration

```ruby
module RHDL::FPGA
  # Partial reconfiguration region
  class ReconfigRegion < SimComponent
    parameter :width, default: 8
    parameter :height, default: 8

    input :clk
    input :reset

    # Static interface (decoupled during reconfig)
    input :static_in, width: 32
    output :static_out, width: 32
    input :static_valid
    output :static_ready

    # Configuration interface
    input :reconfig_start
    input :reconfig_data, width: 32
    input :reconfig_valid
    output :reconfig_done

    # Decoupling
    wire :decoupled
    wire :region_reset

    behavior do
      # During reconfiguration:
      # 1. Assert decoupled (isolate from static logic)
      # 2. Hold region in reset
      # 3. Load new bitstream
      # 4. Release reset
      # 5. Deassert decoupled

      if reconfig_start == 1
        decoupled <= 1
        region_reset <= 1
        static_ready <= 0
      end

      if reconfig_done == 1
        decoupled <= 0
        region_reset <= 0
        static_ready <= 1
      end

      # Static interface isolation
      if decoupled == 1
        static_out <= 0
      end
    end
  end
end
```

---

## Sample FPGA Top-Level

```ruby
module RHDL::FPGA
  # Example: Simple FPGA with 4x4 CLB array
  class MiniPFGA < SimComponent
    parameter :clb_rows, default: 4
    parameter :clb_cols, default: 4

    input :clk
    input :reset

    # Configuration
    input :cfg_clk
    input :cfg_data, width: 32
    input :cfg_valid

    # User I/O
    input :io_in, width: 8
    output :io_out, width: 8

    # Instantiate CLB array
    # (Simplified - real FPGA would have full routing)

    behavior do
      # In a real FPGA:
      # 1. Configuration controller loads bitstream
      # 2. Bitstream programs LUT contents, routing, I/O
      # 3. User logic operates based on configuration

      # This is a behavioral model - actual FPGA has
      # physical LUTs and routing that get programmed
    end
  end
end
```

---

## Mapping RHDL to FPGA

```ruby
# Example: Map a counter to FPGA primitives
class Counter4Bit < SimComponent
  input :clk
  input :reset
  output :count, width: 4
  output :carry

  # In RHDL - behavioral
  behavior do
    on_rising_edge(:clk) do
      if reset == 1
        count <= 0
      else
        count <= count + 1
      end
    end
    carry <= count == 0xF ? 1 : 0
  end
end

# Mapped to FPGA:
# - 4 slices with LUTs configured for increment
# - 4 flip-flops for count register
# - Carry chain for fast increment
# - Additional LUT for carry output

class Counter4BitFPGA < SimComponent
  input :clk
  input :reset
  output :count, width: 4
  output :carry

  # Explicit FPGA primitives
  instance :slice0, RHDL::FPGA::SliceWithCarry
  instance :slice1, RHDL::FPGA::SliceWithCarry
  instance :slice2, RHDL::FPGA::SliceWithCarry
  instance :slice3, RHDL::FPGA::SliceWithCarry

  instance :carry_lut, RHDL::FPGA::LUT4, init: 0x8000  # 4-input AND

  # ... wiring for increment with carry chain
end
```

---

## Further Resources

- Xilinx UG474: 7 Series CLB User Guide
- Intel Cyclone V Device Handbook
- Kuon & Rose, "FPGA Architecture Survey"
- Project IceStorm (reverse-engineered iCE40 documentation)

> Return to [Chapter 16](16-reconfigurable-computing.md) for conceptual introduction.
