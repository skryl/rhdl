# Game Boy Top-Level Module
# Corresponds to: reference/rtl/gb.v
#
# Main Game Boy system integrating all subsystems:
# - SM83 CPU (Z80 variant)
# - PPU (Pixel Processing Unit)
# - APU (Audio Processing Unit)
# - Timer
# - Memory controllers
# - DMA engines
# - Serial link

require_relative '../../lib/rhdl'
require_relative '../../lib/rhdl/dsl/behavior'
require_relative '../../lib/rhdl/dsl/sequential'

module GameBoy
  class GB < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # Clock and reset
    input :reset
    input :clk_sys
    input :ce          # 4MHz clock enable
    input :ce_n        # 4MHz inverted clock enable
    input :ce_2x       # 8MHz clock enable (for GBC double speed)

    # Configuration
    input :joystick, width: 8
    input :isGBC              # Game Boy Color mode
    input :real_cgb_boot      # Real CGB boot ROM
    input :isSGB              # Super Game Boy mode
    input :extra_spr_en       # Extra sprites enable

    # Cartridge interface (up to 1MB ROM)
    output :ext_bus_addr, width: 15
    output :ext_bus_a15
    output :cart_rd
    output :cart_wr
    input :cart_do, width: 8
    output :cart_di, width: 8
    input :cart_oe

    # WRAM/Cart RAM chip select
    output :nCS

    # Boot ROM download interface
    input :cgb_boot_download
    input :dmg_boot_download
    input :sgb_boot_download
    input :ioctl_wr
    input :ioctl_addr, width: 25
    input :ioctl_dout, width: 16

    # Boot ROM features
    input :boot_gba_en
    input :fast_boot_en

    # Audio outputs
    output :audio_l, width: 16
    output :audio_r, width: 16
    input :audio_no_pops

    # Megaduck mode
    input :megaduck

    # LCD interface
    output :lcd_clkena
    output :lcd_data, width: 15
    output :lcd_data_gb, width: 2
    output :lcd_mode, width: 2
    output :lcd_on
    output :lcd_vsync

    # Joypad interface
    output :joy_p54, width: 2
    input :joy_din, width: 4

    # GBC specific outputs
    output :speed
    output :DMA_on

    # Game Genie
    input :gg_reset
    input :gg_en
    input :gg_code, width: 129
    output :gg_available

    # Serial port
    output :sc_int_clock2
    input :serial_clk_in
    output :serial_clk_out
    input :serial_data_in
    output :serial_data_out

    # Save states
    input :increaseSSHeaderCount
    input :cart_ram_size, width: 8
    input :save_state
    input :load_state
    input :savestate_number, width: 2
    output :sleep_savestate

    # External savestate interface
    output :SaveStateExt_Din, width: 64
    output :SaveStateExt_Adr, width: 10
    output :SaveStateExt_wren
    output :SaveStateExt_rst
    input :SaveStateExt_Dout, width: 64
    output :SaveStateExt_load

    # Cart RAM savestate interface
    output :Savestate_CRAMAddr, width: 20
    output :Savestate_CRAMRWrEn
    output :Savestate_CRAMWriteData, width: 8
    input :Savestate_CRAMReadData, width: 8

    # Save out interface
    output :SAVE_out_Din, width: 64
    input :SAVE_out_Dout, width: 64
    output :SAVE_out_Adr, width: 26
    output :SAVE_out_rnw
    output :SAVE_out_ena
    output :SAVE_out_be, width: 8
    input :SAVE_out_done

    # Rewind
    input :rewind_on
    input :rewind_active

    # Internal signals
    wire :cpu_addr, width: 16
    wire :cpu_do, width: 8
    wire :cpu_di, width: 8
    wire :cpu_wr_n
    wire :cpu_rd_n
    wire :cpu_iorq_n
    wire :cpu_m1_n
    wire :cpu_mreq_n
    wire :cpu_clken

    # Memory select signals
    wire :sel_timer
    wire :sel_video_reg
    wire :sel_video_oam
    wire :sel_joy
    wire :sel_sb
    wire :sel_sc
    wire :sel_rom
    wire :sel_cram
    wire :sel_vram
    wire :sel_ie
    wire :sel_if
    wire :sel_wram
    wire :sel_zpram
    wire :sel_audio
    wire :sel_ext_bus
    wire :sel_boot_rom

    # Register file
    wire :boot_rom_enabled
    wire :wram_bank, width: 3
    wire :vram_bank
    wire :if_r, width: 5
    wire :ie_r, width: 8
    wire :cpu_speed
    wire :prepare_switch

    # Interrupt signals
    wire :irq_n
    wire :irq_ack
    wire :irq_vec, width: 8
    wire :video_irq
    wire :vblank_irq
    wire :timer_irq
    wire :serial_irq

    # Data outputs from subsystems
    wire :joy_do, width: 8
    wire :sb_o, width: 8
    wire :timer_do, width: 8
    wire :video_do, width: 8
    wire :audio_do, width: 8
    wire :boot_do, width: 8
    wire :vram_do, width: 8
    wire :vram1_do, width: 8
    wire :zpram_do, width: 8
    wire :wram_do, width: 8
    wire :hdma_do, width: 8

    # OAM/VRAM access control
    wire :oam_cpu_allow
    wire :vram_cpu_allow

    # DMA signals
    wire :dma_addr, width: 16
    wire :dma_rd
    wire :hdma_rd
    wire :hdma_active
    wire :hdma_source_addr, width: 16
    wire :hdma_target_addr, width: 16

    # External bus signals
    wire :ext_bus_di, width: 8
    wire :ext_bus_rd
    wire :ext_bus_wr
    wire :ext_bus_wram_sel
    wire :ext_bus_cram_sel
    wire :ext_bus_rom_sel

    # Sub-component instances
    instance :cpu, SM83
    instance :timer_unit, Timer
    instance :video_unit, Video
    instance :audio_unit, Sound
    instance :hdma_unit, HDMA
    instance :link_unit, Link

    # Memory instances
    instance :vram0, DPRAM, addr_width: 13
    instance :vram1, DPRAM, addr_width: 13
    instance :wram, DPRAM, addr_width: 15
    instance :zpram, DPRAM, addr_width: 7

    # Clock distribution
    port :clk_sys => [[:cpu, :clk], [:timer_unit, :clk_sys], [:video_unit, :clk],
                      [:audio_unit, :clk], [:hdma_unit, :clk], [:link_unit, :clk_sys],
                      [:vram0, :clock_a], [:vram0, :clock_b],
                      [:vram1, :clock_a], [:vram1, :clock_b],
                      [:wram, :clock_a], [:wram, :clock_b],
                      [:zpram, :clock_a], [:zpram, :clock_b]]

    # Reset distribution
    port :reset => [:timer_unit, :reset]

    # CPU connections
    port [:cpu, :A] => :cpu_addr
    port [:cpu, :DO] => :cpu_do
    port :cpu_di => [:cpu, :DI]
    port [:cpu, :WR_n] => :cpu_wr_n
    port [:cpu, :RD_n] => :cpu_rd_n
    port [:cpu, :IORQ_n] => :cpu_iorq_n
    port [:cpu, :M1_n] => :cpu_m1_n
    port [:cpu, :MREQ_n] => :cpu_mreq_n
    port :cpu_clken => [:cpu, :CLKEN]
    port :irq_n => [:cpu, :INT_n]
    port :isGBC => [:cpu, :isGBC]

    # Timer connections
    port :sel_timer => [:timer_unit, :cpu_sel]
    port [:timer_unit, :irq] => :timer_irq
    port [:timer_unit, :cpu_do] => :timer_do

    # Video connections
    port [:video_unit, :irq] => :video_irq
    port [:video_unit, :vblank_irq] => :vblank_irq
    port [:video_unit, :cpu_do] => :video_do
    port [:video_unit, :lcd_on] => :lcd_on
    port [:video_unit, :lcd_clkena] => :lcd_clkena
    port [:video_unit, :lcd_data] => :lcd_data
    port [:video_unit, :lcd_data_gb] => :lcd_data_gb
    port [:video_unit, :mode] => :lcd_mode
    port [:video_unit, :lcd_vsync] => :lcd_vsync
    port [:video_unit, :oam_cpu_allow] => :oam_cpu_allow
    port [:video_unit, :vram_cpu_allow] => :vram_cpu_allow
    port [:video_unit, :dma_rd] => :dma_rd
    port [:video_unit, :dma_addr] => :dma_addr

    # Audio connections
    port [:audio_unit, :snd_left] => :audio_l
    port [:audio_unit, :snd_right] => :audio_r
    port [:audio_unit, :s1_readdata] => :audio_do

    # HDMA connections (GBC)
    port [:hdma_unit, :hdma_rd] => :hdma_rd
    port [:hdma_unit, :hdma_active] => :hdma_active
    port [:hdma_unit, :hdma_source_addr] => :hdma_source_addr
    port [:hdma_unit, :hdma_target_addr] => :hdma_target_addr
    port [:hdma_unit, :dout] => :hdma_do

    # Link port connections
    port [:link_unit, :sb] => :sb_o
    port [:link_unit, :serial_irq] => :serial_irq
    port [:link_unit, :serial_clk_out] => :serial_clk_out
    port [:link_unit, :serial_data_out] => :serial_data_out
    port :serial_clk_in => [:link_unit, :serial_clk_in]
    port :serial_data_in => [:link_unit, :serial_data_in]

    # Combinational logic for address decoding and data muxing
    behavior do
      # Memory select signals (directly from gb.v lines 156-172)
      sel_timer <= (cpu_addr[15..4] == lit(0xFF0, width: 12)) & (cpu_addr[3..2] == lit(1, width: 2))
      sel_video_reg <= (cpu_addr[15..4] == lit(0xFF4, width: 12)) |
                       (isGBC & (cpu_addr[15..4] == lit(0xFF6, width: 12)) &
                        (cpu_addr[3..0] >= lit(8, width: 4)) & (cpu_addr[3..0] <= lit(0xC, width: 4)))
      sel_video_oam <= cpu_addr[15..8] == lit(0xFE, width: 8)
      sel_joy <= cpu_addr == lit(0xFF00, width: 16)
      sel_sb <= cpu_addr == lit(0xFF01, width: 16)
      sel_sc <= cpu_addr == lit(0xFF02, width: 16)
      sel_rom <= ~cpu_addr[15]
      sel_cram <= cpu_addr[15..13] == lit(0b101, width: 3)
      sel_vram <= cpu_addr[15..13] == lit(0b100, width: 3)
      sel_ie <= cpu_addr == lit(0xFFFF, width: 16)
      sel_if <= cpu_addr == lit(0xFF0F, width: 16)
      sel_wram <= (cpu_addr[15..14] == lit(0b11, width: 2)) & ~(cpu_addr[13..9] == lit(0b11111, width: 5))
      sel_zpram <= (cpu_addr[15..7] == lit(0b111111111, width: 9)) & (cpu_addr != lit(0xFFFF, width: 16))
      sel_audio <= (cpu_addr[15..8] == lit(0xFF, width: 8)) &
                   ((cpu_addr[7..5] == lit(0b001, width: 3)) |
                    (cpu_addr[7..4] == lit(0b0001, width: 4)) |
                    (cpu_addr[7..0] == lit(0x76, width: 8)) |
                    (cpu_addr[7..0] == lit(0x77, width: 8)))
      sel_ext_bus <= sel_rom | sel_cram | sel_wram

      # CPU clock enable (HDMA can stop CPU on GBC)
      cpu_clken <= ~(isGBC & hdma_active & cpu_rd_n & cpu_wr_n) & ce

      # IRQ acknowledge
      irq_ack <= ~cpu_iorq_n & ~cpu_m1_n

      # IRQ vector priority
      irq_vec <= mux(if_r[0] & ie_r[0], lit(0x40, width: 8),
                 mux(if_r[1] & ie_r[1], lit(0x48, width: 8),
                 mux(if_r[2] & ie_r[2], lit(0x50, width: 8),
                 mux(if_r[3] & ie_r[3], lit(0x58, width: 8),
                 mux(if_r[4] & ie_r[4], lit(0x60, width: 8),
                     lit(0x00, width: 8))))))

      # IRQ active when any enabled interrupt is pending
      irq_n <= ~(ie_r[4..0] & if_r).reduce_or

      # CPU data input mux (priority-encoded)
      cpu_di <= mux(irq_ack, irq_vec,
                mux(sel_if, cat(lit(0b111, width: 3), if_r),
                mux(sel_timer, timer_do,
                mux(sel_video_reg, video_do,
                mux(sel_video_oam & oam_cpu_allow, video_do,
                mux(sel_audio, audio_do,
                mux(sel_boot_rom, boot_do,
                mux(isGBC & sel_wram, wram_do,
                mux(sel_ext_bus, ext_bus_di,
                mux(sel_vram & vram_cpu_allow, mux(isGBC & vram_bank, vram1_do, vram_do),
                mux(sel_zpram, zpram_do,
                mux(sel_ie, ie_r,
                    lit(0xFF, width: 8)))))))))))))

      # Joypad output
      joy_do <= cat(lit(0b11, width: 2), joy_p54, joy_din)

      # Speed output (GBC)
      speed <= cpu_speed

      # DMA on signal
      DMA_on <= (ext_bus_rom_sel | ext_bus_cram_sel) & (hdma_active | dma_rd)

      # Cart interface
      cart_di <= cpu_do
    end

    # Sequential logic for registers
    sequential clock: :clk_sys, reset: :reset do
      # Boot ROM enable (disabled by writing to FF50)
      boot_rom_enabled <= mux(boot_rom_enabled & ce &
                              (cpu_addr == lit(0xFF50, width: 16)) &
                              ~cpu_wr_n & cpu_do[0],
                              lit(0, width: 1),
                              mux(reset, lit(1, width: 1), boot_rom_enabled))
    end

  end
end
