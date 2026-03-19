# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

require_relative '../../../../examples/gameboy/utilities/cli'

RSpec.describe RHDL::Examples::GameBoy::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  describe '.run' do
    it 'shows import-specific help' do
      status = described_class.run(%w[import --help], out: stdout, err: stderr)

      expect(status).to eq(0)
      expect(stderr.string).to eq('')
      expect(stdout.string).to include('Usage: bin/gb import [options]')
      expect(stdout.string).to include('--out DIR')
      expect(stdout.string).to include('--workspace DIR')
      expect(stdout.string).to include('--strategy STRATEGY')
      expect(stdout.string).to include('--[no-]keep-structure')
      expect(stdout.string).to include('--keep-workspace')
      expect(stdout.string).to include('--[no-]clean')
      expect(stdout.string).to include('--[no-]auto-stub-modules')
      expect(stdout.string).to include('--[no-]strict')
    end

    it 'shows emulator options for imported staged Verilog runs' do
      status = described_class.run(%w[--help], out: stdout, err: stderr)

      expect(status).to eq(0)
      expect(stderr.string).to eq('')
      expect(stdout.string).to include('--source DIR')
      expect(stdout.string).to include(RHDL::Examples::GameBoy::CLI::DEFAULT_SOURCE_DIR)
      expect(stdout.string).to include('--top NAME')
      expect(stdout.string).to include('--use-staged-source')
      expect(stdout.string).to include('--use-normalized-source')
      expect(stdout.string).to include('--use-rhdl-source')
      expect(stdout.string).to include('--[no-]debug')
      expect(stdout.string).to include('Cycles per frame (default: 1000)')
      expect(stdout.string).not_to include('--jit')
      expect(stdout.string).to include('Simulation mode: ir (default), ruby, verilog (Verilator RTL), circt (ARC)')
      expect(stdout.string).to include('Simulator backend: ruby, interpret, jit, compile (default: compile)')
      expect(stdout.string).not_to include('circt/arcilator')
    end

    it 'rejects the removed arcilator CLI mode alias' do
      status = described_class.run(%w[--mode arcilator --demo --headless --cycles 1], out: stdout, err: stderr)

      expect(status).to eq(1)
      expect(stderr.string).to include('invalid argument: --mode arcilator')
    end

    it 'shows help and requires --out before invoking the importer' do
      result_class = Struct.new(:success, :diagnostics, :output_dir, :files_written, :report_path, keyword_init: true) do
        def success?
          !!success
        end
      end

      fake_importer_class = Class.new do
        class << self
          attr_accessor :last_kwargs
        end

        def initialize(**kwargs)
          self.class.last_kwargs = kwargs
        end

        def run
          self.class.const_get(:RESULT_CLASS).new(
            success: true,
            diagnostics: [],
            output_dir: '/tmp/gameboy_import',
            files_written: ['/tmp/gameboy_import/gb.rb'],
            report_path: '/tmp/gameboy_import/import_report.json'
          )
        end
      end
      fake_importer_class.const_set(:RESULT_CLASS, result_class)

      status = described_class.run(['import'], out: stdout, err: stderr, importer_class: fake_importer_class)

      expect(status).to eq(1)
      expect(stdout.string).to eq('')
      expect(stderr.string).to include('Usage: bin/gb import [options]')
      expect(stderr.string).to include('Error: --out is required to run import.')
      expect(fake_importer_class.last_kwargs).to be_nil
    end

    it 'passes import options through to the importer' do
      result_class = Struct.new(:success, :diagnostics, :output_dir, :files_written, :report_path, keyword_init: true) do
        def success?
          !!success
        end
      end

      fake_importer_class = Class.new do
        class << self
          attr_accessor :last_kwargs
        end

        def initialize(**kwargs)
          self.class.last_kwargs = kwargs
        end

        def run
          self.class.const_get(:RESULT_CLASS).new(
            success: true,
            diagnostics: [],
            output_dir: '/tmp/custom_gameboy_import',
            files_written: [],
            report_path: '/tmp/custom_gameboy_import/import_report.json'
          )
        end
      end
      fake_importer_class.const_set(:RESULT_CLASS, result_class)

      status = described_class.run(
        [
          'import',
          '--out', 'tmp/gameboy_out',
          '--workspace', 'tmp/gameboy_ws',
          '--no-clean',
          '--no-strict',
          '--qip', 'examples/gameboy/reference/files.qip',
          '--top-file', 'examples/gameboy/reference/rtl/gb.v',
          '--top', 'gb_top',
          '--strategy', 'mixed',
          '--no-keep-structure',
          '--auto-stub-modules',
          '--reference-root', 'examples/gameboy/reference',
          '--keep-workspace'
        ],
        out: stdout,
        err: stderr,
        importer_class: fake_importer_class
      )

      expect(status).to eq(0)
      expect(stderr.string).to eq('')
      expect(fake_importer_class.last_kwargs[:output_dir]).to eq(File.expand_path('tmp/gameboy_out', Dir.pwd))
      expect(fake_importer_class.last_kwargs[:workspace_dir]).to eq(File.expand_path('tmp/gameboy_ws', Dir.pwd))
      expect(fake_importer_class.last_kwargs[:clean_output]).to eq(false)
      expect(fake_importer_class.last_kwargs[:strict]).to eq(false)
      expect(fake_importer_class.last_kwargs[:import_strategy]).to eq(:mixed)
      expect(fake_importer_class.last_kwargs[:maintain_directory_structure]).to eq(false)
      expect(fake_importer_class.last_kwargs[:auto_stub_modules]).to eq(true)
      expect(fake_importer_class.last_kwargs[:qip_path]).to eq(File.expand_path('examples/gameboy/reference/files.qip', Dir.pwd))
      expect(fake_importer_class.last_kwargs[:top_file]).to eq(File.expand_path('examples/gameboy/reference/rtl/gb.v', Dir.pwd))
      expect(fake_importer_class.last_kwargs[:top]).to eq('gb_top')
      expect(fake_importer_class.last_kwargs[:reference_root]).to eq(File.expand_path('examples/gameboy/reference', Dir.pwd))
      expect(fake_importer_class.last_kwargs[:keep_workspace]).to eq(true)
    end

    it 'can explicitly disable importer auto stubs' do
      result_class = Struct.new(:success, :diagnostics, :output_dir, :files_written, :report_path, keyword_init: true) do
        def success?
          !!success
        end
      end

      fake_importer_class = Class.new do
        class << self
          attr_accessor :last_kwargs
        end

        def initialize(**kwargs)
          self.class.last_kwargs = kwargs
        end

        def run
          self.class.const_get(:RESULT_CLASS).new(
            success: true,
            diagnostics: [],
            output_dir: '/tmp/custom_gameboy_import',
            files_written: [],
            report_path: '/tmp/custom_gameboy_import/import_report.json'
          )
        end
      end
      fake_importer_class.const_set(:RESULT_CLASS, result_class)

      status = described_class.run(
        %w[import --out tmp/gameboy_import --no-auto-stub-modules],
        out: stdout,
        err: stderr,
        importer_class: fake_importer_class
      )

      expect(status).to eq(0)
      expect(fake_importer_class.last_kwargs[:auto_stub_modules]).to eq(false)
    end

    it 'prints diagnostics and exits non-zero when import fails' do
      result_class = Struct.new(:success, :diagnostics, :output_dir, :files_written, :report_path, keyword_init: true) do
        def success?
          !!success
        end
      end

      fake_importer_class = Class.new do
        def initialize(**_kwargs); end

        def run
          self.class.const_get(:RESULT_CLASS).new(
            success: false,
            diagnostics: ['missing ghdl', 'missing circt-verilog'],
            output_dir: '/tmp/gameboy_import',
            files_written: [],
            report_path: nil
          )
        end
      end
      fake_importer_class.const_set(:RESULT_CLASS, result_class)

      status = described_class.run(['import', '--out', '/tmp/gameboy_import'], out: stdout, err: stderr, importer_class: fake_importer_class)

      expect(status).to eq(1)
      expect(stderr.string).to include('missing ghdl')
      expect(stderr.string).to include('missing circt-verilog')
    end

    it 'passes imported runner options through for emulator runs' do
      fake_run_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
        end

        def run
          { pc: 0x1234, a: 0x56, cycles: 7 }
        end
      end

      status = described_class.run(
        %w[--mode verilog --source examples/gameboy/import --top Gameboy --use-staged-source --pop --headless --cycles 7],
        out: stdout,
        err: stderr,
        run_task_class: fake_run_task_class
      )

      expect(status).to eq(0)
      expect(fake_run_task_class.last_options[:source_dir]).to eq(File.expand_path('examples/gameboy/import', Dir.pwd))
      expect(fake_run_task_class.last_options[:top]).to eq('Gameboy')
      expect(fake_run_task_class.last_options[:use_staged_source]).to eq(true)
    end

    it 'defaults emulator runs to the Gameboy wrapper top' do
      fake_run_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
        end

        def run
          { pc: 0x1234, a: 0x56, cycles: 7 }
        end
      end

      status = described_class.run(
        %w[--mode circt --sim jit --source examples/gameboy/import --pop --headless --cycles 7],
        out: stdout,
        err: stderr,
        run_task_class: fake_run_task_class
      )

      expect(status).to eq(0)
      expect(fake_run_task_class.last_options[:top]).to eq('Gameboy')
      expect(fake_run_task_class.last_options[:sim]).to eq(:jit)
      expect(fake_run_task_class.last_options[:use_staged_source]).to eq(true)
      expect(fake_run_task_class.last_options[:use_normalized_source]).to eq(false)
      expect(fake_run_task_class.last_options[:use_rhdl_source]).to eq(false)
    end

    it 'passes normalized imported-source selection through for runtime backends' do
      fake_run_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
        end

        def run
          { pc: 0x1234, a: 0x56, cycles: 7 }
        end
      end

      status = described_class.run(
        %w[--mode circt --sim jit --source examples/gameboy/import --use-normalized-source --pop --headless --cycles 7],
        out: stdout,
        err: stderr,
        run_task_class: fake_run_task_class
      )

      expect(status).to eq(0)
      expect(fake_run_task_class.last_options[:use_staged_source]).to eq(false)
      expect(fake_run_task_class.last_options[:use_normalized_source]).to eq(true)
      expect(fake_run_task_class.last_options[:use_rhdl_source]).to eq(false)
    end

    it 'passes rhdl source selection through for runtime backends' do
      fake_run_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
        end

        def run
          { pc: 0x1234, a: 0x56, cycles: 7 }
        end
      end

      status = described_class.run(
        %w[--mode circt --sim jit --source examples/gameboy/import --use-rhdl-source --pop --headless --cycles 7],
        out: stdout,
        err: stderr,
        run_task_class: fake_run_task_class
      )

      expect(status).to eq(0)
      expect(fake_run_task_class.last_options[:use_staged_source]).to eq(false)
      expect(fake_run_task_class.last_options[:use_normalized_source]).to eq(false)
      expect(fake_run_task_class.last_options[:use_rhdl_source]).to eq(true)
    end

    it 'defaults debug on and allows --no-debug' do
      fake_run_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
        end

        def run
          { pc: 0x1234, a: 0x56, cycles: 7 }
        end
      end

      status = described_class.run(
        %w[--mode verilog --source examples/gameboy/import --pop --headless --cycles 7],
        out: stdout,
        err: stderr,
        run_task_class: fake_run_task_class
      )

      expect(status).to eq(0)
      expect(fake_run_task_class.last_options[:debug]).to eq(true)

      status = described_class.run(
        %w[--mode verilog --source examples/gameboy/import --no-debug --pop --headless --cycles 7],
        out: stdout,
        err: stderr,
        run_task_class: fake_run_task_class
      )

      expect(status).to eq(0)
      expect(fake_run_task_class.last_options[:debug]).to eq(false)
    end

    it 'defaults emulator runs to ir/compile when mode and sim are omitted' do
      fake_run_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
        end

        def run
          { pc: 0x1234, a: 0x56, cycles: 7 }
        end
      end

      status = described_class.run(
        %w[--demo --headless --cycles 7],
        out: stdout,
        err: stderr,
        run_task_class: fake_run_task_class
      )

      expect(status).to eq(0)
      expect(fake_run_task_class.last_options[:mode]).to eq(:ir)
      expect(fake_run_task_class.last_options[:sim]).to eq(:compile)
      expect(fake_run_task_class.last_options[:speed]).to eq(1000)
      expect(fake_run_task_class.last_options[:source_dir]).to eq(RHDL::Examples::GameBoy::CLI::DEFAULT_SOURCE_DIR)
    end

    it 'fails when imported-artifact-dependent options are used without .mixed_import' do
      Dir.mktmpdir('rhdl_gameboy_source_dir_missing_mixed') do |dir|
        File.write(File.join(dir, 'import_report.json'), '{}')

        status = described_class.run(
          ['--mode', 'verilog', '--source', dir, '--use-staged-source', '--demo', '--headless', '--cycles', '1'],
          out: stdout,
          err: stderr
        )

        expect(status).to eq(1)
        expect(stderr.string).to include('.mixed_import')
      end
    end

    it 'fails verilog mode by default against the handwritten source tree' do
      status = described_class.run(
        %w[--mode verilog --demo --headless --cycles 1],
        out: stdout,
        err: stderr
      )

      expect(status).to eq(1)
      expect(stderr.string).to include('.mixed_import')
      expect(stderr.string).to include(RHDL::Examples::GameBoy::CLI::DEFAULT_SOURCE_DIR)
    end

    it 'does not require imported artifacts for the default ir run path' do
      fake_run_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
        end

        def run
          { pc: 0x1234, a: 0x56, cycles: 1 }
        end
      end

      status = described_class.run(
        %w[--pop --headless --cycles 1],
        out: stdout,
        err: stderr,
        run_task_class: fake_run_task_class
      )

      expect(status).to eq(0)
      expect(stderr.string).to eq('')
      expect(fake_run_task_class.last_options[:mode]).to eq(:ir)
      expect(fake_run_task_class.last_options[:source_dir]).to eq(RHDL::Examples::GameBoy::CLI::DEFAULT_SOURCE_DIR)
      expect(fake_run_task_class.last_options[:use_staged_source]).to eq(false)
      expect(fake_run_task_class.last_options[:use_normalized_source]).to eq(false)
      expect(fake_run_task_class.last_options[:use_rhdl_source]).to eq(false)
    end
  end
end
