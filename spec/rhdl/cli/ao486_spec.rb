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
    expect(stdout).to include('Subcommands:')
    expect(stdout).to include('import')
    expect(stdout).to include('parity')
    expect(stdout).to include('verify')
  end

  it 'shows import-specific help' do
    stdout, stderr, status = run_cli('examples', 'ao486', 'import', '--help')

    expect(status.success?).to be(true)
    expect(stderr).not_to include('Unknown examples ao486 subcommand')
    expect(stdout).to include('Usage: rhdl examples ao486 import')
    expect(stdout).to include('--source FILE')
    expect(stdout).to include('--out DIR')
    expect(stdout).to include('--workspace DIR')
    expect(stdout).to include('--report FILE')
    expect(stdout).to include('--strategy STRATEGY')
    expect(stdout).to include('--[no-]fallback')
    expect(stdout).to include('--[no-]maintain-directory-structure')
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

  it 'fails cleanly for unknown examples ao486 subcommand' do
    _stdout, stderr, status = run_cli('examples', 'ao486', 'unknown_subcommand')

    expect(status.success?).to be(false)
    expect(stderr).to include('Unknown examples ao486 subcommand')
  end
end
