# frozen_string_literal: true

require_relative '../task'
require_relative '../config'
require 'rbconfig'

module RHDL
  module CLI
    module Tasks
      # Task for building and managing native Rust extensions
      class NativeTask < Task
        EXT_DIR = File.expand_path('examples/mos6502/utilities/isa_simulator_native', Config.project_root)
        LIB_DIR = File.join(EXT_DIR, 'lib')
        TARGET_DIR = File.join(EXT_DIR, 'target')

        def run
          if options[:build]
            build
          elsif options[:clean]
            clean
          elsif options[:check]
            check
          else
            build
          end
        end

        # Build the native Rust extension
        def build
          puts_header "Building native ISA simulator"

          check_cargo_available!
          ensure_dir(LIB_DIR)
          run_cargo_build!
          copy_library!

          puts
          puts "Native ISA simulator built successfully!"
          puts "Library: #{dst_lib_path}"
          puts '=' * 50
        end

        # Clean build artifacts
        def clean
          FileUtils.rm_rf(TARGET_DIR) if Dir.exist?(TARGET_DIR)
          FileUtils.rm_rf(LIB_DIR) if Dir.exist?(LIB_DIR)
          puts "Native extension build artifacts cleaned."
        end

        # Check if native extension is available
        def check
          $LOAD_PATH.unshift File.expand_path('examples/mos6502/utilities', Config.project_root)

          begin
            require 'isa_simulator_native'
            if defined?(MOS6502::NATIVE_AVAILABLE) && MOS6502::NATIVE_AVAILABLE
              puts "Native ISA simulator: AVAILABLE"
              print_cpu_status
              puts "Native extension working correctly!"
              true
            else
              puts "Native ISA simulator: NOT AVAILABLE"
              puts "Run 'rake native:build' to build it."
              false
            end
          rescue LoadError => e
            puts "Native ISA simulator: NOT AVAILABLE"
            puts "Error: #{e.message}"
            puts "Run 'rake native:build' to build it."
            false
          end
        end

        # Check if native extension is available (without output)
        def available?
          $LOAD_PATH.unshift File.expand_path('examples/mos6502/utilities', Config.project_root)
          require 'isa_simulator_native'
          defined?(MOS6502::NATIVE_AVAILABLE) && MOS6502::NATIVE_AVAILABLE
        rescue LoadError
          false
        end

        private

        def check_cargo_available!
          unless command_available?('cargo')
            raise "Cargo (Rust) not found. Install Rust from https://rustup.rs/"
          end
        end

        def run_cargo_build!
          Dir.chdir(EXT_DIR) do
            unless system('cargo build --release')
              raise "Cargo build failed!"
            end
          end
        end

        def copy_library!
          unless File.exist?(src_lib_path)
            raise "Built library not found at #{src_lib_path}"
          end
          FileUtils.cp(src_lib_path, dst_lib_path)
        end

        def print_cpu_status
          puts "Creating test instance..."
          cpu = MOS6502::ISASimulatorNative.new(nil)
          puts "  PC: 0x#{cpu.pc.to_s(16).upcase}"
          puts "  A:  0x#{cpu.a.to_s(16).upcase}"
          puts "  X:  0x#{cpu.x.to_s(16).upcase}"
          puts "  Y:  0x#{cpu.y.to_s(16).upcase}"
          puts "  SP: 0x#{cpu.sp.to_s(16).upcase}"
          puts "  P:  0x#{cpu.p.to_s(16).upcase}"
        end

        def host_os
          RbConfig::CONFIG['host_os']
        end

        def src_lib_name
          case host_os
          when /darwin/ then 'libisa_simulator_native.dylib'
          when /linux/ then 'libisa_simulator_native.so'
          when /mswin|mingw/ then 'isa_simulator_native.dll'
          else 'libisa_simulator_native.so'
          end
        end

        def dst_lib_name
          case host_os
          when /darwin/ then 'isa_simulator_native.bundle'
          when /linux/ then 'isa_simulator_native.so'
          when /mswin|mingw/ then 'isa_simulator_native.dll'
          else 'isa_simulator_native.so'
          end
        end

        def src_lib_path
          File.join(EXT_DIR, 'target', 'release', src_lib_name)
        end

        def dst_lib_path
          File.join(LIB_DIR, dst_lib_name)
        end
      end
    end
  end
end
