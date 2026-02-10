# frozen_string_literal: true

require 'fileutils'
require 'fiddle'
require 'rbconfig'

module RHDL
  module Codegen
    module Verilog
      # Backend manager for native Verilog simulators (Verilator today).
      # The API is backend-parameterized so additional backends (e.g. Icarus)
      # can be added without changing runner call sites.
      class VerilogSimulator
        DEFAULT_WARNING_FLAGS = %w[
          -Wno-fatal
          -Wno-WIDTHEXPAND
          -Wno-WIDTHTRUNC
          -Wno-UNOPTFLAT
          -Wno-PINMISSING
        ].freeze

        attr_reader :backend, :build_dir, :verilog_dir, :obj_dir
        attr_reader :library_basename, :top_module, :verilator_prefix
        attr_reader :cxx, :cflags, :x_assign, :x_initial

        def initialize(
          backend:,
          build_dir:,
          library_basename:,
          top_module: nil,
          verilator_prefix: nil,
          cxx: 'clang++',
          cflags: '-fPIC -O3 -march=native',
          x_assign: '0',
          x_initial: 'unique',
          extra_verilator_flags: []
        )
          @backend = backend.to_sym
          @build_dir = build_dir
          @verilog_dir = File.join(build_dir, 'verilog')
          @obj_dir = File.join(build_dir, 'obj_dir')
          @library_basename = library_basename
          @top_module = top_module
          @verilator_prefix = verilator_prefix
          @cxx = cxx
          @cflags = cflags
          @x_assign = x_assign
          @x_initial = x_initial
          @extra_verilator_flags = extra_verilator_flags
        end

        def ensure_backend_available!
          cmd = case backend
                when :verilator then 'verilator'
                when :iverilog then 'iverilog'
                else
                  raise ArgumentError, "Unsupported Verilog simulator backend: #{backend.inspect}"
                end
          return if command_available?(cmd)

          message = case backend
                    when :verilator
                      <<~MSG
                        Verilator not found in PATH.
                        Install Verilator:
                          Ubuntu/Debian: sudo apt-get install verilator
                          macOS: brew install verilator
                          Fedora: sudo dnf install verilator
                      MSG
                    when :iverilog
                      <<~MSG
                        Icarus Verilog not found in PATH.
                        Install Icarus Verilog:
                          Ubuntu/Debian: sudo apt-get install iverilog
                          macOS: brew install icarus-verilog
                          Fedora: sudo dnf install iverilog
                      MSG
                    end
          raise LoadError, message
        end

        def prepare_build_dirs!
          FileUtils.mkdir_p(verilog_dir)
          FileUtils.mkdir_p(obj_dir)
        end

        def write_file_if_changed(path, content)
          return false if File.exist?(path) && File.read(path) == content

          File.write(path, content)
          true
        end

        def shared_library_path
          File.join(obj_dir, "lib#{library_basename}.#{library_suffix}")
        end

        def compile_backend(verilog_file:, wrapper_file:, log_file: File.join(build_dir, 'build.log'))
          case backend
          when :verilator
            compile_verilator(verilog_file: verilog_file, wrapper_file: wrapper_file, log_file: log_file)
          when :iverilog
            raise NotImplementedError, 'Icarus backend is not implemented yet'
          else
            raise ArgumentError, "Unsupported Verilog simulator backend: #{backend.inspect}"
          end
        end

        def build_shared_library
          case backend
          when :verilator
            link_verilator_shared_library
          when :iverilog
            raise NotImplementedError, 'Icarus backend is not implemented yet'
          else
            raise ArgumentError, "Unsupported Verilog simulator backend: #{backend.inspect}"
          end
        end

        def load_library!(lib_path = shared_library_path)
          unless File.exist?(lib_path)
            raise LoadError, "Verilog simulator shared library not found: #{lib_path}"
          end
          Fiddle.dlopen(lib_path)
        end

        private

        def compile_verilator(verilog_file:, wrapper_file:, log_file:)
          lib_path = shared_library_path
          lib_name = File.basename(lib_path)
          makefile_name = "#{verilator_prefix}.mk"

          verilate_cmd = [
            'verilator',
            '--cc',
            '--top-module', top_module,
            '-O3',
            '--x-assign', x_assign,
            '--x-initial', x_initial,
            '--noassert',
            *DEFAULT_WARNING_FLAGS,
            '-CFLAGS', cflags,
            '-LDFLAGS', '-shared',
            '--Mdir', obj_dir,
            '--prefix', verilator_prefix,
            '-o', lib_name,
            wrapper_file,
            verilog_file,
            *@extra_verilator_flags
          ]

          File.open(log_file, 'w') do |log|
            Dir.chdir(verilog_dir) do
              result = system(*verilate_cmd, out: log, err: log)
              raise "Verilator compilation failed. See #{log_file} for details." unless result
            end

            Dir.chdir(obj_dir) do
              result = system('make', '-f', makefile_name, "CXX=#{cxx}", out: log, err: log)
              raise "Verilator make failed. See #{log_file} for details." unless result
            end
          end

          ensure_verilator_library_fresh
        end

        def ensure_verilator_library_fresh
          component_lib = File.join(obj_dir, "lib#{verilator_prefix}.a")
          verilated_lib = File.join(obj_dir, 'libverilated.a')
          newest_input = [component_lib, verilated_lib].filter_map { |p| File.exist?(p) ? File.mtime(p) : nil }.max
          lib_path = shared_library_path
          lib_mtime = File.exist?(lib_path) ? File.mtime(lib_path) : nil

          if lib_mtime.nil? || (!newest_input.nil? && lib_mtime < newest_input)
            link_verilator_shared_library
          end
        end

        def link_verilator_shared_library
          lib_path = shared_library_path
          component_lib = File.join(obj_dir, "lib#{verilator_prefix}.a")
          verilated_lib = File.join(obj_dir, 'libverilated.a')

          unless File.exist?(component_lib) && File.exist?(verilated_lib)
            raise "Verilator archives not found for linking in #{obj_dir}"
          end

          link_args = if RbConfig::CONFIG['host_os'] =~ /darwin/
                        [cxx, '-shared', '-dynamiclib', '-o', lib_path,
                         '-Wl,-all_load', component_lib, verilated_lib]
                      else
                        [cxx, '-shared', '-o', lib_path,
                         '-Wl,--whole-archive', component_lib, verilated_lib,
                         '-Wl,--no-whole-archive', '-latomic']
                      end

          raise "Failed to link Verilator shared library: #{lib_path}" unless system(*link_args)
        end

        def library_suffix
          case RbConfig::CONFIG['host_os']
          when /darwin/ then 'dylib'
          when /mswin|mingw/ then 'dll'
          else 'so'
          end
        end

        def command_available?(cmd)
          ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
            File.executable?(File.join(path, cmd))
          end
        end
      end
    end
  end
end
