# frozen_string_literal: true

module RHDL
  module HDL
    # FIFO Queue
    # Sequential - requires always @(posedge clk) for synthesis
    class FIFO < SimComponent
      port_input :clk
      port_input :rst
      port_input :wr_en
      port_input :rd_en
      port_input :din, width: 8
      port_output :dout, width: 8
      port_output :empty
      port_output :full
      port_output :count, width: 5

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
        return if @data_width == 8 && @depth == 16
        @inputs[:din] = Wire.new("#{@name}.din", width: @data_width)
        @outputs[:dout] = Wire.new("#{@name}.dout", width: @data_width)
        @outputs[:count] = Wire.new("#{@name}.count", width: @addr_width + 1)
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
