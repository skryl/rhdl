require 'spec_helper'

# Component using internal Vec
class TestVecInternal < RHDL::HDL::Component
  parameter :depth, default: 4
  parameter :width, default: 8

  input :write_idx, width: 2
  input :write_data, width: :width
  input :write_enable
  input :read_idx, width: 2
  output :read_data, width: :width

  vec :regs, count: :depth, width: :width
end

# Component using input Vec
class TestVecInput < RHDL::HDL::Component
  input_vec :data_in, count: 4, width: 8
  input :sel, width: 2
  output :data_out, width: 8

  behavior do
    data_out <= data_in[sel]
  end
end

# Component using output Vec
class TestVecOutput < RHDL::HDL::Component
  input :data_in, width: 8
  input :sel, width: 2
  input :enable
  output_vec :data_out, count: 4, width: 8

  behavior do
    # Only set the selected output
    data_out_0 <= mux(sel == 0, data_in, 0)
    data_out_1 <= mux(sel == 1, data_in, 0)
    data_out_2 <= mux(sel == 2, data_in, 0)
    data_out_3 <= mux(sel == 3, data_in, 0)
  end
end

# Component demonstrating hardware-indexed Vec read
# Note: Vec name cannot be 'inputs' as it conflicts with @inputs hash
class TestVecMux < RHDL::HDL::Component
  parameter :depth, default: 8

  input_vec :data_inputs, count: 8, width: 8
  input :sel, width: 3
  output :result, width: 8

  behavior do
    result <= data_inputs[sel]
  end
end

# Component with parameterized Vec
class TestVecParam < RHDL::HDL::Component
  parameter :depth, default: 16
  parameter :width, default: 32

  input :read_addr, width: 4
  output :read_data, width: :width

  vec :memory, count: :depth, width: :width
end

RSpec.describe RHDL::Sim::Vec do
  describe 'Vec class' do
    it 'creates a Vec with correct attributes' do
      component = Object.new
      component.define_singleton_method(:name) { 'test' }
      component.define_singleton_method(:inputs) { {} }
      component.define_singleton_method(:outputs) { {} }
      component.define_singleton_method(:internal_signals) { {} }
      component.define_singleton_method(:propagate) { }

      vec = RHDL::Sim::Vec.new(:test_vec, count: 4, width: 8, component: component)

      expect(vec.count).to eq(4)
      expect(vec.element_width).to eq(8)
      expect(vec.total_width).to eq(32)
      expect(vec.index_width).to eq(2)
    end
  end

  describe 'VecInstance' do
    let(:component) { TestVecInternal.new('test_vec_internal') }

    it 'creates Vec with correct element count' do
      vec = component.instance_variable_get(:@regs)
      expect(vec.count).to eq(4)
      expect(vec.element_width).to eq(8)
    end

    it 'supports constant index access' do
      vec = component.instance_variable_get(:@regs)
      vec[0].set(0x11)
      vec[1].set(0x22)
      vec[2].set(0x33)
      vec[3].set(0x44)

      expect(vec[0].get).to eq(0x11)
      expect(vec[1].get).to eq(0x22)
      expect(vec[2].get).to eq(0x33)
      expect(vec[3].get).to eq(0x44)
    end

    it 'calculates correct index width' do
      vec = component.instance_variable_get(:@regs)
      expect(vec.index_width).to eq(2)  # 2 bits for 4 elements
    end
  end
end

RSpec.describe 'input_vec' do
  let(:component) { TestVecInput.new('vec_input') }

  it 'creates flattened input ports' do
    expect(component.inputs.keys).to include(:data_in_0)
    expect(component.inputs.keys).to include(:data_in_1)
    expect(component.inputs.keys).to include(:data_in_2)
    expect(component.inputs.keys).to include(:data_in_3)
  end

  it 'supports hardware-indexed read' do
    component.set_input(:data_in_0, 0x10)
    component.set_input(:data_in_1, 0x20)
    component.set_input(:data_in_2, 0x30)
    component.set_input(:data_in_3, 0x40)

    component.set_input(:sel, 0)
    component.propagate
    expect(component.get_output(:data_out)).to eq(0x10)

    component.set_input(:sel, 1)
    component.propagate
    expect(component.get_output(:data_out)).to eq(0x20)

    component.set_input(:sel, 2)
    component.propagate
    expect(component.get_output(:data_out)).to eq(0x30)

    component.set_input(:sel, 3)
    component.propagate
    expect(component.get_output(:data_out)).to eq(0x40)
  end

  it 'generates valid Verilog with individual ports' do
    verilog = TestVecInput.to_verilog
    expect(verilog).to include('module test_vec_input')
    expect(verilog).to include('input [7:0] data_in_0')
    expect(verilog).to include('input [7:0] data_in_1')
    expect(verilog).to include('input [7:0] data_in_2')
    expect(verilog).to include('input [7:0] data_in_3')
  end
end

RSpec.describe 'output_vec' do
  let(:component) { TestVecOutput.new('vec_output') }

  it 'creates flattened output ports' do
    expect(component.outputs.keys).to include(:data_out_0)
    expect(component.outputs.keys).to include(:data_out_1)
    expect(component.outputs.keys).to include(:data_out_2)
    expect(component.outputs.keys).to include(:data_out_3)
  end

  it 'drives selected output' do
    component.set_input(:data_in, 0xAB)
    component.set_input(:enable, 1)

    component.set_input(:sel, 0)
    component.propagate
    expect(component.get_output(:data_out_0)).to eq(0xAB)
    expect(component.get_output(:data_out_1)).to eq(0)

    component.set_input(:sel, 2)
    component.propagate
    expect(component.get_output(:data_out_2)).to eq(0xAB)
    expect(component.get_output(:data_out_0)).to eq(0)
  end
end

RSpec.describe 'Vec mux (hardware indexing)' do
  let(:component) { TestVecMux.new('vec_mux') }

  it 'creates correct number of input ports' do
    expect(component.inputs.keys.count { |k| k.to_s.start_with?('data_inputs_') }).to eq(8)
  end

  it 'selects correct input based on sel' do
    # Set all inputs with different values
    8.times do |i|
      component.set_input("data_inputs_#{i}".to_sym, i * 0x10 + i)
    end

    8.times do |i|
      component.set_input(:sel, i)
      component.propagate
      expect(component.get_output(:result)).to eq(i * 0x10 + i),
        "Expected result=#{i * 0x10 + i} for sel=#{i}, got #{component.get_output(:result)}"
    end
  end
end

RSpec.describe 'Parameterized Vec' do
  describe 'with default parameters' do
    let(:component) { TestVecParam.new('param_vec') }

    it 'creates Vec with default size' do
      vec = component.instance_variable_get(:@memory)
      expect(vec.count).to eq(16)
      expect(vec.element_width).to eq(32)
    end
  end

  describe 'with custom parameters' do
    let(:component) { TestVecParam.new('param_vec', depth: 8, width: 16) }

    it 'creates Vec with custom size' do
      vec = component.instance_variable_get(:@memory)
      expect(vec.count).to eq(8)
      expect(vec.element_width).to eq(16)
    end
  end
end

RSpec.describe 'Vec iteration' do
  let(:component) { TestVecInternal.new('iter_vec') }

  it 'supports each iteration' do
    vec = component.instance_variable_get(:@regs)
    vec[0].set(1)
    vec[1].set(2)
    vec[2].set(3)
    vec[3].set(4)

    values = []
    vec.each { |el| values << el.get }
    expect(values).to eq([1, 2, 3, 4])
  end

  it 'supports each_with_index' do
    vec = component.instance_variable_get(:@regs)
    4.times { |i| vec[i].set(i * 10) }

    pairs = []
    vec.each_with_index { |el, i| pairs << [i, el.get] }
    expect(pairs).to eq([[0, 0], [1, 10], [2, 20], [3, 30]])
  end

  it 'supports map' do
    vec = component.instance_variable_get(:@regs)
    4.times { |i| vec[i].set(i + 1) }

    result = vec.map(&:get)
    expect(result).to eq([1, 2, 3, 4])
  end

  it 'supports values accessor' do
    vec = component.instance_variable_get(:@regs)
    vec[0].set(0xAA)
    vec[1].set(0xBB)
    vec[2].set(0xCC)
    vec[3].set(0xDD)

    expect(vec.values).to eq([0xAA, 0xBB, 0xCC, 0xDD])
  end

  it 'supports set_values' do
    vec = component.instance_variable_get(:@regs)
    vec.set_values([0x11, 0x22, 0x33, 0x44])

    expect(vec.values).to eq([0x11, 0x22, 0x33, 0x44])
  end
end
