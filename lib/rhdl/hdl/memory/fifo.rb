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

      behavior do
        depth_val = param(:depth)
        data_width = param(:data_width)
        data_mask = (1 << data_width) - 1

        rd_ptr = get_var(:rd_ptr)
        wr_ptr = get_var(:wr_ptr)
        cnt = get_var(:count)

        if rising_edge?
          if rst.value == 1
            set_var(:rd_ptr, 0)
            set_var(:wr_ptr, 0)
            set_var(:count, 0)
            rd_ptr = 0
            wr_ptr = 0
            cnt = 0
          else
            wrote = false
            did_read = false

            # Write
            if wr_en.value == 1 && cnt < depth_val
              mem_write(wr_ptr, din.value & data_mask)
              set_var(:wr_ptr, (wr_ptr + 1) % depth_val)
              wrote = true
            end

            # Read
            if rd_en.value == 1 && cnt > 0
              rd_ptr = (rd_ptr + 1) % depth_val
              set_var(:rd_ptr, rd_ptr)
              did_read = true
            end

            # Update count
            if wrote && !did_read
              set_var(:count, cnt + 1)
              cnt += 1
            elsif did_read && !wrote
              set_var(:count, cnt - 1)
              cnt -= 1
            end
          end
        end

        # Read current rd_ptr for output
        current_rd_ptr = get_var(:rd_ptr)
        current_count = get_var(:count)

        dout <= mem_read(current_rd_ptr)
        empty <= (current_count == 0 ? 1 : 0)
        full <= (current_count >= depth_val ? 1 : 0)
        count <= current_count
      end

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
    end
  end
end
