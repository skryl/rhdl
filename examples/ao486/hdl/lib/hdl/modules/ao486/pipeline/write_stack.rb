# frozen_string_literal: true

class WriteStack < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: write_stack

  def self._import_decl_kinds
    {
      __VdfgRegularize_h55106442_0_0: :logic,
      __VdfgRegularize_h55106442_0_1: :logic,
      __VdfgRegularize_h55106442_0_2: :logic,
      __VdfgRegularize_h55106442_0_3: :logic,
      _unused_ok: :wire,
      w_new_upper_limit: :wire,
      w_upper_limit: :wire
    }
  end

  # Ports

  input :glob_descriptor, width: 64
  input :esp, width: 32
  input :ss_cache, width: 64
  input :ss_base, width: 32
  input :ss_limit, width: 32
  input :glob_desc_base, width: 32
  input :glob_desc_limit, width: 32
  input :wr_operand_16bit
  input :wr_stack_offset, width: 32
  input :wr_new_push_ss_fault_check
  input :wr_push_length_word
  input :wr_push_length_dword
  input :wr_push_ss_fault_check
  output :wr_stack_esp, width: 32
  output :wr_push_linear, width: 32
  output :wr_new_stack_esp, width: 32
  output :wr_new_push_linear, width: 32
  output :wr_push_length, width: 3
  output :wr_push_ss_fault
  output :wr_new_push_ss_fault

  # Signals

  signal :__VdfgRegularize_h55106442_0_0, width: 32
  signal :__VdfgRegularize_h55106442_0_1
  signal :__VdfgRegularize_h55106442_0_2, width: 32
  signal :__VdfgRegularize_h55106442_0_3
  signal :_unused_ok
  signal :w_new_upper_limit, width: 32
  signal :w_upper_limit, width: 32

  # Assignments

  assign :wr_stack_esp,
    mux(
      sig(:ss_cache, width: 64)[54],
      sig(:wr_stack_offset, width: 32),
      sig(:__VdfgRegularize_h55106442_0_0, width: 32)
    )
  assign :__VdfgRegularize_h55106442_0_0,
    sig(:esp, width: 32)[31..16].concat(
      sig(:wr_stack_offset, width: 32)[15..0]
    )
  assign :wr_push_linear,
    (
        sig(:ss_base, width: 32) +
        sig(:wr_stack_offset, width: 32)
    )
  assign :wr_push_length,
    mux(
      (
          sig(:wr_push_length_word, width: 1) |
          (
              (
                ~sig(:wr_push_length_dword, width: 1)
              ) &
              sig(:wr_operand_16bit, width: 1)
          )
      ),
      lit(2, width: 3, base: "h", signed: false),
      lit(4, width: 3, base: "h", signed: false)
    )
  assign :wr_new_stack_esp,
    mux(
      sig(:glob_descriptor, width: 64)[54],
      sig(:wr_stack_offset, width: 32),
      sig(:__VdfgRegularize_h55106442_0_0, width: 32)
    )
  assign :wr_new_push_linear,
    (
        sig(:glob_desc_base, width: 32) +
        sig(:wr_stack_offset, width: 32)
    )
  assign :w_new_upper_limit,
    mux(
      sig(:glob_descriptor, width: 64)[54],
      lit(4294967295, width: 32, base: "h", signed: false),
      lit(65535, width: 32, base: "h", signed: false)
    )
  assign :wr_new_push_ss_fault,
    (
        sig(:wr_new_push_ss_fault_check, width: 1) &
        (
            (
              ~sig(:glob_descriptor, width: 64)[41]
            ) |
            (
                sig(:glob_descriptor, width: 64)[43] |
                (
                    mux(
                      sig(:__VdfgRegularize_h55106442_0_3, width: 1),
                      (
                          (
                              sig(:glob_desc_limit, width: 32) -
                              sig(:wr_stack_offset, width: 32)
                          ) <
                          sig(:__VdfgRegularize_h55106442_0_2, width: 32)
                      ),
                      (
                          (
                              sig(:w_new_upper_limit, width: 32) -
                              sig(:wr_stack_offset, width: 32)
                          ) <
                          sig(:__VdfgRegularize_h55106442_0_2, width: 32)
                      )
                    ) |
                    (
                        (
                            sig(:__VdfgRegularize_h55106442_0_3, width: 1) &
                            (
                                sig(:wr_stack_offset, width: 32) >
                                sig(:glob_desc_limit, width: 32)
                            )
                        ) |
                        (
                            (
                              ~sig(:glob_descriptor, width: 64)[43]
                            ) &
                            (
                                sig(:glob_descriptor, width: 64)[42] &
                                (
                                    (
                                        sig(:wr_stack_offset, width: 32) <=
                                        sig(:glob_desc_limit, width: 32)
                                    ) |
                                    (
                                        sig(:wr_stack_offset, width: 32) >
                                        sig(:w_new_upper_limit, width: 32)
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h55106442_0_3,
    (
        (
          ~sig(:glob_descriptor, width: 64)[42]
        ) |
        sig(:glob_descriptor, width: 64)[43]
    )
  assign :__VdfgRegularize_h55106442_0_2,
    lit(0, width: 29, base: "d", signed: false).concat(
      (
          (
              (
                  sig(:wr_push_length, width: 3) -
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
  assign :w_upper_limit,
    mux(
      sig(:ss_cache, width: 64)[54],
      lit(4294967295, width: 32, base: "h", signed: false),
      lit(65535, width: 32, base: "h", signed: false)
    )
  assign :wr_push_ss_fault,
    (
        sig(:wr_push_ss_fault_check, width: 1) &
        (
            mux(
              sig(:__VdfgRegularize_h55106442_0_1, width: 1),
              (
                  (
                      sig(:ss_limit, width: 32) -
                      sig(:wr_stack_offset, width: 32)
                  ) <
                  sig(:__VdfgRegularize_h55106442_0_2, width: 32)
              ),
              (
                  (
                      sig(:w_upper_limit, width: 32) -
                      sig(:wr_stack_offset, width: 32)
                  ) <
                  sig(:__VdfgRegularize_h55106442_0_2, width: 32)
              )
            ) |
            (
                (
                    sig(:__VdfgRegularize_h55106442_0_1, width: 1) &
                    (
                        sig(:wr_stack_offset, width: 32) >
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
                                sig(:wr_stack_offset, width: 32) <=
                                sig(:ss_limit, width: 32)
                            ) |
                            (
                                sig(:wr_stack_offset, width: 32) >
                                sig(:w_upper_limit, width: 32)
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h55106442_0_1,
    (
        (
          ~sig(:ss_cache, width: 64)[42]
        ) |
        sig(:ss_cache, width: 64)[43]
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
