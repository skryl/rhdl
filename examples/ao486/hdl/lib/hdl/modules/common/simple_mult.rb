# frozen_string_literal: true

class SimpleMultW21WB21WC42 < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: simple_mult__W21_WB21_WC42

  def self._import_decl_kinds
    {
      a_reg: :reg,
      b_reg: :reg,
      mult_out: :wire,
      out_1: :reg
    }
  end

  # Parameters

  generic :widtha, default: "32'sh21"
  generic :widthb, default: "32'sh21"
  generic :widthp, default: "32'sh42"

  # Ports

  input :clk
  input :a, width: 33
  input :b, width: 33
  output :out, width: 66

  # Signals

  signal :a_reg, width: 33
  signal :b_reg, width: 33
  signal :mult_out, width: 66
  signal :out_1, width: 66

  # Assignments

  assign :out,
    sig(:out_1, width: 66)

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :a_reg,
      sig(:a, width: 33),
      kind: :nonblocking
    )
    assign(
      :b_reg,
      sig(:b, width: 33),
      kind: :nonblocking
    )
    assign(
      :out_1,
      sig(:mult_out, width: 66),
      kind: :nonblocking
    )
  end

end
