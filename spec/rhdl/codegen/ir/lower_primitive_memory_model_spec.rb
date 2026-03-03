# frozen_string_literal: true

require "spec_helper"

require "rhdl/codegen/ir/lower"

RSpec.describe RHDL::Codegen::IR::Lower do
  it "lowers imported altdpram variants into memory/write-port IR in lir mode" do
    klass = Class.new(RHDL::Component) do
      generic :width, default: "32'h14"
      generic :widthad, default: "32'h7"

      input :inclock
      input :inclocken
      input :wren
      input :wraddressstall
      input :wraddress, width: 7
      input :rdaddress, width: 7
      input :data, width: 20
      output :q, width: 20
    end

    ir = described_class.new(klass, top_name: "altdpram__W14_WB7", mode: :lir).build

    expect(ir.memories.length).to eq(1)
    expect(ir.memories.first.name).to eq("__mem")
    expect(ir.memories.first.width).to eq(20)
    expect(ir.memories.first.depth).to eq(128)
    expect(ir.write_ports.length).to eq(1)
    expect(ir.write_ports.first.memory).to eq("__mem")
    expect(ir.write_ports.first.clock).to eq("inclock")
    expect(ir.assigns.map(&:target)).to include(:q)
    expect(ir.processes).to eq([])
    expect(ir.instances).to eq([])
  end

  it "lowers imported altsyncram variants into memory/write-port IR in lir mode" do
    klass = Class.new(RHDL::Component) do
      generic :width_a, default: "32'h20"
      generic :width_b, default: "32'h20"
      generic :widthad_a, default: "32'ha"
      generic :widthad_b, default: "32'ha"

      input :clock0
      input :clocken0
      input :wren_a
      input :addressstall_a
      input :address_a, width: 10
      input :address_b, width: 10
      input :byteena_a, width: 4
      input :data_a, width: 32
      output :q_b, width: 32
    end

    ir = described_class.new(klass, top_name: "altsyncram__Az1", mode: :lir).build

    expect(ir.memories.length).to eq(1)
    expect(ir.memories.first.name).to eq("__mem")
    expect(ir.memories.first.width).to eq(32)
    expect(ir.memories.first.depth).to eq(1024)
    expect(ir.write_ports.length).to eq(1)
    expect(ir.write_ports.first.memory).to eq("__mem")
    expect(ir.write_ports.first.clock).to eq("clock0")
    expect(ir.assigns.map(&:target)).to include(:q_b)
    expect(ir.processes).to eq([])
    expect(ir.instances).to eq([])
  end
end
