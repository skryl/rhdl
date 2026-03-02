# frozen_string_literal: true

class Altdpram < RHDL::Component
  include RHDL::DSL::Behavior
  include RHDL::DSL::Structure
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: altdpram
  # generated_blackbox_stub: true

  generic :indata_aclr, default: 0
  generic :indata_reg, default: 0
  generic :intended_device_family, default: 0
  generic :lpm_type, default: 0
  generic :outdata_aclr, default: 0
  generic :outdata_reg, default: 0
  generic :ram_block_type, default: 0
  generic :rdaddress_aclr, default: 0
  generic :rdaddress_reg, default: 0
  generic :rdcontrol_aclr, default: 0
  generic :rdcontrol_reg, default: 0
  generic :read_during_write_mode_mixed_ports, default: 0
  generic :width, default: 0
  generic :width_byteena, default: 0
  generic :widthad, default: 0
  generic :wraddress_aclr, default: 0
  generic :wraddress_reg, default: 0
  generic :wrcontrol_aclr, default: 0
  generic :wrcontrol_reg, default: 0

  input :aclr
  input :byteena, width: :width_byteena
  input :data, width: :width
  input :inclock
  input :inclocken
  input :outclock
  input :outclocken
  output :q, width: :width
  input :rdaddress, width: :widthad
  input :rdaddressstall
  input :rden
  input :sclr
  input :wraddress, width: :widthad
  input :wraddressstall
  input :wren

  assign :q,
    0

end
