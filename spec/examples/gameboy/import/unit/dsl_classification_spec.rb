# frozen_string_literal: true

require 'spec_helper'
require_relative 'support'

RSpec.describe 'GameBoy imported DSL classification', slow: true do
  include_context 'gameboy import unit fixture'

  let(:fixture) { gameboy_import_fixture }
  let(:source_result) { fixture[:raise_source_result] }
  let(:provenance_by_module) { gameboy_module_provenance_by_name }

  it 'adds Behavior to every imported component that emits a behavior block' do
    offenders = provenance_by_module.each_with_object([]) do |(name, provenance), memo|
      next unless provenance.dig('expected_dsl_features', 'behavior')
      source = source_result.sources.fetch(name)
      next if source.include?('include RHDL::DSL::Behavior')

      memo << name
    end

    expect(offenders).to eq([])
  end

  it 'adds Sequential and Behavior to every imported component that emits a sequential block' do
    sequential_modules = []
    missing_behavior = []
    missing_sequential = []

    provenance_by_module.each do |name, provenance|
      next unless provenance.dig('expected_dsl_features', 'sequential')
      source = source_result.sources.fetch(name)

      sequential_modules << name
      missing_behavior << name unless source.include?('include RHDL::DSL::Behavior')
      missing_sequential << name unless source.include?('include RHDL::DSL::Sequential')
    end

    expect(sequential_modules).not_to be_empty
    expect(missing_behavior).to eq([])
    expect(missing_sequential).to eq([])
  end

  it 'does not over-promote representative structural combinational wrappers to Sequential' do
    spram = source_result.sources.fetch('spram')
    alu = source_result.sources.fetch('t80_alu_3_4_6_0_0_5_0_7_0__5a58f40d')

    expect(spram).to include('include RHDL::DSL::Behavior')
    expect(spram).not_to include('include RHDL::DSL::Sequential')

    expect(alu).to include('include RHDL::DSL::Behavior')
    expect(alu).not_to include('include RHDL::DSL::Sequential')
  end

  it 'adds Memory to imported memory-backed modules' do
    memory_modules = provenance_by_module.select do |_name, provenance|
      provenance.dig('expected_dsl_features', 'memory')
    end

    expect(memory_modules).not_to be_empty

    missing_memory = memory_modules.each_with_object([]) do |(name, _provenance), memo|
      source = source_result.sources.fetch(name)
      memo << name unless source.include?('include RHDL::DSL::Memory')
    end

    expect(missing_memory).to eq([])
  end
end
