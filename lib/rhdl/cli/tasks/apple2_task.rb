# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for Apple II HDL emulator
      class Apple2Task < Task
        def run
          if options[:demo]
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
        # @return [RHDL::Apple2::HeadlessRunner] Initialized runner ready for use
        def create_runner
          require File.join(Config.project_root, 'examples/apple2/utilities/headless_runner')

          mode = options[:mode] || :hdl
          sim = options[:sim] || :ruby
          sub_cycles = options[:sub_cycles] || 14

          runner = RHDL::Apple2::HeadlessRunner.new(mode: mode, sim: sim, sub_cycles: sub_cycles)

          # Load ROM if specified
          runner.load_rom(options[:rom]) if options[:rom]

          # Load program if specified
          if options[:program]
            load_address = options[:address] ? options[:address].to_i(16) : 0x0800
            runner.load_program(options[:program], base_addr: load_address)
            runner.setup_reset_vector(load_address)
          end

          # Load memory dump if specified
          if options[:memdump]
            pc = options[:pc] ? options[:pc].to_i(16) : 0x0800
            runner.load_memdump(options[:memdump], pc: pc, use_appleiigo: options[:appleiigo])
          end

          # Load disk if specified
          runner.load_disk(options[:disk]) if options[:disk]

          runner
        end

        # Create a headless runner with demo program loaded
        # @return [RHDL::Apple2::HeadlessRunner] Runner with demo program
        def create_demo_runner
          require File.join(Config.project_root, 'examples/apple2/utilities/headless_runner')

          mode = options[:mode] || :hdl
          sim = options[:sim] || :ruby
          sub_cycles = options[:sub_cycles] || 14

          RHDL::Apple2::HeadlessRunner.with_demo(mode: mode, sim: sim, sub_cycles: sub_cycles)
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
          run_with_rom(rom_file)
        end

        # Run Karateka from pre-loaded memory dump
        def run_karateka
          exec_args = [apple2_script, "--karateka"]
          add_common_args(exec_args)
          exec(*exec_args)
        end

        # Run the emulator with any provided options
        def run_emulator
          exec_script
        end

        private

        def apple2_script
          File.join(Config.project_root, 'examples/apple2/bin/apple2')
        end

        def run_with_rom(rom_file)
          exec_args = [apple2_script, "-r", rom_file]
          add_common_args(exec_args)
          exec(*exec_args)
        end

        def exec_script(*extra_args)
          exec_args = [apple2_script]
          exec_args += ["-r", options[:rom]] if options[:rom]
          exec_args += ["-a", options[:address]] if options[:address]
          add_common_args(exec_args)
          exec_args += extra_args
          # Add positional argument (program file) if provided
          exec_args << options[:program] if options[:program]
          exec_args += options[:remaining_args] if options[:remaining_args]
          exec(*exec_args)
        end

        def add_common_args(exec_args)
          exec_args << "-d" if options[:debug]

          # apple2 binary: --mode hdl|netlist|verilog (default: hdl), --sim ruby|interpret|jit|compile (default: ruby)
          if options[:mode] && options[:mode] != :hdl
            exec_args.push("-m", options[:mode].to_s)
          end
          if options[:sim] && options[:sim] != :ruby
            exec_args.push("--sim", options[:sim].to_s)
          end

          exec_args.push("-s", options[:speed].to_s) if options[:speed]
          exec_args << "-g" if options[:green]
          exec_args << "-A" if options[:audio]
          exec_args << "-H" if options[:hires]
          exec_args << "-C" if options[:color]
          exec_args.push("--hires-width", options[:hires_width].to_s) if options[:hires_width]
          exec_args.push("--memdump", options[:memdump]) if options[:memdump]
          exec_args.push("--pc", options[:pc]) if options[:pc]
          exec_args.push("--disk", options[:disk]) if options[:disk]
          # Sub-cycles: 14=full accuracy, 7=~2x speed, 2=~7x speed (compile backend only)
          exec_args.push("--sub-cycles", options[:sub_cycles].to_s) if options[:sub_cycles]
        end
      end
    end
  end
end
