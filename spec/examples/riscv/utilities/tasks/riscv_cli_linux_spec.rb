# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tempfile'
require 'tmpdir'
load File.expand_path('../../../../../examples/riscv/bin/riscv', __dir__)

RSpec.describe RHDL::Examples::RISCV::CLI do
  def with_temp_binary(bytes)
    file = Tempfile.new(['riscv_cli', '.bin'])
    file.binmode
    file.write(bytes)
    file.flush
    yield file.path
  ensure
    file.close!
  end

  def build_fake_task_class(software_root: Dir.pwd)
    Class.new do
      class << self
        attr_accessor :last_instance
      end

      attr_reader :options, :load_linux_args, :load_xv6_args, :load_program_args, :pc_values, :ran

      define_method(:initialize) do |options|
        @options = options
        @pc_values = []
        self.class.last_instance = self
      end

      define_method(:software_path) do |path = nil|
        return software_root if path.nil? || path.empty?

        File.expand_path(path, software_root)
      end

      define_method(:load_linux) do |**kwargs|
        @load_linux_args = kwargs
      end

      define_method(:load_xv6) do |**kwargs|
        @load_xv6_args = kwargs
      end

      define_method(:load_program) do |path, base_addr:|
        @load_program_args = { path: path, base_addr: base_addr }
      end

      define_method(:set_pc) do |value|
        @pc_values << value
      end

      define_method(:run) do
        @ran = true
      end
    end
  end

  it 'parses linux options and invokes linux load path with overrides' do
    with_temp_binary("KERN") do |kernel_path|
      with_temp_binary("INIT") do |initramfs_path|
        with_temp_binary("DTB!") do |dtb_path|
          out = StringIO.new
          task_class = build_fake_task_class

          exit_code = described_class.run(
            [
              '--linux',
              '--kernel', kernel_path,
              '--initramfs', initramfs_path,
              '--dtb', dtb_path,
              '--kernel-addr', '0x80201000',
              '--initramfs-addr', '0x84002000',
              '--dtb-addr', '0x87f03000',
              '--pc', '0x80204000'
            ],
            out: out,
            task_class: task_class
          )

          instance = task_class.last_instance
          expect(exit_code).to eq(0)
          expect(out.string).to include('Info: forcing --io uart for linux mode.')
          expect(instance.options[:linux]).to eq(true)
          expect(instance.options[:io]).to eq(:uart)
          expect(instance.load_linux_args).to eq(
            kernel: kernel_path,
            initramfs: initramfs_path,
            dtb: dtb_path,
            kernel_addr: 0x8020_1000,
            initramfs_addr: 0x8400_2000,
            dtb_addr: 0x87F0_3000,
            pc: 0x8020_4000
          )
          expect(instance.ran).to eq(true)
        end
      end
    end
  end

  it 'defaults linux kernel and dtb paths when omitted' do
    Dir.mktmpdir('riscv_cli_linux_defaults') do |software_root|
      bin_dir = File.join(software_root, 'bin')
      Dir.mkdir(bin_dir)
      kernel_path = File.join(bin_dir, 'linux_kernel.bin')
      initramfs_path = File.join(bin_dir, 'linux_initramfs.cpio')
      dtb_path = File.join(bin_dir, 'rhdl_riscv_virt.dtb')
      File.binwrite(kernel_path, "KERN")
      File.binwrite(initramfs_path, "INIT")
      File.binwrite(dtb_path, "DTB!")

      out = StringIO.new
      task_class = build_fake_task_class(software_root: software_root)

      exit_code = described_class.run(
        ['--linux'],
        out: out,
        task_class: task_class
      )

      instance = task_class.last_instance
      expect(exit_code).to eq(0)
      expect(out.string).to include('Info: forcing --io uart for linux mode.')
      expect(instance.options[:linux]).to eq(true)
      expect(instance.options[:io]).to eq(:uart)
      expect(instance.options[:kernel]).to eq(kernel_path)
      expect(instance.options[:initramfs]).to eq(initramfs_path)
      expect(instance.options[:dtb]).to eq(dtb_path)
      expect(instance.load_linux_args).to eq(
        kernel: kernel_path,
        initramfs: initramfs_path,
        dtb: dtb_path
      )
      expect(instance.ran).to eq(true)
    end
  end

  it 'reports missing default linux initramfs file clearly' do
    Dir.mktmpdir('riscv_cli_linux_missing_initramfs') do |software_root|
      bin_dir = File.join(software_root, 'bin')
      Dir.mkdir(bin_dir)
      File.binwrite(File.join(bin_dir, 'linux_kernel.bin'), "KERN")
      File.binwrite(File.join(bin_dir, 'rhdl_riscv_virt.dtb'), "DTB!")
      default_initramfs_path = File.join(bin_dir, 'linux_initramfs.cpio')

      out = StringIO.new
      task_class = build_fake_task_class(software_root: software_root)

      exit_code = described_class.run(
        ['--linux'],
        out: out,
        task_class: task_class
      )

      expect(exit_code).to eq(1)
      expect(out.string).to include("Error: Linux initramfs not found: #{default_initramfs_path}")
    end
  end

  it 'reports missing default linux dtb file clearly' do
    Dir.mktmpdir('riscv_cli_linux_missing_dtb') do |software_root|
      bin_dir = File.join(software_root, 'bin')
      Dir.mkdir(bin_dir)
      File.binwrite(File.join(bin_dir, 'linux_kernel.bin'), "KERN")
      File.binwrite(File.join(bin_dir, 'linux_initramfs.cpio'), "INIT")
      default_dtb_path = File.join(bin_dir, 'rhdl_riscv_virt.dtb')

      out = StringIO.new
      task_class = build_fake_task_class(software_root: software_root)

      exit_code = described_class.run(
        ['--linux'],
        out: out,
        task_class: task_class
      )

      expect(exit_code).to eq(1)
      expect(out.string).to include("Error: Linux DTB not found: #{default_dtb_path}")
    end
  end

  it 'reports missing linux kernel file clearly' do
    out = StringIO.new
    task_class = build_fake_task_class

    exit_code = described_class.run(
      ['--linux', '--kernel', '/tmp/does/not/exist/linux.bin'],
      out: out,
      task_class: task_class
    )

    expect(exit_code).to eq(1)
    expect(out.string).to include('Error: Linux kernel not found: /tmp/does/not/exist/linux.bin')
  end

  it 'reports missing linux initramfs file clearly' do
    with_temp_binary("KERN") do |kernel_path|
      out = StringIO.new
      task_class = build_fake_task_class

      exit_code = described_class.run(
        ['--linux', '--kernel', kernel_path, '--initramfs', '/tmp/does/not/exist/initramfs.cpio'],
        out: out,
        task_class: task_class
      )

      expect(exit_code).to eq(1)
      expect(out.string).to include('Error: Linux initramfs not found: /tmp/does/not/exist/initramfs.cpio')
    end
  end

  it 'keeps xv6 mode behavior unchanged while forcing uart io' do
    with_temp_binary("XV6K") do |kernel_path|
      with_temp_binary("XV6F") do |fs_path|
        out = StringIO.new
        task_class = build_fake_task_class

        exit_code = described_class.run(
          ['--xv6', '--io', 'mmap', '--kernel', kernel_path, '--fs', fs_path],
          out: out,
          task_class: task_class
        )

        instance = task_class.last_instance
        expect(exit_code).to eq(0)
        expect(out.string).to include('Info: forcing --io uart for xv6 mode.')
        expect(instance.options[:xv6]).to eq(true)
        expect(instance.options[:io]).to eq(:uart)
        expect(instance.load_xv6_args).to eq(
          kernel: kernel_path,
          fs: fs_path,
          pc: 0x8000_0000
        )
        expect(instance.ran).to eq(true)
      end
    end
  end
end
