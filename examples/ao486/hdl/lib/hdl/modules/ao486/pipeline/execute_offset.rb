# frozen_string_literal: true

class ExecuteOffset < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: execute_offset

  def self._import_decl_kinds
    {
      __VdfgRegularize_hc3c8c2a0_0_0: :logic,
      __VdfgRegularize_hc3c8c2a0_0_1: :logic,
      __VdfgRegularize_hc3c8c2a0_0_2: :logic,
      _unused_ok: :wire,
      e_final_offset: :wire,
      e_new_stack_final_offset: :wire,
      e_push_offset: :wire,
      e_push_real_int_offset: :wire,
      e_temp_esp_real_int: :wire
    }
  end

  # Ports

  input :exe_operand_16bit
  input :exe_decoder, width: 40
  input :ebp, width: 32
  input :esp, width: 32
  input :ss_cache, width: 64
  input :glob_descriptor, width: 64
  input :glob_param_1, width: 32
  input :glob_param_3, width: 32
  input :glob_param_4, width: 32
  input :exe_address_effective, width: 32
  input :wr_stack_offset, width: 32
  input :offset_ret_far_se
  input :offset_new_stack
  input :offset_new_stack_minus
  input :offset_new_stack_continue
  input :offset_leave
  input :offset_pop
  input :offset_enter_last
  input :offset_ret
  input :offset_iret_glob_param_4
  input :offset_iret
  input :offset_ret_imm
  input :offset_esp
  input :offset_call
  input :offset_call_keep
  input :offset_call_int_same_first
  input :offset_call_int_same_next
  input :offset_int_real
  input :offset_int_real_next
  input :offset_task
  output :exe_stack_offset, width: 32
  output :exe_enter_offset, width: 32

  # Signals

  signal :__VdfgRegularize_hc3c8c2a0_0_0, width: 32
  signal :__VdfgRegularize_hc3c8c2a0_0_1, width: 32
  signal :__VdfgRegularize_hc3c8c2a0_0_2
  signal :_unused_ok
  signal :e_final_offset, width: 32
  signal :e_new_stack_final_offset, width: 32
  signal :e_push_offset, width: 32
  signal :e_push_real_int_offset, width: 32
  signal :e_temp_esp_real_int, width: 32

  # Assignments

  assign :e_push_offset,
    mux(
      sig(:exe_operand_16bit, width: 1),
      sig(:e_push_real_int_offset, width: 32),
      sig(:__VdfgRegularize_hc3c8c2a0_0_0, width: 32)
    )
  assign :e_push_real_int_offset,
    (
        sig(:esp, width: 32) -
        lit(2, width: 32, base: "h", signed: false)
    )
  assign :__VdfgRegularize_hc3c8c2a0_0_0,
    (
        sig(:esp, width: 32) -
        lit(4, width: 32, base: "h", signed: false)
    )
  assign :e_temp_esp_real_int,
    (
        sig(:wr_stack_offset, width: 32) -
        lit(2, width: 32, base: "h", signed: false)
    )
  assign :e_final_offset,
    mux(
      sig(:offset_leave, width: 1),
      mux(
        sig(:exe_operand_16bit, width: 1),
        (
            lit(2, width: 32, base: "h", signed: false) +
            sig(:ebp, width: 32)
        ),
        (
            lit(4, width: 32, base: "h", signed: false) +
            sig(:ebp, width: 32)
        )
      ),
      mux(
        sig(:offset_pop, width: 1),
        mux(
          sig(:exe_operand_16bit, width: 1),
          (
              lit(2, width: 32, base: "h", signed: false) +
              sig(:esp, width: 32)
          ),
          (
              lit(4, width: 32, base: "h", signed: false) +
              sig(:esp, width: 32)
          )
        ),
        mux(
          sig(:offset_enter_last, width: 1),
          sig(:exe_address_effective, width: 32),
          mux(
            sig(:offset_ret, width: 1),
            mux(
              sig(:exe_operand_16bit, width: 1),
              (
                  lit(2, width: 32, base: "h", signed: false) +
                  (
                      sig(:esp, width: 32) +
                      (
                          sig(:exe_decoder, width: 40)[23] &
                          sig(:offset_ret_far_se, width: 1)
                      ).replicate(
                      lit(16, width: 32, base: "h", signed: true)
                    ).concat(
                      sig(:exe_decoder, width: 40)[23..8]
                    )
                  )
              ),
              (
                  lit(4, width: 32, base: "h", signed: false) +
                  (
                      sig(:esp, width: 32) +
                      lit(0, width: 16, base: "d", signed: false).concat(
                      sig(:exe_decoder, width: 40)[23..8]
                    )
                  )
              )
            ),
            mux(
              sig(:offset_iret, width: 1),
              mux(
                sig(:exe_operand_16bit, width: 1),
                (
                    lit(6, width: 32, base: "h", signed: false) +
                    sig(:esp, width: 32)
                ),
                (
                    lit(12, width: 32, base: "h", signed: false) +
                    sig(:esp, width: 32)
                )
              ),
              mux(
                sig(:offset_iret_glob_param_4, width: 1),
                sig(:glob_param_4, width: 32),
                mux(
                  sig(:offset_ret_imm, width: 1),
                  (
                      sig(:glob_param_4, width: 32) +
                      lit(0, width: 16, base: "d", signed: false).concat(
                      sig(:exe_decoder, width: 40)[23..8]
                    )
                  ),
                  mux(
                    sig(:offset_esp, width: 1),
                    sig(:esp, width: 32),
                    mux(
                      sig(:offset_call, width: 1),
                      mux(
                        sig(:exe_operand_16bit, width: 1),
                        sig(:e_temp_esp_real_int, width: 32),
                        sig(:__VdfgRegularize_hc3c8c2a0_0_1, width: 32)
                      ),
                      mux(
                        sig(:offset_call_keep, width: 1),
                        sig(:wr_stack_offset, width: 32),
                        mux(
                          sig(:offset_call_int_same_first, width: 1),
                          mux(
                            sig(:glob_param_1, width: 32)[19],
                            sig(:__VdfgRegularize_hc3c8c2a0_0_0, width: 32),
                            sig(:e_push_real_int_offset, width: 32)
                          ),
                          mux(
                            sig(:offset_call_int_same_next, width: 1),
                            mux(
                              sig(:glob_param_1, width: 32)[19],
                              sig(:__VdfgRegularize_hc3c8c2a0_0_1, width: 32),
                              sig(:e_temp_esp_real_int, width: 32)
                            ),
                            mux(
                              sig(:offset_int_real, width: 1),
                              sig(:e_push_real_int_offset, width: 32),
                              mux(
                                sig(:offset_int_real_next, width: 1),
                                sig(:e_temp_esp_real_int, width: 32),
                                mux(
                                  sig(:offset_task, width: 1),
                                  mux(
                                    sig(:glob_param_3, width: 32)[17],
                                    sig(:__VdfgRegularize_hc3c8c2a0_0_0, width: 32),
                                    sig(:e_push_real_int_offset, width: 32)
                                  ),
                                  sig(:e_push_offset, width: 32)
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hc3c8c2a0_0_1,
    (
        sig(:wr_stack_offset, width: 32) -
        lit(4, width: 32, base: "h", signed: false)
    )
  assign :e_new_stack_final_offset,
    mux(
      sig(:offset_new_stack, width: 1),
      sig(:glob_param_4, width: 32),
      mux(
        (
            (
              ~sig(:glob_param_3, width: 32)[19]
            ) &
            sig(:offset_new_stack_minus, width: 1)
        ),
        (
            sig(:glob_param_4, width: 32) -
            lit(2, width: 32, base: "h", signed: false)
        ),
        mux(
          sig(:offset_new_stack_minus, width: 1),
          (
              sig(:glob_param_4, width: 32) -
              lit(4, width: 32, base: "h", signed: false)
          ),
          mux(
            sig(:glob_param_3, width: 32)[19],
            sig(:__VdfgRegularize_hc3c8c2a0_0_1, width: 32),
            sig(:e_temp_esp_real_int, width: 32)
          )
        )
      )
    )
  assign :exe_stack_offset,
    mux(
      (
          sig(:__VdfgRegularize_hc3c8c2a0_0_2, width: 1) &
          sig(:glob_descriptor, width: 64)[54]
      ),
      sig(:e_new_stack_final_offset, width: 32),
      mux(
        sig(:__VdfgRegularize_hc3c8c2a0_0_2, width: 1),
        lit(0, width: 16, base: "d", signed: false).concat(
          sig(:e_new_stack_final_offset, width: 32)[15..0]
        ),
        mux(
          sig(:ss_cache, width: 64)[54],
          sig(:e_final_offset, width: 32),
          lit(0, width: 16, base: "d", signed: false).concat(
            sig(:e_final_offset, width: 32)[15..0]
          )
        )
      )
    )
  assign :__VdfgRegularize_hc3c8c2a0_0_2,
    (
        sig(:offset_new_stack, width: 1) |
        (
            sig(:offset_new_stack_continue, width: 1) |
            sig(:offset_new_stack_minus, width: 1)
        )
    )
  assign :exe_enter_offset,
    mux(
      sig(:ss_cache, width: 64)[54],
      sig(:e_push_offset, width: 32),
      sig(:esp, width: 32)[31..16].concat(
        sig(:e_push_offset, width: 32)[15..0]
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
