# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for Apple II emulator and ROM tools
      class Apple2Task < Task
        def run
          if options[:clean]
            clean
          elsif options[:build]
            build_rom
          elsif options[:demo]
            run_demo
          elsif options[:appleiigo]
            run_appleiigo
          elsif options[:ink]
            run_ink
          else
            run_emulator
          end
        end

        # Build the mini monitor ROM
        def build_rom
          require File.join(Config.project_root, 'examples/mos6502/utilities/assembler')

          puts "Apple II ROM Assembler"
          puts '=' * 50
          puts

          ensure_dir(Config.rom_output_dir)

          asm_file = File.join(Config.roms_dir, 'mini_monitor.asm')
          raise "Assembly file not found: #{asm_file}" unless File.exist?(asm_file)

          source = File.read(asm_file)
          puts "Source: #{asm_file}"
          puts "Size: #{source.length} bytes"
          puts

          assembler = MOS6502::Assembler.new
          bytes = assembler.assemble(source, 0xF800)
          puts "Assembled: #{bytes.length} bytes"

          rom_size = 0x10000 - 0xF800
          bytes += [0xFF] * (rom_size - bytes.length) if bytes.length < rom_size

          rom_file = File.join(Config.rom_output_dir, 'mini_monitor.bin')
          File.binwrite(rom_file, bytes.pack('C*'))
          puts "Output: #{rom_file}"
          puts

          reset_lo = bytes[0xFFFC - 0xF800]
          reset_hi = bytes[0xFFFD - 0xF800]
          reset_vector = (reset_hi << 8) | reset_lo
          puts "Reset vector: $#{reset_vector.to_s(16).upcase.rjust(4, '0')}"
          puts
          puts "ROM built successfully!"

          # If --run was also specified, run the emulator
          if options[:run]
            puts
            puts "Starting emulator..."
            run_with_rom(rom_file, 'F800')
          end
        end

        # Clean ROM output files
        def clean
          if Dir.exist?(Config.rom_output_dir)
            FileUtils.rm_rf(Config.rom_output_dir)
            puts "Cleaned: #{Config.rom_output_dir}"
          end
        end

        # Run emulator in demo mode
        def run_demo
          exec_apple2_script('--demo')
        end

        # Run with AppleIIGo ROM
        def run_appleiigo
          rom_file = File.join(Config.roms_dir, 'appleiigo.rom')
          unless File.exist?(rom_file)
            raise "AppleIIGo ROM not found: #{rom_file}\n" \
                  "Download from: https://a2go.applearchives.com/roms/"
          end
          run_with_rom(rom_file, 'D000')
        end

        # Run with Ink TUI
        def run_ink
          $LOAD_PATH.unshift File.join(Config.apple2_dir, 'utilities')

          require File.join(Config.project_root, 'examples/mos6502/utilities/apple2_harness')
          require File.join(Config.project_root, 'examples/mos6502/utilities/apple2_ink_adapter')

          mode = options[:hdl] ? :hdl : :isa
          program_file = options[:program]

          if program_file
            raise "Program file not found: #{program_file}" unless File.exist?(program_file)

            puts "Starting Apple ][ Ink TUI with #{program_file}..."
            puts '=' * 50

            program = File.binread(program_file).bytes
            runner_class = options[:hdl] ? Apple2Harness::Runner : Apple2Harness::ISARunner
            runner = runner_class.new
            runner.load_ram(program, base_addr: 0x0800)
            runner.bus.write(0xFFFC, 0x00)
            runner.bus.write(0xFFFD, 0x08)
            runner.reset

            adapter = Apple2Harness::InkAdapter.new(runner, mode: mode)
            adapter.run
          elsif options[:hdl]
            puts "Starting Apple ][ Ink TUI (HDL mode)..."
            puts '=' * 50

            demo = create_demo_program
            runner = Apple2Harness::Runner.new
            runner.load_ram(demo, base_addr: 0x0800)
            runner.bus.write(0xFFFC, 0x00)
            runner.bus.write(0xFFFD, 0x08)
            runner.reset

            adapter = Apple2Harness::InkAdapter.new(runner, mode: :hdl)
            adapter.run
          else
            puts "Starting Apple ][ Ink TUI..."
            puts '=' * 50

            demo = create_demo_program
            runner = Apple2Harness::ISARunner.new
            runner.load_ram(demo, base_addr: 0x0800)
            runner.bus.write(0xFFFC, 0x00)
            runner.bus.write(0xFFFD, 0x08)
            runner.reset

            adapter = Apple2Harness::InkAdapter.new(runner, mode: :isa)
            adapter.run
          end
        end

        # Run the emulator with any provided options
        def run_emulator
          exec_apple2_script
        end

        # Create the Apple II demo program
        def create_demo_program
          asm = []

          cursor_lo = 0x00
          cursor_hi = 0x01

          # INIT: Set up cursor at start of text page
          asm << 0xA9 << 0x00        # LDA #$00
          asm << 0x85 << cursor_lo   # STA $00
          asm << 0xA9 << 0x04        # LDA #$04
          asm << 0x85 << cursor_hi   # STA $01

          # Clear text page
          asm << 0xA0 << 0x00        # LDY #$00
          asm << 0xA9 << 0xA0        # LDA #$A0 (space)
          asm << 0x91 << cursor_lo   # STA ($00),Y
          asm << 0xC8                # INY
          asm << 0xD0 << 0xFB        # BNE -5
          asm << 0xE6 << cursor_hi   # INC $01
          asm << 0xA5 << cursor_hi   # LDA $01
          asm << 0xC9 << 0x08        # CMP #$08
          asm << 0xD0 << 0xF3        # BNE -13

          # Reset cursor
          asm << 0xA9 << 0x00        # LDA #$00
          asm << 0x85 << cursor_lo   # STA $00
          asm << 0xA9 << 0x04        # LDA #$04
          asm << 0x85 << cursor_hi   # STA $01

          # Print "APPLE ][ READY" message
          message = "APPLE ][ READY\r"
          print_char = asm.length + message.length * 5 + 20

          message.each_byte do |b|
            b = b | 0x80
            asm << 0xA9 << b         # LDA #char
            asm << 0x20 << (print_char & 0xFF) << ((print_char >> 8) + 0x08)  # JSR
          end

          # Main loop
          main_loop = asm.length
          asm << 0xAD << 0x00 << 0xC0  # LDA $C000
          asm << 0x10 << 0xFB          # BPL -5
          asm << 0x8D << 0x10 << 0xC0  # STA $C010
          asm << 0x29 << 0x7F          # AND #$7F
          asm << 0xC9 << 0x0D          # CMP #$0D
          asm << 0xF0 << 0x08          # BEQ +8 (newline)
          asm << 0x09 << 0x80          # ORA #$80
          asm << 0x20 << (print_char & 0xFF) << ((print_char >> 8) + 0x08)  # JSR
          asm << 0x4C << (main_loop & 0xFF) << ((main_loop >> 8) + 0x08)  # JMP

          # Newline handler
          asm << 0x18                  # CLC
          asm << 0xA5 << cursor_lo     # LDA $00
          asm << 0x69 << 0x28          # ADC #40
          asm << 0x85 << cursor_lo     # STA $00
          asm << 0xA5 << cursor_hi     # LDA $01
          asm << 0x69 << 0x00          # ADC #0
          asm << 0x85 << cursor_hi     # STA $01
          asm << 0xC9 << 0x08          # CMP #$08
          asm << 0x90 << 0x04          # BCC +4
          asm << 0xA9 << 0x04          # LDA #$04
          asm << 0x85 << cursor_hi     # STA $01
          asm << 0x4C << (main_loop & 0xFF) << ((main_loop >> 8) + 0x08)  # JMP

          # Print char subroutine
          asm << 0xA0 << 0x00          # LDY #$00
          asm << 0x91 << cursor_lo     # STA ($00),Y
          asm << 0xE6 << cursor_lo     # INC $00
          asm << 0xD0 << 0x02          # BNE +2
          asm << 0xE6 << cursor_hi     # INC $01
          asm << 0x60                  # RTS

          asm
        end

        private

        def apple2_script
          File.join(Config.project_root, 'examples/mos6502/bin/apple2')
        end

        def run_with_rom(rom_file, rom_address)
          exec_args = [apple2_script, "-r", rom_file, "--rom-address", rom_address]
          add_common_args(exec_args)
          exec(*exec_args)
        end

        def exec_apple2_script(*extra_args)
          exec_args = [apple2_script]
          exec_args += ["-r", options[:rom]] if options[:rom]
          exec_args += ["-a", options[:address]] if options[:address]
          exec_args += ["--rom-address", options[:rom_address]] if options[:rom_address]
          add_common_args(exec_args)
          exec_args += extra_args
          exec_args += options[:remaining_args] if options[:remaining_args]
          exec(*exec_args)
        end

        def add_common_args(exec_args)
          exec_args << "-d" if options[:debug]
          exec_args << "-f" if options[:fast]
          exec_args += ["-s", options[:speed].to_s] if options[:speed]
          exec_args << "-g" if options[:green]
          exec_args += ["--disk", options[:disk]] if options[:disk]
          exec_args += ["--disk2", options[:disk2]] if options[:disk2]
        end
      end
    end
  end
end
