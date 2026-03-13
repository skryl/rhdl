# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe 'rhdl import command' do
  let(:project_root) { File.expand_path('../../..', __dir__) }
  let(:cli_path) { File.join(project_root, 'exe/rhdl') }

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, '-Ilib', cli_path, *args, chdir: project_root)
  end

  it 'shows mixed mode and manifest options in import help' do
    stdout, stderr, status = run_cli('import', '--help')

    expect(status.success?).to be(true)
    expect(stderr).not_to include('Unknown command')
    expect(stdout).to include('Import mode: verilog, mixed, or circt')
    expect(stdout).to include('--manifest FILE')
    expect(stdout).to include('Mixed mode')
  end
end
