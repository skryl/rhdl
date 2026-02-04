require 'spec_helper'
require_relative 'shared_cpu_spec'

RSpec.describe RHDL::HDL::CPU::Harness do
  include CpuTestHelper

  # Use HDL CPU implementation
  def setup_cpu
    use_hdl_cpu!
    @cpu = cpu_class.new(@memory)
    @cpu.reset
    setup_test_values
  end

  it_behaves_like 'a CPU implementation'
end
