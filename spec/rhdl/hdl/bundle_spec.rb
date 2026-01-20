require 'spec_helper'

# Test Bundle definitions
class TestValidBundle < RHDL::Sim::Bundle
  field :data, width: 8, direction: :output
  field :valid, width: 1, direction: :output
  field :ready, width: 1, direction: :input
end

class TestAxiLiteWrite < RHDL::Sim::Bundle
  field :awaddr, width: 32, direction: :output
  field :awvalid, width: 1, direction: :output
  field :awready, width: 1, direction: :input
  field :wdata, width: 32, direction: :output
  field :wvalid, width: 1, direction: :output
  field :wready, width: 1, direction: :input
end

# Component using input bundle (producer)
class TestBundleProducer < RHDL::HDL::Component
  input :clk
  input :enable
  input :data_in, width: 8
  input_bundle :out_port, TestValidBundle

  behavior do
    out_port_data <= data_in
    out_port_valid <= enable
  end
end

# Component using output bundle (consumer, flipped)
class TestBundleConsumer < RHDL::HDL::Component
  input :clk
  output :data_out, width: 8
  output :data_valid
  output_bundle :in_port, TestValidBundle

  behavior do
    data_out <= in_port_data
    data_valid <= in_port_valid
    in_port_ready <= 1  # Always ready
  end
end

# Component using bundle with explicit flipped: false
class TestBundleProducerExplicit < RHDL::HDL::Component
  input :data_in, width: 8
  input :valid_in
  output_bundle :out_port, TestValidBundle, flipped: false

  behavior do
    out_port_data <= data_in
    out_port_valid <= valid_in
  end
end

RSpec.describe RHDL::Sim::Bundle do
  describe 'Bundle class definition' do
    it 'defines fields with correct attributes' do
      expect(TestValidBundle.fields.length).to eq(3)

      data_field = TestValidBundle.field_def(:data)
      expect(data_field.width).to eq(8)
      expect(data_field.direction).to eq(:output)

      ready_field = TestValidBundle.field_def(:ready)
      expect(ready_field.width).to eq(1)
      expect(ready_field.direction).to eq(:input)
    end

    it 'calculates total width' do
      expect(TestValidBundle.total_width).to eq(10)  # 8 + 1 + 1
    end

    it 'returns field names' do
      expect(TestValidBundle.field_names).to eq([:data, :valid, :ready])
    end

    it 'supports flipped accessor' do
      flipped = TestValidBundle.flipped
      expect(flipped).to be_a(RHDL::Sim::FlippedBundle)
      expect(flipped.bundle_class).to eq(TestValidBundle)
    end
  end

  describe 'FlippedBundle' do
    let(:flipped) { TestValidBundle.flipped }

    it 'delegates field access to original bundle' do
      expect(flipped.fields).to eq(TestValidBundle.fields)
      expect(flipped.total_width).to eq(TestValidBundle.total_width)
    end

    it 'creates flipped Bundle instances' do
      instance = flipped.new(:test_port)
      expect(instance).to be_a(RHDL::Sim::Bundle)
      expect(instance.flipped).to be(true)
    end
  end

  describe 'Bundle instance' do
    let(:bundle) { RHDL::Sim::Bundle.new(:test, TestValidBundle) }

    it 'has correct field directions (not flipped)' do
      expect(bundle.field_direction(:data)).to eq(:output)
      expect(bundle.field_direction(:valid)).to eq(:output)
      expect(bundle.field_direction(:ready)).to eq(:input)
    end

    it 'generates flattened ports' do
      ports = bundle.flattened_ports
      expect(ports.length).to eq(3)

      data_port = ports.find { |p| p[0] == :test_data }
      expect(data_port[1]).to eq(8)  # width
      expect(data_port[2]).to eq(:output)  # direction
    end
  end

  describe 'Flipped Bundle instance' do
    let(:bundle) { RHDL::Sim::Bundle.new(:test, TestValidBundle, flipped: true) }

    it 'reverses field directions' do
      expect(bundle.field_direction(:data)).to eq(:input)
      expect(bundle.field_direction(:valid)).to eq(:input)
      expect(bundle.field_direction(:ready)).to eq(:output)
    end

    it 'generates flattened ports with reversed directions' do
      ports = bundle.flattened_ports
      data_port = ports.find { |p| p[0] == :test_data }
      expect(data_port[2]).to eq(:input)

      ready_port = ports.find { |p| p[0] == :test_ready }
      expect(ready_port[2]).to eq(:output)
    end
  end
end

RSpec.describe 'Bundle in Component' do
  describe 'input_bundle' do
    let(:producer) { TestBundleProducer.new('producer') }

    it 'creates flattened input/output ports' do
      # data is :output in bundle, so it's an output port
      expect(producer.outputs.keys).to include(:out_port_data)
      expect(producer.outputs.keys).to include(:out_port_valid)

      # ready is :input in bundle, so it's an input port
      expect(producer.inputs.keys).to include(:out_port_ready)
    end

    it 'propagates data through bundle fields' do
      producer.set_input(:data_in, 0x42)
      producer.set_input(:enable, 1)
      producer.propagate

      expect(producer.get_output(:out_port_data)).to eq(0x42)
      expect(producer.get_output(:out_port_valid)).to eq(1)
    end

    it 'generates valid Verilog' do
      verilog = TestBundleProducer.to_verilog
      expect(verilog).to include('module test_bundle_producer')
      expect(verilog).to include('input [7:0] out_port_data') .or include('output [7:0] out_port_data')
      expect(verilog).to include('out_port_valid')
      expect(verilog).to include('out_port_ready')
    end
  end

  describe 'output_bundle (flipped)' do
    let(:consumer) { TestBundleConsumer.new('consumer') }

    it 'creates flattened ports with flipped directions' do
      # data is :output in bundle, but flipped means it's an input
      expect(consumer.inputs.keys).to include(:in_port_data)
      expect(consumer.inputs.keys).to include(:in_port_valid)

      # ready is :input in bundle, but flipped means it's an output
      expect(consumer.outputs.keys).to include(:in_port_ready)
    end

    it 'propagates data through flipped bundle fields' do
      consumer.set_input(:in_port_data, 0x55)
      consumer.set_input(:in_port_valid, 1)
      consumer.propagate

      expect(consumer.get_output(:data_out)).to eq(0x55)
      expect(consumer.get_output(:data_valid)).to eq(1)
      expect(consumer.get_output(:in_port_ready)).to eq(1)
    end
  end

  describe 'Complex bundle (AXI-Lite)' do
    it 'defines bundle with multiple fields' do
      expect(TestAxiLiteWrite.fields.length).to eq(6)
      expect(TestAxiLiteWrite.total_width).to eq(68)  # 32 + 1 + 1 + 32 + 1 + 1
    end
  end
end

RSpec.describe 'Bundle behavior block access' do
  it 'allows field access in behavior blocks' do
    producer = TestBundleProducer.new('producer')

    producer.set_input(:data_in, 0xAB)
    producer.set_input(:enable, 1)
    producer.propagate

    expect(producer.get_output(:out_port_data)).to eq(0xAB)
    expect(producer.get_output(:out_port_valid)).to eq(1)
  end
end
