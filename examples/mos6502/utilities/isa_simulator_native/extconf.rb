# frozen_string_literal: true

# Build configuration for the native ISA simulator extension
# This file is used by `rake compile` to build the Rust extension

require 'fileutils'

# Determine the target library name based on platform
def library_name
  case RbConfig::CONFIG['host_os']
  when /darwin/
    'libisa_simulator_native.dylib'
  when /linux/
    'libisa_simulator_native.so'
  when /mswin|mingw/
    'isa_simulator_native.dll'
  else
    'libisa_simulator_native.so'
  end
end

def target_name
  case RbConfig::CONFIG['host_os']
  when /darwin/
    'isa_simulator_native.bundle'
  when /linux/
    'isa_simulator_native.so'
  when /mswin|mingw/
    'isa_simulator_native.dll'
  else
    'isa_simulator_native.so'
  end
end

def build_native_extension
  ext_dir = __dir__
  lib_dir = File.join(ext_dir, 'lib')

  puts "Building native ISA simulator extension..."
  puts "Extension directory: #{ext_dir}"

  # Create lib directory
  FileUtils.mkdir_p(lib_dir)

  # Build with cargo
  Dir.chdir(ext_dir) do
    system('cargo build --release') || raise("Cargo build failed")
  end

  # Copy the built library
  src_lib = File.join(ext_dir, 'target', 'release', library_name)
  dst_lib = File.join(lib_dir, target_name)

  unless File.exist?(src_lib)
    raise "Built library not found at #{src_lib}"
  end

  FileUtils.cp(src_lib, dst_lib)
  puts "Native extension built successfully: #{dst_lib}"
end

if __FILE__ == $0
  build_native_extension
end
