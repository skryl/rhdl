require 'spec_helper'

RSpec.describe 'RHDL DSL multiple sequential blocks' do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:multi_seq_fixture) do
    stub_const('MultiSequentialFixture', Class.new(RHDL::Sim::SequentialComponent) do
      include RHDL::DSL::Sequential

      input :clk
      input :a
      input :b
      output :q
      output :r

      sequential clock: :clk do
        q <= a
      end

      sequential clock: :clk do
        r <= b
      end
    end)
  end

  let(:reset_child_fixture) do
    stub_const('ResetChildFixture', Class.new(RHDL::Sim::SequentialComponent) do
      include RHDL::DSL::Sequential

      input :clk
      input :rst_l
      input :d
      output :q

      sequential clock: :clk, reset: :rst_l, reset_values: { q: 0 } do
        q <= d
      end
    end)
  end

  let(:reset_parent_fixture) do
    reset_child_fixture
    stub_const('ResetParentFixture', Class.new(RHDL::Sim::Component) do
      input :clk
      input :rst_l
      input :d
      output :q

      instance :child, ResetChildFixture
      port :clk => [:child, :clk]
      port :rst_l => [:child, :rst_l]
      port :d => [:child, :d]
      port [:child, :q] => :q
    end)
  end

  it 'updates all sequential assignments during simulation' do
    component = multi_seq_fixture.new

    component.set_input(:a, 1)
    component.set_input(:b, 0)
    clock_cycle(component)
    expect(component.get_output(:q)).to eq(1)
    expect(component.get_output(:r)).to eq(0)

    component.set_input(:a, 0)
    component.set_input(:b, 1)
    clock_cycle(component)
    expect(component.get_output(:q)).to eq(0)
    expect(component.get_output(:r)).to eq(1)
  end

  it 'emits one CIRCT process per sequential block' do
    ir = multi_seq_fixture.to_circt_nodes

    expect(ir.processes.length).to eq(2)

    targets = ir.processes.flat_map do |process|
      Array(process.statements).map(&:target)
    end.compact.map(&:to_sym)
    expect(targets).to include(:q, :r)
  end

  it 'preserves reset metadata when flattening child sequential processes' do
    ir = reset_parent_fixture.to_flat_circt_nodes
    process = ir.processes.find { |entry| entry.name.to_s == 'child__seq_logic' }

    expect(process).not_to be_nil
    expect(process.reset.to_s).to eq('child__rst_l')
    expect(process.reset_active_low).to eq(true)
    expect(process.reset_values).to include('q' => 0)
  end
end
