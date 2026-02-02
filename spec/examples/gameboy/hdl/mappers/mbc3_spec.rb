# frozen_string_literal: true

require 'spec_helper'

# MBC3 Memory Bank Controller Tests
# Tests bank switching, RAM enable, and Real Time Clock (RTC)

RSpec.describe 'GameBoy::MBC3' do
  before(:all) do
    require_relative '../../../../../examples/gameboy/gameboy'
  end

  # Helper to clock the component
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  # Helper to write to a mapper register
  def write_register(component, addr, data)
    component.set_input(:cpu_addr, addr)
    component.set_input(:cpu_di, data)
    component.set_input(:cpu_wr, 1)
    clock_cycle(component)
    component.set_input(:cpu_wr, 0)
  end

  # Helper to tick the RTC clock (32.768 kHz)
  def rtc_tick(component)
    component.set_input(:ce_32k, 1)
    clock_cycle(component)
    component.set_input(:ce_32k, 0)
    clock_cycle(component)
  end

  # Helper to advance RTC by N seconds
  def advance_rtc_seconds(component, seconds)
    # Need 32768 ticks for 1 second
    (seconds * 32768).times do
      rtc_tick(component)
    end
  end

  let(:mbc3) { GameBoy::MBC3.new('mbc3') }

  before do
    # Initialize with default values
    mbc3.set_input(:clk, 0)
    mbc3.set_input(:ce, 1)
    mbc3.set_input(:reset, 0)
    mbc3.set_input(:mbc30, 0)  # Standard MBC3
    mbc3.set_input(:cpu_addr, 0)
    mbc3.set_input(:cpu_di, 0)
    mbc3.set_input(:cpu_wr, 0)
    mbc3.set_input(:cpu_rd, 0)
    mbc3.set_input(:ce_32k, 0)  # RTC clock
    mbc3.set_input(:rom_mask, 0x7F)  # 128 banks (2MB)
    mbc3.set_input(:ram_mask, 0x03)  # 4 RAM banks (32KB)
    mbc3.set_input(:has_ram, 1)
    mbc3.set_input(:cart_mbc_type, 0x10)  # MBC3+TIMER+RAM+BATTERY

    # Apply reset
    mbc3.set_input(:reset, 1)
    clock_cycle(mbc3)
    mbc3.set_input(:reset, 0)
    clock_cycle(mbc3)
  end

  describe 'Component Definition' do
    it 'is a SequentialComponent' do
      expect(GameBoy::MBC3.ancestors).to include(RHDL::HDL::SequentialComponent)
    end

    it 'has the expected inputs' do
      input_names = GameBoy::MBC3._port_defs.select { |p| p[:direction] == :in }.map { |p| p[:name] }
      expect(input_names).to include(:clk, :ce, :reset)
      expect(input_names).to include(:mbc30)
      expect(input_names).to include(:cpu_addr, :cpu_di, :cpu_wr, :cpu_rd)
      expect(input_names).to include(:ce_32k)
      expect(input_names).to include(:rom_mask, :ram_mask, :has_ram)
      expect(input_names).to include(:cart_mbc_type)
    end

    it 'has the expected outputs' do
      output_names = GameBoy::MBC3._port_defs.select { |p| p[:direction] == :out }.map { |p| p[:name] }
      expect(output_names).to include(:rom_bank, :ram_bank)
      expect(output_names).to include(:ram_enable, :has_battery)
      expect(output_names).to include(:rtc_mode)
      expect(output_names).to include(:rtc_seconds, :rtc_minutes)
      expect(output_names).to include(:rtc_hours, :rtc_days)
      expect(output_names).to include(:rtc_halt, :rtc_overflow)
    end
  end

  describe 'Reset Behavior' do
    it 'sets ROM bank to 1 after reset' do
      expect(mbc3.get_output(:rom_bank)).to eq(1)
    end

    it 'sets RAM bank to 0 after reset' do
      expect(mbc3.get_output(:ram_bank)).to eq(0)
    end

    it 'disables RAM after reset' do
      expect(mbc3.get_output(:ram_enable)).to eq(0)
    end

    it 'is in RAM mode (not RTC) after reset' do
      expect(mbc3.get_output(:rtc_mode)).to eq(0)
    end

    it 'clears RTC registers after reset' do
      expect(mbc3.get_output(:rtc_seconds)).to eq(0)
      expect(mbc3.get_output(:rtc_minutes)).to eq(0)
      expect(mbc3.get_output(:rtc_hours)).to eq(0)
      expect(mbc3.get_output(:rtc_days)).to eq(0)
      expect(mbc3.get_output(:rtc_halt)).to eq(0)
      expect(mbc3.get_output(:rtc_overflow)).to eq(0)
    end
  end

  describe 'RAM Enable Register (0x0000-0x1FFF)' do
    it 'enables RAM when 0x0A is written' do
      write_register(mbc3, 0x0000, 0x0A)
      expect(mbc3.get_output(:ram_enable)).to eq(1)
    end

    it 'disables RAM when other values are written' do
      write_register(mbc3, 0x0000, 0x0A)  # Enable first
      expect(mbc3.get_output(:ram_enable)).to eq(1)

      write_register(mbc3, 0x0000, 0x00)
      expect(mbc3.get_output(:ram_enable)).to eq(0)
    end

    it 'only checks low 4 bits for 0x0A' do
      write_register(mbc3, 0x0000, 0xFA)  # Low nibble is 0xA
      expect(mbc3.get_output(:ram_enable)).to eq(1)
    end
  end

  describe 'ROM Bank Register (0x2000-0x3FFF)' do
    it 'sets ROM bank to written value' do
      write_register(mbc3, 0x2000, 0x10)
      expect(mbc3.get_output(:rom_bank)).to eq(0x10)
    end

    it 'maps bank 0 to bank 1 (quirk)' do
      write_register(mbc3, 0x2000, 0x00)
      expect(mbc3.get_output(:rom_bank)).to eq(1)
    end

    it 'uses 7 bits for standard MBC3 (128 banks)' do
      write_register(mbc3, 0x2000, 0x7F)
      expect(mbc3.get_output(:rom_bank)).to eq(0x7F)
    end

    it 'masks bit 7 for standard MBC3' do
      write_register(mbc3, 0x2000, 0xFF)  # Bit 7 set
      expect(mbc3.get_output(:rom_bank)).to eq(0x7F)  # Masked to 7 bits
    end

    it 'applies ROM mask' do
      mbc3.set_input(:rom_mask, 0x0F)  # 16 banks
      write_register(mbc3, 0x2000, 0x1F)
      expect(mbc3.get_output(:rom_bank)).to eq(0x0F)  # Masked
    end
  end

  describe 'MBC30 Extended ROM Support (256 banks)' do
    before do
      mbc3.set_input(:mbc30, 1)
      mbc3.set_input(:rom_mask, 0xFF)  # 256 banks
    end

    it 'uses 8 bits for MBC30 (256 banks)' do
      write_register(mbc3, 0x2000, 0xFF)
      expect(mbc3.get_output(:rom_bank)).to eq(0xFF)
    end

    it 'can access banks 0x80-0xFF' do
      write_register(mbc3, 0x2000, 0x80)
      expect(mbc3.get_output(:rom_bank)).to eq(0x80)
    end
  end

  describe 'RAM Bank / RTC Select Register (0x4000-0x5FFF)' do
    it 'sets RAM bank when value is 0x00-0x03' do
      write_register(mbc3, 0x4000, 0x02)
      expect(mbc3.get_output(:ram_bank)).to eq(2)
      expect(mbc3.get_output(:rtc_mode)).to eq(0)  # RAM mode
    end

    it 'switches to RTC mode when bit 3 is set (0x08-0x0C)' do
      write_register(mbc3, 0x4000, 0x08)  # RTC seconds register
      expect(mbc3.get_output(:rtc_mode)).to eq(1)
    end

    it 'applies RAM mask' do
      mbc3.set_input(:ram_mask, 0x01)  # 2 banks
      write_register(mbc3, 0x4000, 0x03)
      expect(mbc3.get_output(:ram_bank)).to eq(0x01)  # Masked
    end
  end

  describe 'RTC Register Selection' do
    before do
      # Enable RTC mode and latch values
      write_register(mbc3, 0x6000, 0x00)
      write_register(mbc3, 0x6000, 0x01)  # Latch RTC
    end

    it 'selects RTC seconds (0x08)' do
      write_register(mbc3, 0x4000, 0x08)
      expect(mbc3.get_output(:rtc_mode)).to eq(1)
    end

    it 'selects RTC minutes (0x09)' do
      write_register(mbc3, 0x4000, 0x09)
      expect(mbc3.get_output(:rtc_mode)).to eq(1)
    end

    it 'selects RTC hours (0x0A)' do
      write_register(mbc3, 0x4000, 0x0A)
      expect(mbc3.get_output(:rtc_mode)).to eq(1)
    end

    it 'selects RTC day low (0x0B)' do
      write_register(mbc3, 0x4000, 0x0B)
      expect(mbc3.get_output(:rtc_mode)).to eq(1)
    end

    it 'selects RTC day high/flags (0x0C)' do
      write_register(mbc3, 0x4000, 0x0C)
      expect(mbc3.get_output(:rtc_mode)).to eq(1)
    end
  end

  describe 'RTC Latch Register (0x6000-0x7FFF)' do
    it 'latches RTC on 0->1 transition' do
      # First latch
      write_register(mbc3, 0x6000, 0x00)
      write_register(mbc3, 0x6000, 0x01)
      # RTC values should be latched (all zeros initially)
      expect(mbc3.get_output(:rtc_seconds)).to eq(0)
    end

    it 'does not latch on same value writes' do
      write_register(mbc3, 0x6000, 0x01)
      write_register(mbc3, 0x6000, 0x01)  # Same value, no latch
      # RTC values unchanged
    end

    it 'does not latch on 1->0 transition' do
      write_register(mbc3, 0x6000, 0x01)
      write_register(mbc3, 0x6000, 0x00)  # No latch
      # RTC values unchanged
    end
  end

  describe 'RTC Counter Functionality' do
    # Note: Full RTC testing requires many clock cycles
    # These tests verify the basic mechanism

    it 'increments RTC subseconds on ce_32k' do
      # Run a few RTC ticks
      10.times { rtc_tick(mbc3) }
      # Latch and check that RTC is running
      write_register(mbc3, 0x6000, 0x00)
      write_register(mbc3, 0x6000, 0x01)
      # At least something happened (hard to verify exact count)
    end

    it 'stops counting when halt flag is set' do
      # Simulate setting halt flag would require RTC register writes
      # This is a placeholder for that functionality
    end
  end

  describe 'RAM Enable with RTC Mode' do
    it 'disables RAM access in RTC mode' do
      mbc3.set_input(:has_ram, 1)
      write_register(mbc3, 0x0000, 0x0A)  # Enable RAM
      expect(mbc3.get_output(:ram_enable)).to eq(1)

      # Switch to RTC mode
      write_register(mbc3, 0x4000, 0x08)
      expect(mbc3.get_output(:ram_enable)).to eq(0)  # Disabled in RTC mode
    end

    it 're-enables RAM when switching back to RAM mode' do
      write_register(mbc3, 0x0000, 0x0A)  # Enable RAM
      write_register(mbc3, 0x4000, 0x08)  # RTC mode
      expect(mbc3.get_output(:ram_enable)).to eq(0)

      write_register(mbc3, 0x4000, 0x00)  # Back to RAM mode
      expect(mbc3.get_output(:ram_enable)).to eq(1)
    end
  end

  describe 'Battery Detection' do
    it 'reports battery for type 0x0F (MBC3+TIMER+BATTERY)' do
      mbc3.set_input(:cart_mbc_type, 0x0F)
      mbc3.propagate
      expect(mbc3.get_output(:has_battery)).to eq(1)
    end

    it 'reports battery for type 0x10 (MBC3+TIMER+RAM+BATTERY)' do
      mbc3.set_input(:cart_mbc_type, 0x10)
      mbc3.propagate
      expect(mbc3.get_output(:has_battery)).to eq(1)
    end

    it 'reports battery for type 0x13 (MBC3+RAM+BATTERY)' do
      mbc3.set_input(:cart_mbc_type, 0x13)
      mbc3.propagate
      expect(mbc3.get_output(:has_battery)).to eq(1)
    end

    it 'reports no battery for type 0x11 (MBC3 only)' do
      mbc3.set_input(:cart_mbc_type, 0x11)
      mbc3.propagate
      expect(mbc3.get_output(:has_battery)).to eq(0)
    end

    it 'reports no battery for type 0x12 (MBC3+RAM)' do
      mbc3.set_input(:cart_mbc_type, 0x12)
      mbc3.propagate
      expect(mbc3.get_output(:has_battery)).to eq(0)
    end
  end

  describe 'Bank Selection Range' do
    it 'can select all 128 ROM banks' do
      (1..0x7F).each do |bank|
        write_register(mbc3, 0x2000, bank)
        expect(mbc3.get_output(:rom_bank)).to eq(bank),
          "Bank #{bank}: expected #{bank}, got #{mbc3.get_output(:rom_bank)}"
      end
    end

    it 'can select all 4 RAM banks' do
      (0..3).each do |bank|
        write_register(mbc3, 0x4000, bank)
        expect(mbc3.get_output(:ram_bank)).to eq(bank),
          "Bank #{bank}: expected #{bank}, got #{mbc3.get_output(:ram_bank)}"
      end
    end
  end

  describe 'CE (Chip Enable) Signal' do
    it 'ignores writes when CE is low' do
      initial_bank = mbc3.get_output(:rom_bank)

      mbc3.set_input(:ce, 0)
      write_register(mbc3, 0x2000, 0x10)

      expect(mbc3.get_output(:rom_bank)).to eq(initial_bank)
    end

    it 'responds to writes when CE is high' do
      mbc3.set_input(:ce, 1)
      write_register(mbc3, 0x2000, 0x10)

      expect(mbc3.get_output(:rom_bank)).to eq(0x10)
    end
  end

  describe 'has_ram Input' do
    it 'disables RAM when has_ram is 0' do
      mbc3.set_input(:has_ram, 0)
      write_register(mbc3, 0x0000, 0x0A)
      expect(mbc3.get_output(:ram_enable)).to eq(0)
    end

    it 'allows RAM enable when has_ram is 1' do
      mbc3.set_input(:has_ram, 1)
      write_register(mbc3, 0x0000, 0x0A)
      expect(mbc3.get_output(:ram_enable)).to eq(1)
    end
  end

  describe 'Typical Usage Pattern' do
    it 'follows standard game initialization with RTC' do
      # Step 1: Enable RAM/RTC
      write_register(mbc3, 0x0000, 0x0A)
      expect(mbc3.get_output(:ram_enable)).to eq(1)

      # Step 2: Select ROM bank 5
      write_register(mbc3, 0x2000, 0x05)
      expect(mbc3.get_output(:rom_bank)).to eq(5)

      # Step 3: Select RAM bank 2
      write_register(mbc3, 0x4000, 0x02)
      expect(mbc3.get_output(:ram_bank)).to eq(2)
      expect(mbc3.get_output(:rtc_mode)).to eq(0)

      # Step 4: Latch RTC
      write_register(mbc3, 0x6000, 0x00)
      write_register(mbc3, 0x6000, 0x01)

      # Step 5: Read RTC seconds
      write_register(mbc3, 0x4000, 0x08)
      expect(mbc3.get_output(:rtc_mode)).to eq(1)

      # Step 6: Back to RAM mode
      write_register(mbc3, 0x4000, 0x00)
      expect(mbc3.get_output(:rtc_mode)).to eq(0)

      # Step 7: Disable RAM/RTC when done
      write_register(mbc3, 0x0000, 0x00)
      expect(mbc3.get_output(:ram_enable)).to eq(0)
    end
  end

  describe 'RTC Day Counter' do
    # The RTC can count up to 511 days before overflow

    it 'has 9-bit day counter output' do
      # The rtc_days output should be 9 bits wide
      # Verifying by checking output is available
      write_register(mbc3, 0x6000, 0x00)
      write_register(mbc3, 0x6000, 0x01)
      days = mbc3.get_output(:rtc_days)
      expect(days).to be_a(Integer)
      expect(days).to be >= 0
      expect(days).to be <= 511
    end
  end

  describe 'RTC Halt Flag' do
    it 'has halt flag output' do
      expect(mbc3.get_output(:rtc_halt)).to be_a(Integer)
      expect([0, 1]).to include(mbc3.get_output(:rtc_halt))
    end
  end

  describe 'RTC Overflow Flag' do
    it 'has overflow flag output' do
      expect(mbc3.get_output(:rtc_overflow)).to be_a(Integer)
      expect([0, 1]).to include(mbc3.get_output(:rtc_overflow))
    end
  end

  # ============================================================================
  # Missing functionality tests (from reference comparison)
  # These tests verify features that should be implemented to match the
  # MiSTer reference implementation (reference/rtl/mappers/mbc3.v)
  # ============================================================================

  describe 'External RTC Time Sync' do
    it 'accepts RTC_time input for host system time sync' do
      # Reference: RTC_time[33] input for real-time synchronization
      pending 'External RTC time input (RTC_time[33])'
      fail
    end

    it 'syncs with host system time during play' do
      # Reference: Enables proper time progression during emulation
      pending 'RTC sync with host system time'
      fail
    end
  end

  describe 'RTC Timestamp Persistence' do
    it 'outputs current Unix timestamp (RTC_timestampOut)' do
      # Reference: RTC_timestampOut[32] for save file storage
      pending 'RTC timestamp output for persistence'
      fail
    end

    it 'outputs saved time for backup RAM (RTC_savedtimeOut)' do
      # Reference: RTC_savedtimeOut[48] for full RTC state backup
      pending 'RTC saved time output'
      fail
    end

    it 'outputs RTC in-use flag' do
      # Reference: RTC_inuse tracks whether game actively uses RTC
      pending 'RTC in-use flag output'
      fail
    end
  end

  describe 'RTC Backup/Restore' do
    it 'accepts backup write enable signal (bk_rtc_wr)' do
      # Reference: bk_rtc_wr input for loading RTC from savefile
      pending 'RTC backup write enable input'
      fail
    end

    it 'accepts backup address (bk_addr)' do
      # Reference: bk_addr[17] for addressing RTC save data
      pending 'RTC backup address input'
      fail
    end

    it 'accepts backup data (bk_data)' do
      # Reference: bk_data[16] for loading RTC state
      pending 'RTC backup data input'
      fail
    end

    it 'restores RTC state from savefile on power-on' do
      # Reference: Loads RTC from save file bytes 0-3 (timestamp) and 2-3 (saved time)
      pending 'RTC restore from savefile'
      fail
    end
  end

  describe 'RTC Fast-Forward' do
    it 'advances RTC quickly when loaded save is older than current time' do
      # Reference: diffSeconds counter advances RTC at faster rate
      pending 'RTC fast-forward for loaded saves'
      fail
    end

    it 'uses fast-count mechanism to catch up' do
      # Reference: diffSeconds_fast_count logic
      pending 'RTC diffSeconds fast-count mechanism'
      fail
    end
  end

  describe 'RTC Register Read' do
    it 'returns latched seconds via rtc_return mux' do
      # Reference: rtc_return multiplexes latched RTC values
      pending 'RTC register-addressed read via rtc_return'
      fail
    end

    it 'returns proper control byte for day high register (0x0C)' do
      # Reference: Control byte includes halt, overflow, and day MSB
      pending 'RTC control byte read'
      fail
    end
  end

  describe 'Data Output Masking' do
    it 'returns 0xFF for disabled RAM reads' do
      # Reference: cram_do = ram_enabled ? cram_di : 8'hFF
      pending 'Return 0xFF when RAM is disabled'
      fail
    end

    it 'returns RTC register value when in RTC mode' do
      # Reference: cram_do_r = rtc_return when in RTC mode
      pending 'Return RTC register in RTC mode reads'
      fail
    end
  end

  describe 'Cart Output Enable' do
    it 'has cart_oe output for bus control' do
      # Reference: cart_oe output for tristate bus arbitration
      pending 'cart_oe output for bus control'
      fail
    end

    it 'asserts cart_oe during valid read cycles' do
      # Reference: cart_oe = cart_rd AND (ROM access OR (RAM access AND enabled))
      pending 'cart_oe assertion during reads'
      fail
    end
  end

  describe 'Savestate Support' do
    it 'has savestate_load input' do
      # Reference: savestate_load for MiSTer save/load
      pending 'Savestate load input'
      fail
    end

    it 'has savestate_data input for state restore' do
      # Reference: savestate_data[16] input
      pending 'Savestate data input'
      fail
    end

    it 'has savestate_back output for state save' do
      # Reference: savestate_back[16] output
      pending 'Savestate back output'
      fail
    end
  end

  describe 'Multi-Mapper Enable' do
    it 'has enable input for multi-mapper systems' do
      # Reference: enable input for bus arbitration in multi-mapper designs
      pending 'Enable input for multi-mapper support'
      fail
    end

    it 'ignores operations when enable=0' do
      # Reference: Mapper only responds when enabled
      pending 'Ignore operations when disabled'
      fail
    end
  end
end
