# frozen_string_literal: true

# Apple II emulator tasks

namespace :cli do
  namespace :apple2 do
    desc "[CLI] Assemble the mini monitor ROM"
    task :build do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(build: true).run
    end

    desc "[CLI] Run the Apple II emulator with the mini monitor"
    task run: :build do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(build: true, run: true).run
    end

    desc "[CLI] Run with AppleIIGo public domain ROM"
    task :run_appleiigo do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(appleiigo: true).run
    end

    desc "[CLI] Run with AppleIIGo ROM and disk image"
    task :boot_disk, [:disk] do |_, args|
      unless args[:disk]
        puts "Usage: rake cli:apple2:boot_disk[path/to/disk.dsk]"
        puts "Example: rake cli:apple2:boot_disk[examples/mos6502/software/disks/karateka.dsk]"
        exit 1
      end
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(appleiigo: true, disk: args[:disk]).run
    end

    desc "[CLI] Run the Apple II emulator demo (no ROM needed)"
    task :demo do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(demo: true).run
    end

    desc "[CLI] Run Apple II emulator with Ink TUI"
    task :ink do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(ink: true).run
    end

    desc "[CLI] Run Apple II emulator with Ink TUI (HDL mode)"
    task :ink_hdl do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(ink: true, hdl: true).run
    end

    desc "[CLI] Run Apple II with program file using Ink TUI"
    task :ink_run, [:program] do |_, args|
      unless args[:program]
        puts "Usage: rake cli:apple2:ink_run[path/to/program.bin]"
        exit 1
      end
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(ink: true, program: args[:program]).run
    end

    desc "[CLI] Clean ROM output files"
    task :clean do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(clean: true).run
    end
  end

  desc "[CLI] Build Apple II ROM (alias for cli:apple2:build)"
  task apple2: 'cli:apple2:build'
end
