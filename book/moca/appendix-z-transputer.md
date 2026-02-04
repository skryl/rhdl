# Appendix Z: Transputer Implementation

*CSP hardware in RHDL*

---

## Overview

This appendix provides RHDL implementations of key Transputer components:

1. **EvaluationStack**: The 3-register A/B/C stack
2. **LinkEngine**: Serial communication hardware
3. **ProcessScheduler**: Two-priority hardware scheduler
4. **Channel**: Internal process communication
5. **ALTController**: Alternative input handling
6. **TransputerCore**: Simplified processor core

---

## Evaluation Stack

The Transputer's unique 3-register evaluation stack.

```ruby
# Three-register evaluation stack (A, B, C)
# All arithmetic operates on this stack
class EvaluationStack < SimComponent
  parameter :width, default: 32

  input :clk
  input :reset

  # Control signals
  input :push       # Push new value, shift down
  input :pop        # Pop A, shift up
  input :swap       # Swap A and B (REV instruction)
  input :dup        # Duplicate A to B, B to C

  # Data
  input :data_in, width: :width   # Value to push
  output :a_out, width: :width    # Top of stack
  output :b_out, width: :width    # Second
  output :c_out, width: :width    # Third

  # Internal registers
  wire :a_reg, width: :width
  wire :b_reg, width: :width
  wire :c_reg, width: :width

  behavior do
    # Connect outputs
    a_out <= a_reg
    b_out <= b_reg
    c_out <= c_reg

    on(posedge: :clk) do
      if reset == 1
        a_reg <= 0
        b_reg <= 0
        c_reg <= 0
      elsif push == 1
        # Push: C lost, B->C, A->B, new->A
        c_reg <= b_reg
        b_reg <= a_reg
        a_reg <= data_in
      elsif pop == 1
        # Pop: A discarded, B->A, C->B, C undefined
        a_reg <= b_reg
        b_reg <= c_reg
        # c_reg stays (undefined in real Transputer)
      elsif swap == 1
        # REV: Swap A and B
        a_reg <= b_reg
        b_reg <= a_reg
      elsif dup == 1
        # Duplicate: A stays, A->B, B->C
        c_reg <= b_reg
        b_reg <= a_reg
      end
    end
  end
end
```

---

## Operand Register and Prefix Handling

The prefix mechanism for building larger constants.

```ruby
# Operand register with prefix handling
class OperandRegister < SimComponent
  parameter :width, default: 32

  input :clk
  input :reset

  # Control signals
  input :pfix         # PFIX instruction
  input :nfix         # NFIX instruction
  input :clear        # Clear after use
  input :operand, width: 4  # 4-bit operand from instruction

  output :oreg, width: :width  # Full operand value

  wire :oreg_internal, width: :width

  behavior do
    oreg <= oreg_internal

    on(posedge: :clk) do
      if reset == 1
        oreg_internal <= 0
      elsif pfix == 1
        # PFIX: Oreg = (Oreg | operand) << 4
        oreg_internal <= ((oreg_internal | operand.zext(width)) << 4)
      elsif nfix == 1
        # NFIX: Oreg = (~(Oreg | operand)) << 4
        oreg_internal <= ((~(oreg_internal | operand.zext(width))) << 4)
      elsif clear == 1
        # Clear after instruction uses operand
        oreg_internal <= 0
      end
    end
  end
end
```

---

## Link Engine

The serial communication hardware for inter-Transputer links.

```ruby
# Transputer link engine - handles serial communication
class LinkEngine < SimComponent
  parameter :clock_div, default: 4  # Clock divider for bit rate

  input :clk
  input :reset

  # Internal interface (to CPU)
  input :send_data, width: 8   # Byte to send
  input :send_start            # Start sending
  output :send_busy            # Sending in progress
  output :send_done            # Byte sent, ack received

  input :recv_ready            # Ready to receive
  output :recv_data, width: 8  # Received byte
  output :recv_valid           # Data valid

  # External link signals
  output :link_out             # Serial output
  input :link_in               # Serial input

  # State definitions
  IDLE = 0
  SENDING = 1
  WAIT_ACK = 2
  RECEIVING = 3
  SEND_ACK = 4

  # Internal state
  wire :tx_state, width: 3
  wire :rx_state, width: 3
  wire :tx_shift, width: 8
  wire :rx_shift, width: 8
  wire :bit_count, width: 4
  wire :clock_count, width: 8

  behavior do
    # Default outputs
    send_busy <= (tx_state != IDLE) ? 1 : 0
    recv_data <= rx_shift

    on(posedge: :clk) do
      if reset == 1
        tx_state <= IDLE
        rx_state <= IDLE
        link_out <= 1  # Idle high
        send_done <= 0
        recv_valid <= 0
        clock_count <= 0
        bit_count <= 0
      else
        # Clear single-cycle flags
        send_done <= 0
        recv_valid <= 0

        # Transmit state machine
        case tx_state
        when IDLE
          if send_start == 1
            tx_shift <= send_data
            tx_state <= SENDING
            bit_count <= 0
            clock_count <= 0
            link_out <= 0  # Start bit
          end

        when SENDING
          clock_count <= clock_count + 1
          if clock_count == clock_div - 1
            clock_count <= 0
            if bit_count < 8
              link_out <= tx_shift[0]
              tx_shift <= tx_shift >> 1
              bit_count <= bit_count + 1
            else
              link_out <= 1  # Stop bit
              tx_state <= WAIT_ACK
            end
          end

        when WAIT_ACK
          # Wait for acknowledge from receiver
          if link_in == 0  # Ack received
            send_done <= 1
            tx_state <= IDLE
            link_out <= 1
          end
        end

        # Receive state machine
        case rx_state
        when IDLE
          if recv_ready == 1 && link_in == 0  # Start bit detected
            rx_state <= RECEIVING
            bit_count <= 0
            clock_count <= clock_div / 2  # Sample in middle
          end

        when RECEIVING
          clock_count <= clock_count + 1
          if clock_count == clock_div - 1
            clock_count <= 0
            if bit_count < 8
              rx_shift <= (rx_shift >> 1) | (link_in << 7)
              bit_count <= bit_count + 1
            else
              rx_state <= SEND_ACK
            end
          end

        when SEND_ACK
          recv_valid <= 1
          link_out <= 0  # Send acknowledge
          rx_state <= IDLE
        end
      end
    end
  end
end
```

---

## Process Scheduler

Hardware scheduler with two priority levels.

```ruby
# Two-priority hardware process scheduler
class ProcessScheduler < SimComponent
  parameter :addr_width, default: 16  # Workspace address width

  input :clk
  input :reset

  # Current process
  output :wptr, width: :addr_width     # Current workspace pointer
  output :iptr, width: :addr_width     # Current instruction pointer
  output :priority                     # Current priority (0=high, 1=low)
  output :running                      # A process is running

  # Process control
  input :deschedule                    # Remove current from queue
  input :schedule_wptr, width: :addr_width  # Process to schedule
  input :schedule_iptr, width: :addr_width
  input :schedule_pri                  # Priority of process to schedule
  input :schedule_en                   # Enable scheduling

  input :save_iptr, width: :addr_width # Save Iptr when descheduling

  # Memory interface for queue manipulation
  output :mem_addr, width: :addr_width
  output :mem_write_data, width: :addr_width
  output :mem_write_en
  input :mem_read_data, width: :addr_width

  # Queue pointers (front and back for each priority)
  wire :fptr_hi, width: :addr_width   # Front pointer, high priority
  wire :bptr_hi, width: :addr_width   # Back pointer, high priority
  wire :fptr_lo, width: :addr_width   # Front pointer, low priority
  wire :bptr_lo, width: :addr_width   # Back pointer, low priority

  wire :queue_hi_empty
  wire :queue_lo_empty

  wire :current_wptr, width: :addr_width
  wire :current_iptr, width: :addr_width
  wire :current_pri

  # Scheduler states
  IDLE = 0
  SAVE_IPTR = 1
  LOAD_NEXT = 2
  ADD_TO_QUEUE = 3

  wire :state, width: 3

  behavior do
    # Queue empty detection
    queue_hi_empty <= (fptr_hi == 0) ? 1 : 0
    queue_lo_empty <= (fptr_lo == 0) ? 1 : 0

    # Current process outputs
    wptr <= current_wptr
    iptr <= current_iptr
    priority <= current_pri
    running <= (state == IDLE && (queue_hi_empty == 0 || queue_lo_empty == 0)) ? 1 : 0

    on(posedge: :clk) do
      if reset == 1
        fptr_hi <= 0
        bptr_hi <= 0
        fptr_lo <= 0
        bptr_lo <= 0
        current_wptr <= 0
        current_iptr <= 0
        current_pri <= 1
        state <= IDLE
        mem_write_en <= 0
      else
        mem_write_en <= 0

        case state
        when IDLE
          # Check for deschedule request
          if deschedule == 1
            # Save Iptr to workspace[-4]
            mem_addr <= current_wptr - 4
            mem_write_data <= save_iptr
            mem_write_en <= 1
            state <= LOAD_NEXT
          elsif schedule_en == 1
            # Add new process to queue
            state <= ADD_TO_QUEUE
          end

        when LOAD_NEXT
          # Load next process from highest priority non-empty queue
          if queue_hi_empty == 0
            current_wptr <= fptr_hi
            current_pri <= 0
            # Would read next pointer from workspace, simplified here
            state <= IDLE
          elsif queue_lo_empty == 0
            current_wptr <= fptr_lo
            current_pri <= 1
            state <= IDLE
          else
            # No process ready
            current_wptr <= 0
            state <= IDLE
          end

        when ADD_TO_QUEUE
          # Add process to back of appropriate queue
          if schedule_pri == 0
            # High priority
            if queue_hi_empty == 1
              fptr_hi <= schedule_wptr
            end
            bptr_hi <= schedule_wptr
          else
            # Low priority
            if queue_lo_empty == 1
              fptr_lo <= schedule_wptr
            end
            bptr_lo <= schedule_wptr
          end
          state <= IDLE
        end
      end
    end
  end
end
```

---

## Internal Channel

Memory-based channel for same-Transputer communication.

```ruby
# Internal channel - synchronous communication
class Channel < SimComponent
  parameter :width, default: 32

  input :clk
  input :reset

  # Sender interface
  input :send_data, width: :width
  input :send_valid
  output :send_ready   # Sender can proceed

  # Receiver interface
  output :recv_data, width: :width
  input :recv_ready
  output :recv_valid   # Data available

  # Process control outputs
  output :sender_wake          # Wake sending process
  output :receiver_wake        # Wake receiving process
  output :sender_wptr, width: 16   # Stored sender workspace
  output :receiver_wptr, width: 16 # Stored receiver workspace

  # State: EMPTY, SENDER_WAITING, RECEIVER_WAITING
  EMPTY = 0
  SENDER_WAITING = 1
  RECEIVER_WAITING = 2

  wire :state, width: 2
  wire :stored_data, width: :width
  wire :stored_sender, width: 16
  wire :stored_receiver, width: 16

  behavior do
    # Default outputs
    send_ready <= 0
    recv_valid <= 0
    sender_wake <= 0
    receiver_wake <= 0
    recv_data <= stored_data
    sender_wptr <= stored_sender
    receiver_wptr <= stored_receiver

    on(posedge: :clk) do
      if reset == 1
        state <= EMPTY
        stored_data <= 0
      else
        sender_wake <= 0
        receiver_wake <= 0

        case state
        when EMPTY
          if send_valid == 1 && recv_ready == 1
            # Both ready simultaneously - immediate transfer
            stored_data <= send_data
            send_ready <= 1
            recv_valid <= 1
          elsif send_valid == 1
            # Sender first - store data and wait
            stored_data <= send_data
            state <= SENDER_WAITING
          elsif recv_ready == 1
            # Receiver first - wait for sender
            state <= RECEIVER_WAITING
          end

        when SENDER_WAITING
          if recv_ready == 1
            # Receiver arrived - complete transfer
            recv_valid <= 1
            sender_wake <= 1  # Wake the waiting sender
            state <= EMPTY
          end

        when RECEIVER_WAITING
          if send_valid == 1
            # Sender arrived - complete transfer
            stored_data <= send_data
            send_ready <= 1
            receiver_wake <= 1  # Wake the waiting receiver
            state <= EMPTY
          end
        end
      end
    end
  end
end
```

---

## ALT Controller

Hardware support for the ALT (alternative) construct.

```ruby
# ALT controller - wait for first of multiple channels
class ALTController < SimComponent
  parameter :num_channels, default: 4

  input :clk
  input :reset

  # ALT operation control
  input :alt_start         # Begin ALT
  input :alt_wait          # Enter waiting state
  input :alt_end           # Complete ALT
  input :enable, width: :num_channels  # Enable each channel
  input :disable, width: :num_channels # Disable each channel

  # Channel ready signals
  input :channel_ready, width: :num_channels

  # Outputs
  output :selected, width: 8           # Which channel fired (index)
  output :ready                        # A channel is ready
  output :waiting                      # ALT is waiting

  # State
  ALT_IDLE = 0
  ALT_ENABLING = 1
  ALT_WAITING = 2
  ALT_READY = 3
  ALT_DISABLING = 4

  wire :state, width: 3
  wire :enabled_mask, width: :num_channels
  wire :ready_mask, width: :num_channels

  behavior do
    # Check for ready channels among enabled ones
    ready_mask <= enabled_mask & channel_ready
    ready <= (ready_mask != 0) ? 1 : 0
    waiting <= (state == ALT_WAITING) ? 1 : 0

    # Priority encoder - find lowest numbered ready channel
    if ready_mask[0] == 1
      selected <= 0
    elsif ready_mask[1] == 1
      selected <= 1
    elsif ready_mask[2] == 1
      selected <= 2
    elsif ready_mask[3] == 1
      selected <= 3
    else
      selected <= 0xFF  # None ready
    end

    on(posedge: :clk) do
      if reset == 1
        state <= ALT_IDLE
        enabled_mask <= 0
      else
        case state
        when ALT_IDLE
          if alt_start == 1
            state <= ALT_ENABLING
            enabled_mask <= 0
          end

        when ALT_ENABLING
          # Enable channels one by one
          enabled_mask <= enabled_mask | enable
          if alt_wait == 1
            if ready_mask != 0
              # Already have a ready channel
              state <= ALT_READY
            else
              state <= ALT_WAITING
            end
          end

        when ALT_WAITING
          if ready_mask != 0
            # A channel became ready
            state <= ALT_READY
          end

        when ALT_READY
          if disable != 0
            state <= ALT_DISABLING
          end

        when ALT_DISABLING
          enabled_mask <= enabled_mask & ~disable
          if alt_end == 1
            state <= ALT_IDLE
          end
        end
      end
    end
  end
end
```

---

## Instruction Decoder

Decodes Transputer's compact instruction format.

```ruby
# Transputer instruction decoder
class TransputerDecoder < SimComponent
  input :instruction, width: 8
  input :oreg, width: 32       # Current operand register

  # Decoded fields
  output :function, width: 4   # Function code (0-15)
  output :operand, width: 4    # 4-bit operand

  # Decoded operation type
  output :is_pfix              # Prefix instruction
  output :is_nfix              # Negative prefix
  output :is_opr               # Operate (secondary)
  output :is_direct            # Direct function

  # For OPR, decode secondary function
  output :secondary, width: 8  # Secondary function from Oreg

  behavior do
    # Extract fields
    function <= instruction[7:4]
    operand <= instruction[3:0]

    # Decode function type
    is_pfix <= (instruction[7:4] == 0x2) ? 1 : 0   # PFIX
    is_nfix <= (instruction[7:4] == 0x6) ? 1 : 0   # NFIX
    is_opr <= (instruction[7:4] == 0xF) ? 1 : 0    # OPR

    # Direct if not PFIX, NFIX, or OPR
    is_direct <= ((instruction[7:4] != 0x2) &&
                  (instruction[7:4] != 0x6) &&
                  (instruction[7:4] != 0xF)) ? 1 : 0

    # Secondary function comes from operand register
    secondary <= oreg[7:0]
  end
end
```

---

## ALU

Transputer arithmetic logic unit.

```ruby
# Transputer ALU
class TransputerALU < SimComponent
  parameter :width, default: 32

  input :a, width: :width      # Top of stack (also first operand)
  input :b, width: :width      # Second on stack
  input :operation, width: 4   # ALU operation

  output :result, width: :width
  output :overflow             # Overflow flag

  # ALU operations (subset)
  OP_ADD = 0
  OP_SUB = 1
  OP_MUL = 2
  OP_AND = 3
  OP_OR = 4
  OP_XOR = 5
  OP_NOT = 6
  OP_SHL = 7
  OP_SHR = 8
  OP_GT = 9
  OP_EQ = 10
  OP_DIFF = 11

  wire :add_result, width: :width + 1
  wire :sub_result, width: :width + 1

  behavior do
    add_result <= a.zext(width + 1) + b.zext(width + 1)
    sub_result <= b.zext(width + 1) - a.zext(width + 1)

    overflow <= 0

    case operation
    when OP_ADD
      result <= add_result[width-1:0]
      overflow <= add_result[width]
    when OP_SUB
      result <= sub_result[width-1:0]
    when OP_MUL
      result <= (a * b)[width-1:0]
    when OP_AND
      result <= a & b
    when OP_OR
      result <= a | b
    when OP_XOR
      result <= a ^ b
    when OP_NOT
      result <= ~a
    when OP_SHL
      result <= b << a[4:0]  # Shift amount from A
    when OP_SHR
      result <= b >> a[4:0]
    when OP_GT
      result <= (b > a) ? 1 : 0
    when OP_EQ
      result <= (a == b) ? 1 : 0
    when OP_DIFF
      result <= a ^ b  # Actually DIFF is more complex
    else
      result <= 0
    end
  end
end
```

---

## Timer

Hardware timer for process timing.

```ruby
# Transputer timer
class TransputerTimer < SimComponent
  parameter :width, default: 32

  input :clk
  input :reset

  # Timer read
  output :timer_value, width: :width

  # Timer comparison for AFTER
  input :compare_value, width: :width
  output :timer_after            # timer_value AFTER compare_value

  wire :counter, width: :width

  behavior do
    timer_value <= counter

    # AFTER comparison (handles wraparound)
    # A is AFTER B if (A - B) is positive in signed arithmetic
    timer_after <= ((counter - compare_value)[width-1] == 0) ? 1 : 0

    on(posedge: :clk) do
      if reset == 1
        counter <= 0
      else
        counter <= counter + 1
      end
    end
  end
end
```

---

## Simplified Transputer Core

A simplified core showing the main datapath.

```ruby
# Simplified Transputer core
class TransputerCore < SimComponent
  parameter :width, default: 32

  input :clk
  input :reset

  # Memory interface
  output :mem_addr, width: :width
  output :mem_write_data, width: :width
  output :mem_write_en
  output :mem_read_en
  input :mem_read_data, width: :width

  # Link interfaces (simplified - one link shown)
  output :link0_out_data, width: 8
  output :link0_out_valid
  input :link0_out_ready
  input :link0_in_data, width: 8
  input :link0_in_valid
  output :link0_in_ready

  # Internal state
  wire :wptr, width: :width           # Workspace pointer
  wire :iptr, width: :width           # Instruction pointer
  wire :oreg, width: :width           # Operand register

  # Evaluation stack
  wire :a_reg, width: :width
  wire :b_reg, width: :width
  wire :c_reg, width: :width

  # Instruction register
  wire :instr, width: 8
  wire :function, width: 4
  wire :operand, width: 4

  # CPU states
  FETCH = 0
  DECODE = 1
  EXECUTE = 2
  MEMORY = 3
  WRITEBACK = 4
  WAIT_LINK = 5

  wire :state, width: 3
  wire :next_state, width: 3

  # Sub-components
  instance :alu, TransputerALU, width: width
  instance :timer, TransputerTimer, width: width

  port :clk => [:timer, :clk]
  port :reset => [:timer, :reset]
  port :a_reg => [:alu, :a]
  port :b_reg => [:alu, :b]

  behavior do
    # Extract instruction fields
    function <= instr[7:4]
    operand <= instr[3:0]

    # Default memory signals
    mem_write_en <= 0
    mem_read_en <= 0

    on(posedge: :clk) do
      if reset == 1
        state <= FETCH
        iptr <= 0
        wptr <= 0
        oreg <= 0
        a_reg <= 0
        b_reg <= 0
        c_reg <= 0
      else
        case state
        when FETCH
          # Fetch next instruction
          mem_addr <= iptr
          mem_read_en <= 1
          state <= DECODE

        when DECODE
          instr <= mem_read_data[7:0]
          iptr <= iptr + 1
          state <= EXECUTE

        when EXECUTE
          case function
          # PFIX - Prefix
          when 0x2
            oreg <= (oreg | operand.zext(width)) << 4
            state <= FETCH

          # NFIX - Negative prefix
          when 0x6
            oreg <= (~(oreg | operand.zext(width))) << 4
            state <= FETCH

          # LDC - Load constant
          when 0x4
            c_reg <= b_reg
            b_reg <= a_reg
            a_reg <= oreg | operand.zext(width)
            oreg <= 0
            state <= FETCH

          # LDL - Load local
          when 0x7
            mem_addr <= wptr + ((oreg | operand.zext(width)) << 2)
            mem_read_en <= 1
            state <= MEMORY

          # STL - Store local
          when 0xD
            mem_addr <= wptr + ((oreg | operand.zext(width)) << 2)
            mem_write_data <= a_reg
            mem_write_en <= 1
            a_reg <= b_reg
            b_reg <= c_reg
            oreg <= 0
            state <= FETCH

          # J - Jump
          when 0x0
            iptr <= iptr + (oreg | operand.zext(width))
            oreg <= 0
            state <= FETCH

          # CJ - Conditional jump
          when 0xA
            if a_reg == 0
              iptr <= iptr + (oreg | operand.zext(width))
            end
            a_reg <= b_reg
            b_reg <= c_reg
            oreg <= 0
            state <= FETCH

          # ADC - Add constant
          when 0x8
            a_reg <= a_reg + (oreg | operand.zext(width))
            oreg <= 0
            state <= FETCH

          # AJW - Adjust workspace
          when 0xB
            wptr <= wptr + ((oreg | operand.zext(width)) << 2)
            oreg <= 0
            state <= FETCH

          # OPR - Operate (secondary instructions)
          when 0xF
            execute_secondary(oreg | operand.zext(width))
            oreg <= 0

          else
            state <= FETCH
          end

        when MEMORY
          # Complete load
          c_reg <= b_reg
          b_reg <= a_reg
          a_reg <= mem_read_data
          oreg <= 0
          state <= FETCH

        when WRITEBACK
          state <= FETCH

        when WAIT_LINK
          # Wait for link operation to complete
          if link0_out_ready == 1 || link0_in_valid == 1
            state <= FETCH
          end
        end
      end
    end
  end

  # Secondary instruction execution (subset)
  def execute_secondary(opcode)
    case opcode
    # ADD
    when 0x05
      a_reg <= b_reg + a_reg
      b_reg <= c_reg
      state <= FETCH

    # SUB
    when 0x0C
      a_reg <= b_reg - a_reg
      b_reg <= c_reg
      state <= FETCH

    # MUL
    when 0x53
      a_reg <= (b_reg * a_reg)[width-1:0]
      b_reg <= c_reg
      state <= FETCH

    # AND
    when 0x46
      a_reg <= a_reg & b_reg
      b_reg <= c_reg
      state <= FETCH

    # OR
    when 0x4B
      a_reg <= a_reg | b_reg
      b_reg <= c_reg
      state <= FETCH

    # XOR
    when 0x33
      a_reg <= a_reg ^ b_reg
      b_reg <= c_reg
      state <= FETCH

    # NOT
    when 0x32
      a_reg <= ~a_reg
      state <= FETCH

    # REV - Reverse A and B
    when 0x00
      temp = a_reg
      a_reg <= b_reg
      b_reg <= temp
      state <= FETCH

    # GT - Greater than
    when 0x09
      a_reg <= (b_reg > a_reg) ? 1 : 0
      b_reg <= c_reg
      state <= FETCH

    # SHL - Shift left
    when 0x41
      a_reg <= b_reg << a_reg[4:0]
      b_reg <= c_reg
      state <= FETCH

    # SHR - Shift right
    when 0x40
      a_reg <= b_reg >> a_reg[4:0]
      b_reg <= c_reg
      state <= FETCH

    # LDTIMER - Load timer
    when 0x22
      c_reg <= b_reg
      b_reg <= a_reg
      a_reg <= timer.timer_value
      state <= FETCH

    # OUT - Output to channel
    when 0x0B
      # A = channel, B = address, C = count
      link0_out_data <= mem_read_data[7:0]
      link0_out_valid <= 1
      state <= WAIT_LINK

    # IN - Input from channel
    when 0x07
      # A = channel, B = address, C = count
      link0_in_ready <= 1
      state <= WAIT_LINK

    # STOPP - Stop process
    when 0x15
      # Would deschedule here
      state <= FETCH

    # STARTP - Start process
    when 0x0D
      # A = workspace, B = Iptr
      # Would add to scheduler queue
      state <= FETCH

    else
      state <= FETCH
    end
  end
end
```

---

## Multi-Transputer System

Connecting multiple Transputers in a network.

```ruby
# Four-node Transputer ring
class TransputerRing < SimComponent
  input :clk
  input :reset

  # External memory interfaces (one per Transputer)
  output :mem0_addr, width: 32
  output :mem0_write_data, width: 32
  output :mem0_write_en
  input :mem0_read_data, width: 32

  output :mem1_addr, width: 32
  output :mem1_write_data, width: 32
  output :mem1_write_en
  input :mem1_read_data, width: 32

  output :mem2_addr, width: 32
  output :mem2_write_data, width: 32
  output :mem2_write_en
  input :mem2_read_data, width: 32

  output :mem3_addr, width: 32
  output :mem3_write_data, width: 32
  output :mem3_write_en
  input :mem3_read_data, width: 32

  # Four Transputer cores
  instance :t0, TransputerCore
  instance :t1, TransputerCore
  instance :t2, TransputerCore
  instance :t3, TransputerCore

  # Link connections forming a ring: T0 <-> T1 <-> T2 <-> T3 <-> T0

  # Internal link wires
  wire :link_0_to_1_data, width: 8
  wire :link_0_to_1_valid
  wire :link_0_to_1_ready
  wire :link_1_to_0_data, width: 8
  wire :link_1_to_0_valid
  wire :link_1_to_0_ready

  wire :link_1_to_2_data, width: 8
  wire :link_1_to_2_valid
  wire :link_1_to_2_ready
  wire :link_2_to_1_data, width: 8
  wire :link_2_to_1_valid
  wire :link_2_to_1_ready

  wire :link_2_to_3_data, width: 8
  wire :link_2_to_3_valid
  wire :link_2_to_3_ready
  wire :link_3_to_2_data, width: 8
  wire :link_3_to_2_valid
  wire :link_3_to_2_ready

  wire :link_3_to_0_data, width: 8
  wire :link_3_to_0_valid
  wire :link_3_to_0_ready
  wire :link_0_to_3_data, width: 8
  wire :link_0_to_3_valid
  wire :link_0_to_3_ready

  # Clock and reset to all cores
  port :clk => [[:t0, :clk], [:t1, :clk], [:t2, :clk], [:t3, :clk]]
  port :reset => [[:t0, :reset], [:t1, :reset], [:t2, :reset], [:t3, :reset]]

  # Memory interfaces
  port [:t0, :mem_addr] => :mem0_addr
  port [:t0, :mem_write_data] => :mem0_write_data
  port [:t0, :mem_write_en] => :mem0_write_en
  port :mem0_read_data => [:t0, :mem_read_data]

  port [:t1, :mem_addr] => :mem1_addr
  port [:t1, :mem_write_data] => :mem1_write_data
  port [:t1, :mem_write_en] => :mem1_write_en
  port :mem1_read_data => [:t1, :mem_read_data]

  port [:t2, :mem_addr] => :mem2_addr
  port [:t2, :mem_write_data] => :mem2_write_data
  port [:t2, :mem_write_en] => :mem2_write_en
  port :mem2_read_data => [:t2, :mem_read_data]

  port [:t3, :mem_addr] => :mem3_addr
  port [:t3, :mem_write_data] => :mem3_write_data
  port [:t3, :mem_write_en] => :mem3_write_en
  port :mem3_read_data => [:t3, :mem_read_data]

  # Ring topology: T0 -> T1 -> T2 -> T3 -> T0
  # T0 link0 <-> T1 link0
  port [:t0, :link0_out_data] => :link_0_to_1_data
  port [:t0, :link0_out_valid] => :link_0_to_1_valid
  port :link_1_to_0_ready => [:t0, :link0_out_ready]

  port [:t1, :link0_out_data] => :link_1_to_0_data
  port [:t1, :link0_out_valid] => :link_1_to_0_valid
  port :link_0_to_1_ready => [:t1, :link0_out_ready]

  port :link_0_to_1_data => [:t1, :link0_in_data]
  port :link_0_to_1_valid => [:t1, :link0_in_valid]
  port [:t1, :link0_in_ready] => :link_0_to_1_ready

  port :link_1_to_0_data => [:t0, :link0_in_data]
  port :link_1_to_0_valid => [:t0, :link0_in_valid]
  port [:t0, :link0_in_ready] => :link_1_to_0_ready
end
```

---

## Test Bench: Channel Communication

```ruby
# Test bench for channel communication
class ChannelTestBench < SimComponent
  input :clk
  input :reset

  output :test_pass
  output :test_done

  instance :channel, Channel, width: 32

  # Test state
  wire :state, width: 4
  wire :send_data, width: 32
  wire :recv_data, width: 32

  port :clk => [:channel, :clk]
  port :reset => [:channel, :reset]

  IDLE = 0
  SEND_FIRST = 1
  RECV_FIRST = 2
  SIMULTANEOUS = 3
  VERIFY = 4
  DONE = 5

  behavior do
    test_pass <= 0
    test_done <= 0

    on(posedge: :clk) do
      if reset == 1
        state <= IDLE
        send_data <= 0x12345678
      else
        case state
        when IDLE
          state <= SEND_FIRST

        when SEND_FIRST
          # Test: sender arrives first
          channel.send_data <= send_data
          channel.send_valid <= 1
          channel.recv_ready <= 0
          state <= RECV_FIRST

        when RECV_FIRST
          # Now receiver arrives
          channel.send_valid <= 0
          channel.recv_ready <= 1
          if channel.recv_valid == 1
            recv_data <= channel.recv_data
            state <= VERIFY
          end

        when VERIFY
          channel.recv_ready <= 0
          if recv_data == send_data
            test_pass <= 1
          end
          state <= DONE

        when DONE
          test_done <= 1
        end
      end
    end
  end
end
```

---

## Performance Notes

### Implementation Characteristics

| Component | Gates | DFFs | Critical Path |
|-----------|-------|------|---------------|
| EvaluationStack | ~300 | 96 | 1 cycle |
| OperandRegister | ~200 | 32 | 1 cycle |
| LinkEngine | ~500 | 48 | Multi-cycle |
| ProcessScheduler | ~1000 | 128 | 3 cycles |
| Channel | ~200 | 48 | 2 cycles |
| ALTController | ~300 | 24 | 1 cycle |
| TransputerCore | ~5000 | 256 | 5 cycles |

### Timing

```
Internal channel transfer: 2-10 cycles
External link byte: ~40 cycles (at 20 Mbit/s equivalent)
Context switch: 1-2 cycles
ALT wait completion: 1 cycle after ready
```

---

## Further Work

Potential extensions:

1. **Complete instruction set**: All 100+ instructions
2. **Floating-point unit**: T800-style 64-bit FPU
3. **Multiple links**: All four link engines
4. **2D mesh router**: For larger networks
5. **Virtual channels**: Multiple logical channels per link
6. **Error handling**: Link error detection and recovery

---

*Back to [Chapter 26 - Transputer](26-transputer.md)*
