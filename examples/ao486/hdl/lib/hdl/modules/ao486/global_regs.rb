# frozen_string_literal: true

class GlobalRegs < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: global_regs

  def self._import_decl_kinds
    {}
  end

  # Ports

  input :clk
  input :rst_n
  input :glob_param_1_set
  input :glob_param_1_value, width: 32
  input :glob_param_2_set
  input :glob_param_2_value, width: 32
  input :glob_param_3_set
  input :glob_param_3_value, width: 32
  input :glob_param_4_set
  input :glob_param_4_value, width: 32
  input :glob_param_5_set
  input :glob_param_5_value, width: 32
  input :glob_descriptor_set
  input :glob_descriptor_value, width: 64
  input :glob_descriptor_2_set
  input :glob_descriptor_2_value, width: 64
  output :glob_param_1, width: 32
  output :glob_param_2, width: 32
  output :glob_param_3, width: 32
  output :glob_param_4, width: 32
  output :glob_param_5, width: 32
  output :glob_descriptor, width: 64
  output :glob_descriptor_2, width: 64
  output :glob_desc_base, width: 32
  output :glob_desc_limit, width: 32
  output :glob_desc_2_limit, width: 32

  # Assignments

  assign :glob_desc_limit,
    mux(
      sig(:glob_descriptor, width: 64)[55],
      sig(:glob_descriptor, width: 64)[51..48].concat(
        sig(:glob_descriptor, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:glob_descriptor, width: 64)[51..48].concat(
          sig(:glob_descriptor, width: 64)[15..0]
        )
      )
    )
  assign :glob_desc_base,
    sig(:glob_descriptor, width: 64)[63..56].concat(
      sig(:glob_descriptor, width: 64)[39..16]
    )
  assign :glob_desc_2_limit,
    mux(
      sig(:glob_descriptor_2, width: 64)[55],
      sig(:glob_descriptor_2, width: 64)[51..48].concat(
        sig(:glob_descriptor_2, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:glob_descriptor_2, width: 64)[51..48].concat(
          sig(:glob_descriptor_2, width: 64)[15..0]
        )
      )
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:glob_param_1_set, width: 1)) do
        assign(
          :glob_param_1,
          sig(:glob_param_1_value, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :glob_param_1,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_2,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:glob_param_2_set, width: 1)) do
        assign(
          :glob_param_2,
          sig(:glob_param_2_value, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :glob_param_2,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_3,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:glob_param_3_set, width: 1)) do
        assign(
          :glob_param_3,
          sig(:glob_param_3_value, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :glob_param_3,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_4,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:glob_param_4_set, width: 1)) do
        assign(
          :glob_param_4,
          sig(:glob_param_4_value, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :glob_param_4,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_5,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:glob_param_5_set, width: 1)) do
        assign(
          :glob_param_5,
          sig(:glob_param_5_value, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :glob_param_5,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_6,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:glob_descriptor_set, width: 1)) do
        assign(
          :glob_descriptor,
          sig(:glob_descriptor_value, width: 64),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :glob_descriptor,
          lit(0, width: 64, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_7,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:glob_descriptor_2_set, width: 1)) do
        assign(
          :glob_descriptor_2,
          sig(:glob_descriptor_2_value, width: 64),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :glob_descriptor_2,
          lit(0, width: 64, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

end
