# frozen_string_literal: true

require_relative 'run_task'

module RHDL
  module Examples
    module GameBoy
      module Tasks
        # Task for creating and running demo ROMs
      # Provides utilities for generating test ROMs for the Game Boy
      class DemoTask < Task
        # Nintendo logo bytes (required for boot verification)
        NINTENDO_LOGO = [
          0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
          0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
          0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
          0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
          0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
          0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
        ].freeze

        def run
          case options[:action]
          when :create
            create_demo_rom_file
          when :run
            run_demo
          when :info
            show_demo_info
          else
            run_demo
          end
        end

        # Create demo ROM and save to file
        def create_demo_rom_file
          output_path = options[:output] || 'demo.gb'
          rom = create_demo_rom(options[:title] || 'DEMO')

          File.binwrite(output_path, rom)
          puts "Created demo ROM: #{output_path} (#{rom.length} bytes)"
          output_path
        end

        # Run demo ROM in emulator
        def run_demo
          rom = create_demo_rom(options[:title] || 'RHDL TEST')

          run_options = options.merge(
            rom_bytes: rom,
            demo: false  # We're providing rom_bytes directly
          )

          RunTask.new(run_options).run
        end

        # Show information about demo ROM
        def show_demo_info
          rom = create_demo_rom(options[:title] || 'DEMO')
          bytes = rom.bytes

          puts "Demo ROM Information"
          puts "=" * 40
          puts "Size: #{rom.length} bytes (#{rom.length / 1024}KB)"
          puts "Title: #{bytes[0x134, 16].pack('C*').gsub(/\x00.*/, '').strip}"
          puts "Entry point: 0x#{bytes[0x102..0x103].pack('C*').unpack1('v').to_s(16).upcase}"
          puts "Cartridge type: ROM Only"
          puts "Header checksum: 0x#{bytes[0x14D].to_s(16).upcase.rjust(2, '0')}"

          # Verify header checksum
          checksum = 0
          (0x134...0x14D).each { |i| checksum = (checksum - bytes[i] - 1) & 0xFF }
          valid = bytes[0x14D] == checksum
          puts "Checksum valid: #{valid ? 'Yes' : 'No'}"
        end

        # Create a demo ROM with the specified title
        # @param title [String] ROM title (max 16 chars)
        # @param size_kb [Integer] ROM size in KB (default 32)
        # @return [String] ROM bytes as packed string
        def create_demo_rom(title = 'DEMO', size_kb: 32)
          rom = Array.new(size_kb * 1024, 0)

          # Nintendo logo at 0x104
          NINTENDO_LOGO.each_with_index { |b, i| rom[0x104 + i] = b }

          # Title at 0x134 (max 16 bytes)
          title_bytes = title[0, 16].bytes
          title_bytes.each_with_index { |b, i| rom[0x134 + i] = b }

          # Cartridge type (0x147) - ROM only
          rom[0x147] = 0x00

          # ROM size (0x148) - calculate bank count
          rom[0x148] = Math.log2(size_kb / 32).to_i

          # RAM size (0x149) - None
          rom[0x149] = 0x00

          # Header checksum at 0x14D
          checksum = 0
          (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
          rom[0x14D] = checksum

          # Entry point at 0x100 - NOP NOP JP 0x150
          rom[0x100] = 0x00  # NOP
          rom[0x101] = 0x00  # NOP
          rom[0x102] = 0xC3  # JP
          rom[0x103] = 0x50  # addr low
          # Note: 0x104 is overwritten by Nintendo logo

          # Main program at 0x150
          write_demo_program(rom, 0x150)

          rom.pack('C*')
        end

        # Create a minimal test ROM (smaller, for quick tests)
        # @return [String] ROM bytes as packed string
        def create_minimal_rom
          rom = Array.new(0x200, 0)

          # Entry point at 0x100 - jump to 0x150
          rom[0x100] = 0x00  # NOP
          rom[0x101] = 0xC3  # JP 0x0150
          rom[0x102] = 0x50
          rom[0x103] = 0x01

          # Nintendo logo
          NINTENDO_LOGO.each_with_index { |b, i| rom[0x104 + i] = b }

          # Title
          "TEST".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

          # Cartridge type - ROM only
          rom[0x147] = 0x00
          rom[0x148] = 0x00  # 32KB
          rom[0x149] = 0x00  # No RAM

          # Header checksum
          checksum = 0
          (0x134..0x14C).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
          rom[0x14D] = checksum

          # Simple infinite loop at 0x150
          rom[0x150] = 0x00  # NOP
          rom[0x151] = 0x18  # JR -2
          rom[0x152] = 0xFE

          rom.pack('C*')
        end

        private

        # Write demo program to ROM at specified address
        def write_demo_program(rom, start_addr)
          pc = start_addr

          # Turn on LCD: LD A, $91; LDH ($40), A
          rom[pc] = 0x3E; pc += 1  # LD A, imm
          rom[pc] = 0x91; pc += 1  # $91 = LCD enable + BG enable
          rom[pc] = 0xE0; pc += 1  # LDH (n), A
          rom[pc] = 0x40; pc += 1  # $FF40 = LCDC register

          # Infinite loop
          loop_addr = pc
          rom[pc] = 0x00; pc += 1  # NOP
          rom[pc] = 0x18; pc += 1  # JR offset
          rom[pc] = (loop_addr - pc - 1) & 0xFF  # Relative jump back
        end
        end
      end
    end
  end
end
