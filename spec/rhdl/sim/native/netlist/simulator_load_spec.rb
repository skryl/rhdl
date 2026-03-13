# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Sim::Native::Netlist do
  describe '.sim_backend_available?' do
    it 'returns false when the library path is nil' do
      expect(described_class.sim_backend_available?(nil)).to be(false)
    end
  end

  describe 'backend availability constants' do
    it 'exposes boolean availability flags even when native libraries are missing' do
      expect([true, false]).to include(described_class::INTERPRETER_AVAILABLE)
      expect([true, false]).to include(described_class::JIT_AVAILABLE)
      expect([true, false]).to include(described_class::COMPILER_AVAILABLE)
    end

    it 'keeps expected library paths available for missing-library diagnostics' do
      expect(described_class::INTERPRETER_LIB_PATH).to be_a(String)
      expect(described_class::JIT_LIB_PATH).to be_a(String)
      expect(described_class::COMPILER_LIB_PATH).to be_a(String)
    end
  end
end
