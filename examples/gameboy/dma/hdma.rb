# Game Boy Color HDMA (H-Blank DMA)
# Corresponds to: reference/rtl/hdma.v
#
# HDMA transfers data from ROM/RAM to VRAM:
# - General Purpose DMA (GDMA): transfers all data at once
# - H-Blank DMA (HDMA): transfers 16 bytes per H-Blank
#
# Registers:
# - FF51: HDMA1 - Source High
# - FF52: HDMA2 - Source Low (lower 4 bits ignored)
# - FF53: HDMA3 - Destination High (only bits 0-4 used, ORed with 0x80)
# - FF54: HDMA4 - Destination Low (lower 4 bits ignored)
# - FF55: HDMA5 - Length/Mode/Start

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class HDMA < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :reset
    input :clk
    input :ce
    input :speed              # CPU speed (0=normal, 1=double)

    # CPU interface
    input :sel_reg            # HDMA registers selected (FF51-FF55)
    input :addr, width: 4     # Register address (1-5)
    input :wr                 # Write
    output :dout, width: 8    # Data out
    input :din, width: 8      # Data in

    # LCD mode (for H-Blank detection)
    input :lcd_mode, width: 2

    # DMA interface
    output :hdma_rd           # Reading from source
    output :hdma_active       # DMA active (CPU halted)
    output :hdma_source_addr, width: 16
    output :hdma_target_addr, width: 16

    # Internal registers
    wire :source_hi, width: 8     # FF51
    wire :source_lo, width: 8     # FF52
    wire :dest_hi, width: 8       # FF53
    wire :dest_lo, width: 8       # FF54
    wire :hdma5, width: 8         # FF55

    # DMA state
    wire :dma_active              # DMA in progress
    wire :hdma_mode               # 0=GDMA, 1=HDMA
    wire :remaining, width: 7     # Remaining blocks (0-127, each block = 16 bytes)
    wire :byte_counter, width: 4  # Current byte within block
    wire :hblank_transfer         # Currently transferring during H-Blank

    # Source and destination addresses
    wire :source, width: 16
    wire :dest, width: 16

    behavior do
      # Assemble addresses
      source <= cat(source_hi, source_lo[7..4], lit(0, width: 4))
      dest <= cat(lit(0b1, width: 1), dest_hi[4..0], dest_lo[7..4], lit(0, width: 4))

      # Current addresses (source + transferred bytes, dest in VRAM)
      hdma_source_addr <= source + cat(remaining, byte_counter)
      hdma_target_addr <= dest + cat(remaining, byte_counter)

      # Active when DMA in progress and (GDMA or in H-Blank)
      hdma_active <= dma_active & (~hdma_mode | (lcd_mode == lit(0, width: 2)))
      hdma_rd <= hdma_active

      # CPU read data
      dout <= case_select(addr, {
        1 => source_hi,
        2 => source_lo,
        3 => dest_hi,
        4 => dest_lo,
        5 => cat(~dma_active, remaining)  # Bit 7: 1=inactive, 0=active
      }, default: lit(0xFF, width: 8))
    end

    sequential clock: :clk, reset: :reset, reset_values: {
      source_hi: 0,
      source_lo: 0,
      dest_hi: 0,
      dest_lo: 0,
      hdma5: 0xFF,
      dma_active: 0,
      hdma_mode: 0,
      remaining: 0,
      byte_counter: 0,
      hblank_transfer: 0
    } do
      # Register writes
      source_hi <= mux(ce & sel_reg & wr & (addr == lit(1, width: 4)),
                       din, source_hi)
      source_lo <= mux(ce & sel_reg & wr & (addr == lit(2, width: 4)),
                       din, source_lo)
      dest_hi <= mux(ce & sel_reg & wr & (addr == lit(3, width: 4)),
                     din, dest_hi)
      dest_lo <= mux(ce & sel_reg & wr & (addr == lit(4, width: 4)),
                     din, dest_lo)

      # FF55 write starts or stops DMA
      hdma5 <= mux(ce & sel_reg & wr & (addr == lit(5, width: 4)),
                   din, hdma5)

      # Start DMA on FF55 write
      dma_active <= mux(ce & sel_reg & wr & (addr == lit(5, width: 4)) & ~dma_active,
                        lit(1, width: 1),
                        mux((remaining == lit(0, width: 7)) & (byte_counter == lit(15, width: 4)),
                            lit(0, width: 1),
                            dma_active))

      hdma_mode <= mux(ce & sel_reg & wr & (addr == lit(5, width: 4)) & ~dma_active,
                       din[7], hdma_mode)

      remaining <= mux(ce & sel_reg & wr & (addr == lit(5, width: 4)) & ~dma_active,
                       din[6..0], remaining)

      # Cancel HDMA by writing 0 to bit 7 while active
      dma_active <= mux(ce & sel_reg & wr & (addr == lit(5, width: 4)) &
                        dma_active & hdma_mode & ~din[7],
                        lit(0, width: 1), dma_active)

      # DMA progress
      byte_counter <= mux(ce & hdma_active,
                          byte_counter + lit(1, width: 4),
                          byte_counter)

      # Block complete
      remaining <= mux(ce & hdma_active & (byte_counter == lit(15, width: 4)),
                       remaining - lit(1, width: 7),
                       remaining)
      byte_counter <= mux(ce & hdma_active & (byte_counter == lit(15, width: 4)),
                          lit(0, width: 4), byte_counter)
    end
  end
end
