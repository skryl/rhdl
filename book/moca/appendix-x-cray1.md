# Appendix X: Cray-1 Implementation

*Companion appendix to [Chapter 24: The Cray-1](24-cray1.md)*

## Overview

This appendix provides RHDL implementations of Cray-1 vector processor components, from registers to complete vector pipelines with chaining.

---

## Vector Register File

```ruby
module RHDL::Cray1
  # Vector Register File: 8 registers × 64 elements × 64 bits
  class VectorRegisterFile < SimComponent
    parameter :num_regs, default: 8
    parameter :vector_len, default: 64
    parameter :elem_width, default: 64

    input :clk
    input :reset

    # Read port (outputs full vector)
    input :read_sel, width: 3
    output :read_data, width: vector_len * elem_width

    # Write port
    input :write_sel, width: 3
    input :write_data, width: vector_len * elem_width
    input :write_enable

    # Vector length register
    input :vl, width: 7  # 0-64

    # Storage: 8 registers, each 64×64 bits = 4096 bits
    memory :regs, depth: num_regs, width: vector_len * elem_width

    behavior do
      # Read combinational
      read_data <= regs[read_sel]

      # Write on clock edge
      on_rising_edge(:clk) do
        if reset == 1
          num_regs.times { |i| regs[i] <= 0 }
        elsif write_enable == 1
          regs[write_sel] <= write_data
        end
      end
    end
  end

  # Single vector register with element access
  class VectorRegister < SimComponent
    parameter :length, default: 64
    parameter :width, default: 64

    input :clk
    input :reset

    # Full vector access
    input :write_vector, width: length * width
    input :write_vector_en

    # Element access
    input :write_elem, width: width
    input :write_elem_idx, width: 6
    input :write_elem_en

    # Read access
    input :read_elem_idx, width: 6
    output :read_elem, width: width
    output :read_vector, width: length * width

    memory :elements, depth: length, width: width

    behavior do
      # Read element
      read_elem <= elements[read_elem_idx]

      # Read full vector (concatenate all elements)
      full = 0
      length.times { |i| full |= (elements[i] << (i * width)) }
      read_vector <= full

      on_rising_edge(:clk) do
        if reset == 1
          length.times { |i| elements[i] <= 0 }
        elsif write_vector_en == 1
          length.times do |i|
            elements[i] <= (write_vector >> (i * width)) & ((1 << width) - 1)
          end
        elsif write_elem_en == 1
          elements[write_elem_idx] <= write_elem
        end
      end
    end
  end
end
```

---

## Pipelined Functional Units

```ruby
module RHDL::Cray1
  # Generic pipelined functional unit
  class PipelinedUnit < SimComponent
    parameter :width, default: 64
    parameter :stages, default: 6

    input :clk
    input :reset
    input :valid_in
    input :operand_a, width: width
    input :operand_b, width: width

    output :result, width: width
    output :valid_out

    # Pipeline registers
    wire :pipe_data, width: width, depth: stages
    wire :pipe_valid, width: stages

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          stages.times do |i|
            pipe_data[i] <= 0
            pipe_valid[i] <= 0
          end
        else
          # Shift pipeline
          (stages - 1).downto(1) do |i|
            pipe_data[i] <= pipe_data[i - 1]
            pipe_valid[i] <= pipe_valid[i - 1]
          end

          # First stage: compute and enter pipeline
          pipe_data[0] <= compute(operand_a, operand_b)
          pipe_valid[0] <= valid_in
        end
      end

      result <= pipe_data[stages - 1]
      valid_out <= pipe_valid[stages - 1]
    end

    # Override in subclasses
    def compute(a, b)
      a + b
    end
  end

  # Vector Integer Add (3 stages)
  class VectorIntegerAdd < PipelinedUnit
    parameter :stages, default: 3

    def compute(a, b)
      a + b
    end
  end

  # Vector FP Add (6 stages, simplified)
  class VectorFPAdd < PipelinedUnit
    parameter :stages, default: 6

    def compute(a, b)
      # Simplified: treat as integers for simulation
      # Real implementation would handle IEEE 754
      a + b
    end
  end

  # Vector FP Multiply (7 stages)
  class VectorFPMultiply < PipelinedUnit
    parameter :stages, default: 7

    def compute(a, b)
      # Simplified multiplication
      a * b
    end
  end

  # Vector Logical (2 stages)
  class VectorLogical < SimComponent
    parameter :width, default: 64
    parameter :stages, default: 2

    input :clk
    input :valid_in
    input :operand_a, width: width
    input :operand_b, width: width
    input :op, width: 2  # 00=AND, 01=OR, 10=XOR, 11=NOT

    output :result, width: width
    output :valid_out

    wire :pipe_result, width: width
    wire :pipe_valid

    behavior do
      # Compute
      case op
      when 0b00 then computed = operand_a & operand_b
      when 0b01 then computed = operand_a | operand_b
      when 0b10 then computed = operand_a ^ operand_b
      when 0b11 then computed = ~operand_a
      end

      on_rising_edge(:clk) do
        pipe_result <= computed
        pipe_valid <= valid_in

        result <= pipe_result
        valid_out <= pipe_valid
      end
    end
  end
end
```

---

## Vector Chaining

```ruby
module RHDL::Cray1
  # Chaining controller: allows result of one unit to feed another
  class ChainingController < SimComponent
    input :clk
    input :reset

    # Source functional unit
    input :src_result, width: 64
    input :src_valid
    input :src_reg, width: 3      # Destination register of source op

    # Destination functional unit
    input :dst_operand_reg, width: 3  # Which register dst wants to read
    output :dst_operand, width: 64
    output :dst_operand_valid

    # Register file read port (fallback)
    input :regfile_data, width: 64

    # Chain enable
    output :chain_active

    behavior do
      # Check if chaining applies
      if src_valid == 1 && src_reg == dst_operand_reg
        # Chain! Bypass register file
        dst_operand <= src_result
        dst_operand_valid <= 1
        chain_active <= 1
      else
        # No chain, use register file
        dst_operand <= regfile_data
        dst_operand_valid <= 1
        chain_active <= 0
      end
    end
  end

  # Vector execution unit with chaining support
  class VectorExecutionUnit < SimComponent
    parameter :width, default: 64
    parameter :length, default: 64

    input :clk
    input :reset

    # Instruction
    input :start
    input :opcode, width: 4
    input :src1_reg, width: 3
    input :src2_reg, width: 3
    input :dst_reg, width: 3
    input :vl, width: 7  # Vector length

    # Chaining inputs
    input :chain_data, width: width
    input :chain_valid
    input :chain_reg, width: 3

    # Register file interface
    output :rf_read_reg, width: 3
    input :rf_read_data, width: width
    output :rf_write_reg, width: 3
    output :rf_write_data, width: width
    output :rf_write_en

    # Status
    output :busy
    output :done

    # Chaining output (for downstream units)
    output :result_data, width: width
    output :result_valid
    output :result_reg, width: 3

    # Functional units
    instance :fp_add, VectorFPAdd
    instance :fp_mul, VectorFPMultiply
    instance :int_add, VectorIntegerAdd

    # State
    wire :element_idx, width: 7
    wire :state, width: 2

    IDLE = 0
    RUNNING = 1
    DRAINING = 2

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          state <= IDLE
          element_idx <= 0
          busy <= 0
        else
          case state
          when IDLE
            if start == 1
              state <= RUNNING
              element_idx <= 0
              busy <= 1
            end

          when RUNNING
            # Feed elements into pipeline
            if element_idx < vl
              # Check for chaining
              if chain_valid == 1 && chain_reg == src1_reg
                # Use chained data
                operand_a = chain_data
              else
                # Read from register file
                rf_read_reg <= src1_reg
                operand_a = rf_read_data
              end

              # Route to appropriate functional unit
              # (simplified - just use fp_add for demo)
              fp_add.operand_a <= operand_a
              fp_add.operand_b <= rf_read_data  # src2
              fp_add.valid_in <= 1

              element_idx <= element_idx + 1
            else
              state <= DRAINING
            end

          when DRAINING
            # Wait for pipeline to empty
            if fp_add.valid_out == 0
              state <= IDLE
              busy <= 0
              done <= 1
            end
          end

          # Write results (chain output)
          if fp_add.valid_out == 1
            result_data <= fp_add.result
            result_valid <= 1
            result_reg <= dst_reg

            rf_write_data <= fp_add.result
            rf_write_reg <= dst_reg
            rf_write_en <= 1
          else
            result_valid <= 0
            rf_write_en <= 0
          end
        end
      end
    end
  end
end
```

---

## Memory System

```ruby
module RHDL::Cray1
  # 16-bank memory system
  class BankedMemory < SimComponent
    parameter :num_banks, default: 16
    parameter :words_per_bank, default: 65536
    parameter :word_width, default: 64
    parameter :bank_latency, default: 4

    input :clk
    input :reset

    # Vector load/store interface
    input :addr, width: 24
    input :stride, width: 16
    input :vl, width: 7
    input :write_data, width: word_width
    input :read_req
    input :write_req

    output :read_data, width: word_width
    output :read_valid
    output :busy
    output :bank_conflict

    # Bank memories
    memory :banks, depth: num_banks, width: words_per_bank * word_width

    # Bank busy counters (for latency simulation)
    wire :bank_busy, width: num_banks

    behavior do
      # Determine which bank
      bank_num = addr % num_banks
      bank_addr = addr / num_banks

      # Check for bank conflict
      if bank_busy[bank_num] > 0
        bank_conflict <= 1
        busy <= 1
      else
        bank_conflict <= 0

        if read_req == 1
          # Start read
          # In real hardware, this takes bank_latency cycles
          read_data <= banks[bank_num][bank_addr]
          read_valid <= 1
          bank_busy[bank_num] <= bank_latency
        elsif write_req == 1
          banks[bank_num][bank_addr] <= write_data
          bank_busy[bank_num] <= bank_latency
        end
      end

      # Decrement busy counters
      on_rising_edge(:clk) do
        num_banks.times do |i|
          if bank_busy[i] > 0
            bank_busy[i] <= bank_busy[i] - 1
          end
        end
      end
    end
  end

  # Vector memory unit (handles strided access)
  class VectorMemoryUnit < SimComponent
    parameter :width, default: 64
    parameter :length, default: 64

    input :clk
    input :reset

    # Command
    input :start
    input :is_store      # 0=load, 1=store
    input :base_addr, width: 24
    input :stride, width: 16
    input :vl, width: 7
    input :vector_reg, width: 3

    # Memory interface
    output :mem_addr, width: 24
    output :mem_write_data, width: width
    output :mem_read_req
    output :mem_write_req
    input :mem_read_data, width: width
    input :mem_read_valid
    input :mem_bank_conflict

    # Register file interface
    input :rf_read_data, width: width
    output :rf_write_data, width: width
    output :rf_write_en

    output :busy
    output :done

    wire :element_idx, width: 7
    wire :current_addr, width: 24
    wire :state, width: 2

    IDLE = 0
    LOADING = 1
    STORING = 2

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          state <= IDLE
          busy <= 0
        else
          case state
          when IDLE
            if start == 1
              element_idx <= 0
              current_addr <= base_addr
              busy <= 1

              if is_store == 0
                state <= LOADING
              else
                state <= STORING
              end
            end

          when LOADING
            if mem_bank_conflict == 0
              mem_addr <= current_addr
              mem_read_req <= 1

              if mem_read_valid == 1
                rf_write_data <= mem_read_data
                rf_write_en <= 1

                element_idx <= element_idx + 1
                current_addr <= current_addr + stride

                if element_idx >= vl - 1
                  state <= IDLE
                  busy <= 0
                  done <= 1
                end
              end
            else
              mem_read_req <= 0  # Stall on conflict
            end

          when STORING
            if mem_bank_conflict == 0
              mem_addr <= current_addr
              mem_write_data <= rf_read_data
              mem_write_req <= 1

              element_idx <= element_idx + 1
              current_addr <= current_addr + stride

              if element_idx >= vl - 1
                state <= IDLE
                busy <= 0
                done <= 1
              end
            else
              mem_write_req <= 0
            end
          end
        end
      end
    end
  end
end
```

---

## Complete Vector Processor

```ruby
module RHDL::Cray1
  # Simplified Cray-1 vector processor
  class Cray1Processor < SimComponent
    input :clk
    input :reset

    # Instruction interface
    input :instr, width: 32
    input :instr_valid

    # Memory interface
    output :mem_addr, width: 24
    output :mem_write_data, width: 64
    output :mem_read_req
    output :mem_write_req
    input :mem_read_data, width: 64
    input :mem_ready

    output :busy

    # Vector registers
    instance :vrf, VectorRegisterFile

    # Scalar registers (simplified: 8 registers)
    instance :srf, RegisterFile, num_regs: 8, width: 64

    # Address registers
    instance :arf, RegisterFile, num_regs: 8, width: 24

    # Functional units
    instance :v_add, VectorFPAdd
    instance :v_mul, VectorFPMultiply
    instance :v_int, VectorIntegerAdd
    instance :v_log, VectorLogical

    # Memory unit
    instance :v_mem, VectorMemoryUnit

    # Chaining controller
    instance :chain, ChainingController

    # Vector length and mask
    wire :vl, width: 7
    wire :vm, width: 64

    # Instruction decode
    wire :opcode, width: 6
    wire :dst, width: 3
    wire :src1, width: 3
    wire :src2, width: 3

    behavior do
      # Decode instruction
      opcode <= (instr >> 26) & 0x3F
      dst <= (instr >> 23) & 0x7
      src1 <= (instr >> 20) & 0x7
      src2 <= (instr >> 17) & 0x7

      # Connect chaining between units
      chain.src_result <= v_add.result
      chain.src_valid <= v_add.valid_out

      # Route to functional units based on opcode
      # (Simplified instruction set)
    end
  end
end
```

---

## Sample Programs

### DAXPY Test

```ruby
describe "Cray-1 DAXPY" do
  it "computes Y = a*X + Y with chaining" do
    cray = RHDL::Cray1::Cray1Processor.new
    sim = Simulator.new(cray)

    # Initialize vectors
    n = 64
    a = 2.0
    x = (0...n).map { |i| i.to_f }
    y = (0...n).map { |i| (i * 10).to_f }

    # Load X into V0, Y into V1
    # Set VL = 64
    # Execute: V2 = V0 * S0 (where S0 = a)
    # Execute: V3 = V2 + V1 (chained!)
    # Store V3 to Y

    # Verify results
    n.times do |i|
      expected = a * x[i] + y[i]
      # Check result...
    end
  end
end
```

### Matrix-Vector Multiply

```ruby
# y = A * x where A is m×n matrix
describe "Cray-1 Matrix-Vector" do
  it "computes matrix-vector product" do
    # For each row i:
    #   Load row A[i,:] into V0 (stride = n for column-major)
    #   V1 = V0 * Vx (element-wise multiply with x vector)
    #   Reduce V1 to scalar (sum)
    #   Store to y[i]

    # With strip-mining for matrices larger than 64
  end
end
```

---

## Further Resources

- Cray Research, "Cray-1 Hardware Reference Manual"
- Russell, "The Cray-1 Computer System" (CACM 1978)
- Hennessy & Patterson, "Computer Architecture: A Quantitative Approach"

> Return to [Chapter 24](24-cray1.md) for conceptual introduction.
