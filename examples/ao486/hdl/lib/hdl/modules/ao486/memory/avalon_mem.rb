# frozen_string_literal: true

class AvalonMem < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: avalon_mem

  def self._import_decl_kinds
    {
      __VdfgRegularize_h48595f48_0_0: :logic,
      __VdfgRegularize_h48595f48_0_1: :logic,
      __VdfgRegularize_h48595f48_0_10: :logic,
      __VdfgRegularize_h48595f48_0_11: :logic,
      __VdfgRegularize_h48595f48_0_12: :logic,
      __VdfgRegularize_h48595f48_0_13: :logic,
      __VdfgRegularize_h48595f48_0_14: :logic,
      __VdfgRegularize_h48595f48_0_15: :logic,
      __VdfgRegularize_h48595f48_0_16: :logic,
      __VdfgRegularize_h48595f48_0_2: :logic,
      __VdfgRegularize_h48595f48_0_3: :logic,
      __VdfgRegularize_h48595f48_0_4: :logic,
      __VdfgRegularize_h48595f48_0_5: :logic,
      __VdfgRegularize_h48595f48_0_6: :logic,
      __VdfgRegularize_h48595f48_0_7: :logic,
      __VdfgRegularize_h48595f48_0_8: :logic,
      __VdfgRegularize_h48595f48_0_9: :logic,
      bus_0: :reg,
      bus_1: :reg,
      byteenable_next: :reg,
      counter: :reg,
      len_be: :reg,
      readaddrmux: :reg,
      readburst_data: :wire,
      readburst_dword_length: :wire,
      save_readburst: :reg,
      state: :reg,
      writeaddr_next: :reg,
      writeburst_byteenable_0: :wire,
      writeburst_byteenable_1: :wire,
      writeburst_data: :wire,
      writeburst_dword_length: :wire,
      writedata_next: :reg
    }
  end

  # Parameters

  generic :STATE_IDLE, default: "3'h0"
  generic :STATE_WRITE, default: "3'h1"
  generic :STATE_READ, default: "3'h2"
  generic :STATE_READ_CODE, default: "3'h3"
  generic :STATE_WRITE_DMA, default: "3'h4"
  generic :STATE_READ_DMA, default: "3'h5"

  # Ports

  input :clk
  input :rst_n
  input :writeburst_do
  output :writeburst_done
  input :writeburst_address, width: 32
  input :writeburst_length, width: 3
  input :writeburst_data_in, width: 32
  input :readburst_do
  output :readburst_done
  input :readburst_address, width: 32
  input :readburst_length, width: 4
  output :readburst_data_out, width: 96
  input :readcode_do
  output :readcode_done
  input :readcode_address, width: 32
  output :readcode_partial, width: 32
  output :snoop_addr, width: (27..2)
  output :snoop_data, width: 32
  output :snoop_be, width: 4
  output :snoop_we, width: 4
  output :avm_address, width: (31..2)
  output :avm_writedata, width: 32
  output :avm_byteenable, width: 4
  output :avm_burstcount, width: 4
  output :avm_write
  output :avm_read
  input :avm_waitrequest
  input :avm_readdatavalid
  input :avm_readdata, width: 32
  input :dma_address, width: 24
  input :dma_16bit
  input :dma_write
  input :dma_writedata, width: 16
  input :dma_read
  output :dma_readdata, width: 16
  output :dma_readdatavalid
  output :dma_waitrequest

  # Signals

  signal :__VdfgRegularize_h48595f48_0_0
  signal :__VdfgRegularize_h48595f48_0_1
  signal :__VdfgRegularize_h48595f48_0_10
  signal :__VdfgRegularize_h48595f48_0_11
  signal :__VdfgRegularize_h48595f48_0_12
  signal :__VdfgRegularize_h48595f48_0_13
  signal :__VdfgRegularize_h48595f48_0_14
  signal :__VdfgRegularize_h48595f48_0_15, width: 4
  signal :__VdfgRegularize_h48595f48_0_16, width: 64
  signal :__VdfgRegularize_h48595f48_0_2
  signal :__VdfgRegularize_h48595f48_0_3
  signal :__VdfgRegularize_h48595f48_0_4
  signal :__VdfgRegularize_h48595f48_0_5
  signal :__VdfgRegularize_h48595f48_0_6
  signal :__VdfgRegularize_h48595f48_0_7
  signal :__VdfgRegularize_h48595f48_0_8
  signal :__VdfgRegularize_h48595f48_0_9
  signal :bus_0, width: 32
  signal :bus_1, width: 32
  signal :byteenable_next, width: 4
  signal :counter, width: 3
  signal :len_be, width: (0..6)
  signal :readaddrmux, width: 2
  signal :readburst_data, width: 96
  signal :readburst_dword_length, width: 2
  signal :save_readburst, width: 2
  signal :state, width: 3
  signal :writeaddr_next, width: (31..2)
  signal :writeburst_byteenable_0, width: 4
  signal :writeburst_byteenable_1, width: 4
  signal :writeburst_data, width: 56
  signal :writeburst_dword_length, width: 2
  signal :writedata_next, width: 32

  # Assignments

  assign :readburst_dword_length,
    mux(
      (
          (
              lit(2, width: 4, base: "h", signed: false) ==
              sig(:readburst_length, width: 4)
          ) &
          sig(:__VdfgRegularize_h48595f48_0_0, width: 1)
      ),
      lit(2, width: 2, base: "h", signed: false),
      mux(
        (
            (
                lit(3, width: 4, base: "h", signed: false) ==
                sig(:readburst_length, width: 4)
            ) &
            sig(:readburst_address, width: 32)[1]
        ),
        lit(2, width: 2, base: "h", signed: false),
        mux(
          (
              (
                  lit(4, width: 4, base: "h", signed: false) ==
                  sig(:readburst_length, width: 4)
              ) &
              sig(:__VdfgRegularize_h48595f48_0_1, width: 1)
          ),
          lit(2, width: 2, base: "h", signed: false),
          mux(
            (
                lit(4, width: 4, base: "h", signed: false) >=
                sig(:readburst_length, width: 4)
            ),
            lit(1, width: 2, base: "h", signed: false),
            mux(
              (
                  lit(5, width: 4, base: "h", signed: false) ==
                  sig(:readburst_length, width: 4)
              ),
              lit(2, width: 2, base: "h", signed: false),
              mux(
                (
                    (
                        lit(6, width: 4, base: "h", signed: false) ==
                        sig(:readburst_length, width: 4)
                    ) &
                    sig(:__VdfgRegularize_h48595f48_0_0, width: 1)
                ),
                lit(3, width: 2, base: "h", signed: false),
                mux(
                  (
                      (
                          lit(7, width: 4, base: "h", signed: false) ==
                          sig(:readburst_length, width: 4)
                      ) &
                      sig(:readburst_address, width: 32)[1]
                  ),
                  lit(3, width: 2, base: "h", signed: false),
                  mux(
                    (
                        (
                            lit(8, width: 4, base: "h", signed: false) ==
                            sig(:readburst_length, width: 4)
                        ) &
                        sig(:__VdfgRegularize_h48595f48_0_1, width: 1)
                    ),
                    lit(3, width: 2, base: "h", signed: false),
                    lit(2, width: 2, base: "h", signed: false)
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h48595f48_0_0,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:readburst_address, width: 32)[1..0]
    )
  assign :__VdfgRegularize_h48595f48_0_1,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:readburst_address, width: 32)[1..0]
    )
  assign :readburst_data_out,
    case_select(
      sig(:readaddrmux, width: 2),
      cases: {
        0 => lit(0, width: 32, base: "d", signed: false).concat(sig(:__VdfgRegularize_h48595f48_0_16, width: 64)),
        1 => lit(0, width: 32, base: "d", signed: false).concat(sig(:readburst_data, width: 96)[71..8]),
        2 => lit(0, width: 32, base: "d", signed: false).concat(sig(:readburst_data, width: 96)[79..16])
      },
      default: lit(0, width: 32, base: "d", signed: false).concat(
        sig(:readburst_data, width: 96)[87..24]
      )
    )
  assign :__VdfgRegularize_h48595f48_0_16,
    mux(
      u(
        :&,
        sig(:save_readburst, width: 2)
      ),
      sig(:bus_0, width: 32),
      sig(:avm_readdata, width: 32)
    ).concat(
      mux(
        sig(:save_readburst, width: 2)[1],
        sig(:bus_1, width: 32),
        sig(:avm_readdata, width: 32)
      )
    )
  assign :readburst_data,
    sig(:avm_readdata, width: 32).concat(
      sig(:__VdfgRegularize_h48595f48_0_16, width: 64)
    )
  assign :readcode_partial,
    sig(:avm_readdata, width: 32)
  assign :writeburst_dword_length,
    mux(
      (
          sig(:__VdfgRegularize_h48595f48_0_2, width: 1) &
          sig(:__VdfgRegularize_h48595f48_0_3, width: 1)
      ),
      lit(2, width: 2, base: "h", signed: false),
      mux(
        (
            sig(:__VdfgRegularize_h48595f48_0_4, width: 1) &
            sig(:writeburst_address, width: 32)[1]
        ),
        lit(2, width: 2, base: "h", signed: false),
        mux(
          (
              sig(:__VdfgRegularize_h48595f48_0_5, width: 1) &
              (
                  lit(0, width: 2, base: "h", signed: false) !=
                  sig(:writeburst_address, width: 32)[1..0]
              )
          ),
          lit(2, width: 2, base: "h", signed: false),
          lit(1, width: 2, base: "h", signed: false)
        )
      )
    )
  assign :__VdfgRegularize_h48595f48_0_2,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:writeburst_length, width: 3)
    )
  assign :__VdfgRegularize_h48595f48_0_3,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:writeburst_address, width: 32)[1..0]
    )
  assign :__VdfgRegularize_h48595f48_0_4,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:writeburst_length, width: 3)
    )
  assign :__VdfgRegularize_h48595f48_0_5,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:writeburst_length, width: 3)
    )
  assign :writeburst_byteenable_0,
    mux(
      (
          sig(:__VdfgRegularize_h48595f48_0_6, width: 1) &
          sig(:__VdfgRegularize_h48595f48_0_7, width: 1)
      ),
      lit(1, width: 4, base: "h", signed: false),
      mux(
        (
            sig(:__VdfgRegularize_h48595f48_0_8, width: 1) &
            sig(:__VdfgRegularize_h48595f48_0_7, width: 1)
        ),
        lit(2, width: 4, base: "h", signed: false),
        mux(
          (
              sig(:__VdfgRegularize_h48595f48_0_9, width: 1) &
              sig(:__VdfgRegularize_h48595f48_0_7, width: 1)
          ),
          lit(4, width: 4, base: "h", signed: false),
          mux(
            (
                sig(:__VdfgRegularize_h48595f48_0_6, width: 1) &
                sig(:__VdfgRegularize_h48595f48_0_2, width: 1)
            ),
            lit(3, width: 4, base: "h", signed: false),
            mux(
              (
                  sig(:__VdfgRegularize_h48595f48_0_8, width: 1) &
                  sig(:__VdfgRegularize_h48595f48_0_2, width: 1)
              ),
              lit(6, width: 4, base: "h", signed: false),
              mux(
                (
                    sig(:__VdfgRegularize_h48595f48_0_6, width: 1) &
                    sig(:__VdfgRegularize_h48595f48_0_4, width: 1)
                ),
                lit(7, width: 4, base: "h", signed: false),
                mux(
                  (
                      sig(:__VdfgRegularize_h48595f48_0_8, width: 1) &
                      (
                          lit(3, width: 3, base: "h", signed: false) <=
                          sig(:writeburst_length, width: 3)
                      )
                  ),
                  lit(14, width: 4, base: "h", signed: false),
                  mux(
                    (
                        sig(:__VdfgRegularize_h48595f48_0_9, width: 1) &
                        (
                            lit(2, width: 3, base: "h", signed: false) <=
                            sig(:writeburst_length, width: 3)
                        )
                    ),
                    lit(12, width: 4, base: "h", signed: false),
                    mux(
                      (
                          sig(:__VdfgRegularize_h48595f48_0_6, width: 1) &
                          sig(:__VdfgRegularize_h48595f48_0_5, width: 1)
                      ),
                      lit(15, width: 4, base: "h", signed: false),
                      lit(8, width: 4, base: "h", signed: false)
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h48595f48_0_6,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:writeburst_address, width: 32)[1..0]
    )
  assign :__VdfgRegularize_h48595f48_0_7,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:writeburst_length, width: 3)
    )
  assign :__VdfgRegularize_h48595f48_0_8,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:writeburst_address, width: 32)[1..0]
    )
  assign :__VdfgRegularize_h48595f48_0_9,
    (
        lit(2, width: 2, base: "h", signed: false) ==
        sig(:writeburst_address, width: 32)[1..0]
    )
  assign :writeburst_byteenable_1,
    mux(
      (
          sig(:__VdfgRegularize_h48595f48_0_3, width: 1) &
          sig(:__VdfgRegularize_h48595f48_0_2, width: 1)
      ),
      lit(1, width: 4, base: "h", signed: false),
      mux(
        (
            sig(:__VdfgRegularize_h48595f48_0_9, width: 1) &
            sig(:__VdfgRegularize_h48595f48_0_4, width: 1)
        ),
        lit(1, width: 4, base: "h", signed: false),
        mux(
          (
              sig(:__VdfgRegularize_h48595f48_0_3, width: 1) &
              sig(:__VdfgRegularize_h48595f48_0_4, width: 1)
          ),
          lit(3, width: 4, base: "h", signed: false),
          mux(
            (
                sig(:__VdfgRegularize_h48595f48_0_8, width: 1) &
                sig(:__VdfgRegularize_h48595f48_0_5, width: 1)
            ),
            lit(1, width: 4, base: "h", signed: false),
            mux(
              (
                  sig(:__VdfgRegularize_h48595f48_0_9, width: 1) &
                  sig(:__VdfgRegularize_h48595f48_0_5, width: 1)
              ),
              lit(3, width: 4, base: "h", signed: false),
              lit(7, width: 4, base: "h", signed: false)
            )
          )
        )
      )
    )
  assign :writeburst_data,
    mux(
      sig(:__VdfgRegularize_h48595f48_0_6, width: 1),
      lit(0, width: 24, base: "d", signed: false).concat(
        sig(:writeburst_data_in, width: 32)
      ),
      mux(
        sig(:__VdfgRegularize_h48595f48_0_8, width: 1),
        lit(0, width: 16, base: "d", signed: false).concat(
          sig(:writeburst_data_in, width: 32).concat(
            lit(0, width: 8, base: "h", signed: false)
          )
        ),
        mux(
          sig(:__VdfgRegularize_h48595f48_0_9, width: 1),
          lit(0, width: 8, base: "d", signed: false).concat(
            sig(:writeburst_data_in, width: 32).concat(
              lit(0, width: 16, base: "h", signed: false)
            )
          ),
          sig(:writeburst_data_in, width: 32).concat(
            lit(0, width: 24, base: "h", signed: false)
          )
        )
      )
    )
  assign :dma_readdata,
    mux(
      sig(:dma_16bit, width: 1),
      sig(:avm_readdata, width: 32)[(sig(:dma_address, width: 24)[1].concat(lit(0, width: 4, base: "h", signed: false)) + lit(15, width: nil, base: "d", signed: false))..sig(:dma_address, width: 24)[1].concat(lit(0, width: 4, base: "h", signed: false))],
      lit(0, width: 8, base: "d", signed: false).concat(
        sig(:avm_readdata, width: 32)[(sig(:dma_address, width: 24)[1..0].concat(lit(0, width: 3, base: "h", signed: false)) + lit(7, width: nil, base: "d", signed: false))..sig(:dma_address, width: 24)[1..0].concat(lit(0, width: 3, base: "h", signed: false))]
      )
    )
  assign :dma_waitrequest,
    (
        (
            lit(5, width: 3, base: "h", signed: false) !=
            sig(:state, width: 3)
        ) &
        (
            lit(4, width: 3, base: "h", signed: false) !=
            sig(:state, width: 3)
        )
    )
  assign :dma_readdatavalid,
    (
        (
            lit(5, width: 3, base: "h", signed: false) ==
            sig(:state, width: 3)
        ) &
        sig(:avm_readdatavalid, width: 1)
    )
  assign :writeburst_done,
    (
        sig(:__VdfgRegularize_h48595f48_0_10, width: 1) &
        (
            sig(:__VdfgRegularize_h48595f48_0_11, width: 1) &
            sig(:writeburst_do, width: 1)
        )
    )
  assign :__VdfgRegularize_h48595f48_0_10,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:state, width: 3)
    )
  assign :__VdfgRegularize_h48595f48_0_11,
    (
      ~sig(:avm_waitrequest, width: 1)
    )
  assign :readburst_done,
    (
        (
            lit(2, width: 3, base: "h", signed: false) ==
            sig(:state, width: 3)
        ) &
        (
            (
                lit(0, width: 3, base: "h", signed: false) ==
                sig(:counter, width: 3)
            ) &
            sig(:avm_readdatavalid, width: 1)
        )
    )
  assign :readcode_done,
    (
        (
            lit(3, width: 3, base: "h", signed: false) ==
            sig(:state, width: 3)
        ) &
        sig(:avm_readdatavalid, width: 1)
    )
  assign :avm_address,
    mux(
      sig(:__VdfgRegularize_h48595f48_0_12, width: 1),
      sig(:writeaddr_next, width: 30),
      mux(
        sig(:writeburst_do, width: 1),
        sig(:writeburst_address, width: 32)[31..2],
        mux(
          sig(:readburst_do, width: 1),
          sig(:readburst_address, width: 32)[31..2],
          mux(
            sig(:readcode_do, width: 1),
            sig(:readcode_address, width: 32)[31..2],
            lit(0, width: 8, base: "d", signed: false).concat(
              sig(:dma_address, width: 24)[23..2]
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h48595f48_0_12,
    (
        lit(0, width: 3, base: "h", signed: false) !=
        sig(:state, width: 3)
    )
  assign :avm_writedata,
    sig(:snoop_data, width: 32)
  assign :snoop_data,
    mux(
      sig(:__VdfgRegularize_h48595f48_0_12, width: 1),
      sig(:writedata_next, width: 32),
      mux(
        sig(:writeburst_do, width: 1),
        sig(:writeburst_data, width: 56)[31..0],
        mux(
          sig(:dma_16bit, width: 1),
          sig(:dma_writedata, width: 16).replicate(
            lit(2, width: 32, base: "h", signed: true)
          ),
          sig(:dma_writedata, width: 16)[7..0].replicate(
            lit(4, width: 32, base: "h", signed: true)
          )
        )
      )
    )
  assign :avm_byteenable,
    mux(
      sig(:__VdfgRegularize_h48595f48_0_12, width: 1),
      sig(:byteenable_next, width: 4),
      mux(
        sig(:writeburst_do, width: 1),
        sig(:writeburst_byteenable_0, width: 4),
        mux(
          sig(:__VdfgRegularize_h48595f48_0_13, width: 1),
          sig(:len_be, width: 7)[((lit(3, width: 3, base: "h", signed: false) - lit(0, width: 1, base: "d", signed: false).concat(sig(:readburst_address, width: 32)[1..0])) + lit(3, width: nil, base: "d", signed: false))..(lit(3, width: 3, base: "h", signed: false) - lit(0, width: 1, base: "d", signed: false).concat(sig(:readburst_address, width: 32)[1..0]))],
          sig(:__VdfgRegularize_h48595f48_0_15, width: 4)
        )
      )
    )
  assign :__VdfgRegularize_h48595f48_0_13,
    (
        sig(:readburst_do, width: 1) |
        sig(:readcode_do, width: 1)
    )
  assign :__VdfgRegularize_h48595f48_0_15,
    mux(
      sig(:dma_16bit, width: 1),
      sig(:dma_address, width: 24)[1].concat(
        sig(:dma_address, width: 24)[1].concat(
          sig(:__VdfgRegularize_h48595f48_0_14, width: 1).replicate(
            lit(2, width: 32, base: "h", signed: false)
          )
        )
      ),
      (
          lit(1, width: 4, base: "h", signed: false) <<
          sig(:dma_address, width: 24)[1..0]
      )
    )
  assign :avm_burstcount,
    mux(
      sig(:readburst_do, width: 1),
      lit(0, width: 2, base: "d", signed: false).concat(
        sig(:readburst_dword_length, width: 2)
      ),
      mux(
        sig(:readcode_do, width: 1),
        lit(8, width: 4, base: "h", signed: false),
        lit(1, width: 4, base: "h", signed: false)
      )
    )
  assign :avm_write,
    (
        sig(:rst_n, width: 1) &
        (
            (
                sig(:__VdfgRegularize_h48595f48_0_10, width: 1) &
                (
                    sig(:writeburst_do, width: 1) |
                    (
                        (
                          ~(
                              sig(:writeburst_do, width: 1) |
                              sig(:__VdfgRegularize_h48595f48_0_13, width: 1)
                          )
                        ) &
                        sig(:dma_write, width: 1)
                    )
                )
            ) |
            (
                lit(1, width: 3, base: "h", signed: false) ==
                sig(:state, width: 3)
            )
        )
    )
  assign :avm_read,
    (
        sig(:rst_n, width: 1) &
        (
            sig(:__VdfgRegularize_h48595f48_0_10, width: 1) &
            (
                (
                  ~sig(:writeburst_do, width: 1)
                ) &
                (
                    sig(:__VdfgRegularize_h48595f48_0_13, width: 1) |
                    sig(:dma_read, width: 1)
                )
            )
        )
    )
  assign :snoop_addr,
    sig(:avm_address, width: 30)[25..0]
  assign :snoop_be,
    mux(
      sig(:__VdfgRegularize_h48595f48_0_12, width: 1),
      sig(:byteenable_next, width: 4),
      mux(
        sig(:writeburst_do, width: 1),
        sig(:writeburst_byteenable_0, width: 4),
        sig(:__VdfgRegularize_h48595f48_0_15, width: 4)
      )
    )
  assign :snoop_we,
    (
        (
          ~u(:|, sig(:avm_address, width: 30)[29..26])
        ) &
        (
            sig(:__VdfgRegularize_h48595f48_0_11, width: 1) &
            sig(:avm_write, width: 1)
        )
    )
  assign :__VdfgRegularize_h48595f48_0_14,
    (
      ~sig(:dma_address, width: 24)[1]
    )

  # Processes

  process :combinational_logic_0,
    sensitivity: [
    ],
    clocked: false,
    initial: false do
    case_stmt(lit(0, width: 28, base: "d", signed: false).concat(sig(:readburst_length, width: 4))) do
      when_value(lit(1, width: 32, base: "h", signed: true)) do
        assign(
          :len_be,
          lit(8, width: 7, base: "h", signed: false),
          kind: :blocking
        )
      end
      when_value(lit(2, width: 32, base: "h", signed: true)) do
        assign(
          :len_be,
          lit(24, width: 7, base: "h", signed: false),
          kind: :blocking
        )
      end
      when_value(lit(3, width: 32, base: "h", signed: true)) do
        assign(
          :len_be,
          lit(56, width: 7, base: "h", signed: false),
          kind: :blocking
        )
      end
      default do
        assign(
          :len_be,
          lit(120, width: 7, base: "h", signed: false),
          kind: :blocking
        )
      end
    end
  end

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      case_stmt(sig(:state, width: 3)) do
        when_value(lit(0, width: 3, base: "h", signed: false)) do
          assign(
            :readaddrmux,
            sig(:readburst_address, width: 32)[1..0],
            kind: :nonblocking
          )
          if_stmt((~sig(:avm_waitrequest, width: 1))) do
            if_stmt(sig(:writeburst_do, width: 1)) do
              if_stmt((lit(1, width: 2, base: "h", signed: false) < sig(:writeburst_dword_length, width: 2))) do
                assign(
                  :state,
                  lit(1, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
              assign(
                :writedata_next,
                lit(0, width: 8, base: "d", signed: false).concat(
                  sig(:writeburst_data, width: 56)[55..32]
                ),
                kind: :nonblocking
              )
              assign(
                :byteenable_next,
                sig(:writeburst_byteenable_1, width: 4),
                kind: :nonblocking
              )
              assign(
                :writeaddr_next,
                (
                    lit(1, width: 30, base: "h", signed: false) +
                    sig(:writeburst_address, width: 32)[31..2]
                ),
                kind: :nonblocking
              )
              elsif_block(sig(:readburst_do, width: 1)) do
                assign(
                  :state,
                  lit(2, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
                assign(
                  :counter,
                  (
                      lit(0, width: 1, base: "d", signed: false).concat(
                        sig(:readburst_dword_length, width: 2)
                      ) -
                      lit(1, width: 3, base: "h", signed: false)
                  ),
                  kind: :nonblocking
                )
                assign(
                  :save_readburst,
                  sig(:readburst_dword_length, width: 2),
                  kind: :nonblocking
                )
              end
              elsif_block(sig(:readcode_do, width: 1)) do
                assign(
                  :state,
                  lit(3, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
                assign(
                  :counter,
                  lit(7, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
              elsif_block(sig(:dma_write, width: 1)) do
                assign(
                  :state,
                  lit(4, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
              elsif_block(sig(:dma_read, width: 1)) do
                assign(
                  :state,
                  lit(5, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
            end
          end
        end
        when_value(lit(1, width: 3, base: "h", signed: false)) do
          if_stmt((~sig(:avm_waitrequest, width: 1))) do
            assign(
              :state,
              lit(0, width: 3, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
        when_value(lit(2, width: 3, base: "h", signed: false)) do
          if_stmt(sig(:avm_readdatavalid, width: 1)) do
            assign(
              :counter,
              (
                  sig(:counter, width: 3) -
                  lit(1, width: 3, base: "h", signed: false)
              ),
              kind: :nonblocking
            )
            if_stmt(u(:|, sig(:counter, width: 3))) do
              if_stmt(((lit(2, width: 3, base: "h", signed: false) == sig(:counter, width: 3)) | (lit(2, width: 2, base: "h", signed: false) == sig(:save_readburst, width: 2)))) do
                assign(
                  :bus_1,
                  sig(:avm_readdata, width: 32),
                  kind: :nonblocking
                )
              end
              assign(
                :bus_0,
                sig(:avm_readdata, width: 32),
                kind: :nonblocking
              )
              else_block do
                assign(
                  :state,
                  lit(0, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
            end
          end
        end
        when_value(lit(3, width: 3, base: "h", signed: false)) do
          if_stmt(sig(:avm_readdatavalid, width: 1)) do
            assign(
              :counter,
              (
                  sig(:counter, width: 3) -
                  lit(1, width: 3, base: "h", signed: false)
              ),
              kind: :nonblocking
            )
            if_stmt((lit(0, width: 3, base: "h", signed: false) == sig(:counter, width: 3))) do
              assign(
                :state,
                lit(0, width: 3, base: "h", signed: false),
                kind: :nonblocking
              )
            end
          end
        end
        when_value(lit(4, width: 3, base: "h", signed: false)) do
          assign(
            :state,
            lit(0, width: 3, base: "h", signed: false),
            kind: :nonblocking
          )
        end
        when_value(lit(5, width: 3, base: "h", signed: false)) do
          if_stmt(sig(:avm_readdatavalid, width: 1)) do
            assign(
              :state,
              lit(0, width: 3, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :state,
          lit(0, width: 3, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

end
