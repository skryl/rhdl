# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for MOS 6502 emulator
      class MOS6502Task < Task
        def run
          if options[:clean]
            clean
          elsif options[:build]
            build_rom
          elsif options[:demo]
            run_demo
          elsif options[:appleiigo]
            run_appleiigo
          elsif options[:karateka]
            run_karateka
          else
            run_emulator
          end
        end

        # Create a headless runner with the configured options
        # @return [MOS6502::HeadlessRunner] Initialized runner ready for use
        def create_runner
          require File.join(Config.project_root, 'examples/mos6502/utilities/headless_runner')

          mode = options[:mode] || :isa
          sim = options[:sim] || :jit

          runner = MOS6502::HeadlessRunner.new(mode: mode, sim: sim)

          # Load ROM if specified
          if options[:rom]
            rom_address = options[:rom_address] ? options[:rom_address].to_i(16) : 0xF800
            runner.load_rom(options[:rom], base_addr: rom_address)
          end

          # Load program if specified
          if options[:program]
            load_address = options[:address] ? options[:address].to_i(16) : 0x0800
            runner.load_program(options[:program], base_addr: load_address)
            entry = options[:entry] ? options[:entry].to_i(16) : load_address
            runner.setup_reset_vector(entry)
          end

          # Load disk if specified
          runner.load_disk(options[:disk], drive: 0) if options[:disk]
          runner.load_disk(options[:disk2], drive: 1) if options[:disk2]

          runner
        end

        # Create a headless runner with demo program loaded
        # @return [MOS6502::HeadlessRunner] Runner with demo program
        def create_demo_runner
          require File.join(Config.project_root, 'examples/mos6502/utilities/headless_runner')

          mode = options[:mode] || :isa
          sim = options[:sim] || :jit

          MOS6502::HeadlessRunner.with_demo(mode: mode, sim: sim)
        end

        # Build the mini monitor ROM
        def build_rom
          require File.join(Config.project_root, 'examples/mos6502/utilities/assembler')

          puts "MOS 6502 ROM Assembler"
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
          exec_script('--demo')
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

        # Run Karateka from pre-loaded memory dump
        def run_karateka
          exec_args = [mos6502_script, "--karateka"]
          add_common_args(exec_args)
          exec(*exec_args)
        end

        # Run the emulator with any provided options
        def run_emulator
          exec_script
        end

        private

        def mos6502_script
          File.join(Config.project_root, 'examples/mos6502/bin/mos6502')
        end

        def run_with_rom(rom_file, rom_address)
          exec_args = [mos6502_script, "-r", rom_file, "--rom-address", rom_address]
          add_common_args(exec_args)
          exec(*exec_args)
        end

        def exec_script(*extra_args)
          exec_args = [mos6502_script]
          exec_args += ["-r", options[:rom]] if options[:rom]
          exec_args += ["-a", options[:address]] if options[:address]
          exec_args += ["--rom-address", options[:rom_address]] if options[:rom_address]
          add_common_args(exec_args)
          exec_args += extra_args
          # Add positional argument (program file) if provided
          exec_args << options[:program] if options[:program]
          exec_args += options[:remaining_args] if options[:remaining_args]
          exec(*exec_args)
        end

        def add_common_args(exec_args)
          exec_args << "-d" if options[:debug]

          # mos6502 binary: --mode isa|hdl|netlist (default: isa), --sim interpret|jit|compile (default: jit)
          if options[:mode] && options[:mode] != :isa
            exec_args.push("-m", options[:mode].to_s)
          end
          if options[:sim] && options[:sim] != :jit
            exec_args.push("--sim", options[:sim].to_s)
          end

          exec_args.push("-s", options[:speed].to_s) if options[:speed]
          exec_args << "-g" if options[:green]
          exec_args << "-A" if options[:audio]
          exec_args << "-H" if options[:hires]
          exec_args << "-C" if options[:color]
          exec_args.push("--hires-width", options[:hires_width].to_s) if options[:hires_width]
          exec_args.push("--disk", options[:disk]) if options[:disk]
          exec_args.push("--disk2", options[:disk2]) if options[:disk2]
          exec_args.push("-b", options[:bin]) if options[:bin]
          exec_args.push("-e", options[:entry]) if options[:entry]
          exec_args << "--init-hires" if options[:init_hires]
          exec_args << "--no-audio" if options[:no_audio]
        end
      end
    end
  end
end
