require 'spec_helper'
require_relative '../../../../../../examples/mos6502/utilities/simulators/isa_simulator/loader'

RSpec.describe RHDL::Examples::MOS6502::Components::CPU::CPU do
  include CpuTestHelper

  # Use behavior CPU implementation
  def setup_cpu
    use_behavior_cpu!
    @cpu = cpu_class.new(@memory)
    @cpu.reset
    setup_test_values
  end

  it_behaves_like 'a CPU implementation'
end
