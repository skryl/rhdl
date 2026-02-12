# Minimal VirtIO block device (MMIO) for RISC-V simulation.
# Exposes the register subset xv6 expects and processes queue 0 requests.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'

module RHDL
  module Examples
    module RISCV
      class VirtioBlk < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    BASE_ADDR = 0x1000_1000

    MAGIC_VALUE_ADDR = BASE_ADDR + 0x000
    VERSION_ADDR = BASE_ADDR + 0x004
    DEVICE_ID_ADDR = BASE_ADDR + 0x008
    VENDOR_ID_ADDR = BASE_ADDR + 0x00C
    DEVICE_FEATURES_ADDR = BASE_ADDR + 0x010
    DEVICE_FEATURES_SEL_ADDR = BASE_ADDR + 0x014
    DRIVER_FEATURES_ADDR = BASE_ADDR + 0x020
    DRIVER_FEATURES_SEL_ADDR = BASE_ADDR + 0x024
    GUEST_PAGE_SIZE_ADDR = BASE_ADDR + 0x028
    QUEUE_SEL_ADDR = BASE_ADDR + 0x030
    QUEUE_NUM_MAX_ADDR = BASE_ADDR + 0x034
    QUEUE_NUM_ADDR = BASE_ADDR + 0x038
    QUEUE_ALIGN_ADDR = BASE_ADDR + 0x03C
    QUEUE_PFN_ADDR = BASE_ADDR + 0x040
    QUEUE_READY_ADDR = BASE_ADDR + 0x044
    QUEUE_NOTIFY_ADDR = BASE_ADDR + 0x050
    INTERRUPT_STATUS_ADDR = BASE_ADDR + 0x060
    INTERRUPT_ACK_ADDR = BASE_ADDR + 0x064
    STATUS_ADDR = BASE_ADDR + 0x070
    QUEUE_DESC_LOW_ADDR = BASE_ADDR + 0x080
    QUEUE_DESC_HIGH_ADDR = BASE_ADDR + 0x084
    QUEUE_DRIVER_LOW_ADDR = BASE_ADDR + 0x090
    QUEUE_DRIVER_HIGH_ADDR = BASE_ADDR + 0x094
    QUEUE_DEVICE_LOW_ADDR = BASE_ADDR + 0x0A0
    QUEUE_DEVICE_HIGH_ADDR = BASE_ADDR + 0x0A4
    CONFIG_GENERATION_ADDR = BASE_ADDR + 0x0FC
    CONFIG_CAPACITY_LOW_ADDR = BASE_ADDR + 0x100
    CONFIG_CAPACITY_HIGH_ADDR = BASE_ADDR + 0x104

    VIRTIO_MAGIC = 0x7472_6976
    VIRTIO_VENDOR_ID = 0x554D_4551

    STATUS_ACKNOWLEDGE = 0x01
    STATUS_DRIVER = 0x02
    STATUS_DRIVER_OK = 0x04
    STATUS_FEATURES_OK = 0x08
    STATUS_FAILED = 0x80

    INTERRUPT_USED_BUFFER = 0x01

    DESC_F_NEXT = 0x0001
    DESC_F_WRITE = 0x0002

    REQ_T_IN = 0
    REQ_T_OUT = 1

    SECTOR_BYTES = 512
    QUEUE_NUM_MAX = 8
    DEFAULT_DISK_BYTES = 8 * 1024 * 1024

    input :clk
    input :rst

    # MMIO access port.
    input :addr, width: 32
    input :write_data, width: 32
    input :mem_read
    input :mem_write
    input :funct3, width: 3

    output :read_data, width: 32
    output :irq

    def initialize(name = nil, disk_size: DEFAULT_DISK_BYTES, queue_num_max: QUEUE_NUM_MAX)
      super(name)
      @disk = Array.new(disk_size, 0)
      @queue_num_max = queue_num_max
      reset_state!
    end

    def load_disk_bytes(bytes, offset: 0)
      base = offset & 0xFFFF_FFFF
      bytes.each_with_index do |byte, idx|
        pos = base + idx
        break if pos >= @disk.length

        @disk[pos] = byte & 0xFF
      end
    end

    def read_disk_byte(offset)
      pos = offset & 0xFFFF_FFFF
      pos < @disk.length ? (@disk[pos] & 0xFF) : 0
    end

    # Process pending queue notifications against the provided system memory.
    # Returns true when at least one request was completed.
    def service_queues!(mem)
      return false unless @notify_pending == 1

      @notify_pending = 0
      return false unless queue_operational?

      processed = process_available!(mem)
      out_set(:irq, irq_asserted? ? 1 : 0)
      processed
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      @prev_clk ||= 0

      addr = in_val(:addr) & 0xFFFF_FFFF
      write_data = in_val(:write_data) & 0xFFFF_FFFF
      mem_read = in_val(:mem_read)
      mem_write = in_val(:mem_write)
      funct3 = in_val(:funct3)

      if rst == 1
        reset_state!
        out_set(:read_data, 0)
        out_set(:irq, 0)
        @prev_clk = clk
        return
      end

      word_access = funct3 == Funct3::WORD

      if @prev_clk == 0 && clk == 1 && mem_write == 1 && word_access
        write_register(addr, write_data)
      end
      @prev_clk = clk

      if mem_read == 1 && word_access
        out_set(:read_data, read_register(addr))
      else
        out_set(:read_data, 0)
      end
      out_set(:irq, irq_asserted? ? 1 : 0)
    end

    private

    def reset_state!
      @device_features_sel = 0
      @driver_features_sel = 0
      @driver_features_0 = 0
      @driver_features_1 = 0
      @guest_page_size = 0
      @queue_sel = 0
      @queue_num = 0
      @queue_ready = 0
      @queue_desc = 0
      @queue_driver = 0
      @queue_device = 0
      @queue_pfn = 0
      @queue_align = 0
      @status = 0
      @interrupt_status = 0
      @notify_pending = 0
      @last_avail_idx = 0
    end

    def queue_operational?
      @queue_sel == 0 &&
        @queue_ready == 1 &&
        @queue_num > 0 &&
        (@status & STATUS_DRIVER_OK) != 0
    end

    def irq_asserted?
      (@interrupt_status & 0x3) != 0
    end

    def capacity_sectors
      @disk.length / SECTOR_BYTES
    end

    def read_register(addr)
      case addr
      when MAGIC_VALUE_ADDR then VIRTIO_MAGIC
      when VERSION_ADDR then 2
      when DEVICE_ID_ADDR then 2
      when VENDOR_ID_ADDR then VIRTIO_VENDOR_ID
      when DEVICE_FEATURES_ADDR then device_features_for_sel(@device_features_sel)
      when DEVICE_FEATURES_SEL_ADDR then @device_features_sel
      when DRIVER_FEATURES_ADDR then @driver_features_sel == 0 ? @driver_features_0 : @driver_features_1
      when DRIVER_FEATURES_SEL_ADDR then @driver_features_sel
      when GUEST_PAGE_SIZE_ADDR then @guest_page_size
      when QUEUE_SEL_ADDR then @queue_sel
      when QUEUE_NUM_MAX_ADDR then @queue_sel == 0 ? @queue_num_max : 0
      when QUEUE_NUM_ADDR then @queue_sel == 0 ? @queue_num : 0
      when QUEUE_ALIGN_ADDR then @queue_align
      when QUEUE_PFN_ADDR then @queue_pfn
      when QUEUE_READY_ADDR then @queue_sel == 0 ? @queue_ready : 0
      when INTERRUPT_STATUS_ADDR then @interrupt_status & 0x3
      when STATUS_ADDR then @status & 0xFF
      when QUEUE_DESC_LOW_ADDR then @queue_desc & 0xFFFF_FFFF
      when QUEUE_DESC_HIGH_ADDR then (@queue_desc >> 32) & 0xFFFF_FFFF
      when QUEUE_DRIVER_LOW_ADDR then @queue_driver & 0xFFFF_FFFF
      when QUEUE_DRIVER_HIGH_ADDR then (@queue_driver >> 32) & 0xFFFF_FFFF
      when QUEUE_DEVICE_LOW_ADDR then @queue_device & 0xFFFF_FFFF
      when QUEUE_DEVICE_HIGH_ADDR then (@queue_device >> 32) & 0xFFFF_FFFF
      when CONFIG_GENERATION_ADDR then 0
      when CONFIG_CAPACITY_LOW_ADDR then capacity_sectors & 0xFFFF_FFFF
      when CONFIG_CAPACITY_HIGH_ADDR then (capacity_sectors >> 32) & 0xFFFF_FFFF
      else
        0
      end
    end

    def write_register(addr, value)
      case addr
      when DEVICE_FEATURES_SEL_ADDR
        @device_features_sel = value & 0x1
      when DRIVER_FEATURES_SEL_ADDR
        @driver_features_sel = value & 0x1
      when DRIVER_FEATURES_ADDR
        if @driver_features_sel == 0
          @driver_features_0 = value
        else
          @driver_features_1 = value
        end
      when GUEST_PAGE_SIZE_ADDR
        @guest_page_size = value
      when QUEUE_SEL_ADDR
        @queue_sel = value & 0xFFFF_FFFF
        @last_avail_idx = 0 if @queue_sel != 0
      when QUEUE_NUM_ADDR
        num = value & 0xFFFF
        @queue_num = if @queue_sel == 0
                       [[num, 1].max, @queue_num_max].min
                     else
                       0
                     end
      when QUEUE_ALIGN_ADDR
        @queue_align = value
      when QUEUE_PFN_ADDR
        @queue_pfn = value
      when QUEUE_READY_ADDR
        @queue_ready = @queue_sel == 0 ? (value & 0x1) : 0
        @last_avail_idx = 0 if @queue_ready == 0
      when QUEUE_NOTIFY_ADDR
        @notify_pending = 1 if (value & 0xFFFF) == 0
      when INTERRUPT_ACK_ADDR
        @interrupt_status &= ~(value & 0x3)
      when STATUS_ADDR
        if (value & 0xFF) == 0
          reset_state!
        else
          @status = value & 0xFF
        end
      when QUEUE_DESC_LOW_ADDR
        @queue_desc = (@queue_desc & 0xFFFF_FFFF_0000_0000) | (value & 0xFFFF_FFFF)
      when QUEUE_DESC_HIGH_ADDR
        @queue_desc = ((value & 0xFFFF_FFFF) << 32) | (@queue_desc & 0xFFFF_FFFF)
      when QUEUE_DRIVER_LOW_ADDR
        @queue_driver = (@queue_driver & 0xFFFF_FFFF_0000_0000) | (value & 0xFFFF_FFFF)
      when QUEUE_DRIVER_HIGH_ADDR
        @queue_driver = ((value & 0xFFFF_FFFF) << 32) | (@queue_driver & 0xFFFF_FFFF)
      when QUEUE_DEVICE_LOW_ADDR
        @queue_device = (@queue_device & 0xFFFF_FFFF_0000_0000) | (value & 0xFFFF_FFFF)
      when QUEUE_DEVICE_HIGH_ADDR
        @queue_device = ((value & 0xFFFF_FFFF) << 32) | (@queue_device & 0xFFFF_FFFF)
      end
    end

    def device_features_for_sel(_sel)
      # xv6 clears feature bits it does not support and accepts the rest.
      # Advertising zero feature bits is sufficient for boot/runtime.
      0
    end

    def process_available!(mem)
      processed_any = false
      guard = 0
      max_guard = [@queue_num * 4, 16].max

      avail_idx = mem_read_u16(mem, @queue_driver + 2)
      while @last_avail_idx != avail_idx && guard < max_guard
        ring_slot = @last_avail_idx % @queue_num
        head_idx = mem_read_u16(mem, @queue_driver + 4 + (ring_slot * 2))
        process_one_request!(mem, head_idx)
        @last_avail_idx = (@last_avail_idx + 1) & 0xFFFF
        processed_any = true
        guard += 1
        avail_idx = mem_read_u16(mem, @queue_driver + 2)
      end

      processed_any
    end

    def process_one_request!(mem, head_idx)
      desc0 = read_desc(mem, head_idx)
      return unless desc0
      return unless (desc0[:flags] & DESC_F_NEXT) != 0

      desc1 = read_desc(mem, desc0[:next])
      return unless desc1
      return unless (desc1[:flags] & DESC_F_NEXT) != 0

      desc2 = read_desc(mem, desc1[:next])
      return unless desc2

      req_addr = desc0[:addr]
      req_type = mem_read_u32(mem, req_addr + 0)
      sector = mem_read_u64(mem, req_addr + 8)

      success = transfer_data!(mem, req_type, sector, desc1[:addr], desc1[:len])
      mem_write_u8(mem, desc2[:addr], success ? 0 : 1)
      push_used!(mem, head_idx, success ? desc1[:len] : 0)
      @interrupt_status |= INTERRUPT_USED_BUFFER
    end

    def transfer_data!(mem, req_type, sector, data_addr, data_len)
      disk_offset = (sector & 0xFFFF_FFFF_FFFF_FFFF) * SECTOR_BYTES
      return false if disk_offset >= @disk.length

      len = data_len & 0xFFFF_FFFF

      case req_type
      when REQ_T_IN
        len.times do |idx|
          src = disk_offset + idx
          byte = src < @disk.length ? @disk[src] : 0
          mem_write_u8(mem, data_addr + idx, byte)
        end
        true
      when REQ_T_OUT
        len.times do |idx|
          dst = disk_offset + idx
          break if dst >= @disk.length

          @disk[dst] = mem_read_u8(mem, data_addr + idx)
        end
        true
      else
        false
      end
    end

    def push_used!(mem, head_idx, used_len)
      used_idx = mem_read_u16(mem, @queue_device + 2)
      slot = used_idx % @queue_num
      elem_addr = @queue_device + 4 + (slot * 8)
      mem_write_u32(mem, elem_addr + 0, head_idx & 0xFFFF_FFFF)
      mem_write_u32(mem, elem_addr + 4, used_len & 0xFFFF_FFFF)
      mem_write_u16(mem, @queue_device + 2, (used_idx + 1) & 0xFFFF)
    end

    def read_desc(mem, desc_idx)
      idx = desc_idx & 0xFFFF
      return nil if @queue_num <= 0 || idx >= @queue_num

      base = @queue_desc + (idx * 16)
      {
        addr: mem_read_u64(mem, base + 0),
        len: mem_read_u32(mem, base + 8),
        flags: mem_read_u16(mem, base + 12),
        next: mem_read_u16(mem, base + 14)
      }
    end

    def mem_read_u8(mem, addr)
      mem.read_byte(addr & 0xFFFF_FFFF) & 0xFF
    end

    def mem_write_u8(mem, addr, value)
      mem.write_byte(addr & 0xFFFF_FFFF, value & 0xFF)
    end

    def mem_read_u16(mem, addr)
      lo = mem_read_u8(mem, addr)
      hi = mem_read_u8(mem, addr + 1)
      (hi << 8) | lo
    end

    def mem_write_u16(mem, addr, value)
      mem_write_u8(mem, addr, value & 0xFF)
      mem_write_u8(mem, addr + 1, (value >> 8) & 0xFF)
    end

    def mem_read_u32(mem, addr)
      mem.read_word(addr & 0xFFFF_FFFF) & 0xFFFF_FFFF
    end

    def mem_write_u32(mem, addr, value)
      mem.write_word(addr & 0xFFFF_FFFF, value & 0xFFFF_FFFF)
    end

    def mem_read_u64(mem, addr)
      lo = mem_read_u32(mem, addr)
      hi = mem_read_u32(mem, addr + 4)
      ((hi << 32) | lo) & 0xFFFF_FFFF_FFFF_FFFF
    end

      end
    end
  end
end
