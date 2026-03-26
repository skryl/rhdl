# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe 'rhdl examples command' do
  let(:project_root) { File.expand_path('../../..', __dir__) }
  let(:cli_path) { File.join(project_root, 'exe/rhdl') }

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, '-Ilib', cli_path, *args, chdir: project_root)
  end

  it 'shows riscv and sparc64 in examples help' do
    stdout, stderr, status = run_cli('examples', '--help')

    expect(status.success?).to be true
    expect(stderr).not_to include('Unknown examples subcommand')
    expect(stdout).to include('Subcommands:')
    expect(stdout).to include('gameboy')
    expect(stdout).to include('riscv')
    expect(stdout).to include('sparc64')
  end

  it 'dispatches examples gameboy to the gameboy runner' do
    stdout, stderr, status = run_cli('examples', 'gameboy', '--help')

    expect(status.success?).to be true
    expect(stderr).not_to include('Unknown examples subcommand')
    expect(stdout).to include('Game Boy HDL Terminal Emulator')
    expect(stdout).to include('import')
    expect(stdout).not_to include('Unknown examples subcommand')
  end

  it 'dispatches examples gameboy import help to the gameboy importer' do
    stdout, stderr, status = run_cli('examples', 'gameboy', 'import', '--help')

    expect(status.success?).to be true
    expect(stderr).not_to include('Unknown examples subcommand')
    expect(stdout).to include('Usage: bin/gameboy import')
    expect(stdout).to include('Import the Game Boy reference design')
  end

  it 'dispatches examples riscv to the riscv runner' do
    stdout, stderr, status = run_cli('examples', 'riscv', '--help')

    expect(status.success?).to be true
    expect(stderr).not_to include('Unknown examples subcommand')
    expect(stdout).to include('RISC-V Core Runner')
    expect(stdout).not_to include('Unknown examples subcommand')
  end

  it 'dispatches examples sparc64 to the sparc64 importer CLI' do
    stdout, stderr, status = run_cli('examples', 'sparc64', '--help')

    expect(status.success?).to be true
    expect(stderr).not_to include('Unknown examples subcommand')
    expect(stdout).to include('SPARC64 CIRCT import workflow')
    expect(stdout).to include('import')
  end

  it 'dispatches examples sparc64 import help to the sparc64 importer' do
    stdout, stderr, status = run_cli('examples', 'sparc64', 'import', '--help')

    expect(status.success?).to be true
    expect(stderr).not_to include('Unknown examples sparc64 subcommand')
    expect(stdout).to include('Usage: rhdl examples sparc64 import')
    expect(stdout).to include('Import the SPARC64 reference design')
  end
end
