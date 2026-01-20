# frozen_string_literal: true

# Native extension tasks

namespace :native do
  desc "Build the native ISA simulator Rust extension"
  task :build do
    ext_dir = File.expand_path('examples/mos6502/utilities/isa_simulator_native', RHDL_ROOT)
    lib_dir = File.join(ext_dir, 'lib')

    puts "Building native ISA simulator..."
    puts "=" * 50

    # Check for Rust/Cargo
    unless system('cargo --version > /dev/null 2>&1')
      abort "Error: Cargo (Rust) not found. Install Rust from https://rustup.rs/"
    end

    # Create lib directory
    require 'fileutils'
    FileUtils.mkdir_p(lib_dir)

    # Build with cargo
    Dir.chdir(ext_dir) do
      unless system('cargo build --release')
        abort "Cargo build failed!"
      end
    end

    # Determine library names based on platform
    host_os = RbConfig::CONFIG['host_os']
    src_name = case host_os
               when /darwin/ then 'libisa_simulator_native.dylib'
               when /linux/ then 'libisa_simulator_native.so'
               when /mswin|mingw/ then 'isa_simulator_native.dll'
               else 'libisa_simulator_native.so'
               end

    dst_name = case host_os
               when /darwin/ then 'isa_simulator_native.bundle'
               when /linux/ then 'isa_simulator_native.so'
               when /mswin|mingw/ then 'isa_simulator_native.dll'
               else 'isa_simulator_native.so'
               end

    src_lib = File.join(ext_dir, 'target', 'release', src_name)
    dst_lib = File.join(lib_dir, dst_name)

    unless File.exist?(src_lib)
      abort "Built library not found at #{src_lib}"
    end

    FileUtils.cp(src_lib, dst_lib)

    puts
    puts "Native ISA simulator built successfully!"
    puts "Library: #{dst_lib}"
    puts "=" * 50
  end

  desc "Clean native extension build artifacts"
  task :clean do
    ext_dir = File.expand_path('examples/mos6502/utilities/isa_simulator_native', RHDL_ROOT)
    target_dir = File.join(ext_dir, 'target')
    lib_dir = File.join(ext_dir, 'lib')

    require 'fileutils'
    FileUtils.rm_rf(target_dir) if Dir.exist?(target_dir)
    FileUtils.rm_rf(lib_dir) if Dir.exist?(lib_dir)

    puts "Native extension build artifacts cleaned."
  end

  desc "Check if native extension is available"
  task :check do
    $LOAD_PATH.unshift File.expand_path('examples/mos6502/utilities', RHDL_ROOT)

    begin
      require 'isa_simulator_native'
      if MOS6502::NATIVE_AVAILABLE
        puts "Native ISA simulator: AVAILABLE"
        puts "Creating test instance..."
        cpu = MOS6502::ISASimulatorNative.new(nil)
        puts "  PC: 0x#{cpu.pc.to_s(16).upcase}"
        puts "  A:  0x#{cpu.a.to_s(16).upcase}"
        puts "  X:  0x#{cpu.x.to_s(16).upcase}"
        puts "  Y:  0x#{cpu.y.to_s(16).upcase}"
        puts "  SP: 0x#{cpu.sp.to_s(16).upcase}"
        puts "  P:  0x#{cpu.p.to_s(16).upcase}"
        puts "Native extension working correctly!"
      else
        puts "Native ISA simulator: NOT AVAILABLE"
        puts "Run 'rake native:build' to build it."
      end
    rescue LoadError => e
      puts "Native ISA simulator: NOT AVAILABLE"
      puts "Error: #{e.message}"
      puts "Run 'rake native:build' to build it."
    end
  end
end

desc "Build native ISA simulator (alias for native:build)"
task native: 'native:build'
