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

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

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
    input :is_gbc              # Game Boy Color mode
    input :real_cgb_boot      # Real CGB boot ROM
    input :is_sgb              # Super Game Boy mode
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
    input :boot_rom_do, width: 8  # Boot ROM data input (directly connected)

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
    output :dma_on

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
    output :save_state_ext_din, width: 64
    output :save_state_ext_adr, width: 10
    output :save_state_ext_wren
    output :save_state_ext_rst
    input :save_state_ext_dout, width: 64
    output :save_state_ext_load

    # Cart RAM savestate interface
    output :savestate_cram_addr, width: 20
    output :savestate_cram_wren
    output :savestate_cram_write_data, width: 8
    input :savestate_cram_read_data, width: 8

    # Save out interface
    output :save_out_din, width: 64
    input :save_out_dout, width: 64
    output :save_out_adr, width: 26
    output :save_out_rnw
    output :save_out_ena
    output :save_out_be, width: 8
    input :save_out_done

    # Rewind
    input :rewind_on
    input :rewind_active

    # Debug outputs (for Verilator simulation visibility)
    output :debug_cpu_pc, width: 16    # CPU Program counter
    output :debug_cpu_acc, width: 8    # CPU Accumulator
    output :debug_f, width: 8          # CPU Flags register
    output :debug_b, width: 8          # CPU B register
    output :debug_c, width: 8          # CPU C register
    output :debug_d, width: 8          # CPU D register
    output :debug_e, width: 8          # CPU E register
    output :debug_h, width: 8          # CPU H register
    output :debug_l, width: 8          # CPU L register
    output :debug_sp, width: 16        # CPU Stack pointer
    output :debug_ir, width: 8         # Current instruction register
    output :debug_save_alu             # ALU save signal
    output :debug_t_state, width: 3    # T-state counter
    output :debug_m_cycle, width: 3    # M-cycle counter
    output :debug_alu_flags, width: 8  # ALU flags output
    output :debug_clken                # Clock enable signal
    output :debug_alu_op, width: 4     # ALU operation
    output :debug_bus_a, width: 8      # ALU input A
    output :debug_bus_b, width: 8      # ALU input B
    output :debug_alu_result, width: 8 # ALU result
    output :debug_z_flag               # Direct zero flag for debugging
    output :debug_bus_a_zero           # Test if bus_a is zero
    output :debug_const_one            # Constant 1 for testing
    output :boot_rom_addr, width: 8    # Boot ROM address (for external boot ROM)

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
    wire :video_wr               # Video unit write enable (active high)
    wire :video_addr, width: 8   # Video unit address low byte
    wire :timer_wr               # Timer unit write enable (active high)
    wire :timer_addr, width: 2   # Timer unit address (0=DIV, 1=TIMA, 2=TMA, 3=TAC)
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
    wire :sel_ff50                     # Boot ROM disable register ($FF50)

    # Register file
    wire :boot_rom_enabled
    wire :wram_bank, width: 3
    wire :vram_bank
    wire :if_r, width: 5
    wire :ie_r, width: 8  # Updated in sequential block
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
    wire :joypad_irq

    # Joypad edge detection pipeline
    # joy_din_sampled: registered version of joy_din (1 cycle delay)
    # joy_din_prev: previous joy_din_sampled (2 cycles delay)
    # This ensures proper edge detection timing in simulation
    wire :joy_din_sampled, width: 4
    wire :joy_din_prev, width: 4

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
    wire :zpram_addr, width: 7
    wire :zpram_wren
    wire :wram_do, width: 8
    wire :wram_addr, width: 15     # WRAM address (15 bits for banking)
    wire :wram_wren                # WRAM write enable
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

    # VRAM interface signals
    wire :vram_addr_cpu, width: 13     # CPU VRAM address (0x8000-0x9FFF mapped to 0-0x1FFF)
    wire :vram_wren_cpu                # CPU VRAM write enable
    wire :vram_addr_ppu, width: 13     # PPU VRAM address
    wire :vram_data_ppu, width: 8      # PPU VRAM data read

    # Reset signal (active-low for CPU)
    wire :reset_n                      # Active-low reset for CPU (inverted from active-high reset input)

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

    # VRAM0 Port A (CPU side - read/write)
    port :vram_addr_cpu => [:vram0, :address_a]
    port :vram_wren_cpu => [:vram0, :wren_a]
    port :cpu_do => [:vram0, :data_a]
    port [:vram0, :q_a] => :vram_do

    # VRAM0 Port B (PPU side - read only)
    port :vram_addr_ppu => [:vram0, :address_b]
    port [:vram0, :q_b] => :vram_data_ppu

    # ZPRAM (High RAM $FF80-$FFFE) - CPU read/write
    port :zpram_addr => [:zpram, :address_a]
    port :zpram_wren => [:zpram, :wren_a]
    port :cpu_do => [:zpram, :data_a]
    port [:zpram, :q_a] => :zpram_do

    # WRAM (Work RAM $C000-$DFFF) - CPU read/write
    # Note: For DMG, WRAM access goes through external bus
    # For GBC, there's a separate WRAM bus with banking
    port :wram_addr => [:wram, :address_a]
    port :wram_wren => [:wram, :wren_a]
    port :cpu_do => [:wram, :data_a]
    port [:wram, :q_a] => :wram_do

    # CPU connections
    port [:cpu, :addr_bus] => :cpu_addr
    port [:cpu, :data_out] => :cpu_do
    port :cpu_di => [:cpu, :data_in]
    port [:cpu, :wr_n] => :cpu_wr_n
    port [:cpu, :rd_n] => :cpu_rd_n
    port [:cpu, :iorq_n] => :cpu_iorq_n
    port [:cpu, :m1_n] => :cpu_m1_n
    port [:cpu, :mreq_n] => :cpu_mreq_n
    port :cpu_clken => [:cpu, :clken]
    port :irq_n => [:cpu, :int_n]
    port :is_gbc => [:cpu, :is_gbc]
    port :reset_n => [:cpu, :reset_n]
    port [:cpu, :debug_pc] => :debug_cpu_pc
    port [:cpu, :debug_acc] => :debug_cpu_acc
    port [:cpu, :debug_f] => :debug_f
    port [:cpu, :debug_b] => :debug_b
    port [:cpu, :debug_c] => :debug_c
    port [:cpu, :debug_d] => :debug_d
    port [:cpu, :debug_e] => :debug_e
    port [:cpu, :debug_h] => :debug_h
    port [:cpu, :debug_l] => :debug_l
    port [:cpu, :debug_sp] => :debug_sp
    port [:cpu, :debug_ir] => :debug_ir
    port [:cpu, :debug_save_alu] => :debug_save_alu
    port [:cpu, :debug_t_state] => :debug_t_state
    port [:cpu, :debug_m_cycle] => :debug_m_cycle
    port [:cpu, :debug_alu_flags] => :debug_alu_flags
    port [:cpu, :debug_clken] => :debug_clken
    port [:cpu, :debug_alu_op] => :debug_alu_op
    port [:cpu, :debug_bus_a] => :debug_bus_a
    port [:cpu, :debug_bus_b] => :debug_bus_b
    port [:cpu, :debug_alu_result] => :debug_alu_result
    port [:cpu, :debug_z_flag] => :debug_z_flag
    port [:cpu, :debug_bus_a_zero] => :debug_bus_a_zero
    port [:cpu, :debug_const_one] => :debug_const_one

    # Timer connections
    port :ce => [:timer_unit, :ce]
    port :sel_timer => [:timer_unit, :cpu_sel]
    port :timer_addr => [:timer_unit, :cpu_addr]
    port :timer_wr => [:timer_unit, :cpu_wr]
    port :cpu_do => [:timer_unit, :cpu_di]
    port [:timer_unit, :irq] => :timer_irq
    port [:timer_unit, :cpu_do] => :timer_do

    # Video clock enables
    port :ce => [:video_unit, :ce]
    port :ce_n => [:video_unit, :ce_n]
    port :ce => [:video_unit, :ce_cpu]  # Use ce for ce_cpu in DMG mode
    port :is_gbc => [:video_unit, :is_gbc]
    port :is_gbc => [:video_unit, :isGBC_mode]  # Same as is_gbc for now
    port :reset => [:video_unit, :reset]
    port :megaduck => [:video_unit, :megaduck]
    port :boot_rom_enabled => [:video_unit, :boot_rom_en]
    port :extra_spr_en => [:video_unit, :extra_spr_en]

    # Video CPU interface
    port :sel_video_oam => [:video_unit, :cpu_sel_oam]
    port :sel_video_reg => [:video_unit, :cpu_sel_reg]
    port :video_addr => [:video_unit, :cpu_addr]     # Address low byte for register select
    port :video_wr => [:video_unit, :cpu_wr]         # Write enable (active high)
    port :cpu_do => [:video_unit, :cpu_di]           # Write data from CPU

    # Video VRAM interface (PPU reads tiles from VRAM)
    port [:video_unit, :vram_addr] => :vram_addr_ppu
    port :vram_data_ppu => [:video_unit, :vram_data]

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
      # Invert reset for CPU (active-low reset_n from active-high reset input)
      reset_n <= ~reset

      # Memory select signals (directly from gb.v lines 156-172)
      sel_timer <= (cpu_addr[15..4] == lit(0xFF0, width: 12)) & (cpu_addr[3..2] == lit(1, width: 2))
      sel_video_reg <= (cpu_addr[15..4] == lit(0xFF4, width: 12)) |
                       (is_gbc & (cpu_addr[15..4] == lit(0xFF6, width: 12)) &
                        (cpu_addr[3..0] >= lit(8, width: 4)) & (cpu_addr[3..0] <= lit(0xC, width: 4)))
      sel_video_oam <= (cpu_addr[15..8] == lit(0xFE, width: 8))

      # Video write interface - PPU needs low byte of address and write enable
      video_addr <= cpu_addr[7..0]
      video_wr <= sel_video_reg & ~cpu_mreq_n & ~cpu_wr_n

      # Timer write interface - Timer needs 2-bit address and write enable
      timer_addr <= cpu_addr[1..0]
      timer_wr <= ~cpu_wr_n

      sel_joy <= (cpu_addr == lit(0xFF00, width: 16))
      sel_sb <= (cpu_addr == lit(0xFF01, width: 16))
      sel_sc <= (cpu_addr == lit(0xFF02, width: 16))
      sel_rom <= ~cpu_addr[15]
      sel_cram <= (cpu_addr[15..13] == lit(0b101, width: 3))
      sel_vram <= (cpu_addr[15..13] == lit(0b100, width: 3))
      sel_ie <= (cpu_addr == lit(0xFFFF, width: 16))
      sel_if <= (cpu_addr == lit(0xFF0F, width: 16))
      sel_wram <= (cpu_addr[15..14] == lit(0b11, width: 2)) & ~(cpu_addr[13..9] == lit(0b11111, width: 5))
      sel_zpram <= (cpu_addr[15..7] == lit(0b111111111, width: 9)) & (cpu_addr != lit(0xFFFF, width: 16))
      sel_audio <= (cpu_addr[15..8] == lit(0xFF, width: 8)) &
                   ((cpu_addr[7..5] == lit(0b001, width: 3)) |
                    (cpu_addr[7..4] == lit(0b0001, width: 4)) |
                    (cpu_addr[7..0] == lit(0x76, width: 8)) |
                    (cpu_addr[7..0] == lit(0x77, width: 8)))
      sel_ext_bus <= sel_rom | sel_cram | sel_wram

      # Boot ROM disable register ($FF50) - SameBoy fast boot check reads this
      sel_ff50 <= (cpu_addr == lit(0xFF50, width: 16))

      # Boot ROM select (0x0000-0x00FF when boot_rom_enabled, DMG mode)
      # Reference: sel_boot_rom = boot_rom_enabled && (!boot_rom_addr[15:8] || sel_boot_rom_cgb) && ~megaduck
      sel_boot_rom <= boot_rom_enabled & (cpu_addr[15..8] == lit(0, width: 8)) & ~megaduck

      # Boot ROM address (lower 8 bits for DMG 256-byte boot ROM)
      boot_rom_addr <= cpu_addr[7..0]

      # Boot ROM data comes from external input (Verilator provides this)
      boot_do <= boot_rom_do

      # CPU clock enable (HDMA can stop CPU on GBC)
      cpu_clken <= ~(is_gbc & hdma_active & cpu_rd_n & cpu_wr_n) & ce

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
      irq_n <= ~reduce_or(ie_r[4..0] & if_r)

      # CPU data input mux (priority-encoded)
      cpu_di <= mux(irq_ack, irq_vec,
                mux(sel_if, cat(lit(0b111, width: 3), if_r),
                mux(sel_timer, timer_do,
                mux(sel_video_reg, video_do,
                mux(sel_video_oam & oam_cpu_allow, video_do,
                mux(sel_audio, audio_do,
                mux(sel_boot_rom, boot_do,
                mux(sel_wram, wram_do,   # WRAM data for both DMG and GBC
                mux(sel_ext_bus, ext_bus_di,
                mux(sel_vram & vram_cpu_allow, mux(is_gbc & vram_bank, vram1_do, vram_do),
                mux(sel_zpram, zpram_do,
                mux(sel_ie, ie_r,
                mux(sel_ff50, lit(0x00, width: 8),   # FF50 returns 0 (fast boot disabled)
                    lit(0xFF, width: 8))))))))))))))

      # Joypad output
      joy_do <= cat(lit(0b11, width: 2), joy_p54, joy_din)

      # Joypad interrupt: fires when any button transitions from released (1) to pressed (0)
      # This is a falling edge on joy_din_sampled bits
      # joy_din_prev was high (1), joy_din_sampled is now low (0) = button just pressed
      # Note: We use joy_din_sampled (registered) vs joy_din_prev for proper pipeline timing
      joy_falling_edge = joy_din_prev & ~joy_din_sampled
      joypad_irq <= reduce_or(joy_falling_edge)

      # Speed output (GBC)
      speed <= cpu_speed

      # DMA on signal
      dma_on <= (ext_bus_rom_sel | ext_bus_cram_sel) & (hdma_active | dma_rd)

      # Cart interface - directly expose CPU address and control signals
      ext_bus_addr <= cpu_addr[14..0]
      ext_bus_a15 <= cpu_addr[15]

      # Cart read when CPU is doing a memory read from ROM space
      # ROM space is when A15=0 (addresses 0x0000-0x7FFF)
      cart_rd <= sel_rom & ~cpu_mreq_n & ~cpu_rd_n
      cart_wr <= sel_rom & ~cpu_mreq_n & ~cpu_wr_n
      cart_di <= cpu_do

      # External bus data input comes from cartridge
      ext_bus_di <= cart_do

      # VRAM CPU interface
      # CPU addresses 0x8000-0x9FFF map to VRAM addresses 0x0000-0x1FFF
      vram_addr_cpu <= cpu_addr[12..0]
      vram_wren_cpu <= sel_vram & ~cpu_mreq_n & ~cpu_wr_n & vram_cpu_allow & ce

      # ZPRAM CPU interface
      # CPU addresses 0xFF80-0xFFFE map to ZPRAM addresses 0x00-0x7E (127 bytes)
      zpram_addr <= cpu_addr[6..0]
      zpram_wren <= sel_zpram & ~cpu_wr_n & ~cpu_mreq_n & ce

      # WRAM CPU interface
      # CPU addresses 0xC000-0xDFFF map to WRAM
      # For DMG: WRAM is accessed through ext_bus, but we still connect directly
      # For GBC: WRAM has banking (bank 0 at $C000-$CFFF, bank 1-7 at $D000-$DFFF)
      # Address bit 12 selects between bank 0 and banked area
      # wram_bank_eff: If wram_bank is 0, use bank 1 (per GB spec)
      wram_bank_eff = mux(wram_bank == lit(0, width: 3), lit(1, width: 3), wram_bank)

      # WRAM address: for $C000-$CFFF use bank 0, for $D000-$DFFF use wram_bank
      wram_addr_lo = cpu_addr[11..0]
      wram_addr_bank = mux(cpu_addr[12],
                           cat(wram_bank_eff, wram_addr_lo),  # $D000-$DFFF: banked
                           cat(lit(0, width: 3), wram_addr_lo)) # $C000-$CFFF: bank 0
      wram_addr <= wram_addr_bank

      # WRAM write enable (when sel_wram active and CPU writes)
      wram_wren <= sel_wram & ~cpu_wr_n & ~cpu_mreq_n & ce
    end

    # Sequential logic for registers
    # boot_rom_enabled: 1 to run boot ROM (initializes hardware properly)
    # joy_din_sampled/joy_din_prev: 0xF = all buttons released (active low)
    sequential clock: :clk_sys, reset: :reset, reset_values: { boot_rom_enabled: 1, if_r: 0, ie_r: 0, joy_din_sampled: 0xF, joy_din_prev: 0xF } do
      # Boot ROM enable (disabled by writing to FF50)
      # Disable boot ROM on any write to FF50 (MiSTer boot ROM writes 0, original writes non-zero)
      boot_rom_enabled <= mux(ce & (cpu_addr == lit(0xFF50, width: 16)) & ~cpu_wr_n,
                              lit(0, width: 1),
                              boot_rom_enabled)

      # Interrupt Enable register ($FFFF)
      # Bit 0: V-Blank, Bit 1: LCD STAT, Bit 2: Timer, Bit 3: Serial, Bit 4: Joypad
      # CPU writes to enable/disable interrupts
      ie_r <= mux(ce & sel_ie & ~cpu_wr_n,
                  cpu_do,
                  ie_r)

      # Interrupt Flag register ($FF0F)
      # Bit 0: V-Blank, Bit 1: LCD STAT, Bit 2: Timer, Bit 3: Serial, Bit 4: Joypad
      # Set by interrupt sources, cleared by CPU writing 1 to the bit OR automatically
      # when the interrupt is acknowledged by the CPU.
      #
      # Start with current value
      if_r_new = if_r

      # Set bits when interrupts fire (on rising edge via pulse signals from sources)
      if_r_new = mux(vblank_irq, if_r_new | lit(0x01, width: 5), if_r_new)
      if_r_new = mux(video_irq, if_r_new | lit(0x02, width: 5), if_r_new)
      if_r_new = mux(timer_irq, if_r_new | lit(0x04, width: 5), if_r_new)
      if_r_new = mux(serial_irq, if_r_new | lit(0x08, width: 5), if_r_new)
      if_r_new = mux(joypad_irq, if_r_new | lit(0x10, width: 5), if_r_new)

      # CPU can clear interrupt flags by writing to $FF0F
      # Writing 1 to a bit clears it (standard interrupt acknowledge)
      if_r_new = mux(ce & sel_if & ~cpu_wr_n,
                     if_r_new & ~cpu_do[4..0],
                     if_r_new)

      # Auto-clear IF bit when interrupt is acknowledged by CPU
      # The bit to clear corresponds to the highest-priority pending interrupt
      # Priority: VBlank > LCD STAT > Timer > Serial > Joypad
      irq_clear_mask = mux(if_r[0] & ie_r[0], lit(0x01, width: 5),
                       mux(if_r[1] & ie_r[1], lit(0x02, width: 5),
                       mux(if_r[2] & ie_r[2], lit(0x04, width: 5),
                       mux(if_r[3] & ie_r[3], lit(0x08, width: 5),
                       mux(if_r[4] & ie_r[4], lit(0x10, width: 5),
                           lit(0x00, width: 5))))))

      if_r_new = mux(irq_ack,
                     if_r_new & ~irq_clear_mask,
                     if_r_new)

      if_r <= if_r_new

      # Joypad edge detection pipeline registers
      # joy_din_sampled captures the current joy_din input (1 cycle delay)
      # joy_din_prev captures the previous joy_din_sampled (2 cycles delay from input)
      # Edge detection in behavior block compares joy_din_prev with joy_din_sampled
      # Note: Order matters in simulation - update joy_din_prev first (from old joy_din_sampled)
      joy_din_prev <= mux(ce, joy_din_sampled, joy_din_prev)
      joy_din_sampled <= mux(ce, joy_din, joy_din_sampled)
    end

  end
end
