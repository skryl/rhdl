# frozen_string_literal: true

class PrefetchControl < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: prefetch_control

  def self._import_decl_kinds
    {
      __VdfgRegularize_hed09424a_0_0: :logic,
      __VdfgRegularize_hed09424a_0_1: :logic,
      __VdfgRegularize_hed09424a_0_2: :logic,
      cache_disable: :reg,
      cache_disable_to_reg: :wire,
      cond_3: :wire,
      cond_4: :wire,
      left_in_page: :wire,
      length: :wire,
      linear: :reg,
      linear_to_reg: :wire,
      offset_update: :wire,
      physical: :reg,
      physical_to_reg: :wire,
      state: :reg,
      state_to_reg: :wire
    }
  end

  # Parameters

  generic :STATE_TLB_REQUEST, default: "2'h0"
  generic :STATE_ICACHE, default: "2'h1"

  # Ports

  input :clk
  input :rst_n
  input :pr_reset
  input :prefetch_address, width: 32
  input :prefetch_length, width: 5
  input :prefetch_su
  input :prefetchfifo_used, width: 5
  output :tlbcoderequest_do
  output :tlbcoderequest_address, width: 32
  output :tlbcoderequest_su
  input :tlbcode_do
  input :tlbcode_linear, width: 32
  input :tlbcode_physical, width: 32
  input :tlbcode_cache_disable
  output :icacheread_do
  output :icacheread_address, width: 32
  output :icacheread_length, width: 5
  output :icacheread_cache_disable

  # Signals

  signal :__VdfgRegularize_hed09424a_0_0
  signal :__VdfgRegularize_hed09424a_0_1
  signal :__VdfgRegularize_hed09424a_0_2, width: 32
  signal :cache_disable
  signal :cache_disable_to_reg
  signal :cond_3
  signal :cond_4
  signal :left_in_page, width: 13
  signal :length, width: 5
  signal :linear, width: 32
  signal :linear_to_reg, width: 32
  signal :offset_update
  signal :physical, width: 32
  signal :physical_to_reg, width: 32
  signal :state, width: 2
  signal :state_to_reg, width: 2

  # Assignments

  assign :tlbcoderequest_address,
    sig(:prefetch_address, width: 32)
  assign :left_in_page,
    (
        lit(4096, width: 13, base: "h", signed: false) -
        lit(0, width: 1, base: "d", signed: false).concat(
        sig(:prefetch_address, width: 32)[11..0]
      )
    )
  assign :length,
    mux(
      (
          sig(:left_in_page, width: 13) <
          lit(0, width: 8, base: "d", signed: false).concat(
          sig(:prefetch_length, width: 5)
        )
      ),
      sig(:left_in_page, width: 13)[4..0],
      sig(:prefetch_length, width: 5)
    )
  assign :offset_update,
    (
        (
            sig(:prefetch_address, width: 32)[31..12] ==
            sig(:linear, width: 32)[31..12]
        ) &
        (
            sig(:prefetch_address, width: 32)[11..0] !=
            sig(:linear, width: 32)[11..0]
        )
    )
  assign :cond_3,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:state, width: 2)
    )
  assign :cond_4,
    (
        (
            sig(:prefetch_address, width: 32)[31..12] !=
            sig(:linear, width: 32)[31..12]
        ) |
        (
            sig(:pr_reset, width: 1) |
            (
                lit(8, width: 5, base: "h", signed: false) <=
                sig(:prefetchfifo_used, width: 5)
            )
        )
    )
  assign :physical_to_reg,
    mux(
      sig(:__VdfgRegularize_hed09424a_0_0, width: 1),
      sig(:tlbcode_physical, width: 32),
      mux(
        sig(:__VdfgRegularize_hed09424a_0_1, width: 1),
        sig(:__VdfgRegularize_hed09424a_0_2, width: 32),
        sig(:physical, width: 32)
      )
    )
  assign :__VdfgRegularize_hed09424a_0_0,
    (
        sig(:tlbcoderequest_do, width: 1) &
        sig(:tlbcode_do, width: 1)
    )
  assign :__VdfgRegularize_hed09424a_0_1,
    (
        sig(:cond_3, width: 1) &
        sig(:offset_update, width: 1)
    )
  assign :__VdfgRegularize_hed09424a_0_2,
    sig(:physical, width: 32)[31..12].concat(
      sig(:prefetch_address, width: 32)[11..0]
    )
  assign :linear_to_reg,
    mux(
      sig(:__VdfgRegularize_hed09424a_0_0, width: 1),
      sig(:tlbcode_linear, width: 32),
      mux(
        sig(:__VdfgRegularize_hed09424a_0_1, width: 1),
        sig(:linear, width: 32)[31..12].concat(
          sig(:prefetch_address, width: 32)[11..0]
        ),
        sig(:linear, width: 32)
      )
    )
  assign :state_to_reg,
    mux(
      sig(:__VdfgRegularize_hed09424a_0_0, width: 1),
      lit(1, width: 2, base: "h", signed: false),
      mux(
        (
            sig(:cond_3, width: 1) &
            sig(:cond_4, width: 1)
        ),
        lit(0, width: 2, base: "h", signed: false),
        sig(:state, width: 2)
      )
    )
  assign :cache_disable_to_reg,
    mux(
      sig(:__VdfgRegularize_hed09424a_0_0, width: 1),
      sig(:tlbcode_cache_disable, width: 1),
      sig(:cache_disable, width: 1)
    )
  assign :icacheread_length,
    mux(
      sig(:__VdfgRegularize_hed09424a_0_0, width: 1),
      sig(:length, width: 5),
      mux(
        sig(:cond_3, width: 1),
        sig(:length, width: 5),
        lit(0, width: 5, base: "h", signed: false)
      )
    )
  assign :tlbcoderequest_do,
    (
        (
            lit(0, width: 2, base: "h", signed: false) ==
            sig(:state, width: 2)
        ) &
        (
            (
              ~sig(:pr_reset, width: 1)
            ) &
            (
                (
                    lit(0, width: 5, base: "h", signed: false) <
                    sig(:prefetch_length, width: 5)
                ) &
                (
                    lit(3, width: 5, base: "h", signed: false) >
                    sig(:prefetchfifo_used, width: 5)
                )
            )
        )
    )
  assign :icacheread_do,
    (
        sig(:__VdfgRegularize_hed09424a_0_0, width: 1) |
        (
            (
              ~sig(:cond_4, width: 1)
            ) &
            sig(:cond_3, width: 1)
        )
    )
  assign :icacheread_cache_disable,
    mux(
      sig(:__VdfgRegularize_hed09424a_0_0, width: 1),
      sig(:tlbcode_cache_disable, width: 1),
      (
          sig(:cond_3, width: 1) &
          sig(:cache_disable, width: 1)
      )
    )
  assign :icacheread_address,
    mux(
      sig(:__VdfgRegularize_hed09424a_0_0, width: 1),
      sig(:tlbcode_physical, width: 32),
      mux(
        sig(:cond_3, width: 1),
        mux(
          sig(:offset_update, width: 1),
          sig(:__VdfgRegularize_hed09424a_0_2, width: 32),
          sig(:physical, width: 32)
        ),
        lit(0, width: 32, base: "h", signed: false)
      )
    )
  assign :tlbcoderequest_su,
    sig(:prefetch_su, width: 1)

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :physical,
      mux(
        sig(:rst_n, width: 1),
        sig(:physical_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_2,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :linear,
      mux(
        sig(:rst_n, width: 1),
        sig(:linear_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_3,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :state,
      mux(
        sig(:rst_n, width: 1),
        sig(:state_to_reg, width: 2),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_4,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cache_disable,
      (
          sig(:rst_n, width: 1) &
          sig(:cache_disable_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

end
