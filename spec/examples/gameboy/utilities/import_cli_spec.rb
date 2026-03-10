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
      expect(stdout.string).to include('--hdl-dir DIR')
      expect(stdout.string).to include('--top NAME')
      expect(stdout.string).to include('--use-staged-verilog')
    end

    it 'runs import with the canonical output dir by default' do
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

      expect(status).to eq(0)
      expect(stderr.string).to eq('')
      expect(fake_importer_class.last_kwargs[:output_dir]).to eq(
        RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_OUTPUT_DIR
      )
      expect(fake_importer_class.last_kwargs[:clean_output]).to eq(true)
      expect(fake_importer_class.last_kwargs[:keep_workspace]).to eq(false)
      expect(fake_importer_class.last_kwargs[:maintain_directory_structure]).to eq(true)
      expect(fake_importer_class.last_kwargs[:strict]).to eq(true)
      expect(fake_importer_class.last_kwargs[:import_strategy]).to eq(
        RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_IMPORT_STRATEGY
      )
      expect(stdout.string).to include('Imported Game Boy reference design')
      expect(stdout.string).to include('/tmp/gameboy_import')
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
        %w[import --no-auto-stub-modules],
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

      status = described_class.run(['import'], out: stdout, err: stderr, importer_class: fake_importer_class)

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
        %w[--mode verilog --hdl-dir examples/gameboy/import --top gb --use-staged-verilog --pop --headless --cycles 7],
        out: stdout,
        err: stderr,
        run_task_class: fake_run_task_class
      )

      expect(status).to eq(0)
      expect(fake_run_task_class.last_options[:top]).to eq('gb')
      expect(fake_run_task_class.last_options[:use_staged_verilog]).to eq(true)
    end
  end
end
