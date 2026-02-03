# frozen_string_literal: true

require_relative '../task'
require_relative '../config'
require 'rbconfig'

module RHDL
  module CLI
    module Tasks
      # Task for building and managing native Rust extensions
      class NativeTask < Task
        # Native extension definitions
        EXTENSIONS = {
          # MOS 6502 ISA simulator (behavioral)
          isa_simulator: {
            name: 'ISA Simulator',
            ext_dir: File.expand_path('examples/mos6502/utilities/simulators/isa_simulator_native', Config.project_root),
            crate_name: 'isa_simulator_native',
            load_path: 'examples/mos6502/utilities/simulators',
            check_const: 'MOS6502::NATIVE_AVAILABLE'
          },

          # Gate-level netlist simulators (netlist backend)
          netlist_interpreter: {
            name: 'Netlist Interpreter (Gate-Level)',
            ext_dir: File.expand_path('lib/rhdl/codegen/netlist/sim/netlist_interpreter', Config.project_root),
            crate_name: 'netlist_interpreter',
            load_path: 'lib/rhdl/codegen/netlist/sim/netlist_interpreter/lib',
            check_const: 'RHDL::Codegen::Netlist::NETLIST_INTERPRETER_AVAILABLE'
          },
          netlist_jit: {
            name: 'Netlist JIT (Gate-Level Cranelift)',
            ext_dir: File.expand_path('lib/rhdl/codegen/netlist/sim/netlist_jit', Config.project_root),
            crate_name: 'netlist_jit',
            load_path: 'lib/rhdl/codegen/netlist/sim/netlist_jit/lib',
            check_const: 'RHDL::Codegen::Netlist::NETLIST_JIT_AVAILABLE'
          },
          netlist_compiler: {
            name: 'Netlist Compiler (Gate-Level SIMD)',
            ext_dir: File.expand_path('lib/rhdl/codegen/netlist/sim/netlist_compiler', Config.project_root),
            crate_name: 'netlist_compiler',
            load_path: 'lib/rhdl/codegen/netlist/sim/netlist_compiler/lib',
            check_const: 'RHDL::Codegen::Netlist::NETLIST_COMPILER_AVAILABLE'
          },

          # IR-level simulators (Behavior IR backend)
          ir_interpreter: {
            name: 'IR Interpreter',
            ext_dir: File.expand_path('lib/rhdl/codegen/ir/sim/ir_interpreter', Config.project_root),
            crate_name: 'ir_interpreter',
            load_path: 'lib/rhdl/codegen/ir/sim/ir_interpreter/lib',
            check_const: 'RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE'
          },
          ir_jit: {
            name: 'IR JIT (Cranelift)',
            ext_dir: File.expand_path('lib/rhdl/codegen/ir/sim/ir_jit', Config.project_root),
            crate_name: 'ir_jit',
            load_path: 'lib/rhdl/codegen/ir/sim/ir_jit/lib',
            check_const: 'RHDL::Codegen::IR::IR_JIT_AVAILABLE'
          },
          ir_compiler: {
            name: 'IR Compiler (AOT)',
            ext_dir: File.expand_path('lib/rhdl/codegen/ir/sim/ir_compiler', Config.project_root),
            crate_name: 'ir_compiler',
            load_path: 'lib/rhdl/codegen/ir/sim/ir_compiler/lib',
            check_const: 'RHDL::Codegen::IR::IR_COMPILER_AVAILABLE'
          }
        }.freeze

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

        # Build all native Rust extensions
        def build
          check_cargo_available!

          target = options[:target]
          extensions = target ? { target.to_sym => EXTENSIONS[target.to_sym] } : EXTENSIONS

          extensions.each do |key, ext|
            next unless ext

            build_extension(key, ext)
          end

          puts
          puts '=' * 50
          puts "All native extensions built successfully!"
          puts '=' * 50
        end

        # Clean build artifacts for all extensions
        def clean
          target = options[:target]
          extensions = target ? { target.to_sym => EXTENSIONS[target.to_sym] } : EXTENSIONS

          extensions.each do |key, ext|
            next unless ext

            clean_extension(key, ext)
          end

          puts "Native extension build artifacts cleaned."
        end

        # Check if native extensions are available
        def check
          all_available = true

          EXTENSIONS.each do |key, ext|
            available = check_extension(key, ext)
            all_available &&= available
          end

          all_available
        end

        # Check if all native extensions are available (without output)
        def available?
          EXTENSIONS.all? { |key, ext| extension_available?(ext) }
        end

        private

        def check_cargo_available!
          unless command_available?('cargo')
            raise "Cargo (Rust) not found. Install Rust from https://rustup.rs/"
          end
        end

        def build_extension(key, ext)
          puts_header "Building #{ext[:name]}"

          lib_dir = File.join(ext[:ext_dir], 'lib')
          ensure_dir(lib_dir)

          Dir.chdir(ext[:ext_dir]) do
            unless system('cargo build --release')
              raise "Cargo build failed for #{ext[:name]}!"
            end
          end

          src_path = src_lib_path(ext)
          dst_path = dst_lib_path(ext)

          unless File.exist?(src_path)
            raise "Built library not found at #{src_path}"
          end

          FileUtils.cp(src_path, dst_path)

          puts "  Built: #{dst_path}"
        end

        def clean_extension(_key, ext)
          target_dir = File.join(ext[:ext_dir], 'target')
          lib_dir = File.join(ext[:ext_dir], 'lib')

          FileUtils.rm_rf(target_dir) if Dir.exist?(target_dir)
          FileUtils.rm_rf(lib_dir) if Dir.exist?(lib_dir)

          puts "  Cleaned: #{ext[:name]}"
        end

        def check_extension(key, ext)
          load_path = File.expand_path(ext[:load_path], Config.project_root)
          $LOAD_PATH.unshift(load_path) unless $LOAD_PATH.include?(load_path)

          begin
            require ext[:crate_name]
            const_parts = ext[:check_const].split('::')
            const_value = const_parts.reduce(Object) { |mod, name| mod.const_get(name) }

            if const_value
              puts "#{ext[:name]}: AVAILABLE"
              print_extension_info(key, ext) if key == :isa_simulator
              true
            else
              puts "#{ext[:name]}: NOT AVAILABLE"
              puts "  Run 'rake native:build' to build it."
              false
            end
          rescue LoadError, NameError => e
            puts "#{ext[:name]}: NOT AVAILABLE"
            puts "  Error: #{e.message}"
            puts "  Run 'rake native:build' to build it."
            false
          end
        end

        def extension_available?(ext)
          load_path = File.expand_path(ext[:load_path], Config.project_root)
          $LOAD_PATH.unshift(load_path) unless $LOAD_PATH.include?(load_path)

          require ext[:crate_name]
          const_parts = ext[:check_const].split('::')
          const_parts.reduce(Object) { |mod, name| mod.const_get(name) }
        rescue LoadError, NameError
          false
        end

        def print_extension_info(key, _ext)
          return unless key == :isa_simulator

          puts "  Creating test instance..."
          cpu = MOS6502::ISASimulatorNative.new(nil)
          puts "    PC: 0x#{cpu.pc.to_s(16).upcase}"
          puts "    A:  0x#{cpu.a.to_s(16).upcase}"
          puts "    X:  0x#{cpu.x.to_s(16).upcase}"
          puts "    Y:  0x#{cpu.y.to_s(16).upcase}"
          puts "    SP: 0x#{cpu.sp.to_s(16).upcase}"
          puts "    P:  0x#{cpu.p.to_s(16).upcase}"
        end

        def host_os
          RbConfig::CONFIG['host_os']
        end

        def src_lib_name(ext)
          case host_os
          when /darwin/ then "lib#{ext[:crate_name]}.dylib"
          when /linux/ then "lib#{ext[:crate_name]}.so"
          when /mswin|mingw/ then "#{ext[:crate_name]}.dll"
          else "lib#{ext[:crate_name]}.so"
          end
        end

        def dst_lib_name(ext)
          case host_os
          when /darwin/ then "#{ext[:crate_name]}.dylib"
          when /linux/ then "#{ext[:crate_name]}.so"
          when /mswin|mingw/ then "#{ext[:crate_name]}.dll"
          else "#{ext[:crate_name]}.so"
          end
        end

        def src_lib_path(ext)
          File.join(ext[:ext_dir], 'target', 'release', src_lib_name(ext))
        end

        def dst_lib_path(ext)
          File.join(ext[:ext_dir], 'lib', dst_lib_name(ext))
        end
      end
    end
  end
end
