# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe 'rhdl examples ao486 command' do
  let(:project_root) { File.expand_path('../../..', __dir__) }
  let(:cli_path) { File.join(project_root, 'exe/rhdl') }

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, '-Ilib', cli_path, *args, chdir: project_root)
  end

  it 'does not expose ao486 as a top-level command' do
    stdout, stderr, status = run_cli('--help')

    expect(status.success?).to be(true)
    expect(stderr).not_to include('Unknown command')
    expect(stdout).not_to include("\nao486")
  end

  it 'shows ao486 under examples help' do
    stdout, stderr, status = run_cli('examples', '--help')

    expect(status.success?).to be(true)
    expect(stderr).not_to include('Unknown examples subcommand')
    expect(stdout).to include('ao486')
  end

  it 'rejects ao486 as a top-level command' do
    stdout, stderr, status = run_cli('ao486', '--help')

    expect(status.success?).to be(false)
    expect(stderr).to include('Unknown command')
  end

  it 'shows examples ao486 subcommands in nested help' do
    stdout, stderr, status = run_cli('examples', 'ao486', '--help')

    expect(status.success?).to be(true)
    expect(stderr).not_to include('Unknown examples ao486 subcommand')
    expect(stdout).to include('Usage: rhdl examples ao486 [options]')
    expect(stdout).to include('Default mode:')
    expect(stdout).to include('Run options:')
    expect(stdout).to include('-m, --mode ir|verilog|circt')
    expect(stdout).to include('--sim interpret|jit|compile')
    expect(stdout).to include('--bios')
    expect(stdout).to include('--dos')
    expect(stdout).to include('--dos-disk1 FILE')
    expect(stdout).to include('--dos-disk2 FILE')
    expect(stdout).to include('--headless')
    expect(stdout).to include('--cycles N')
    expect(stdout).to include('-s, --speed CYCLES')
    expect(stdout).to include('-d, --debug')
    expect(stdout).to include('Subcommands:')
    expect(stdout).to include('import')
    expect(stdout).to include('parity')
    expect(stdout).to include('verify')
  end

  it 'treats unknown flags as run-mode parser errors instead of unknown subcommands' do
    _stdout, stderr, status = run_cli('examples', 'ao486', '--nope')

    expect(status.success?).to be(false)
    expect(stderr).not_to include('Unknown examples ao486 subcommand')
    expect(stderr).to include('Error: invalid option: --nope')
  end

  it 'parses run-mode help without requiring a subcommand' do
    stdout, stderr, status = run_cli('examples', 'ao486', '-m', 'verilog', '--help')

    expect(status.success?).to be(true)
    expect(stderr).not_to include('Unknown examples ao486 subcommand')
    expect(stdout).to include('Run the AO486 CPU-top environment.')
    expect(stdout).to include('--bios')
    expect(stdout).to include('--dos')
    expect(stdout).to include('--dos-disk1 FILE')
    expect(stdout).to include('--dos-disk2 FILE')
    expect(stdout).to include('-s, --speed CYCLES')
    expect(stdout).to include('-d, --debug')
  end

  it 'accepts compiler as a direct IR sim backend option' do
    _stdout, stderr, status = run_cli('examples', 'ao486', '--mode', 'ir', '--sim', 'compiler', '--help')

    expect(status.success?).to be(true)
    expect(stderr).not_to include('invalid option: --sim compiler')
  end

  it 'accepts circt as the shared public mode name' do
    _stdout, stderr, status = run_cli('examples', 'ao486', '-m', 'circt', '--help')

    expect(status.success?).to be(true)
    expect(stderr).not_to include('invalid argument: circt')
  end

  it 'rejects unexpected positional arguments in default run mode' do
    _stdout, stderr, status = run_cli('examples', 'ao486', '--bios', 'extra_arg')

    expect(status.success?).to be(false)
    expect(stderr).to include('Unexpected arguments: extra_arg')
  end

  it 'shows import-specific help' do
    stdout, stderr, status = run_cli('examples', 'ao486', 'import', '--help')

    expect(status.success?).to be(true)
    expect(stderr).not_to include('Unknown examples ao486 subcommand')
    expect(stdout).to include('Usage: rhdl examples ao486 import')
    expect(stdout).to include('rtl/ao486/ao486.v')
    expect(stdout).to include('--source FILE')
    expect(stdout).to include('--out DIR')
    expect(stdout).to include('--workspace DIR')
    expect(stdout).to include('--report FILE')
    expect(stdout).to include('default: ao486')
    expect(stdout).to include('--strategy STRATEGY')
    expect(stdout).to include('--[no-]fallback')
    expect(stdout).to include('--[no-]keep-structure')
    expect(stdout).to include('--[no-]format')
    expect(stdout).to include('--[no-]strict')
    expect(stdout).to include('--[no-]clean')
  end

  it 'requires --out for import' do
    _stdout, stderr, status = run_cli('examples', 'ao486', 'import')

    expect(status.success?).to be(false)
    expect(stderr).to include('Missing required option: --out DIR')
  end

  it 'accepts --no-clean on import' do
    _stdout, stderr, status = run_cli('examples', 'ao486', 'import', '--no-clean')

    expect(status.success?).to be(false)
    expect(stderr).to include('Missing required option: --out DIR')
  end

  it 'accepts --no-strict on import' do
    _stdout, stderr, status = run_cli('examples', 'ao486', 'import', '--no-strict')

    expect(status.success?).to be(false)
    expect(stderr).to include('Missing required option: --out DIR')
  end

  it 'fails cleanly for unknown explicit examples ao486 subcommand after a real subcommand token' do
    _stdout, stderr, status = run_cli('examples', 'ao486', 'unknown_subcommand')

    expect(status.success?).to be(false)
    expect(stderr).to include('Unexpected arguments: unknown_subcommand')
  end
end
