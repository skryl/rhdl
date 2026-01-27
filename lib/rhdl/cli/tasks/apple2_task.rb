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
          exec_args += options[:remaining_args] if options[:remaining_args]
          exec(*exec_args)
        end

        def add_common_args(exec_args)
          exec_args << "-d" if options[:debug]

          # apple2 binary: --mode hdl|netlist (default: hdl), --sim ruby|interpret|jit|compile (default: ruby)
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
          exec_args.push("--hires-width", options[:hires_width].to_s) if options[:hires_width]
          exec_args.push("--disk", options[:disk]) if options[:disk]
          # Sub-cycles: 14=full accuracy, 7=~2x speed, 2=~7x speed (compile backend only)
          exec_args.push("--sub-cycles", options[:sub_cycles].to_s) if options[:sub_cycles]
        end
      end
    end
  end
end
