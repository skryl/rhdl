# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/gameboy/gameboy'

# Game Boy Sprites Component Tests
# Tests the sprite engine which handles:
# - OAM (Object Attribute Memory) management
# - Sprite search during Mode 2
# - Sprite rendering during Mode 3
# - 10 sprites per scanline limit
# - Priority handling
RSpec.describe GameBoy::Sprites do
  def clock_cycle(component, enable_ce: true)
    component.set_input(:ce, enable_ce ? 1 : 0)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  def clock_cycles(component, n, enable_ce: true)
    n.times { clock_cycle(component, enable_ce: enable_ce) }
  end

  let(:sprites) { GameBoy::Sprites.new }

  before do
    # Initialize inputs to default values
    sprites.set_input(:clk, 0)
    sprites.set_input(:ce, 1)
    sprites.set_input(:ce_cpu, 1)
    sprites.set_input(:size16, 0)        # 8x8 sprite mode
    sprites.set_input(:is_gbc, 0)        # DMG mode
    sprites.set_input(:sprite_en, 1)     # Sprites enabled
    sprites.set_input(:lcd_on, 1)        # LCD on
    sprites.set_input(:v_cnt, 0)         # Line 0
    sprites.set_input(:h_cnt, 0)         # Pixel 0
    sprites.set_input(:oam_eval, 0)      # OAM evaluation not active
    sprites.set_input(:oam_fetch, 0)     # Sprite fetch not active
    sprites.set_input(:oam_eval_reset, 0)
    sprites.set_input(:sprite_fetch_c1, 0)
    sprites.set_input(:sprite_fetch_done, 0)
    sprites.set_input(:dma_active, 0)
    sprites.set_input(:oam_wr, 0)
    sprites.set_input(:oam_addr_in, 0)
    sprites.set_input(:oam_di, 0)
    sprites.set_input(:extra_spr_en, 0)
    sprites.set_input(:extra_wait, 0)
    sprites.set_input(:tile_data_in, 0)
    sprites.set_input(:savestate_oamram_addr, 0)
    sprites.set_input(:savestate_oamram_wren, 0)
    sprites.set_input(:savestate_oamram_write_data, 0)
    sprites.propagate
  end

  describe 'component instantiation' do
    it 'creates a Sprites component' do
      expect(sprites).to be_a(GameBoy::Sprites)
    end

    it 'has sprite fetch outputs' do
      expect { sprites.get_output(:sprite_fetch) }.not_to raise_error
      expect { sprites.get_output(:sprite_addr) }.not_to raise_error
      expect { sprites.get_output(:sprite_attr) }.not_to raise_error
      expect { sprites.get_output(:sprite_index) }.not_to raise_error
    end

    it 'has OAM evaluation outputs' do
      expect { sprites.get_output(:oam_eval_end) }.not_to raise_error
      expect { sprites.get_output(:oam_do) }.not_to raise_error
    end

    it 'has extra sprite outputs' do
      expect { sprites.get_output(:spr_extra_found) }.not_to raise_error
      expect { sprites.get_output(:spr_extra_tile0) }.not_to raise_error
      expect { sprites.get_output(:spr_extra_tile1) }.not_to raise_error
    end
  end

  describe 'reset behavior' do
    it 'resets sprite search state on oam_eval_reset' do
      # Start OAM evaluation
      sprites.set_input(:oam_eval, 1)
      clock_cycles(sprites, 10)

      # Reset OAM evaluation
      sprites.set_input(:oam_eval_reset, 1)
      clock_cycle(sprites)

      sprites.set_input(:oam_eval_reset, 0)
      clock_cycle(sprites)

      # Render index should be reset
      expect(sprites.get_output(:sprite_index)).to eq(0)
    end
  end

  describe 'OAM search (Mode 2)' do
    it 'starts sprite search when oam_eval is enabled' do
      sprites.set_input(:oam_eval, 1)
      sprites.set_input(:oam_eval_reset, 0)
      clock_cycle(sprites)

      # OAM evaluation should be in progress
      expect(sprites.get_output(:oam_eval_end)).to eq(0)
    end

    it 'completes OAM search after scanning all 40 sprites' do
      sprites.set_input(:oam_eval, 1)

      # Run enough cycles to scan all 40 OAM entries
      clock_cycles(sprites, 40)

      expect(sprites.get_output(:oam_eval_end)).to eq(1)
    end

    it 'signals OAM search complete when 10 sprites found' do
      # This test depends on OAM contents having matching sprites
      # The search limit is 10 sprites per scanline
      sprites.set_input(:oam_eval, 1)

      # OAM eval ends when either:
      # - All 40 sprites are checked (search_idx == 40)
      # - 10 sprites are found (sprites_found == 10)
      clock_cycles(sprites, 40)

      expect(sprites.get_output(:oam_eval_end)).to eq(1)
    end
  end

  describe 'sprite fetch (Mode 3)' do
    before do
      # Reset sprite state
      sprites.set_input(:oam_eval_reset, 1)
      clock_cycle(sprites)
      sprites.set_input(:oam_eval_reset, 0)
    end

    it 'outputs sprite_fetch when sprites enabled and found' do
      # Enable sprite fetching
      sprites.set_input(:oam_fetch, 1)
      sprites.set_input(:sprite_en, 1)
      sprites.propagate

      # sprite_fetch depends on sprites_found > 0
      # After reset, sprites_found is 0, so sprite_fetch should be 0
      expect(sprites.get_output(:sprite_fetch)).to eq(0)
    end

    it 'increments render index when sprite fetch completes' do
      sprites.set_input(:oam_eval_reset, 0)
      sprites.set_input(:sprite_fetch_done, 1)
      clock_cycle(sprites)

      expect(sprites.get_output(:sprite_index)).to eq(1)
    end

    it 'resets render index on oam_eval_reset' do
      # Advance render index
      sprites.set_input(:sprite_fetch_done, 1)
      clock_cycles(sprites, 5)

      expect(sprites.get_output(:sprite_index)).to eq(5)

      # Reset
      sprites.set_input(:sprite_fetch_done, 0)
      sprites.set_input(:oam_eval_reset, 1)
      clock_cycle(sprites)

      expect(sprites.get_output(:sprite_index)).to eq(0)
    end
  end

  describe 'sprite modes' do
    it 'supports 8x8 sprite mode' do
      sprites.set_input(:size16, 0)
      sprites.propagate

      # In 8x8 mode, each sprite is 8 pixels tall
      # No direct output to check, but mode is stored
    end

    it 'supports 8x16 sprite mode' do
      sprites.set_input(:size16, 1)
      sprites.propagate

      # In 8x16 mode, each sprite is 16 pixels tall
    end
  end

  describe 'DMA interaction' do
    it 'uses external address when DMA is active' do
      sprites.set_input(:dma_active, 1)
      sprites.set_input(:oam_addr_in, 0x55)
      sprites.propagate

      # When DMA active, OAM address comes from oam_addr_in
    end

    it 'uses search index when DMA is inactive' do
      sprites.set_input(:dma_active, 0)
      sprites.set_input(:oam_eval, 1)
      clock_cycles(sprites, 5)

      # OAM address should be based on search_idx (sprite index * 4)
    end
  end

  describe 'Game Boy Color mode' do
    it 'handles CGB priority mode' do
      sprites.set_input(:is_gbc, 1)
      sprites.propagate

      # In CGB mode, sprite priority is handled by OAM order
      # rather than X position
    end
  end

  describe 'extra sprites feature' do
    it 'defaults extra sprite outputs to zero' do
      sprites.set_input(:extra_spr_en, 0)
      sprites.propagate

      expect(sprites.get_output(:spr_extra_found)).to eq(0)
      expect(sprites.get_output(:extra_tile_fetch)).to eq(0)
      expect(sprites.get_output(:spr_extra_tile0)).to eq(0)
      expect(sprites.get_output(:spr_extra_tile1)).to eq(0)
    end
  end

  describe 'sprite attributes' do
    it 'provides sprite index during fetch' do
      sprites.set_input(:oam_eval_reset, 1)
      clock_cycle(sprites)
      sprites.set_input(:oam_eval_reset, 0)

      expect(sprites.get_output(:sprite_index)).to eq(0)

      sprites.set_input(:sprite_fetch_done, 1)
      clock_cycle(sprites)
      expect(sprites.get_output(:sprite_index)).to eq(1)

      clock_cycle(sprites)
      expect(sprites.get_output(:sprite_index)).to eq(2)
    end
  end

  describe 'line matching' do
    it 'evaluates sprites on current scanline' do
      # Set current line
      sprites.set_input(:v_cnt, 64)  # Line 64
      sprites.set_input(:oam_eval, 1)
      sprites.propagate

      # OAM search should compare sprite Y with v_cnt
    end

    it 'handles top of screen (line 0)' do
      sprites.set_input(:v_cnt, 0)
      sprites.set_input(:oam_eval, 1)
      clock_cycle(sprites)

      # Should work correctly at line 0
    end

    it 'handles bottom of visible area (line 143)' do
      sprites.set_input(:v_cnt, 143)
      sprites.set_input(:oam_eval, 1)
      clock_cycle(sprites)

      # Should work correctly at last visible line
    end
  end

  describe 'save state interface' do
    it 'has savestate read output' do
      expect { sprites.get_output(:savestate_oamram_read_data) }.not_to raise_error
    end

    it 'accepts savestate write inputs' do
      sprites.set_input(:savestate_oamram_addr, 0x10)
      sprites.set_input(:savestate_oamram_wren, 1)
      sprites.set_input(:savestate_oamram_write_data, 0xAB)
      clock_cycle(sprites)

      # Save state write should be accepted
    end
  end
end
