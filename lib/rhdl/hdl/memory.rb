# HDL Memory Components
# RAM, ROM, and memory interfaces

module RHDL
  module HDL
    # Synchronous RAM with single port
    class RAM < SimComponent
      def initialize(name = nil, data_width: 8, addr_width: 8)
        @data_width = data_width
        @addr_width = addr_width
        @depth = 1 << addr_width
        @memory = Array.new(@depth, 0)
        @prev_clk = 0
        super(name)
      end

      def setup_ports
        input :clk
        input :we       # Write enable
        input :addr, width: @addr_width
        input :din, width: @data_width
        output :dout, width: @data_width
      end

      def rising_edge?
        prev = @prev_clk
        @prev_clk = in_val(:clk)
        prev == 0 && @prev_clk == 1
      end

      def propagate
        addr = in_val(:addr) & (@depth - 1)

        # Write on rising edge
        if rising_edge? && in_val(:we) == 1
          @memory[addr] = in_val(:din) & ((1 << @data_width) - 1)
        end

        # Async read
        out_set(:dout, @memory[addr])
      end

      # Direct memory access for initialization/debugging
      def read_mem(addr)
        @memory[addr & (@depth - 1)]
      end

      def write_mem(addr, data)
        @memory[addr & (@depth - 1)] = data & ((1 << @data_width) - 1)
      end

      def load_program(program, start_addr = 0)
        program.each_with_index do |byte, i|
          write_mem(start_addr + i, byte)
        end
      end
    end

    # Synchronous RAM with dual port (read + write)
    class DualPortRAM < SimComponent
      def initialize(name = nil, data_width: 8, addr_width: 8)
        @data_width = data_width
        @addr_width = addr_width
        @depth = 1 << addr_width
        @memory = Array.new(@depth, 0)
        @prev_clk = 0
        super(name)
      end

      def setup_ports
        input :clk
        input :we
        input :waddr, width: @addr_width
        input :raddr, width: @addr_width
        input :din, width: @data_width
        output :dout, width: @data_width
      end

      def rising_edge?
        prev = @prev_clk
        @prev_clk = in_val(:clk)
        prev == 0 && @prev_clk == 1
      end

      def propagate
        # Write on rising edge
        if rising_edge? && in_val(:we) == 1
          waddr = in_val(:waddr) & (@depth - 1)
          @memory[waddr] = in_val(:din) & ((1 << @data_width) - 1)
        end

        # Async read from separate port
        raddr = in_val(:raddr) & (@depth - 1)
        out_set(:dout, @memory[raddr])
      end

      def read_mem(addr)
        @memory[addr & (@depth - 1)]
      end

      def write_mem(addr, data)
        @memory[addr & (@depth - 1)] = data & ((1 << @data_width) - 1)
      end
    end

    # ROM (Read-Only Memory)
    class ROM < SimComponent
      def initialize(name = nil, data_width: 8, addr_width: 8, contents: [])
        @data_width = data_width
        @addr_width = addr_width
        @depth = 1 << addr_width
        @memory = Array.new(@depth, 0)
        contents.each_with_index { |v, i| @memory[i] = v if i < @depth }
        super(name)
      end

      def setup_ports
        input :addr, width: @addr_width
        input :en
        output :dout, width: @data_width
      end

      def propagate
        if in_val(:en) == 1
          addr = in_val(:addr) & (@depth - 1)
          out_set(:dout, @memory[addr])
        else
          out_set(:dout, 0)
        end
      end

      def read_mem(addr)
        @memory[addr & (@depth - 1)]
      end
    end

    # Register File (multiple registers with read/write ports)
    class RegisterFile < SimComponent
      def initialize(name = nil, data_width: 8, num_regs: 8)
        @data_width = data_width
        @num_regs = num_regs
        @addr_width = Math.log2(num_regs).ceil
        @registers = Array.new(num_regs, 0)
        @prev_clk = 0
        super(name)
      end

      def setup_ports
        input :clk
        input :we
        input :waddr, width: @addr_width
        input :raddr1, width: @addr_width
        input :raddr2, width: @addr_width
        input :wdata, width: @data_width
        output :rdata1, width: @data_width
        output :rdata2, width: @data_width
      end

      def rising_edge?
        prev = @prev_clk
        @prev_clk = in_val(:clk)
        prev == 0 && @prev_clk == 1
      end

      def propagate
        # Write on rising edge
        if rising_edge? && in_val(:we) == 1
          waddr = in_val(:waddr) & (@num_regs - 1)
          @registers[waddr] = in_val(:wdata) & ((1 << @data_width) - 1)
        end

        # Async read
        raddr1 = in_val(:raddr1) & (@num_regs - 1)
        raddr2 = in_val(:raddr2) & (@num_regs - 1)
        out_set(:rdata1, @registers[raddr1])
        out_set(:rdata2, @registers[raddr2])
      end

      def read_reg(addr)
        @registers[addr & (@num_regs - 1)]
      end

      def write_reg(addr, data)
        @registers[addr & (@num_regs - 1)] = data & ((1 << @data_width) - 1)
      end
    end

    # Stack (LIFO) with fixed depth
    class Stack < SimComponent
      def initialize(name = nil, data_width: 8, depth: 16)
        @data_width = data_width
        @depth = depth
        @addr_width = Math.log2(depth).ceil
        @memory = Array.new(depth, 0)
        @sp = 0
        @prev_clk = 0
        super(name)
      end

      def setup_ports
        input :clk
        input :rst
        input :push
        input :pop
        input :din, width: @data_width
        output :dout, width: @data_width
        output :empty
        output :full
        output :sp, width: @addr_width
      end

      def rising_edge?
        prev = @prev_clk
        @prev_clk = in_val(:clk)
        prev == 0 && @prev_clk == 1
      end

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @sp = 0
          elsif in_val(:push) == 1 && @sp < @depth
            @memory[@sp] = in_val(:din) & ((1 << @data_width) - 1)
            @sp += 1
          elsif in_val(:pop) == 1 && @sp > 0
            @sp -= 1
          end
        end

        # Output top of stack
        dout = @sp > 0 ? @memory[@sp - 1] : 0
        out_set(:dout, dout)
        out_set(:empty, @sp == 0 ? 1 : 0)
        out_set(:full, @sp >= @depth ? 1 : 0)
        out_set(:sp, @sp)
      end
    end

    # FIFO Queue
    class FIFO < SimComponent
      def initialize(name = nil, data_width: 8, depth: 16)
        @data_width = data_width
        @depth = depth
        @addr_width = Math.log2(depth).ceil
        @memory = Array.new(depth, 0)
        @rd_ptr = 0
        @wr_ptr = 0
        @count = 0
        @prev_clk = 0
        super(name)
      end

      def setup_ports
        input :clk
        input :rst
        input :wr_en
        input :rd_en
        input :din, width: @data_width
        output :dout, width: @data_width
        output :empty
        output :full
        output :count, width: @addr_width + 1
      end

      def rising_edge?
        prev = @prev_clk
        @prev_clk = in_val(:clk)
        prev == 0 && @prev_clk == 1
      end

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @rd_ptr = 0
            @wr_ptr = 0
            @count = 0
          else
            wrote = false
            read = false

            # Write
            if in_val(:wr_en) == 1 && @count < @depth
              @memory[@wr_ptr] = in_val(:din) & ((1 << @data_width) - 1)
              @wr_ptr = (@wr_ptr + 1) % @depth
              wrote = true
            end

            # Read
            if in_val(:rd_en) == 1 && @count > 0
              @rd_ptr = (@rd_ptr + 1) % @depth
              read = true
            end

            # Update count
            @count += 1 if wrote && !read
            @count -= 1 if read && !wrote
          end
        end

        out_set(:dout, @memory[@rd_ptr])
        out_set(:empty, @count == 0 ? 1 : 0)
        out_set(:full, @count >= @depth ? 1 : 0)
        out_set(:count, @count)
      end
    end
  end
end
