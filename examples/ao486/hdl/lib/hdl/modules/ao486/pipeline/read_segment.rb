# frozen_string_literal: true

class ReadSegment < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: read_segment

  def self._import_decl_kinds
    {
      __VdfgRegularize_hf9ae18de_0_0: :logic,
      __VdfgRegularize_hf9ae18de_0_1: :logic,
      __VdfgRegularize_hf9ae18de_0_10: :logic,
      __VdfgRegularize_hf9ae18de_0_11: :logic,
      __VdfgRegularize_hf9ae18de_0_12: :logic,
      __VdfgRegularize_hf9ae18de_0_13: :logic,
      __VdfgRegularize_hf9ae18de_0_14: :logic,
      __VdfgRegularize_hf9ae18de_0_15: :logic,
      __VdfgRegularize_hf9ae18de_0_16: :logic,
      __VdfgRegularize_hf9ae18de_0_17: :logic,
      __VdfgRegularize_hf9ae18de_0_18: :logic,
      __VdfgRegularize_hf9ae18de_0_19: :logic,
      __VdfgRegularize_hf9ae18de_0_2: :logic,
      __VdfgRegularize_hf9ae18de_0_20: :logic,
      __VdfgRegularize_hf9ae18de_0_21: :logic,
      __VdfgRegularize_hf9ae18de_0_22: :logic,
      __VdfgRegularize_hf9ae18de_0_3: :logic,
      __VdfgRegularize_hf9ae18de_0_4: :logic,
      __VdfgRegularize_hf9ae18de_0_5: :logic,
      __VdfgRegularize_hf9ae18de_0_6: :logic,
      __VdfgRegularize_hf9ae18de_0_7: :logic,
      __VdfgRegularize_hf9ae18de_0_8: :logic,
      __VdfgRegularize_hf9ae18de_0_9: :logic,
      _unused_ok: :wire,
      cs_left: :wire,
      cs_limit: :wire,
      ds_left: :wire,
      ds_limit: :wire,
      es_left: :wire,
      es_limit: :wire,
      fs_left: :wire,
      fs_limit: :wire,
      gs_left: :wire,
      gs_limit: :wire,
      seg_fault: :wire,
      seg_read: :wire,
      seg_select: :wire,
      seg_write: :wire,
      ss_left: :wire,
      ss_limit: :wire
    }
  end

  # Ports

  input :es_cache, width: 64
  input :cs_cache, width: 64
  input :ss_cache, width: 64
  input :ds_cache, width: 64
  input :fs_cache, width: 64
  input :gs_cache, width: 64
  input :tr_cache, width: 64
  input :ldtr_cache, width: 64
  input :es_cache_valid
  input :cs_cache_valid
  input :ss_cache_valid
  input :ds_cache_valid
  input :fs_cache_valid
  input :gs_cache_valid
  input :address_stack_pop
  input :address_stack_pop_next
  input :address_enter_last
  input :address_enter
  input :address_leave
  input :address_edi
  input :read_virtual
  input :read_rmw_virtual
  input :write_virtual_check
  input :rd_address_effective, width: 32
  input :rd_address_effective_ready
  input :read_length, width: 4
  input :rd_prefix_group_2_seg, width: 3
  output :tr_base, width: 32
  output :ldtr_base, width: 32
  output :tr_limit, width: 32
  output :ldtr_limit, width: 32
  output :rd_seg_gp_fault_init
  output :rd_seg_ss_fault_init
  output :rd_seg_linear, width: 32

  # Signals

  signal :__VdfgRegularize_hf9ae18de_0_0, width: 32
  signal :__VdfgRegularize_hf9ae18de_0_1, width: 32
  signal :__VdfgRegularize_hf9ae18de_0_10
  signal :__VdfgRegularize_hf9ae18de_0_11
  signal :__VdfgRegularize_hf9ae18de_0_12
  signal :__VdfgRegularize_hf9ae18de_0_13
  signal :__VdfgRegularize_hf9ae18de_0_14
  signal :__VdfgRegularize_hf9ae18de_0_15
  signal :__VdfgRegularize_hf9ae18de_0_16
  signal :__VdfgRegularize_hf9ae18de_0_17
  signal :__VdfgRegularize_hf9ae18de_0_18
  signal :__VdfgRegularize_hf9ae18de_0_19
  signal :__VdfgRegularize_hf9ae18de_0_2, width: 32
  signal :__VdfgRegularize_hf9ae18de_0_20
  signal :__VdfgRegularize_hf9ae18de_0_21
  signal :__VdfgRegularize_hf9ae18de_0_22
  signal :__VdfgRegularize_hf9ae18de_0_3, width: 32
  signal :__VdfgRegularize_hf9ae18de_0_4, width: 32
  signal :__VdfgRegularize_hf9ae18de_0_5, width: 32
  signal :__VdfgRegularize_hf9ae18de_0_6
  signal :__VdfgRegularize_hf9ae18de_0_7
  signal :__VdfgRegularize_hf9ae18de_0_8
  signal :__VdfgRegularize_hf9ae18de_0_9
  signal :_unused_ok
  signal :cs_left, width: 32
  signal :cs_limit, width: 32
  signal :ds_left, width: 32
  signal :ds_limit, width: 32
  signal :es_left, width: 32
  signal :es_limit, width: 32
  signal :fs_left, width: 32
  signal :fs_limit, width: 32
  signal :gs_left, width: 32
  signal :gs_limit, width: 32
  signal :seg_fault
  signal :seg_read
  signal :seg_select, width: 3
  signal :seg_write
  signal :ss_left, width: 32
  signal :ss_limit, width: 32

  # Assignments

  assign :es_limit,
    mux(
      sig(:es_cache, width: 64)[55],
      sig(:es_cache, width: 64)[51..48].concat(
        sig(:es_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:es_cache, width: 64)[51..48].concat(
          sig(:es_cache, width: 64)[15..0]
        )
      )
    )
  assign :cs_limit,
    mux(
      sig(:cs_cache, width: 64)[55],
      sig(:cs_cache, width: 64)[51..48].concat(
        sig(:cs_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:cs_cache, width: 64)[51..48].concat(
          sig(:cs_cache, width: 64)[15..0]
        )
      )
    )
  assign :ss_limit,
    mux(
      sig(:ss_cache, width: 64)[55],
      sig(:ss_cache, width: 64)[51..48].concat(
        sig(:ss_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:ss_cache, width: 64)[51..48].concat(
          sig(:ss_cache, width: 64)[15..0]
        )
      )
    )
  assign :ds_limit,
    mux(
      sig(:ds_cache, width: 64)[55],
      sig(:ds_cache, width: 64)[51..48].concat(
        sig(:ds_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:ds_cache, width: 64)[51..48].concat(
          sig(:ds_cache, width: 64)[15..0]
        )
      )
    )
  assign :fs_limit,
    mux(
      sig(:fs_cache, width: 64)[55],
      sig(:fs_cache, width: 64)[51..48].concat(
        sig(:fs_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:fs_cache, width: 64)[51..48].concat(
          sig(:fs_cache, width: 64)[15..0]
        )
      )
    )
  assign :gs_limit,
    mux(
      sig(:gs_cache, width: 64)[55],
      sig(:gs_cache, width: 64)[51..48].concat(
        sig(:gs_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:gs_cache, width: 64)[51..48].concat(
          sig(:gs_cache, width: 64)[15..0]
        )
      )
    )
  assign :es_left,
    mux(
      sig(:__VdfgRegularize_hf9ae18de_0_22, width: 1),
      (
          sig(:es_limit, width: 32) -
          sig(:rd_address_effective, width: 32)
      ),
      (
          sig(:__VdfgRegularize_hf9ae18de_0_0, width: 32) -
          sig(:rd_address_effective, width: 32)
      )
    )
  assign :__VdfgRegularize_hf9ae18de_0_22,
    (
        (
          ~sig(:es_cache, width: 64)[42]
        ) |
        sig(:es_cache, width: 64)[43]
    )
  assign :__VdfgRegularize_hf9ae18de_0_0,
    sig(:es_cache, width: 64)[54].replicate(
      lit(16, width: 32, base: "h", signed: true)
    ).concat(
      lit(65535, width: 16, base: "h", signed: false)
    )
  assign :cs_left,
    mux(
      sig(:__VdfgRegularize_hf9ae18de_0_21, width: 1),
      (
          sig(:cs_limit, width: 32) -
          sig(:rd_address_effective, width: 32)
      ),
      (
          sig(:__VdfgRegularize_hf9ae18de_0_1, width: 32) -
          sig(:rd_address_effective, width: 32)
      )
    )
  assign :__VdfgRegularize_hf9ae18de_0_21,
    (
        (
          ~sig(:cs_cache, width: 64)[42]
        ) |
        sig(:cs_cache, width: 64)[43]
    )
  assign :__VdfgRegularize_hf9ae18de_0_1,
    sig(:cs_cache, width: 64)[54].replicate(
      lit(16, width: 32, base: "h", signed: true)
    ).concat(
      lit(65535, width: 16, base: "h", signed: false)
    )
  assign :ss_left,
    mux(
      sig(:__VdfgRegularize_hf9ae18de_0_20, width: 1),
      (
          sig(:ss_limit, width: 32) -
          sig(:rd_address_effective, width: 32)
      ),
      (
          sig(:__VdfgRegularize_hf9ae18de_0_2, width: 32) -
          sig(:rd_address_effective, width: 32)
      )
    )
  assign :__VdfgRegularize_hf9ae18de_0_20,
    (
        (
          ~sig(:ss_cache, width: 64)[42]
        ) |
        sig(:ss_cache, width: 64)[43]
    )
  assign :__VdfgRegularize_hf9ae18de_0_2,
    sig(:ss_cache, width: 64)[54].replicate(
      lit(16, width: 32, base: "h", signed: true)
    ).concat(
      lit(65535, width: 16, base: "h", signed: false)
    )
  assign :ds_left,
    mux(
      sig(:__VdfgRegularize_hf9ae18de_0_19, width: 1),
      (
          sig(:ds_limit, width: 32) -
          sig(:rd_address_effective, width: 32)
      ),
      (
          sig(:__VdfgRegularize_hf9ae18de_0_3, width: 32) -
          sig(:rd_address_effective, width: 32)
      )
    )
  assign :__VdfgRegularize_hf9ae18de_0_19,
    (
        (
          ~sig(:ds_cache, width: 64)[42]
        ) |
        sig(:ds_cache, width: 64)[43]
    )
  assign :__VdfgRegularize_hf9ae18de_0_3,
    sig(:ds_cache, width: 64)[54].replicate(
      lit(16, width: 32, base: "h", signed: true)
    ).concat(
      lit(65535, width: 16, base: "h", signed: false)
    )
  assign :fs_left,
    mux(
      sig(:__VdfgRegularize_hf9ae18de_0_18, width: 1),
      (
          sig(:fs_limit, width: 32) -
          sig(:rd_address_effective, width: 32)
      ),
      (
          sig(:__VdfgRegularize_hf9ae18de_0_4, width: 32) -
          sig(:rd_address_effective, width: 32)
      )
    )
  assign :__VdfgRegularize_hf9ae18de_0_18,
    (
        (
          ~sig(:fs_cache, width: 64)[42]
        ) |
        sig(:fs_cache, width: 64)[43]
    )
  assign :__VdfgRegularize_hf9ae18de_0_4,
    sig(:fs_cache, width: 64)[54].replicate(
      lit(16, width: 32, base: "h", signed: true)
    ).concat(
      lit(65535, width: 16, base: "h", signed: false)
    )
  assign :gs_left,
    mux(
      sig(:__VdfgRegularize_hf9ae18de_0_17, width: 1),
      (
          sig(:gs_limit, width: 32) -
          sig(:rd_address_effective, width: 32)
      ),
      (
          sig(:__VdfgRegularize_hf9ae18de_0_5, width: 32) -
          sig(:rd_address_effective, width: 32)
      )
    )
  assign :__VdfgRegularize_hf9ae18de_0_17,
    (
        (
          ~sig(:gs_cache, width: 64)[42]
        ) |
        sig(:gs_cache, width: 64)[43]
    )
  assign :__VdfgRegularize_hf9ae18de_0_5,
    sig(:gs_cache, width: 64)[54].replicate(
      lit(16, width: 32, base: "h", signed: true)
    ).concat(
      lit(65535, width: 16, base: "h", signed: false)
    )
  assign :seg_select,
    mux(
      (
          sig(:address_stack_pop, width: 1) |
          (
              sig(:address_enter_last, width: 1) |
              (
                  sig(:address_stack_pop_next, width: 1) |
                  (
                      sig(:address_enter, width: 1) |
                      sig(:address_leave, width: 1)
                  )
              )
          )
      ),
      lit(2, width: 3, base: "h", signed: false),
      mux(
        sig(:address_edi, width: 1),
        lit(0, width: 3, base: "h", signed: false),
        sig(:rd_prefix_group_2_seg, width: 3)
      )
    )
  assign :seg_read,
    (
        sig(:read_rmw_virtual, width: 1) |
        sig(:read_virtual, width: 1)
    )
  assign :seg_write,
    (
        sig(:read_rmw_virtual, width: 1) |
        sig(:write_virtual_check, width: 1)
    )
  assign :seg_fault,
    (
        sig(:rd_address_effective_ready, width: 1) &
        (
            (
                sig(:seg_read, width: 1) |
                sig(:seg_write, width: 1)
            ) &
            (
                (
                    mux(
                      sig(:__VdfgRegularize_hf9ae18de_0_6, width: 1),
                      (
                          sig(:__VdfgRegularize_hf9ae18de_0_11, width: 1) &
                          sig(:es_cache, width: 64)[43]
                      ),
                      mux(
                        sig(:__VdfgRegularize_hf9ae18de_0_7, width: 1),
                        (
                            sig(:__VdfgRegularize_hf9ae18de_0_12, width: 1) &
                            sig(:cs_cache, width: 64)[43]
                        ),
                        mux(
                          sig(:__VdfgRegularize_hf9ae18de_0_8, width: 1),
                          (
                              sig(:__VdfgRegularize_hf9ae18de_0_13, width: 1) &
                              sig(:ss_cache, width: 64)[43]
                          ),
                          mux(
                            sig(:__VdfgRegularize_hf9ae18de_0_9, width: 1),
                            (
                                sig(:__VdfgRegularize_hf9ae18de_0_14, width: 1) &
                                sig(:ds_cache, width: 64)[43]
                            ),
                            mux(
                              sig(:__VdfgRegularize_hf9ae18de_0_10, width: 1),
                              (
                                  sig(:__VdfgRegularize_hf9ae18de_0_15, width: 1) &
                                  sig(:fs_cache, width: 64)[43]
                              ),
                              (
                                  sig(:__VdfgRegularize_hf9ae18de_0_16, width: 1) &
                                  sig(:gs_cache, width: 64)[43]
                              )
                            )
                          )
                        )
                      )
                    ) &
                    sig(:seg_read, width: 1)
                ) |
                (
                    (
                        mux(
                          sig(:__VdfgRegularize_hf9ae18de_0_6, width: 1),
                          (
                              sig(:__VdfgRegularize_hf9ae18de_0_11, width: 1) |
                              sig(:es_cache, width: 64)[43]
                          ),
                          mux(
                            sig(:__VdfgRegularize_hf9ae18de_0_7, width: 1),
                            (
                                sig(:__VdfgRegularize_hf9ae18de_0_12, width: 1) |
                                sig(:cs_cache, width: 64)[43]
                            ),
                            mux(
                              sig(:__VdfgRegularize_hf9ae18de_0_8, width: 1),
                              (
                                  sig(:__VdfgRegularize_hf9ae18de_0_13, width: 1) |
                                  sig(:ss_cache, width: 64)[43]
                              ),
                              mux(
                                sig(:__VdfgRegularize_hf9ae18de_0_9, width: 1),
                                (
                                    sig(:__VdfgRegularize_hf9ae18de_0_14, width: 1) |
                                    sig(:ds_cache, width: 64)[43]
                                ),
                                mux(
                                  sig(:__VdfgRegularize_hf9ae18de_0_10, width: 1),
                                  (
                                      sig(:__VdfgRegularize_hf9ae18de_0_15, width: 1) |
                                      sig(:fs_cache, width: 64)[43]
                                  ),
                                  (
                                      sig(:__VdfgRegularize_hf9ae18de_0_16, width: 1) |
                                      sig(:gs_cache, width: 64)[43]
                                  )
                                )
                              )
                            )
                          )
                        ) &
                        sig(:seg_write, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgRegularize_hf9ae18de_0_6, width: 1) &
                            (
                                (
                                    sig(:__VdfgRegularize_hf9ae18de_0_22, width: 1) &
                                    (
                                        sig(:rd_address_effective, width: 32) >
                                        sig(:es_limit, width: 32)
                                    )
                                ) |
                                (
                                    (
                                      ~sig(:es_cache, width: 64)[43]
                                    ) &
                                    (
                                        sig(:es_cache, width: 64)[42] &
                                        (
                                            (
                                                sig(:rd_address_effective, width: 32) <=
                                                sig(:es_limit, width: 32)
                                            ) |
                                            (
                                                sig(:rd_address_effective, width: 32) >
                                                sig(:__VdfgRegularize_hf9ae18de_0_0, width: 32)
                                            )
                                        )
                                    )
                                )
                            )
                        ) |
                        (
                            (
                                (
                                    sig(:__VdfgRegularize_hf9ae18de_0_7, width: 1) &
                                    (
                                        (
                                            sig(:__VdfgRegularize_hf9ae18de_0_21, width: 1) &
                                            (
                                                sig(:rd_address_effective, width: 32) >
                                                sig(:cs_limit, width: 32)
                                            )
                                        ) |
                                        (
                                            (
                                              ~sig(:cs_cache, width: 64)[43]
                                            ) &
                                            (
                                                sig(:cs_cache, width: 64)[42] &
                                                (
                                                    (
                                                        sig(:rd_address_effective, width: 32) <=
                                                        sig(:cs_limit, width: 32)
                                                    ) |
                                                    (
                                                        sig(:rd_address_effective, width: 32) >
                                                        sig(:__VdfgRegularize_hf9ae18de_0_1, width: 32)
                                                    )
                                                )
                                            )
                                        )
                                    )
                                ) |
                                (
                                    (
                                        sig(:__VdfgRegularize_hf9ae18de_0_8, width: 1) &
                                        (
                                            (
                                                sig(:__VdfgRegularize_hf9ae18de_0_20, width: 1) &
                                                (
                                                    sig(:rd_address_effective, width: 32) >
                                                    sig(:ss_limit, width: 32)
                                                )
                                            ) |
                                            (
                                                (
                                                  ~sig(:ss_cache, width: 64)[43]
                                                ) &
                                                (
                                                    sig(:ss_cache, width: 64)[42] &
                                                    (
                                                        (
                                                            sig(:rd_address_effective, width: 32) <=
                                                            sig(:ss_limit, width: 32)
                                                        ) |
                                                        (
                                                            sig(:rd_address_effective, width: 32) >
                                                            sig(:__VdfgRegularize_hf9ae18de_0_2, width: 32)
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    ) |
                                    (
                                        (
                                            sig(:__VdfgRegularize_hf9ae18de_0_9, width: 1) &
                                            (
                                                (
                                                    sig(:__VdfgRegularize_hf9ae18de_0_19, width: 1) &
                                                    (
                                                        sig(:rd_address_effective, width: 32) >
                                                        sig(:ds_limit, width: 32)
                                                    )
                                                ) |
                                                (
                                                    (
                                                      ~sig(:ds_cache, width: 64)[43]
                                                    ) &
                                                    (
                                                        sig(:ds_cache, width: 64)[42] &
                                                        (
                                                            (
                                                                sig(:rd_address_effective, width: 32) <=
                                                                sig(:ds_limit, width: 32)
                                                            ) |
                                                            (
                                                                sig(:rd_address_effective, width: 32) >
                                                                sig(:__VdfgRegularize_hf9ae18de_0_3, width: 32)
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        ) |
                                        (
                                            (
                                                sig(:__VdfgRegularize_hf9ae18de_0_10, width: 1) &
                                                (
                                                    (
                                                        sig(:__VdfgRegularize_hf9ae18de_0_18, width: 1) &
                                                        (
                                                            sig(:rd_address_effective, width: 32) >
                                                            sig(:fs_limit, width: 32)
                                                        )
                                                    ) |
                                                    (
                                                        (
                                                          ~sig(:fs_cache, width: 64)[43]
                                                        ) &
                                                        (
                                                            sig(:fs_cache, width: 64)[42] &
                                                            (
                                                                (
                                                                    sig(:rd_address_effective, width: 32) <=
                                                                    sig(:fs_limit, width: 32)
                                                                ) |
                                                                (
                                                                    sig(:rd_address_effective, width: 32) >
                                                                    sig(:__VdfgRegularize_hf9ae18de_0_4, width: 32)
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            ) |
                                            (
                                                (
                                                    lit(5, width: 3, base: "h", signed: false) ==
                                                    sig(:seg_select, width: 3)
                                                ) &
                                                (
                                                    (
                                                        sig(:__VdfgRegularize_hf9ae18de_0_17, width: 1) &
                                                        (
                                                            sig(:rd_address_effective, width: 32) >
                                                            sig(:gs_limit, width: 32)
                                                        )
                                                    ) |
                                                    (
                                                        (
                                                          ~sig(:gs_cache, width: 64)[43]
                                                        ) &
                                                        (
                                                            sig(:gs_cache, width: 64)[42] &
                                                            (
                                                                (
                                                                    sig(:rd_address_effective, width: 32) <=
                                                                    sig(:gs_limit, width: 32)
                                                                ) |
                                                                (
                                                                    sig(:rd_address_effective, width: 32) >
                                                                    sig(:__VdfgRegularize_hf9ae18de_0_5, width: 32)
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            ) |
                            (
                                (
                                  ~mux(sig(:__VdfgRegularize_hf9ae18de_0_6, width: 1), (sig(:es_cache, width: 64)[47] & sig(:es_cache_valid, width: 1)), mux(sig(:__VdfgRegularize_hf9ae18de_0_7, width: 1), (sig(:cs_cache, width: 64)[47] & sig(:cs_cache_valid, width: 1)), mux(sig(:__VdfgRegularize_hf9ae18de_0_8, width: 1), (sig(:ss_cache, width: 64)[47] & sig(:ss_cache_valid, width: 1)), mux(sig(:__VdfgRegularize_hf9ae18de_0_9, width: 1), (sig(:ds_cache, width: 64)[47] & sig(:ds_cache_valid, width: 1)), mux(sig(:__VdfgRegularize_hf9ae18de_0_10, width: 1), (sig(:fs_cache, width: 64)[47] & sig(:fs_cache_valid, width: 1)), (sig(:gs_cache, width: 64)[47] & sig(:gs_cache_valid, width: 1)))))))
                                ) |
                                (
                                    mux(
                                      sig(:__VdfgRegularize_hf9ae18de_0_6, width: 1),
                                      mux(
                                        (
                                            lit(15, width: 32, base: "h", signed: false) <=
                                            sig(:es_left, width: 32)
                                        ),
                                        lit(16, width: 5, base: "h", signed: false),
                                        (
                                            lit(1, width: 5, base: "h", signed: false) +
                                            lit(0, width: 1, base: "d", signed: false).concat(
                                            sig(:es_left, width: 32)[3..0]
                                          )
                                        )
                                      ),
                                      mux(
                                        sig(:__VdfgRegularize_hf9ae18de_0_7, width: 1),
                                        mux(
                                          (
                                              lit(15, width: 32, base: "h", signed: false) <=
                                              sig(:cs_left, width: 32)
                                          ),
                                          lit(16, width: 5, base: "h", signed: false),
                                          (
                                              lit(1, width: 5, base: "h", signed: false) +
                                              lit(0, width: 1, base: "d", signed: false).concat(
                                              sig(:cs_left, width: 32)[3..0]
                                            )
                                          )
                                        ),
                                        mux(
                                          sig(:__VdfgRegularize_hf9ae18de_0_8, width: 1),
                                          mux(
                                            (
                                                lit(15, width: 32, base: "h", signed: false) <=
                                                sig(:ss_left, width: 32)
                                            ),
                                            lit(16, width: 5, base: "h", signed: false),
                                            (
                                                lit(1, width: 5, base: "h", signed: false) +
                                                lit(0, width: 1, base: "d", signed: false).concat(
                                                sig(:ss_left, width: 32)[3..0]
                                              )
                                            )
                                          ),
                                          mux(
                                            sig(:__VdfgRegularize_hf9ae18de_0_9, width: 1),
                                            mux(
                                              (
                                                  lit(15, width: 32, base: "h", signed: false) <=
                                                  sig(:ds_left, width: 32)
                                              ),
                                              lit(16, width: 5, base: "h", signed: false),
                                              (
                                                  lit(1, width: 5, base: "h", signed: false) +
                                                  lit(0, width: 1, base: "d", signed: false).concat(
                                                  sig(:ds_left, width: 32)[3..0]
                                                )
                                              )
                                            ),
                                            mux(
                                              sig(:__VdfgRegularize_hf9ae18de_0_10, width: 1),
                                              mux(
                                                (
                                                    lit(15, width: 32, base: "h", signed: false) <=
                                                    sig(:fs_left, width: 32)
                                                ),
                                                lit(16, width: 5, base: "h", signed: false),
                                                (
                                                    lit(1, width: 5, base: "h", signed: false) +
                                                    lit(0, width: 1, base: "d", signed: false).concat(
                                                    sig(:fs_left, width: 32)[3..0]
                                                  )
                                                )
                                              ),
                                              mux(
                                                (
                                                    lit(15, width: 32, base: "h", signed: false) <=
                                                    sig(:gs_left, width: 32)
                                                ),
                                                lit(16, width: 5, base: "h", signed: false),
                                                (
                                                    lit(1, width: 5, base: "h", signed: false) +
                                                    lit(0, width: 1, base: "d", signed: false).concat(
                                                    sig(:gs_left, width: 32)[3..0]
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    ) <
                                    lit(0, width: 1, base: "d", signed: false).concat(
                                    sig(:read_length, width: 4)
                                  )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_hf9ae18de_0_6,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:seg_select, width: 3)
    )
  assign :__VdfgRegularize_hf9ae18de_0_11,
    (
      ~sig(:es_cache, width: 64)[41]
    )
  assign :__VdfgRegularize_hf9ae18de_0_7,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:seg_select, width: 3)
    )
  assign :__VdfgRegularize_hf9ae18de_0_12,
    (
      ~sig(:cs_cache, width: 64)[41]
    )
  assign :__VdfgRegularize_hf9ae18de_0_8,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:seg_select, width: 3)
    )
  assign :__VdfgRegularize_hf9ae18de_0_13,
    (
      ~sig(:ss_cache, width: 64)[41]
    )
  assign :__VdfgRegularize_hf9ae18de_0_9,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:seg_select, width: 3)
    )
  assign :__VdfgRegularize_hf9ae18de_0_14,
    (
      ~sig(:ds_cache, width: 64)[41]
    )
  assign :__VdfgRegularize_hf9ae18de_0_10,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:seg_select, width: 3)
    )
  assign :__VdfgRegularize_hf9ae18de_0_15,
    (
      ~sig(:fs_cache, width: 64)[41]
    )
  assign :__VdfgRegularize_hf9ae18de_0_16,
    (
      ~sig(:gs_cache, width: 64)[41]
    )
  assign :rd_seg_gp_fault_init,
    (
        (
            lit(2, width: 3, base: "h", signed: false) !=
            sig(:seg_select, width: 3)
        ) &
        sig(:seg_fault, width: 1)
    )
  assign :rd_seg_ss_fault_init,
    (
        sig(:__VdfgRegularize_hf9ae18de_0_8, width: 1) &
        sig(:seg_fault, width: 1)
    )
  assign :rd_seg_linear,
    mux(
      sig(:__VdfgRegularize_hf9ae18de_0_6, width: 1),
      (
          sig(:es_cache, width: 64)[63..56].concat(
            sig(:es_cache, width: 64)[39..16]
          ) +
          sig(:rd_address_effective, width: 32)
      ),
      mux(
        sig(:__VdfgRegularize_hf9ae18de_0_7, width: 1),
        (
            sig(:cs_cache, width: 64)[63..56].concat(
              sig(:cs_cache, width: 64)[39..16]
            ) +
            sig(:rd_address_effective, width: 32)
        ),
        mux(
          sig(:__VdfgRegularize_hf9ae18de_0_8, width: 1),
          (
              sig(:ss_cache, width: 64)[63..56].concat(
                sig(:ss_cache, width: 64)[39..16]
              ) +
              sig(:rd_address_effective, width: 32)
          ),
          mux(
            sig(:__VdfgRegularize_hf9ae18de_0_9, width: 1),
            (
                sig(:ds_cache, width: 64)[63..56].concat(
                  sig(:ds_cache, width: 64)[39..16]
                ) +
                sig(:rd_address_effective, width: 32)
            ),
            mux(
              sig(:__VdfgRegularize_hf9ae18de_0_10, width: 1),
              (
                  sig(:fs_cache, width: 64)[63..56].concat(
                    sig(:fs_cache, width: 64)[39..16]
                  ) +
                  sig(:rd_address_effective, width: 32)
              ),
              (
                  sig(:gs_cache, width: 64)[63..56].concat(
                    sig(:gs_cache, width: 64)[39..16]
                  ) +
                  sig(:rd_address_effective, width: 32)
              )
            )
          )
        )
      )
    )
  assign :tr_limit,
    mux(
      sig(:tr_cache, width: 64)[55],
      sig(:tr_cache, width: 64)[51..48].concat(
        sig(:tr_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:tr_cache, width: 64)[51..48].concat(
          sig(:tr_cache, width: 64)[15..0]
        )
      )
    )
  assign :tr_base,
    sig(:tr_cache, width: 64)[63..56].concat(
      sig(:tr_cache, width: 64)[39..16]
    )
  assign :ldtr_limit,
    mux(
      sig(:ldtr_cache, width: 64)[55],
      sig(:ldtr_cache, width: 64)[51..48].concat(
        sig(:ldtr_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:ldtr_cache, width: 64)[51..48].concat(
          sig(:ldtr_cache, width: 64)[15..0]
        )
      )
    )
  assign :ldtr_base,
    sig(:ldtr_cache, width: 64)[63..56].concat(
      sig(:ldtr_cache, width: 64)[39..16]
    )

  # Processes

  process :initial_block_0,
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

end
