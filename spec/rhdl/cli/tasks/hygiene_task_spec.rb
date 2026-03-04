# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'
require 'yaml'

RSpec.describe RHDL::CLI::Tasks::HygieneTask do
  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end
  end

  describe '#run' do
    it 'prints success when all checks pass' do
      task = described_class.new
      allow(task).to receive(:check_submodule_parity).and_return([])
      allow(task).to receive(:check_ignore_rules).and_return([])
      allow(task).to receive(:check_tracked_ephemera).and_return([])
      allow(task).to receive(:check_duplicate_policy).and_return([])

      expect { task.run }.to output(/All hygiene checks passed/).to_stdout
    end

    it 'raises when any check fails' do
      task = described_class.new
      allow(task).to receive(:check_submodule_parity).and_return(['broken submodule'])
      allow(task).to receive(:check_ignore_rules).and_return([])
      allow(task).to receive(:check_tracked_ephemera).and_return([])
      allow(task).to receive(:check_duplicate_policy).and_return([])

      expect { task.run }.to raise_error(RuntimeError, /Hygiene check failed/)
    end
  end

  describe 'private checks' do
    it 'parses submodule paths from .gitmodules' do
      Dir.mktmpdir('rhdl_hygiene_gitmodules_spec') do |dir|
        File.write(File.join(dir, '.gitmodules'), <<~GITMODULES)
          [submodule "examples/foo"]
            path = examples/foo
            url = https://example.com/foo.git
          [submodule "examples/bar"]
            path = examples/bar
            url = https://example.com/bar.git
        GITMODULES

        task = described_class.new(root: dir)
        expect(task.send(:parse_gitmodules_paths)).to eq(%w[examples/bar examples/foo])
      end
    end

    it 'checks required and forbidden entries in .gitignore' do
      Dir.mktmpdir('rhdl_hygiene_gitignore_spec') do |dir|
        FileUtils.mkdir_p(File.join(dir, 'lib/rhdl/sim/native/netlist/netlist_interpreter'))
        FileUtils.mkdir_p(File.join(dir, 'lib/rhdl/sim/native/netlist/netlist_jit'))
        FileUtils.mkdir_p(File.join(dir, 'lib/rhdl/sim/native/netlist/netlist_compiler'))

        %w[
          lib/rhdl/sim/native/netlist/netlist_interpreter/.gitignore
          lib/rhdl/sim/native/netlist/netlist_jit/.gitignore
          lib/rhdl/sim/native/netlist/netlist_compiler/.gitignore
        ].each do |path|
          File.write(File.join(dir, path), "/target/\n/lib/\n")
        end

        File.write(File.join(dir, '.gitignore'), <<~GITIGNORE)
          /.tmp/
          /web/test-results/
          lib/rhdl/sim/native/netlist/netlist_interpreter/target/
          lib/rhdl/sim/native/netlist/netlist_interpreter/lib/
          lib/rhdl/sim/native/netlist/netlist_jit/target/
          lib/rhdl/sim/native/netlist/netlist_jit/lib/
          lib/rhdl/sim/native/netlist/netlist_compiler/target/
          lib/rhdl/sim/native/netlist/netlist_compiler/lib/
          lib/rhdl/sim/native/ir/ir_interpreter/target/
          lib/rhdl/sim/native/ir/ir_interpreter/lib/
          lib/rhdl/sim/native/ir/ir_jit/target/
          lib/rhdl/sim/native/ir/ir_jit/lib/
          lib/rhdl/sim/native/ir/ir_compiler/target/
          lib/rhdl/sim/native/ir/ir_compiler/lib/
          lib/rhdl/sim/native/ir/ir_compiler/*.json
        GITIGNORE

        task = described_class.new(root: dir)
        expect(task.send(:check_ignore_rules)).to eq([])
      end
    end

    it 'validates shared symlink policy from allowlist' do
      Dir.mktmpdir('rhdl_hygiene_symlink_spec') do |dir|
        source = File.join(dir, 'examples/apple2/software/disks/karateka.bin')
        link = File.join(dir, 'examples/mos6502/software/disks/karateka.bin')
        allowlist = File.join(dir, 'config/hygiene_allowlist.yml')

        FileUtils.mkdir_p(File.dirname(source))
        FileUtils.mkdir_p(File.dirname(link))
        FileUtils.mkdir_p(File.dirname(allowlist))
        File.write(source, 'test')
        FileUtils.ln_sf('../../../apple2/software/disks/karateka.bin', link)
        File.write(allowlist, YAML.dump({ 'shared_symlinks' => { 'examples/mos6502/software/disks/karateka.bin' => 'examples/apple2/software/disks/karateka.bin' } }))

        task = described_class.new(root: dir, allowlist_path: allowlist)
        expect(task.send(:check_duplicate_policy)).to eq([])
      end
    end
  end
end
