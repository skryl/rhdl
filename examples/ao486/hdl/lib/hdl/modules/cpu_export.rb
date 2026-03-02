# frozen_string_literal: true

class CpuExport < RHDL::Component
  include RHDL::DSL::Behavior
  include RHDL::DSL::Structure
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: cpu_export
  # generated_blackbox_stub: true

  input :clk
  input :eax
  input :ebp
  input :ebx
  input :ecx
  input :edi
  input :edx
  input :eip
  input :esi
  input :esp
  input :new_export
  input :rst_n

end
