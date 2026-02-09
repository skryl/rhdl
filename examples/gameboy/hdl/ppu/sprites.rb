# Game Boy Sprite Engine
# Corresponds to: reference/rtl/sprites.v (simplified parity model)

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../../../../lib/rhdl/dsl/memory'

module RHDL
  module Examples
    module GameBoy
      class Sprites < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential
        include RHDL::DSL::Memory

        input :clk
        input :ce
        input :ce_cpu
        input :size16
        input :is_gbc
        input :sprite_en
        input :lcd_on

        input :v_cnt, width: 8
        input :h_cnt, width: 8

        input :sprite_fetch_c1
        input :sprite_fetch_done
        output :sprite_fetch

        input :oam_fetch
        input :oam_eval_reset
        output :oam_eval

        output :sprite_addr, width: 11
        output :sprite_attr, width: 8
        output :sprite_index, width: 4

        output :oam_eval_end

        # OAM memory interface
        input :dma_active
        input :oam_wr
        input :oam_addr_in, width: 8
        input :oam_di, width: 8
        output :oam_do, width: 8

        # Extra sprites (not modeled in this parity step)
        input :extra_spr_en
        input :extra_wait

        output :extra_tile_fetch
        output :extra_tile_addr, width: 12
        input :tile_data_in, width: 8

        output :spr_extra_found
        output :spr_extra_tile0, width: 8
        output :spr_extra_tile1, width: 8
        output :spr_extra_cgb_pal, width: 3
        output :spr_extra_index, width: 4
        output :spr_extra_pal
        output :spr_extra_prio

        # Save state interface
        input :savestate_oamram_addr, width: 8
        input :savestate_oamram_wren
        input :savestate_oamram_write_data, width: 8
        output :savestate_oamram_read_data, width: 8

        # OAM memory (160 bytes)
        wire :oam_wren
        wire :oam_waddr, width: 8
        wire :oam_wdata, width: 8
        wire :oam_cpu_q, width: 8
        wire :oam_eval_y_q, width: 8
        wire :oam_eval_x_q, width: 8
        wire :oam_fetch_tile_q, width: 8
        wire :oam_fetch_attr_q, width: 8
        wire :eval_y_addr, width: 8
        wire :eval_x_addr, width: 8
        wire :fetch_tile_addr, width: 8
        wire :fetch_attr_addr, width: 8

        memory :oam_mem, depth: 160, width: 8 do |m|
          m.write_port clock: :clk, enable: :oam_wren, addr: :oam_waddr, data: :oam_wdata
          m.async_read_port addr: :oam_addr_in, output: :oam_cpu_q
          m.async_read_port addr: :eval_y_addr, output: :oam_eval_y_q
          m.async_read_port addr: :eval_x_addr, output: :oam_eval_x_q
          m.async_read_port addr: :fetch_tile_addr, output: :oam_fetch_tile_q
          m.async_read_port addr: :fetch_attr_addr, output: :oam_fetch_attr_q
          m.async_read_port addr: :savestate_oamram_addr, output: :savestate_oamram_read_data
        end

        # Evaluation state
        wire :search_idx, width: 6
        wire :sprite_cnt, width: 4
        wire :old_fetch_done
        wire :tile_index_latched, width: 8
        wire :sprite_attr_latched, width: 8
        wire :oam_eval_w
        wire :oam_eval_end_w
        wire :sprite_fetch_w

        # 10-sprite line buffer (first 10 on line)
        wire :sprite_no0, width: 6
        wire :sprite_no1, width: 6
        wire :sprite_no2, width: 6
        wire :sprite_no3, width: 6
        wire :sprite_no4, width: 6
        wire :sprite_no5, width: 6
        wire :sprite_no6, width: 6
        wire :sprite_no7, width: 6
        wire :sprite_no8, width: 6
        wire :sprite_no9, width: 6

        wire :sprite_row0, width: 4
        wire :sprite_row1, width: 4
        wire :sprite_row2, width: 4
        wire :sprite_row3, width: 4
        wire :sprite_row4, width: 4
        wire :sprite_row5, width: 4
        wire :sprite_row6, width: 4
        wire :sprite_row7, width: 4
        wire :sprite_row8, width: 4
        wire :sprite_row9, width: 4

        wire :sprite_x0, width: 8
        wire :sprite_x1, width: 8
        wire :sprite_x2, width: 8
        wire :sprite_x3, width: 8
        wire :sprite_x4, width: 8
        wire :sprite_x5, width: 8
        wire :sprite_x6, width: 8
        wire :sprite_x7, width: 8
        wire :sprite_x8, width: 8
        wire :sprite_x9, width: 8

        # Active sprite selection
        wire :match0
        wire :match1
        wire :match2
        wire :match3
        wire :match4
        wire :match5
        wire :match6
        wire :match7
        wire :match8
        wire :match9
        wire :any_match
        wire :active_idx, width: 4
        wire :active_sprite_no, width: 6
        wire :active_sprite_row, width: 4

        # Row math
        wire :line_plus_16, width: 8
        wire :spr_height, width: 8
        wire :sprite_on_line
        wire :row_for_addr, width: 4
        wire :row_flipped, width: 4

        behavior do
          oam_eval_end_w <= (search_idx == lit(40, width: 6)) | (sprite_cnt == lit(10, width: 4))
          oam_eval_w <= lcd_on & ~oam_eval_end_w
          oam_eval <= oam_eval_w
          oam_eval_end <= oam_eval_end_w

          # OAM writes from CPU/DMA or savestate interface.
          oam_waddr <= mux(savestate_oamram_wren, savestate_oamram_addr, oam_addr_in)
          oam_wdata <= mux(savestate_oamram_wren, savestate_oamram_write_data, oam_di)
          oam_wren <= (savestate_oamram_wren | (ce_cpu & oam_wr)) & (oam_waddr < lit(160, width: 8))
          oam_do <= mux(oam_addr_in < lit(160, width: 8), oam_cpu_q, lit(0, width: 8))

          eval_y_addr <= cat(search_idx, lit(0, width: 2))
          eval_x_addr <= eval_y_addr + lit(1, width: 8)

          line_plus_16 <= v_cnt + lit(16, width: 8)
          spr_height <= mux(size16, lit(16, width: 8), lit(8, width: 8))
          sprite_on_line <= (line_plus_16 >= oam_eval_y_q) &
                            (line_plus_16 < (oam_eval_y_q + spr_height))

          match0 <= (sprite_cnt > lit(0, width: 4)) & (sprite_x0 == h_cnt)
          match1 <= (sprite_cnt > lit(1, width: 4)) & (sprite_x1 == h_cnt)
          match2 <= (sprite_cnt > lit(2, width: 4)) & (sprite_x2 == h_cnt)
          match3 <= (sprite_cnt > lit(3, width: 4)) & (sprite_x3 == h_cnt)
          match4 <= (sprite_cnt > lit(4, width: 4)) & (sprite_x4 == h_cnt)
          match5 <= (sprite_cnt > lit(5, width: 4)) & (sprite_x5 == h_cnt)
          match6 <= (sprite_cnt > lit(6, width: 4)) & (sprite_x6 == h_cnt)
          match7 <= (sprite_cnt > lit(7, width: 4)) & (sprite_x7 == h_cnt)
          match8 <= (sprite_cnt > lit(8, width: 4)) & (sprite_x8 == h_cnt)
          match9 <= (sprite_cnt > lit(9, width: 4)) & (sprite_x9 == h_cnt)
          any_match <= match0 | match1 | match2 | match3 | match4 |
                       match5 | match6 | match7 | match8 | match9

          active_idx <= mux(match0, lit(0, width: 4),
                        mux(match1, lit(1, width: 4),
                        mux(match2, lit(2, width: 4),
                        mux(match3, lit(3, width: 4),
                        mux(match4, lit(4, width: 4),
                        mux(match5, lit(5, width: 4),
                        mux(match6, lit(6, width: 4),
                        mux(match7, lit(7, width: 4),
                        mux(match8, lit(8, width: 4),
                            lit(9, width: 4))))))))))

          active_sprite_no <= mux(active_idx == lit(0, width: 4), sprite_no0,
                              mux(active_idx == lit(1, width: 4), sprite_no1,
                              mux(active_idx == lit(2, width: 4), sprite_no2,
                              mux(active_idx == lit(3, width: 4), sprite_no3,
                              mux(active_idx == lit(4, width: 4), sprite_no4,
                              mux(active_idx == lit(5, width: 4), sprite_no5,
                              mux(active_idx == lit(6, width: 4), sprite_no6,
                              mux(active_idx == lit(7, width: 4), sprite_no7,
                              mux(active_idx == lit(8, width: 4), sprite_no8,
                                  sprite_no9)))))))))

          active_sprite_row <= mux(active_idx == lit(0, width: 4), sprite_row0,
                               mux(active_idx == lit(1, width: 4), sprite_row1,
                               mux(active_idx == lit(2, width: 4), sprite_row2,
                               mux(active_idx == lit(3, width: 4), sprite_row3,
                               mux(active_idx == lit(4, width: 4), sprite_row4,
                               mux(active_idx == lit(5, width: 4), sprite_row5,
                               mux(active_idx == lit(6, width: 4), sprite_row6,
                               mux(active_idx == lit(7, width: 4), sprite_row7,
                               mux(active_idx == lit(8, width: 4), sprite_row8,
                                   sprite_row9)))))))))

          fetch_tile_addr <= cat(active_sprite_no, lit(2, width: 2))
          fetch_attr_addr <= cat(active_sprite_no, lit(3, width: 2))

          sprite_fetch_w <= any_match & oam_fetch & (is_gbc | sprite_en)
          sprite_fetch <= sprite_fetch_w
          sprite_index <= active_idx
          sprite_attr <= sprite_attr_latched

          row_flipped <= mux(size16,
                             lit(15, width: 4) - active_sprite_row,
                             cat(lit(0, width: 1), lit(7, width: 3) - active_sprite_row[2..0]))
          row_for_addr <= mux(sprite_attr_latched[6], row_flipped, active_sprite_row)
          sprite_addr <= mux(size16,
                             cat(tile_index_latched[7..1], row_for_addr),
                             cat(tile_index_latched, row_for_addr[2..0]))

          # Extra sprite outputs not modeled yet.
          extra_tile_fetch <= lit(0, width: 1)
          extra_tile_addr <= lit(0, width: 12)
          spr_extra_found <= lit(0, width: 1)
          spr_extra_tile0 <= lit(0, width: 8)
          spr_extra_tile1 <= lit(0, width: 8)
          spr_extra_cgb_pal <= lit(0, width: 3)
          spr_extra_index <= lit(0, width: 4)
          spr_extra_pal <= lit(0, width: 1)
          spr_extra_prio <= lit(0, width: 1)
        end

        sequential clock: :clk, reset: :oam_eval_reset, reset_values: {
          search_idx: 0,
          sprite_cnt: 0,
          old_fetch_done: 0,
          tile_index_latched: 0,
          sprite_attr_latched: 0,
          sprite_no0: 0,
          sprite_no1: 0,
          sprite_no2: 0,
          sprite_no3: 0,
          sprite_no4: 0,
          sprite_no5: 0,
          sprite_no6: 0,
          sprite_no7: 0,
          sprite_no8: 0,
          sprite_no9: 0,
          sprite_row0: 0,
          sprite_row1: 0,
          sprite_row2: 0,
          sprite_row3: 0,
          sprite_row4: 0,
          sprite_row5: 0,
          sprite_row6: 0,
          sprite_row7: 0,
          sprite_row8: 0,
          sprite_row9: 0,
          sprite_x0: 0xFF,
          sprite_x1: 0xFF,
          sprite_x2: 0xFF,
          sprite_x3: 0xFF,
          sprite_x4: 0xFF,
          sprite_x5: 0xFF,
          sprite_x6: 0xFF,
          sprite_x7: 0xFF,
          sprite_x8: 0xFF,
          sprite_x9: 0xFF
        } do
          scan_step = ce & lcd_on & oam_eval_w & (search_idx < lit(40, width: 6))
          save_sprite = scan_step & sprite_on_line & (sprite_cnt < lit(10, width: 4))
          row_value = (line_plus_16 - oam_eval_y_q)[3..0]
          consume_sprite = ce & ~old_fetch_done & sprite_fetch_done

          search_idx <= mux(scan_step,
                            search_idx + lit(1, width: 6),
                            search_idx)
          sprite_cnt <= mux(save_sprite,
                            sprite_cnt + lit(1, width: 4),
                            sprite_cnt)

          tile_index_latched <= mux(ce & sprite_fetch_c1,
                                    oam_fetch_tile_q,
                                    tile_index_latched)
          sprite_attr_latched <= mux(ce & sprite_fetch_c1,
                                     oam_fetch_attr_q,
                                     sprite_attr_latched)
          old_fetch_done <= mux(ce, sprite_fetch_done, old_fetch_done)

          sprite_no0 <= mux(save_sprite & (sprite_cnt == lit(0, width: 4)), search_idx,
                        sprite_no0)
          sprite_no1 <= mux(save_sprite & (sprite_cnt == lit(1, width: 4)), search_idx,
                        sprite_no1)
          sprite_no2 <= mux(save_sprite & (sprite_cnt == lit(2, width: 4)), search_idx,
                        sprite_no2)
          sprite_no3 <= mux(save_sprite & (sprite_cnt == lit(3, width: 4)), search_idx,
                        sprite_no3)
          sprite_no4 <= mux(save_sprite & (sprite_cnt == lit(4, width: 4)), search_idx,
                        sprite_no4)
          sprite_no5 <= mux(save_sprite & (sprite_cnt == lit(5, width: 4)), search_idx,
                        sprite_no5)
          sprite_no6 <= mux(save_sprite & (sprite_cnt == lit(6, width: 4)), search_idx,
                        sprite_no6)
          sprite_no7 <= mux(save_sprite & (sprite_cnt == lit(7, width: 4)), search_idx,
                        sprite_no7)
          sprite_no8 <= mux(save_sprite & (sprite_cnt == lit(8, width: 4)), search_idx,
                        sprite_no8)
          sprite_no9 <= mux(save_sprite & (sprite_cnt == lit(9, width: 4)), search_idx,
                        sprite_no9)

          sprite_row0 <= mux(save_sprite & (sprite_cnt == lit(0, width: 4)), row_value,
                         sprite_row0)
          sprite_row1 <= mux(save_sprite & (sprite_cnt == lit(1, width: 4)), row_value,
                         sprite_row1)
          sprite_row2 <= mux(save_sprite & (sprite_cnt == lit(2, width: 4)), row_value,
                         sprite_row2)
          sprite_row3 <= mux(save_sprite & (sprite_cnt == lit(3, width: 4)), row_value,
                         sprite_row3)
          sprite_row4 <= mux(save_sprite & (sprite_cnt == lit(4, width: 4)), row_value,
                         sprite_row4)
          sprite_row5 <= mux(save_sprite & (sprite_cnt == lit(5, width: 4)), row_value,
                         sprite_row5)
          sprite_row6 <= mux(save_sprite & (sprite_cnt == lit(6, width: 4)), row_value,
                         sprite_row6)
          sprite_row7 <= mux(save_sprite & (sprite_cnt == lit(7, width: 4)), row_value,
                         sprite_row7)
          sprite_row8 <= mux(save_sprite & (sprite_cnt == lit(8, width: 4)), row_value,
                         sprite_row8)
          sprite_row9 <= mux(save_sprite & (sprite_cnt == lit(9, width: 4)), row_value,
                         sprite_row9)

          sprite_x0 <= mux(consume_sprite & (active_idx == lit(0, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(0, width: 4)), oam_eval_x_q,
                           sprite_x0))
          sprite_x1 <= mux(consume_sprite & (active_idx == lit(1, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(1, width: 4)), oam_eval_x_q,
                           sprite_x1))
          sprite_x2 <= mux(consume_sprite & (active_idx == lit(2, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(2, width: 4)), oam_eval_x_q,
                           sprite_x2))
          sprite_x3 <= mux(consume_sprite & (active_idx == lit(3, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(3, width: 4)), oam_eval_x_q,
                           sprite_x3))
          sprite_x4 <= mux(consume_sprite & (active_idx == lit(4, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(4, width: 4)), oam_eval_x_q,
                           sprite_x4))
          sprite_x5 <= mux(consume_sprite & (active_idx == lit(5, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(5, width: 4)), oam_eval_x_q,
                           sprite_x5))
          sprite_x6 <= mux(consume_sprite & (active_idx == lit(6, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(6, width: 4)), oam_eval_x_q,
                           sprite_x6))
          sprite_x7 <= mux(consume_sprite & (active_idx == lit(7, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(7, width: 4)), oam_eval_x_q,
                           sprite_x7))
          sprite_x8 <= mux(consume_sprite & (active_idx == lit(8, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(8, width: 4)), oam_eval_x_q,
                           sprite_x8))
          sprite_x9 <= mux(consume_sprite & (active_idx == lit(9, width: 4)), lit(0xFF, width: 8),
                       mux(save_sprite & (sprite_cnt == lit(9, width: 4)), oam_eval_x_q,
                           sprite_x9))
        end

        def initialize(name = nil, **kwargs)
          super(name, **kwargs)
          initialize_memories
        end
      end
    end
  end
end
