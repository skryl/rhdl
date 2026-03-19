# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RHDL::Sim::Native::IR do
  describe '.sim_backend_available?' do
    it 'returns false when the library path is nil' do
      expect(described_class.sim_backend_available?(nil)).to be(false)
    end
  end

  describe '.resolve_backend_lib_path' do
    it 'prefers the cargo release artifact over the staged lib copy' do
      Dir.mktmpdir('ir_backend_lib_path') do |dir|
        ext_dir = File.join(dir, 'ir_compiler', 'lib')
        release_dir = File.join(dir, 'ir_compiler', 'target', 'release')
        FileUtils.mkdir_p(ext_dir)
        FileUtils.mkdir_p(release_dir)

        staged = File.join(ext_dir, described_class.sim_lib_name('ir_compiler'))
        release = File.join(release_dir, described_class.cargo_cdylib_name('ir_compiler'))

        File.write(staged, 'staged')
        File.write(release, 'release')

        expect(
          described_class.resolve_backend_lib_path(
            ext_dir,
            described_class.sim_lib_name('ir_compiler'),
            crate_name: 'ir_compiler'
          )
        ).to eq(release)
      end
    end

    it 'falls back to the staged lib copy when no cargo release artifact exists' do
      Dir.mktmpdir('ir_backend_lib_path') do |dir|
        ext_dir = File.join(dir, 'ir_compiler', 'lib')
        FileUtils.mkdir_p(ext_dir)

        staged = File.join(ext_dir, described_class.sim_lib_name('ir_compiler'))
        File.write(staged, 'staged')

        expect(
          described_class.resolve_backend_lib_path(
            ext_dir,
            described_class.sim_lib_name('ir_compiler'),
            crate_name: 'ir_compiler'
          )
        ).to eq(staged)
      end
    end
  end

  describe 'backend availability constants' do
    it 'exposes boolean availability flags even when native libraries are missing' do
      expect([true, false]).to include(described_class::INTERPRETER_AVAILABLE)
      expect([true, false]).to include(described_class::JIT_AVAILABLE)
      expect([true, false]).to include(described_class::COMPILER_AVAILABLE)
    end

    it 'keeps expected library paths available for missing-library diagnostics' do
      expect(described_class::IR_INTERPRETER_LIB_PATH).to be_a(String)
      expect(described_class::JIT_LIB_PATH).to be_a(String)
      expect(described_class::COMPILER_LIB_PATH).to be_a(String)
    end
  end

  describe 'compiler failure reporting' do
    it 'surfaces the native fast-path blocker details' do
      skip 'IR compiler backend unavailable' unless described_class::COMPILER_AVAILABLE

      json = {
        circt_json_version: 1,
        modules: [
          {
            name: 'top',
            ports: [
              { name: 'a', direction: 'in', width: 128 },
              { name: 'b', direction: 'in', width: 128 },
              { name: 'wide_out', direction: 'out', width: 257 }
            ],
            nets: [],
            regs: [],
            exprs: [],
            assigns: [
              {
                target: 'wide_out',
                expr: {
                  kind: 'concat',
                  parts: [
                    { kind: 'literal', value: 1, width: 1 },
                    { kind: 'signal', name: 'a', width: 128 },
                    { kind: 'signal', name: 'b', width: 128 }
                  ],
                  width: 257
                }
              }
            ],
            processes: [],
            memories: [],
            write_ports: [],
            sync_read_ports: []
          }
        ]
      }.to_json

      expect do
        RHDL::Sim::Native::IR::Simulator.new(json, backend: :compiler)
      end.to raise_error(
        RuntimeError,
        /compiled fast path requires runtime fallback.*wide_out/
      )
    end
  end
end
