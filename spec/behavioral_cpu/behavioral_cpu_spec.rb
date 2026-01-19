require 'spec_helper'

RSpec.describe RHDL::Components::CPU::CPU do
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
