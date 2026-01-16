# MOS 6502 Memory Interface
# 64KB addressable memory with RAM and ROM regions

module MOS6502
  # Simple 64KB memory for 6502
  class Memory < RHDL::HDL::SimComponent
    # Memory map constants
    RAM_START = 0x0000
    RAM_END   = 0x7FFF   # 32KB RAM
    ROM_START = 0x8000
    ROM_END   = 0xFFFF   # 32KB ROM

    # Stack region
    STACK_START = 0x0100
    STACK_END   = 0x01FF

    # Zero page
    ZP_START = 0x0000
    ZP_END   = 0x00FF

    # Vectors
    NMI_VECTOR   = 0xFFFA
    RESET_VECTOR = 0xFFFC
    IRQ_VECTOR   = 0xFFFE

    def initialize(name = nil)
      @memory = Array.new(0x10000, 0)  # 64KB
      @prev_clk = 0
      super(name)
    end

    def setup_ports
      input :clk
      input :addr, width: 16
      input :data_in, width: 8
      input :rw           # 1 = read, 0 = write
      input :cs           # Chip select (active high)

      output :data_out, width: 8
    end

    def rising_edge?
      prev = @prev_clk
      @prev_clk = in_val(:clk)
      prev == 0 && @prev_clk == 1
    end

    def propagate
      addr = in_val(:addr) & 0xFFFF
      cs = in_val(:cs)
      rw = in_val(:rw)

      if cs == 1
        if rising_edge? && rw == 0
          # Write operation (only to RAM region)
          if addr < ROM_START
            @memory[addr] = in_val(:data_in) & 0xFF
          end
          # ROM writes are ignored
        end

        # Async read
        out_set(:data_out, @memory[addr])
      else
        out_set(:data_out, 0)
      end
    end

    # Direct memory access for loading programs
    def read(addr)
      @memory[addr & 0xFFFF]
    end

    def write(addr, data)
      @memory[addr & 0xFFFF] = data & 0xFF
    end

    def load_program(program, start_addr = 0x8000)
      program.each_with_index do |byte, i|
        @memory[(start_addr + i) & 0xFFFF] = byte & 0xFF
      end
    end

    def load_bytes(bytes, start_addr)
      bytes.each_with_index do |byte, i|
        @memory[(start_addr + i) & 0xFFFF] = byte & 0xFF
      end
    end

    # Set the reset vector
    def set_reset_vector(addr)
      @memory[RESET_VECTOR] = addr & 0xFF
      @memory[RESET_VECTOR + 1] = (addr >> 8) & 0xFF
    end

    # Set the IRQ vector
    def set_irq_vector(addr)
      @memory[IRQ_VECTOR] = addr & 0xFF
      @memory[IRQ_VECTOR + 1] = (addr >> 8) & 0xFF
    end

    # Set the NMI vector
    def set_nmi_vector(addr)
      @memory[NMI_VECTOR] = addr & 0xFF
      @memory[NMI_VECTOR + 1] = (addr >> 8) & 0xFF
    end

    # Dump memory region for debugging
    def dump(start_addr, length)
      result = []
      length.times do |i|
        addr = (start_addr + i) & 0xFFFF
        result << @memory[addr]
      end
      result
    end

    # Dump as hex string
    def dump_hex(start_addr, length, bytes_per_line = 16)
      lines = []
      (0...length).step(bytes_per_line) do |offset|
        addr = (start_addr + offset) & 0xFFFF
        hex = (0...bytes_per_line).map do |i|
          if offset + i < length
            format('%02X', @memory[(addr + i) & 0xFFFF])
          else
            '  '
          end
        end.join(' ')
        ascii = (0...bytes_per_line).map do |i|
          if offset + i < length
            c = @memory[(addr + i) & 0xFFFF]
            (c >= 32 && c < 127) ? c.chr : '.'
          else
            ' '
          end
        end.join
        lines << format('%04X: %s  %s', addr, hex, ascii)
      end
      lines.join("\n")
    end

    # Clear all memory
    def clear
      @memory.fill(0)
    end

    # Fill memory region
    def fill(start_addr, length, value)
      length.times do |i|
        @memory[(start_addr + i) & 0xFFFF] = value & 0xFF
      end
    end
  end

  # Memory-mapped I/O region handler
  class MMIO < RHDL::HDL::SimComponent
    def initialize(name = nil, handlers: {})
      @handlers = handlers  # { addr_range => handler_proc }
      @output_buffer = 0
      super(name)
    end

    def setup_ports
      input :addr, width: 16
      input :data_in, width: 8
      input :rw
      input :cs

      output :data_out, width: 8
      output :handled       # 1 if address was handled by MMIO
    end

    def propagate
      addr = in_val(:addr) & 0xFFFF
      handled = 0
      data_out = 0

      @handlers.each do |range, handler|
        if range.include?(addr)
          handled = 1
          if in_val(:rw) == 0  # Write
            handler.call(:write, addr, in_val(:data_in))
          else  # Read
            data_out = handler.call(:read, addr, 0)
          end
          break
        end
      end

      out_set(:data_out, data_out)
      out_set(:handled, handled)
    end

    def add_handler(range, &block)
      @handlers[range] = block
    end
  end
end
