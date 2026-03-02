# frozen_string_literal: true

class WriteString < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: write_string

  def self._import_decl_kinds
    {
      __VdfgRegularize_h9af9438e_0_0: :logic,
      __VdfgRegularize_h9af9438e_0_1: :logic,
      __VdfgRegularize_h9af9438e_0_2: :logic,
      _unused_ok: :wire,
      w_ecx: :wire,
      w_edi: :wire,
      w_edi_offset: :wire,
      w_esi: :wire,
      w_string_es_upper_limit: :wire,
      w_string_size: :wire
    }
  end

  # Ports

  input :wr_is_8bit
  input :wr_operand_16bit
  input :wr_address_16bit
  input :wr_address_32bit
  input :wr_prefix_group_1_rep, width: 2
  input :wr_string_gp_fault_check
  input :dflag
  input :wr_zflag_result
  input :ecx, width: 32
  input :esi, width: 32
  input :edi, width: 32
  input :es_cache, width: 64
  input :es_cache_valid
  input :es_base, width: 32
  input :es_limit, width: 32
  output :wr_esi_final, width: 32
  output :wr_edi_final, width: 32
  output :wr_ecx_final, width: 32
  output :wr_string_ignore
  output :wr_string_finish
  output :wr_string_zf_finish
  output :wr_string_es_linear, width: 32
  output :wr_string_es_fault

  # Signals

  signal :__VdfgRegularize_h9af9438e_0_0
  signal :__VdfgRegularize_h9af9438e_0_1, width: 32
  signal :__VdfgRegularize_h9af9438e_0_2
  signal :_unused_ok
  signal :w_ecx, width: 32
  signal :w_edi, width: 32
  signal :w_edi_offset, width: 32
  signal :w_esi, width: 32
  signal :w_string_es_upper_limit, width: 32
  signal :w_string_size, width: 32

  # Assignments

  assign :w_string_size,
    mux(
      sig(:wr_is_8bit, width: 1),
      lit(1, width: 32, base: "h", signed: false),
      mux(
        sig(:wr_operand_16bit, width: 1),
        lit(2, width: 32, base: "h", signed: false),
        lit(4, width: 32, base: "h", signed: false)
      )
    )
  assign :w_esi,
    mux(
      sig(:dflag, width: 1),
      (
          sig(:esi, width: 32) -
          sig(:w_string_size, width: 32)
      ),
      (
          sig(:esi, width: 32) +
          sig(:w_string_size, width: 32)
      )
    )
  assign :w_edi,
    mux(
      sig(:dflag, width: 1),
      (
          sig(:edi, width: 32) -
          sig(:w_string_size, width: 32)
      ),
      (
          sig(:edi, width: 32) +
          sig(:w_string_size, width: 32)
      )
    )
  assign :w_ecx,
    (
        sig(:ecx, width: 32) -
        lit(1, width: 32, base: "h", signed: false)
    )
  assign :wr_esi_final,
    mux(
      sig(:wr_address_16bit, width: 1),
      sig(:esi, width: 32)[31..16].concat(
        sig(:w_esi, width: 32)[15..0]
      ),
      sig(:w_esi, width: 32)
    )
  assign :wr_edi_final,
    mux(
      sig(:wr_address_16bit, width: 1),
      sig(:edi, width: 32)[31..16].concat(
        sig(:w_edi, width: 32)[15..0]
      ),
      sig(:w_edi, width: 32)
    )
  assign :wr_ecx_final,
    mux(
      sig(:wr_address_16bit, width: 1),
      sig(:ecx, width: 32)[31..16].concat(
        sig(:w_ecx, width: 32)[15..0]
      ),
      sig(:w_ecx, width: 32)
    )
  assign :wr_string_ignore,
    (
        sig(:__VdfgRegularize_h9af9438e_0_0, width: 1) &
        (
            (
                sig(:wr_address_16bit, width: 1) &
                (
                    lit(0, width: 16, base: "h", signed: false) ==
                    sig(:ecx, width: 32)[15..0]
                )
            ) |
            (
                sig(:wr_address_32bit, width: 1) &
                (
                    lit(0, width: 32, base: "h", signed: false) ==
                    sig(:ecx, width: 32)
                )
            )
        )
    )
  assign :__VdfgRegularize_h9af9438e_0_0,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:wr_prefix_group_1_rep, width: 2)
    )
  assign :wr_string_finish,
    (
        sig(:__VdfgRegularize_h9af9438e_0_0, width: 1) &
        (
            (
                sig(:wr_address_16bit, width: 1) &
                (
                    lit(1, width: 16, base: "h", signed: false) ==
                    sig(:ecx, width: 32)[15..0]
                )
            ) |
            (
                sig(:wr_address_32bit, width: 1) &
                (
                    lit(1, width: 32, base: "h", signed: false) ==
                    sig(:ecx, width: 32)
                )
            )
        )
    )
  assign :wr_string_zf_finish,
    (
        sig(:wr_string_finish, width: 1) |
        (
            (
                (
                    lit(1, width: 2, base: "h", signed: false) ==
                    sig(:wr_prefix_group_1_rep, width: 2)
                ) &
                sig(:wr_zflag_result, width: 1)
            ) |
            (
                (
                  ~sig(:wr_zflag_result, width: 1)
                ) &
                (
                    lit(2, width: 2, base: "h", signed: false) ==
                    sig(:wr_prefix_group_1_rep, width: 2)
                )
            )
        )
    )
  assign :w_edi_offset,
    mux(
      sig(:wr_address_16bit, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:edi, width: 32)[15..0]
      ),
      sig(:edi, width: 32)
    )
  assign :wr_string_es_linear,
    (
        sig(:es_base, width: 32) +
        sig(:w_edi_offset, width: 32)
    )
  assign :w_string_es_upper_limit,
    mux(
      sig(:es_cache, width: 64)[54],
      lit(4294967295, width: 32, base: "h", signed: false),
      lit(65535, width: 32, base: "h", signed: false)
    )
  assign :wr_string_es_fault,
    (
        (
          ~sig(:wr_string_ignore, width: 1)
        ) &
        (
            sig(:wr_string_gp_fault_check, width: 1) &
            (
                mux(
                  sig(:__VdfgRegularize_h9af9438e_0_2, width: 1),
                  (
                      (
                          sig(:es_limit, width: 32) -
                          sig(:w_edi_offset, width: 32)
                      ) <
                      sig(:__VdfgRegularize_h9af9438e_0_1, width: 32)
                  ),
                  (
                      (
                          sig(:w_string_es_upper_limit, width: 32) -
                          sig(:w_edi_offset, width: 32)
                      ) <
                      sig(:__VdfgRegularize_h9af9438e_0_1, width: 32)
                  )
                ) |
                (
                    (
                        (
                            sig(:__VdfgRegularize_h9af9438e_0_2, width: 1) &
                            (
                                sig(:w_edi_offset, width: 32) >
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
                                        sig(:w_edi_offset, width: 32) <=
                                        sig(:es_limit, width: 32)
                                    ) |
                                    (
                                        sig(:w_edi_offset, width: 32) >
                                        sig(:w_string_es_upper_limit, width: 32)
                                    )
                                )
                            )
                        )
                    ) |
                    (
                        (
                          ~sig(:es_cache_valid, width: 1)
                        ) |
                        (
                            (
                              ~sig(:es_cache, width: 64)[41]
                            ) |
                            sig(:es_cache, width: 64)[43]
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h9af9438e_0_2,
    (
        (
          ~sig(:es_cache, width: 64)[42]
        ) |
        sig(:es_cache, width: 64)[43]
    )
  assign :__VdfgRegularize_h9af9438e_0_1,
    lit(0, width: 29, base: "d", signed: false).concat(
      (
          (
              (
                  mux(
                    sig(:wr_is_8bit, width: 1),
                    lit(1, width: 3, base: "h", signed: false),
                    mux(
                      sig(:wr_operand_16bit, width: 1),
                      lit(2, width: 3, base: "h", signed: false),
                      lit(4, width: 3, base: "h", signed: false)
                    )
                  ) -
                  lit(1, width: 3, base: "h", signed: false)
              ) >>
              lit(0, width: nil, base: "d", signed: false)
          ) &
          (
              (
                  lit(1, width: 32, base: "d") <<
                  (
                        (
                          lit(2, width: nil, base: "d", signed: false)
                        ) -
                        (
                          lit(0, width: nil, base: "d", signed: false)
                        ) +
                      lit(1, width: 32, base: "d")
                  )
              ) -
              lit(1, width: 32, base: "d")
          )
      )
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
