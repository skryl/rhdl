# Appendix I: GPU Implementation

*Companion appendix to [Chapter 7: GPU Architecture](07-gpu-architecture.md)*

## Overview

This appendix provides RHDL implementations of GPU components, from individual CUDA cores to a simplified streaming multiprocessor.

## CUDA Core (Simplified)

A CUDA core is essentially a simple ALU with floating-point support:

```ruby
class CudaCore < SimComponent
  input :clk
  input :enable
  input :op, width: 4        # Operation select
  input :a, width: 32        # Operand A (IEEE 754 float)
  input :b, width: 32        # Operand B
  output :result, width: 32  # Result
  output :valid              # Result valid

  # Operations
  OP_ADD  = 0x0
  OP_SUB  = 0x1
  OP_MUL  = 0x2
  OP_FMA  = 0x3  # Fused multiply-add
  OP_MIN  = 0x4
  OP_MAX  = 0x5
  OP_ABS  = 0x6
  OP_NEG  = 0x7

  behavior do
    on_posedge(:clk) do
      if enable.high?
        result <= case op.to_i
          when OP_ADD then float_add(a, b)
          when OP_SUB then float_sub(a, b)
          when OP_MUL then float_mul(a, b)
          when OP_FMA then float_fma(a, b, c)
          when OP_MIN then float_min(a, b)
          when OP_MAX then float_max(a, b)
          when OP_ABS then float_abs(a)
          when OP_NEG then float_neg(a)
          else 0
        end
        valid <= 1
      else
        valid <= 0
      end
    end
  end
end
```

## Warp Scheduler

The warp scheduler selects which warp executes next:

```ruby
class WarpScheduler < SimComponent
  input :clk
  input :reset

  # Warp status inputs (4 warps for simplicity)
  input :warp0_ready
  input :warp1_ready
  input :warp2_ready
  input :warp3_ready

  input :warp0_stalled
  input :warp1_stalled
  input :warp2_stalled
  input :warp3_stalled

  output :selected_warp, width: 2
  output :warp_valid

  wire :last_warp, width: 2

  instance :last_warp_reg, Register, width: 2

  behavior do
    # Round-robin scheduling among ready, non-stalled warps
    on_posedge(:clk) do
      if reset.high?
        selected_warp <= 0
        warp_valid <= 0
      else
        # Find next ready warp (round-robin from last+1)
        found = false
        4.times do |offset|
          warp_id = (last_warp.to_i + 1 + offset) % 4
          ready = [warp0_ready, warp1_ready, warp2_ready, warp3_ready][warp_id]
          stalled = [warp0_stalled, warp1_stalled, warp2_stalled, warp3_stalled][warp_id]

          if ready.high? && stalled.low? && !found
            selected_warp <= warp_id
            warp_valid <= 1
            last_warp_reg.d <= warp_id
            found = true
          end
        end

        unless found
          warp_valid <= 0
        end
      end
    end
  end
end
```

## Register File

GPUs have massive register files (64K+ registers per SM):

```ruby
class GpuRegisterFile < SimComponent
  input :clk

  # Read ports (3 for typical instruction)
  input :read_addr0, width: 8
  input :read_addr1, width: 8
  input :read_addr2, width: 8
  output :read_data0, width: 32
  output :read_data1, width: 32
  output :read_data2, width: 32

  # Write port
  input :write_enable
  input :write_addr, width: 8
  input :write_data, width: 32

  # Thread/Warp selection
  input :thread_id, width: 5   # 0-31 within warp
  input :warp_id, width: 4     # Which warp

  # 256 registers per thread × 32 threads × 16 warps = 128K registers
  # Simplified: 256 registers per thread, 4 warps, 32 threads
  REGS_PER_THREAD = 256
  THREADS_PER_WARP = 32
  NUM_WARPS = 4

  behavior do
    # Banked register file for parallel access
    # Each thread has its own register space

    def reg_addr(warp, thread, reg)
      (warp * THREADS_PER_WARP + thread) * REGS_PER_THREAD + reg
    end

    # Combinational reads
    always do
      addr0 = reg_addr(warp_id.to_i, thread_id.to_i, read_addr0.to_i)
      addr1 = reg_addr(warp_id.to_i, thread_id.to_i, read_addr1.to_i)
      addr2 = reg_addr(warp_id.to_i, thread_id.to_i, read_addr2.to_i)

      read_data0 <= @registers[addr0] || 0
      read_data1 <= @registers[addr1] || 0
      read_data2 <= @registers[addr2] || 0
    end

    # Synchronous write
    on_posedge(:clk) do
      if write_enable.high?
        addr = reg_addr(warp_id.to_i, thread_id.to_i, write_addr.to_i)
        @registers[addr] = write_data.to_i
      end
    end
  end

  def initialize(name, params = {})
    super
    @registers = Array.new(REGS_PER_THREAD * THREADS_PER_WARP * NUM_WARPS, 0)
  end
end
```

## Shared Memory

Shared memory with bank conflict detection:

```ruby
class SharedMemory < SimComponent
  input :clk

  # 32 banks, 4 bytes each = 128 bytes per row
  # 768 rows = 96 KB shared memory
  NUM_BANKS = 32
  BANK_WIDTH = 4  # bytes
  NUM_ROWS = 768

  # Access from 32 threads (one warp)
  input :addr, width: 32 * 17  # 32 addresses, 17 bits each
  input :write_data, width: 32 * 32  # 32 data words
  input :write_enable, width: 32  # Per-thread write enable
  input :read_enable

  output :read_data, width: 32 * 32  # 32 data words
  output :bank_conflict  # High if conflict detected
  output :stall_cycles, width: 5  # Number of stall cycles needed

  behavior do
    def get_bank(address)
      (address / BANK_WIDTH) % NUM_BANKS
    end

    always do
      # Check for bank conflicts
      banks_used = Array.new(NUM_BANKS, 0)
      max_conflicts = 0

      32.times do |t|
        thread_addr = addr.bits((t * 17)...((t + 1) * 17)).to_i
        bank = get_bank(thread_addr)
        banks_used[bank] += 1
        max_conflicts = [max_conflicts, banks_used[bank]].max
      end

      bank_conflict <= max_conflicts > 1 ? 1 : 0
      stall_cycles <= max_conflicts - 1  # Additional cycles needed
    end

    on_posedge(:clk) do
      if read_enable.high?
        32.times do |t|
          thread_addr = addr.bits((t * 17)...((t + 1) * 17)).to_i
          row = thread_addr / (NUM_BANKS * BANK_WIDTH)
          bank = get_bank(thread_addr)
          offset = thread_addr % BANK_WIDTH

          # Read 4-byte word
          value = @memory[row * NUM_BANKS + bank] || 0
          read_data.bits((t * 32)...((t + 1) * 32)) <= value
        end
      end

      32.times do |t|
        if write_enable.bit(t).high?
          thread_addr = addr.bits((t * 17)...((t + 1) * 17)).to_i
          row = thread_addr / (NUM_BANKS * BANK_WIDTH)
          bank = get_bank(thread_addr)

          value = write_data.bits((t * 32)...((t + 1) * 32)).to_i
          @memory[row * NUM_BANKS + bank] = value
        end
      end
    end
  end

  def initialize(name, params = {})
    super
    @memory = Array.new(NUM_ROWS * NUM_BANKS, 0)
  end
end
```

## Predicate Registers (for SIMT Divergence)

```ruby
class PredicateUnit < SimComponent
  input :clk

  # Predicate comparison
  input :a, width: 32
  input :b, width: 32
  input :compare_op, width: 3

  CMP_EQ  = 0  # Equal
  CMP_NE  = 1  # Not equal
  CMP_LT  = 2  # Less than
  CMP_LE  = 3  # Less than or equal
  CMP_GT  = 4  # Greater than
  CMP_GE  = 5  # Greater than or equal

  # Per-thread predicate (32 threads)
  output :predicate, width: 32

  # Active mask management
  input :push_mask     # Push current mask to stack
  input :pop_mask      # Pop mask from stack
  input :set_mask, width: 32  # Explicitly set mask

  output :active_mask, width: 32  # Current active threads

  behavior do
    always do
      result = 0
      32.times do |t|
        thread_a = a.bits((t * 32)...((t + 1) * 32)).to_i
        thread_b = b.bits((t * 32)...((t + 1) * 32)).to_i

        cmp_result = case compare_op.to_i
          when CMP_EQ then thread_a == thread_b
          when CMP_NE then thread_a != thread_b
          when CMP_LT then thread_a < thread_b
          when CMP_LE then thread_a <= thread_b
          when CMP_GT then thread_a > thread_b
          when CMP_GE then thread_a >= thread_b
          else false
        end

        result |= (cmp_result ? 1 : 0) << t
      end
      predicate <= result
    end

    on_posedge(:clk) do
      if push_mask.high?
        @mask_stack.push(@current_mask)
      elsif pop_mask.high?
        @current_mask = @mask_stack.pop || 0xFFFFFFFF
      elsif set_mask.to_i != 0
        @current_mask = set_mask.to_i
      end

      active_mask <= @current_mask
    end
  end

  def initialize(name, params = {})
    super
    @mask_stack = []
    @current_mask = 0xFFFFFFFF  # All threads active initially
  end
end
```

## Simplified Streaming Multiprocessor

```ruby
class StreamingMultiprocessor < SimComponent
  input :clk
  input :reset

  # Instruction interface
  input :instruction, width: 64
  input :instruction_valid

  # Memory interface (to L2/global memory)
  output :mem_addr, width: 32
  output :mem_write_data, width: 128  # 4 threads worth
  output :mem_write_enable
  output :mem_read_enable
  input :mem_read_data, width: 128
  input :mem_ready

  # Status
  output :busy
  output :stalled

  # Internal components
  instance :scheduler, WarpScheduler
  instance :regfile, GpuRegisterFile
  instance :shared_mem, SharedMemory
  instance :predicates, PredicateUnit

  # 32 CUDA cores (simplified)
  32.times do |i|
    instance :"core#{i}", CudaCore
  end

  # Warp state (4 warps)
  wire :warp_pc, width: 4 * 32  # PC for each warp
  wire :warp_active, width: 4   # Which warps are active

  behavior do
    on_posedge(:clk) do
      if reset.high?
        warp_active <= 0
        busy <= 0
        stalled <= 0
      else
        # Decode instruction
        opcode = instruction.bits(0...8).to_i
        dst = instruction.bits(8...16).to_i
        src1 = instruction.bits(16...24).to_i
        src2 = instruction.bits(24...32).to_i

        # Get selected warp
        warp = scheduler.selected_warp.to_i

        if scheduler.warp_valid.high?
          # Execute on all 32 cores in parallel
          32.times do |t|
            core = instance_variable_get(:"@core#{t}")
            core.enable <= predicates.active_mask.bit(t)
            core.op <= opcode
            # ... connect operands from register file
          end
        end
      end
    end
  end
end
```

## Memory Coalescing Unit

```ruby
class CoalescingUnit < SimComponent
  input :clk

  # 32 thread addresses
  input :thread_addrs, width: 32 * 32  # 32 addresses
  input :request_valid

  # Coalesced output
  output :coalesced_addr, width: 32
  output :coalesced_mask, width: 32  # Which threads served
  output :transaction_count, width: 6  # How many transactions needed
  output :is_coalesced  # All threads in one transaction

  CACHE_LINE_SIZE = 128  # bytes

  behavior do
    always do
      if request_valid.high?
        # Group addresses by cache line
        cache_lines = {}

        32.times do |t|
          addr = thread_addrs.bits((t * 32)...((t + 1) * 32)).to_i
          line = addr / CACHE_LINE_SIZE
          cache_lines[line] ||= []
          cache_lines[line] << t
        end

        transaction_count <= cache_lines.size
        is_coalesced <= cache_lines.size == 1 ? 1 : 0

        # Output first cache line address and mask
        first_line = cache_lines.keys.first
        coalesced_addr <= first_line * CACHE_LINE_SIZE

        mask = 0
        cache_lines[first_line].each { |t| mask |= (1 << t) }
        coalesced_mask <= mask
      end
    end
  end
end
```

## Tensor Core (Matrix Multiply Unit)

Modern GPUs include tensor cores for ML workloads:

```ruby
class TensorCore < SimComponent
  input :clk
  input :enable

  # 4x4 matrix inputs (FP16)
  input :matrix_a, width: 16 * 16  # 4x4 × 16-bit
  input :matrix_b, width: 16 * 16
  input :matrix_c, width: 32 * 16  # 4x4 × 32-bit (accumulator)

  # Output: D = A × B + C
  output :matrix_d, width: 32 * 16
  output :valid

  behavior do
    on_posedge(:clk) do
      if enable.high?
        # 4x4 matrix multiply-accumulate
        # This is a systolic operation internally

        4.times do |i|
          4.times do |j|
            sum = matrix_c.bits(((i * 4 + j) * 32)...(((i * 4 + j) + 1) * 32)).to_i

            4.times do |k|
              a_elem = matrix_a.bits(((i * 4 + k) * 16)...(((i * 4 + k) + 1) * 16)).to_i
              b_elem = matrix_b.bits(((k * 4 + j) * 16)...(((k * 4 + j) + 1) * 16)).to_i

              # FP16 multiply, FP32 accumulate
              sum += fp16_to_fp32(a_elem) * fp16_to_fp32(b_elem)
            end

            matrix_d.bits(((i * 4 + j) * 32)...(((i * 4 + j) + 1) * 32)) <= sum
          end
        end

        valid <= 1
      else
        valid <= 0
      end
    end
  end
end
```

## Performance Counters

```ruby
class GpuPerfCounters < SimComponent
  input :clk
  input :reset

  # Events to count
  input :warp_issued
  input :warp_stalled_mem
  input :warp_stalled_sync
  input :bank_conflict
  input :cache_hit
  input :cache_miss

  # Counter outputs
  output :total_cycles, width: 64
  output :active_cycles, width: 64
  output :stall_cycles, width: 64
  output :instructions_issued, width: 64
  output :bank_conflicts, width: 32
  output :cache_hits, width: 32
  output :cache_misses, width: 32

  behavior do
    on_posedge(:clk) do
      if reset.high?
        total_cycles <= 0
        active_cycles <= 0
        stall_cycles <= 0
        instructions_issued <= 0
        bank_conflicts <= 0
        cache_hits <= 0
        cache_misses <= 0
      else
        total_cycles <= total_cycles.to_i + 1

        if warp_issued.high?
          active_cycles <= active_cycles.to_i + 1
          instructions_issued <= instructions_issued.to_i + 1
        end

        if warp_stalled_mem.high? || warp_stalled_sync.high?
          stall_cycles <= stall_cycles.to_i + 1
        end

        bank_conflicts <= bank_conflicts.to_i + bank_conflict.to_i
        cache_hits <= cache_hits.to_i + cache_hit.to_i
        cache_misses <= cache_misses.to_i + cache_miss.to_i
      end
    end
  end
end
```

## Key Implementation Notes

1. **Warp-level execution** - All 32 threads execute together, divergence causes serialization
2. **Register banking** - Register file must support 32 parallel reads/writes
3. **Memory coalescing** - Critical for performance; uncoalesced access is 32x slower
4. **Shared memory banking** - 32 banks allow conflict-free parallel access
5. **Tensor cores** - Essentially small systolic arrays embedded in the SM

## Further Reading

- NVIDIA CUDA Programming Guide
- AMD RDNA Architecture Whitepaper
- "Life of a Triangle" - NVIDIA GPU pipeline walkthrough
- Volkov, "Understanding Latency Hiding on GPUs"

> Return to [Chapter 7](07-gpu-architecture.md) for conceptual introduction.
