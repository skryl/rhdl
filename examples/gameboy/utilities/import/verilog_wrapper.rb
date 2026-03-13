# frozen_string_literal: true

module RHDL
  module Examples
    module GameBoy
      module Import
        module VerilogWrapper
          def gameboy_wrapper_top_module
            'gameboy'
          end

          def gb_module_text(verilog_entry)
            text = File.read(verilog_entry)
            text[/\bmodule\s+gb\b.*?\bendmodule\b/m] || text
          end

          def gb_wrapper_profile(verilog_entry)
            if File.basename(verilog_entry) == 'pure_verilog_entry.v'
              return {
                boot_mode: :upload,
                is_gbc: 'isGBC',
                is_sgb: 'isSGB',
                save_state_ext_dout: 'SaveStateExt_Dout',
                savestate_cram_read_data: 'Savestate_CRAMReadData',
                save_out_dout: 'SAVE_out_Dout',
                save_out_done: 'SAVE_out_done',
                boot_rom_do: nil,
                boot_rom_addr: nil,
                cgb_boot_download: 'cgb_boot_download',
                dmg_boot_download: 'dmg_boot_download',
                sgb_boot_download: 'sgb_boot_download',
                ioctl_wr: 'ioctl_wr',
                ioctl_addr: 'ioctl_addr',
                ioctl_dout: 'ioctl_dout'
              }
            end

            text = gb_module_text(verilog_entry)
            present = lambda do |*candidates|
              candidates.find { |candidate| text.match?(/\b#{Regexp.escape(candidate)}\b/) }
            end

            upload_mode =
              present.call('dmg_boot_download') &&
              present.call('ioctl_wr') &&
              present.call('ioctl_addr') &&
              present.call('ioctl_dout')

            profile = {
              boot_mode: upload_mode ? :upload : :direct,
              is_gbc: present.call('isGBC', 'is_gbc'),
              is_sgb: present.call('isSGB', 'is_sgb'),
              save_state_ext_dout: present.call('SaveStateExt_Dout', 'save_state_ext_dout'),
              savestate_cram_read_data: present.call('Savestate_CRAMReadData', 'savestate_cram_read_data'),
              save_out_dout: present.call('SAVE_out_Dout', 'save_out_dout'),
              save_out_done: present.call('SAVE_out_done', 'save_out_done'),
              boot_rom_do: present.call('boot_rom_do'),
              boot_rom_addr: present.call('boot_rom_addr'),
              cgb_boot_download: present.call('cgb_boot_download'),
              dmg_boot_download: present.call('dmg_boot_download'),
              sgb_boot_download: present.call('sgb_boot_download'),
              ioctl_wr: present.call('ioctl_wr'),
              ioctl_addr: present.call('ioctl_addr'),
              ioctl_dout: present.call('ioctl_dout')
            }

            if profile[:is_gbc].nil? || profile[:is_sgb].nil?
              raise "Unable to determine wrapper port profile for #{verilog_entry}"
            end

            if profile[:boot_mode] == :upload
              required = %i[cgb_boot_download dmg_boot_download sgb_boot_download ioctl_wr ioctl_addr ioctl_dout]
              missing = required.reject { |key| profile[key] }
              raise "Upload-mode wrapper profile missing ports #{missing.inspect} for #{verilog_entry}" if missing.any?
            else
              required = %i[boot_rom_do boot_rom_addr]
              missing = required.reject { |key| profile[key] }
              raise "Direct-boot wrapper profile missing ports #{missing.inspect} for #{verilog_entry}" if missing.any?
            end

            profile
          end

          def gameboy_wrapper_source(profile:, use_speedcontrol: false, speedcontrol_module_name: 'speedcontrol')
            return gameboy_wrapper_source_with_speedcontrol(
              profile: profile,
              speedcontrol_module_name: speedcontrol_module_name
            ) if use_speedcontrol

            gameboy_wrapper_source_without_speedcontrol(profile: profile)
          end

          def gameboy_wrapper_source_without_speedcontrol(profile:)
            wrapper_ports = [
              'input wire clk_sys',
              'input wire reset',
              'input wire ce',
              'input wire ce_n',
              'input wire ce_2x',
              'input wire [7:0] joystick',
              'input wire is_gbc',
              'input wire is_sgb',
              'input wire [7:0] cart_do',
              'output wire [14:0] ext_bus_addr',
              'output wire ext_bus_a15',
              'output wire cart_rd',
              'output wire cart_wr',
              'output wire [7:0] cart_di',
              'output wire [15:0] audio_l',
              'output wire [15:0] audio_r',
              'output wire lcd_clkena',
              'output wire [14:0] lcd_data',
              'output wire [1:0] lcd_data_gb',
              'output wire [1:0] lcd_mode',
              'output wire lcd_on',
              'output wire lcd_vsync',
              'input wire [7:0] boot_rom_do',
              'output wire [7:0] boot_rom_addr'
            ]
            wrapper_signals = base_gameboy_wrapper_signals
            connections = base_gb_connections(profile: profile, use_speedcontrol: false)

            append_boot_mode_connections!(
              profile: profile,
              wrapper_signals: wrapper_signals,
              connections: connections
            )

            upload_always_block = boot_upload_always_block(profile: profile)

            <<~VERILOG
              module #{gameboy_wrapper_top_module} (
                #{wrapper_ports.join(",\n        ")}
              );
                #{wrapper_signals.join("\n        ")}

              #{upload_always_block.chomp}
                gb gb_core (
              #{connections.map { |line| "    #{line}" }.join(",\n")}
                );
              endmodule
            VERILOG
          end

          def gameboy_wrapper_source_with_speedcontrol(profile:, speedcontrol_module_name:)
            wrapper_ports = [
              'input wire clk_sys',
              'input wire reset',
              'input wire [7:0] joystick',
              'input wire is_gbc',
              'input wire is_sgb',
              'input wire [7:0] cart_do',
              'output wire [14:0] ext_bus_addr',
              'output wire ext_bus_a15',
              'output wire cart_rd',
              'output wire cart_wr',
              'output wire [7:0] cart_di',
              'output wire [15:0] audio_l',
              'output wire [15:0] audio_r',
              'output wire lcd_clkena',
              'output wire [14:0] lcd_data',
              'output wire [1:0] lcd_data_gb',
              'output wire [1:0] lcd_mode',
              'output wire lcd_on',
              'output wire lcd_vsync',
              'input wire [7:0] boot_rom_do',
              'output wire [7:0] boot_rom_addr'
            ]
            wrapper_signals = base_gameboy_wrapper_signals + [
              'wire ce;',
              'wire ce_n;',
              'wire ce_2x;',
              'wire cart_act = cart_rd | cart_wr;',
              'wire DMA_on;',
              'wire sleep_savestate;'
            ]
            connections = base_gb_connections(profile: profile, use_speedcontrol: true)

            append_boot_mode_connections!(
              profile: profile,
              wrapper_signals: wrapper_signals,
              connections: connections
            )

            upload_always_block = boot_upload_always_block(profile: profile)

            <<~VERILOG
              module #{gameboy_wrapper_top_module} (
                #{wrapper_ports.join(",\n        ")}
              );
                #{wrapper_signals.join("\n        ")}

              #{upload_always_block.chomp}
                #{speedcontrol_module_name} speed_ctrl (
                  .clk_sys(clk_sys),
                  .pause(1'b0),
                  .speedup(1'b0),
                  .cart_act(cart_act),
                  .DMA_on(1'b0),
                  .ce(ce),
                  .ce_n(ce_n),
                  .ce_2x(ce_2x)
                );

                gb gb_core (
              #{connections.map { |line| "    #{line}" }.join(",\n")}
                );
              endmodule
            VERILOG
          end

          def base_gameboy_wrapper_signals
            [
              'wire [1:0] joy_p54;',
              'wire [3:0] joy_dir = joystick[3:0];',
              'wire [3:0] joy_btn = joystick[7:4];',
              'wire [3:0] joy_dir_masked = joy_dir | {4{joy_p54[0]}};',
              'wire [3:0] joy_btn_masked = joy_btn | {4{joy_p54[1]}};',
              'wire [3:0] joy_din_computed = joy_dir_masked & joy_btn_masked;'
            ]
          end

          def base_gb_connections(profile:, use_speedcontrol:)
            connections = [
              '.clk_sys(clk_sys)',
              '.reset(reset)',
              '.joystick(joystick)',
              ".#{profile.fetch(:is_gbc)}(is_gbc)",
              '.real_cgb_boot(1\'b0)',
              ".#{profile.fetch(:is_sgb)}(is_sgb)",
              '.extra_spr_en(1\'b0)',
              '.ext_bus_addr(ext_bus_addr)',
              '.ext_bus_a15(ext_bus_a15)',
              '.cart_rd(cart_rd)',
              '.cart_wr(cart_wr)',
              '.cart_do(cart_do)',
              '.cart_di(cart_di)',
              '.cart_oe(1\'b1)',
              '.boot_gba_en(1\'b0)',
              '.fast_boot_en(1\'b0)',
              '.audio_no_pops(1\'b0)',
              '.megaduck(1\'b0)',
              '.lcd_clkena(lcd_clkena)',
              '.lcd_data(lcd_data)',
              '.lcd_data_gb(lcd_data_gb)',
              '.lcd_mode(lcd_mode)',
              '.lcd_on(lcd_on)',
              '.lcd_vsync(lcd_vsync)',
              '.audio_l(audio_l)',
              '.audio_r(audio_r)',
              '.joy_p54(joy_p54)',
              '.joy_din(joy_din_computed)',
              '.gg_reset(1\'b0)',
              '.gg_en(1\'b0)',
              '.gg_code(129\'d0)',
              '.serial_clk_in(1\'b0)',
              '.serial_data_in(1\'b1)',
              '.increaseSSHeaderCount(1\'b0)',
              '.cart_ram_size(8\'d0)',
              '.save_state(1\'b0)',
              '.load_state(1\'b0)',
              '.savestate_number(2\'d0)',
              '.sleep_savestate(sleep_savestate)',
              ".#{profile.fetch(:save_state_ext_dout)}(64'd0)",
              ".#{profile.fetch(:savestate_cram_read_data)}(8'd0)",
              ".#{profile.fetch(:save_out_dout)}(64'd0)",
              ".#{profile.fetch(:save_out_done)}(1'b1)",
              '.rewind_on(1\'b0)',
              '.rewind_active(1\'b0)'
            ]

            if use_speedcontrol
              connections.insert(2, '.ce(ce)', '.ce_n(ce_n)', '.ce_2x(ce_2x)')
              connections << '.DMA_on(DMA_on)'
            else
              connections.insert(2, '.ce(ce)', '.ce_n(ce_n)', '.ce_2x(ce_2x)')
            end

            connections
          end

          def append_boot_mode_connections!(profile:, wrapper_signals:, connections:)
            if profile.fetch(:boot_mode) == :upload
              wrapper_signals.concat([
                'reg boot_upload_active;',
                'reg boot_upload_phase;',
                'reg [7:0] boot_upload_index;',
                'reg [7:0] boot_upload_low_byte;',
                'wire core_reset = reset | boot_upload_active;',
                'wire core_dmg_boot_download = boot_upload_active;',
                'wire core_ioctl_wr = boot_upload_active & boot_upload_phase;',
                'wire [24:0] core_ioctl_addr = {17\'d0, boot_upload_index};',
                'wire [15:0] core_ioctl_dout = {boot_rom_do, boot_upload_low_byte};',
                'assign boot_rom_addr = boot_upload_active ? (boot_upload_phase ? (boot_upload_index + 8\'d1) : boot_upload_index) : 8\'d0;'
              ])
              connections[1] = '.reset(core_reset)'
              connections << ".#{profile.fetch(:cgb_boot_download)}(1'b0)"
              connections << ".#{profile.fetch(:dmg_boot_download)}(core_dmg_boot_download)"
              connections << ".#{profile.fetch(:sgb_boot_download)}(1'b0)"
              connections << ".#{profile.fetch(:ioctl_wr)}(core_ioctl_wr)"
              connections << ".#{profile.fetch(:ioctl_addr)}(core_ioctl_addr)"
              connections << ".#{profile.fetch(:ioctl_dout)}(core_ioctl_dout)"
            else
              wrapper_signals << 'wire core_reset = reset;'
              connections[1] = '.reset(core_reset)'
              connections << ".#{profile.fetch(:boot_rom_do)}(boot_rom_do)"
              connections << ".#{profile.fetch(:boot_rom_addr)}(boot_rom_addr)"
            end
          end

          def boot_upload_always_block(profile:)
            return '' unless profile.fetch(:boot_mode) == :upload

            <<~UPLOAD
              always @(posedge clk_sys) begin
                if (reset) begin
                  boot_upload_active <= 1'b1;
                  boot_upload_phase <= 1'b0;
                  boot_upload_index <= 8'd0;
                  boot_upload_low_byte <= 8'd0;
                end else begin
                  if (boot_upload_active && !boot_upload_phase) begin
                    boot_upload_low_byte <= boot_rom_do;
                  end
                  if (boot_upload_active) begin
                    boot_upload_phase <= ~boot_upload_phase;
                  end
                  if (boot_upload_active && boot_upload_phase && boot_upload_index != 8'hFE) begin
                    boot_upload_index <= boot_upload_index + 8'd2;
                  end
                  if (boot_upload_active && boot_upload_phase && boot_upload_index == 8'hFE) begin
                    boot_upload_active <= 1'b0;
                  end
                end
              end
            UPLOAD
          end

          def write_gameboy_wrapper(path, profile:, use_speedcontrol: false, speedcontrol_module_name: 'speedcontrol')
            File.write(
              path,
              gameboy_wrapper_source(
                profile: profile,
                use_speedcontrol: use_speedcontrol,
                speedcontrol_module_name: speedcontrol_module_name
              )
            )
          end
        end
      end
    end
  end
end
