# frozen_string_literal: true

class MemoryWrite < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: memory_write

  def self._import_decl_kinds
    {
      __VdfgRegularize_hb4b9eb03_0_0: :logic,
      __VdfgRegularize_hb4b9eb03_0_1: :logic,
      __VdfgRegularize_hb4b9eb03_0_2: :logic,
      __VdfgRegularize_hb4b9eb03_0_3: :logic,
      _unused_ok: :wire,
      ac_fault: :reg,
      address_2_reg: :reg,
      address_2_reg_to_reg: :wire,
      buffer: :reg,
      buffer_to_reg: :wire,
      cond_0: :wire,
      cond_1: :wire,
      cond_2: :wire,
      cond_4: :wire,
      cond_5: :wire,
      cond_6: :wire,
      cond_8: :wire,
      cond_9: :wire,
      left_in_line: :wire,
      length_1: :wire,
      length_2_reg: :reg,
      length_2_reg_to_reg: :wire,
      page_fault: :reg,
      reset_waiting: :reg,
      state: :reg,
      state_to_reg: :wire
    }
  end

  # Parameters

  generic :STATE_IDLE, default: "2'h0"
  generic :STATE_FIRST_WAIT, default: "2'h1"
  generic :STATE_SECOND, default: "2'h2"

  # Ports

  input :clk
  input :rst_n
  input :wr_reset
  input :write_do
  output :write_done
  output :write_page_fault
  output :write_ac_fault
  input :write_cpl, width: 2
  input :write_address, width: 32
  input :write_length, width: 3
  input :write_lock
  input :write_rmw
  input :write_data, width: 32
  output :tlbwrite_do
  input :tlbwrite_done
  input :tlbwrite_page_fault
  input :tlbwrite_ac_fault
  output :tlbwrite_cpl, width: 2
  output :tlbwrite_address, width: 32
  output :tlbwrite_length, width: 3
  output :tlbwrite_length_full, width: 3
  output :tlbwrite_lock
  output :tlbwrite_rmw
  output :tlbwrite_data, width: 32

  # Signals

  signal :__VdfgRegularize_hb4b9eb03_0_0
  signal :__VdfgRegularize_hb4b9eb03_0_1
  signal :__VdfgRegularize_hb4b9eb03_0_2
  signal :__VdfgRegularize_hb4b9eb03_0_3
  signal :_unused_ok
  signal :ac_fault
  signal :address_2_reg, width: 32
  signal :address_2_reg_to_reg, width: 32
  signal :buffer, width: 24
  signal :buffer_to_reg, width: 24
  signal :cond_0
  signal :cond_1
  signal :cond_2
  signal :cond_4
  signal :cond_5
  signal :cond_6
  signal :cond_8
  signal :cond_9
  signal :left_in_line, width: 5
  signal :length_1, width: 3
  signal :length_2_reg, width: 3
  signal :length_2_reg_to_reg, width: 3
  signal :page_fault
  signal :reset_waiting
  signal :state, width: 2
  signal :state_to_reg, width: 2

  # Assignments

  assign :write_page_fault,
    (
        sig(:page_fault, width: 1) |
        sig(:tlbwrite_page_fault, width: 1)
    )
  assign :write_ac_fault,
    (
        sig(:ac_fault, width: 1) |
        sig(:tlbwrite_ac_fault, width: 1)
    )
  assign :left_in_line,
    (
        lit(16, width: 5, base: "h", signed: false) -
        lit(0, width: 1, base: "d", signed: false).concat(
        sig(:write_address, width: 32)[3..0]
      )
    )
  assign :length_1,
    mux(
      (
          sig(:left_in_line, width: 5) >=
          lit(0, width: 2, base: "d", signed: false).concat(
          sig(:write_length, width: 3)
        )
      ),
      sig(:write_length, width: 3),
      sig(:left_in_line, width: 5)[2..0]
    )
  assign :tlbwrite_length_full,
    sig(:write_length, width: 3)
  assign :cond_0,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:state, width: 2)
    )
  assign :cond_1,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:length_1, width: 3)
    )
  assign :cond_2,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:length_1, width: 3)
    )
  assign :cond_4,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:state, width: 2)
    )
  assign :cond_5,
    (
        sig(:tlbwrite_ac_fault, width: 1) |
        sig(:tlbwrite_page_fault, width: 1)
    )
  assign :cond_6,
    (
        sig(:tlbwrite_done, width: 1) &
        (
            lit(0, width: 3, base: "h", signed: false) !=
            sig(:length_2_reg, width: 3)
        )
    )
  assign :cond_8,
    (
      ~sig(:reset_waiting, width: 1)
    )
  assign :cond_9,
    (
        lit(2, width: 2, base: "h", signed: false) ==
        sig(:state, width: 2)
    )
  assign :buffer_to_reg,
    mux(
      (
          sig(:cond_0, width: 1) &
          sig(:cond_1, width: 1)
      ),
      sig(:write_data, width: 32)[31..8],
      mux(
        (
            sig(:__VdfgRegularize_hb4b9eb03_0_3, width: 1) &
            sig(:cond_2, width: 1)
        ),
        lit(0, width: 8, base: "d", signed: false).concat(
          sig(:write_data, width: 32)[31..16]
        ),
        mux(
          (
              (
                ~sig(:cond_2, width: 1)
              ) &
              sig(:__VdfgRegularize_hb4b9eb03_0_3, width: 1)
          ),
          lit(0, width: 16, base: "d", signed: false).concat(
            sig(:write_data, width: 32)[31..24]
          ),
          sig(:buffer, width: 24)
        )
      )
    )
  assign :__VdfgRegularize_hb4b9eb03_0_3,
    (
        (
          ~sig(:cond_1, width: 1)
        ) &
        sig(:cond_0, width: 1)
    )
  assign :address_2_reg_to_reg,
    mux(
      sig(:cond_0, width: 1),
      (
          (
              (
                  lit(16, width: 32, base: "h", signed: false) +
                  sig(:write_address, width: 32)[31..4].concat(
                  lit(0, width: 4, base: "h", signed: false)
                )
              ) >>
              lit(4, width: 32, base: "h", signed: false)
          ) &
          (
              (
                  lit(1, width: 32, base: "d") <<
                  (
                        (
                          (
                              lit(4, width: 32, base: "h", signed: false) +
                              lit(27, width: nil, base: "d", signed: false)
                          )
                        ) -
                        (
                          lit(4, width: 32, base: "h", signed: false)
                        ) +
                      lit(1, width: 32, base: "d")
                  )
              ) -
              lit(1, width: 32, base: "d")
          )
      ).concat(
        lit(0, width: 4, base: "h", signed: false)
      ),
      sig(:address_2_reg, width: 32)
    )
  assign :length_2_reg_to_reg,
    mux(
      sig(:cond_0, width: 1),
      (
          sig(:write_length, width: 3) -
          sig(:length_1, width: 3)
      ),
      sig(:length_2_reg, width: 3)
    )
  assign :state_to_reg,
    mux(
      sig(:__VdfgRegularize_hb4b9eb03_0_0, width: 1),
      lit(1, width: 2, base: "h", signed: false),
      mux(
        (
            sig(:cond_4, width: 1) &
            sig(:cond_5, width: 1)
        ),
        lit(0, width: 2, base: "h", signed: false),
        mux(
          (
              sig(:__VdfgRegularize_hb4b9eb03_0_2, width: 1) &
              sig(:cond_6, width: 1)
          ),
          lit(2, width: 2, base: "h", signed: false),
          mux(
            sig(:__VdfgRegularize_hb4b9eb03_0_1, width: 1),
            lit(0, width: 2, base: "h", signed: false),
            mux(
              (
                  sig(:cond_9, width: 1) &
                  (
                      sig(:cond_5, width: 1) |
                      sig(:tlbwrite_done, width: 1)
                  )
              ),
              lit(0, width: 2, base: "h", signed: false),
              sig(:state, width: 2)
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hb4b9eb03_0_0,
    (
        sig(:cond_0, width: 1) &
        (
            (
              ~sig(:wr_reset, width: 1)
            ) &
            (
                (
                  ~(
                      sig(:write_page_fault, width: 1) |
                      sig(:write_ac_fault, width: 1)
                  )
                ) &
                sig(:write_do, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hb4b9eb03_0_2,
    (
        (
          ~sig(:cond_5, width: 1)
        ) &
        sig(:cond_4, width: 1)
    )
  assign :__VdfgRegularize_hb4b9eb03_0_1,
    (
        sig(:__VdfgRegularize_hb4b9eb03_0_2, width: 1) &
        (
            (
              ~sig(:cond_6, width: 1)
            ) &
            sig(:tlbwrite_done, width: 1)
        )
    )
  assign :write_done,
    (
        (
            sig(:cond_8, width: 1) &
            sig(:__VdfgRegularize_hb4b9eb03_0_1, width: 1)
        ) |
        (
            sig(:cond_9, width: 1) &
            (
                sig(:cond_8, width: 1) &
                sig(:tlbwrite_done, width: 1)
            )
        )
    )
  assign :tlbwrite_do,
    (
        sig(:__VdfgRegularize_hb4b9eb03_0_0, width: 1) |
        (
            sig(:cond_4, width: 1) |
            sig(:cond_9, width: 1)
        )
    )
  assign :tlbwrite_address,
    mux(
      sig(:cond_0, width: 1),
      sig(:write_address, width: 32),
      mux(
        sig(:cond_4, width: 1),
        sig(:write_address, width: 32),
        mux(
          sig(:cond_9, width: 1),
          sig(:address_2_reg, width: 32),
          lit(0, width: 32, base: "h", signed: false)
        )
      )
    )
  assign :tlbwrite_length,
    mux(
      sig(:cond_0, width: 1),
      sig(:length_1, width: 3),
      mux(
        sig(:cond_4, width: 1),
        sig(:length_1, width: 3),
        mux(
          sig(:cond_9, width: 1),
          sig(:length_2_reg, width: 3),
          lit(0, width: 3, base: "h", signed: false)
        )
      )
    )
  assign :tlbwrite_data,
    mux(
      sig(:cond_0, width: 1),
      sig(:write_data, width: 32),
      mux(
        sig(:cond_4, width: 1),
        sig(:write_data, width: 32),
        mux(
          sig(:cond_9, width: 1),
          lit(0, width: 8, base: "d", signed: false).concat(
            sig(:buffer, width: 24)
          ),
          lit(0, width: 32, base: "h", signed: false)
        )
      )
    )
  assign :tlbwrite_cpl,
    sig(:write_cpl, width: 2)
  assign :tlbwrite_lock,
    sig(:write_lock, width: 1)
  assign :tlbwrite_rmw,
    sig(:write_rmw, width: 1)

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:wr_reset, width: 1) & (lit(0, width: 2, base: "h", signed: false) != sig(:state, width: 2)))) do
        assign(
          :reset_waiting,
          lit(1, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block((lit(0, width: 2, base: "h", signed: false) == sig(:state, width: 2))) do
          assign(
            :reset_waiting,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :reset_waiting,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:wr_reset, width: 1)) do
        assign(
          :page_fault,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block((sig(:tlbwrite_page_fault, width: 1) & (~sig(:reset_waiting, width: 1)))) do
          assign(
            :page_fault,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :page_fault,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:wr_reset, width: 1)) do
        assign(
          :ac_fault,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block((sig(:tlbwrite_ac_fault, width: 1) & (~sig(:reset_waiting, width: 1)))) do
          assign(
            :ac_fault,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :ac_fault,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_3,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :_unused_ok,
      lit(0, width: 1, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :sequential_posedge_clk_4,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :buffer,
      mux(
        sig(:rst_n, width: 1),
        sig(:buffer_to_reg, width: 24),
        lit(0, width: 24, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_5,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :address_2_reg,
      mux(
        sig(:rst_n, width: 1),
        sig(:address_2_reg_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_6,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :length_2_reg,
      mux(
        sig(:rst_n, width: 1),
        sig(:length_2_reg_to_reg, width: 3),
        lit(0, width: 3, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_7,
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

end
