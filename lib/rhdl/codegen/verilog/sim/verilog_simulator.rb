# frozen_string_literal: true

require 'fileutils'
require 'fiddle'
require 'rbconfig'

module RHDL
  module Codegen
  module Verilog
      # Backend manager for native Verilog simulation (Verilator).
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
        attr_reader :cxx, :cflags, :x_assign, :x_initial, :threads

        class << self
          def normalize_threads(value)
            count = value.to_i
            count > 1 ? count : 1
          end
        end

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
          extra_verilator_flags: [],
          threads: 1
        )
          @backend = backend.to_sym
          @threads = self.class.normalize_threads(threads)
          @build_dir = build_dir
          @verilog_dir = File.join(build_dir, 'verilog')
          @library_basename = threaded_library_basename(library_basename)
          @obj_dir = File.join(build_dir, 'obj_dir', sanitize_path_component(@library_basename))
          @top_module = top_module
          @verilator_prefix = verilator_prefix
          @cxx = cxx
          @cflags = cflags
          @x_assign = x_assign
          @x_initial = x_initial
          @extra_verilator_flags = threaded_verilator_flags(extra_verilator_flags)
        end

        def ensure_backend_available!
          cmd = case backend
                when :verilator then 'verilator'
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

        def compile_backend(verilog_file: nil, verilog_files: nil, wrapper_file:, log_file: File.join(build_dir, 'build.log'))
          with_build_lock do
            case backend
            when :verilator
              compile_verilator(
                verilog_file: verilog_file,
                verilog_files: verilog_files,
                wrapper_file: wrapper_file,
                log_file: log_file
              )
            else
              raise ArgumentError, "Unsupported Verilog simulator backend: #{backend.inspect}"
            end
          end
        end

        def build_shared_library
          case backend
          when :verilator
            link_verilator_shared_library
          else
            raise ArgumentError, "Unsupported Verilog simulator backend: #{backend.inspect}"
          end
        end

        def load_library!(lib_path = shared_library_path)
          unless File.exist?(lib_path)
            raise LoadError, "Verilog simulator shared library not found: #{lib_path}"
          end

          sign_darwin_shared_library(lib_path)
          Fiddle.dlopen(lib_path)
        rescue Fiddle::DLError
          raise unless RbConfig::CONFIG['host_os'] =~ /darwin/

          # Freshly linked dylibs can occasionally trip macOS library policy on
          # the first load even after an ad-hoc sign. Re-sign and retry once.
          sign_darwin_shared_library(lib_path)
          sleep 0.1
          Fiddle.dlopen(lib_path)
        end

        private

        def sanitize_path_component(value)
          value.to_s.gsub(/[^A-Za-z0-9_.-]/, '_')
        end

        def threaded_library_basename(base_name)
          return base_name.to_s unless backend == :verilator && threads > 1

          "#{base_name}_threads#{threads}"
        end

        def threaded_verilator_flags(flags)
          resolved = Array(flags).flatten.compact
          return resolved unless backend == :verilator && threads > 1

          resolved + ['--threads', threads.to_s]
        end

        def compile_verilator(verilog_file: nil, verilog_files: nil, wrapper_file:, log_file:)
          sources = Array(verilog_files || verilog_file).compact
          raise ArgumentError, 'No Verilog sources provided for Verilator compilation' if sources.empty?

          lib_path = shared_library_path
          lib_name = File.basename(lib_path)
          makefile_name = "#{verilator_prefix}.mk"
          wrapper_include_dir = File.dirname(File.expand_path(wrapper_file))
          verilator_cflags = [cflags, "-I#{wrapper_include_dir}"].join(' ')
          clean_verilator_obj_dir!

          verilate_cmd = [
            'verilator',
            '--cc',
            '--top-module', top_module,
            '-O3',
            '--x-assign', x_assign,
            '--x-initial', x_initial,
            '--noassert',
            *DEFAULT_WARNING_FLAGS,
            '-CFLAGS', verilator_cflags,
            '-LDFLAGS', '-shared',
            '--Mdir', obj_dir,
            '--prefix', verilator_prefix,
            '-o', lib_name,
            wrapper_file,
            *sources,
            *@extra_verilator_flags
          ]

          File.open(log_file, 'w') do |log|
            Dir.chdir(verilog_dir) do
              result = system(*verilate_cmd, out: log, err: log)
              raise "Verilator compilation failed. See #{log_file} for details." unless result
            end

            Dir.chdir(obj_dir) do
              result = system({ 'MAKEFLAGS' => '-j1' }, 'make', '-j1', '-f', makefile_name, "CXX=#{cxx}", out: log, err: log)
              raise "Verilator make failed. See #{log_file} for details." unless result
            end
          end

          ensure_verilator_library_fresh
        end

        def clean_verilator_obj_dir!
          Dir.glob(File.join(obj_dir, '*'), File::FNM_DOTMATCH).each do |path|
            basename = File.basename(path)
            next if ['.', '..'].include?(basename)

            FileUtils.rm_rf(path)
          end
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
                        hash_shim_obj = ensure_darwin_hash_memory_shim
                        [cxx, '-shared', '-dynamiclib', '-o', lib_path,
                         '-Wl,-all_load', component_lib, verilated_lib, hash_shim_obj]
                      else
                        [cxx, '-shared', '-o', lib_path,
                         '-Wl,--whole-archive', component_lib, verilated_lib,
                         '-Wl,--no-whole-archive', '-latomic']
                      end

          raise "Failed to link Verilator shared library: #{lib_path}" unless system(*link_args)

          sign_darwin_shared_library(lib_path)
        end

        def sign_darwin_shared_library(lib_path)
          return unless RbConfig::CONFIG['host_os'] =~ /darwin/
          return unless File.exist?(lib_path)
          return unless command_available?('codesign')

          system('codesign', '--force', '--sign', '-', '--timestamp=none', lib_path, out: File::NULL, err: File::NULL)
        end

        def ensure_darwin_hash_memory_shim
          src_path = File.join(obj_dir, 'rhdl_hash_memory_shim.cpp')
          obj_path = File.join(obj_dir, 'rhdl_hash_memory_shim.o')
          source = <<~CPP
            #include <cstddef>
            #include <cstdint>

            #if defined(__APPLE__) && defined(__aarch64__)
            namespace std {
            inline namespace __1 {
            size_t __hash_memory(const void* ptr, size_t len) {
              const auto* bytes = static_cast<const std::uint8_t*>(ptr);
              std::size_t hash = 1469598103934665603ull;
              for (std::size_t i = 0; i < len; ++i) {
                hash ^= static_cast<std::size_t>(bytes[i]);
                hash *= 1099511628211ull;
              }
              return hash;
            }
            } // namespace __1
            } // namespace std
            #endif
          CPP

          write_file_if_changed(src_path, source)
          if !File.exist?(obj_path) || File.mtime(obj_path) < File.mtime(src_path)
            result = system(cxx, '-std=c++17', '-fPIC', '-c', src_path, '-o', obj_path)
            raise "Failed to build Darwin hash shim object: #{obj_path}" unless result
          end

          obj_path
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

        def with_build_lock
          FileUtils.mkdir_p(build_dir)
          File.open(File.join(build_dir, '.verilator_build.lock'), File::RDWR | File::CREAT, 0o644) do |lock|
            lock.flock(File::LOCK_EX)
            yield
          ensure
            lock.flock(File::LOCK_UN) rescue nil
          end
        end
      end
    end
  end
end
