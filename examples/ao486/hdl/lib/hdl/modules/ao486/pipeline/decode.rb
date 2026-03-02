# frozen_string_literal: true

class Decode < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: decode

  def self._import_decl_kinds
    {
      __VdfgRegularize_h87cdc9d2_0_0: :logic,
      __VdfgRegularize_h87cdc9d2_0_1: :logic,
      __VdfgRegularize_h87cdc9d2_0_2: :logic,
      consume_call_jmp_imm: :wire,
      consume_count: :wire,
      consume_count_local: :wire,
      consume_mem_offset: :wire,
      consume_modregrm_imm: :wire,
      consume_modregrm_one: :wire,
      consume_one: :wire,
      consume_one_imm: :wire,
      consume_one_one: :wire,
      consume_one_three: :wire,
      consume_one_two: :wire,
      dec_exception_ud: :wire,
      dec_is_modregrm: :wire,
      dec_ready_2byte_imm: :wire,
      dec_ready_2byte_modregrm: :wire,
      dec_ready_2byte_modregrm_imm: :wire,
      dec_ready_2byte_one: :wire,
      dec_ready_call_jmp_imm: :wire,
      dec_ready_mem_offset: :wire,
      dec_ready_modregrm_imm: :wire,
      dec_ready_modregrm_one: :wire,
      dec_ready_one: :wire,
      dec_ready_one_imm: :wire,
      dec_ready_one_one: :wire,
      dec_ready_one_three: :wire,
      dec_ready_one_two: :wire,
      decoder_count: :wire,
      enable: :wire,
      gp_fault: :wire,
      gp_fault_last: :reg,
      instr_finished: :wire,
      instr_prefix: :wire,
      is_prefix: :wire,
      pf_fault: :wire,
      pf_fault_last: :reg,
      prefix_count: :wire,
      prefix_group_1_lock: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :dec_reset
  input :cs_cache, width: 64
  input :protected_mode
  input :pr_reset
  input :prefetch_eip, width: 32
  output :eip, width: 32
  input :fetch_valid, width: 4
  input :fetch, width: 64
  input :fetch_limit
  input :fetch_page_fault
  output :dec_acceptable, width: 4
  output :dec_gp_fault
  output :dec_ud_fault
  output :dec_pf_fault
  input :micro_busy
  output :dec_ready
  output :decoder, width: 96
  output :dec_eip, width: 32
  output :dec_operand_32bit
  output :dec_address_32bit
  output :dec_prefix_group_1_rep, width: 2
  output :dec_prefix_group_1_lock
  output :dec_prefix_group_2_seg, width: 3
  output :dec_prefix_2byte
  output :dec_consumed, width: 4
  output :dec_modregrm_len, width: 3
  output :dec_is_8bit
  output :dec_cmd, width: 7
  output :dec_cmdex, width: 4
  output :dec_is_complex

  # Signals

  signal :__VdfgRegularize_h87cdc9d2_0_0
  signal :__VdfgRegularize_h87cdc9d2_0_1
  signal :__VdfgRegularize_h87cdc9d2_0_2
  signal :consume_call_jmp_imm
  signal :consume_count, width: 4
  signal :consume_count_local, width: 4
  signal :consume_mem_offset
  signal :consume_modregrm_imm
  signal :consume_modregrm_one
  signal :consume_one
  signal :consume_one_imm
  signal :consume_one_one
  signal :consume_one_three
  signal :consume_one_two
  signal :dec_exception_ud
  signal :dec_is_modregrm
  signal :dec_ready_2byte_imm
  signal :dec_ready_2byte_modregrm
  signal :dec_ready_2byte_modregrm_imm
  signal :dec_ready_2byte_one
  signal :dec_ready_call_jmp_imm
  signal :dec_ready_mem_offset
  signal :dec_ready_modregrm_imm
  signal :dec_ready_modregrm_one
  signal :dec_ready_one
  signal :dec_ready_one_imm
  signal :dec_ready_one_one
  signal :dec_ready_one_three
  signal :dec_ready_one_two
  signal :decoder_count, width: 4
  signal :enable
  signal :gp_fault
  signal :gp_fault_last
  signal :instr_finished
  signal :instr_prefix
  signal :is_prefix
  signal :pf_fault
  signal :pf_fault_last
  signal :prefix_count, width: 4
  signal :prefix_group_1_lock

  # Assignments

  assign :enable,
    (
      ~(
          sig(:dec_ud_fault, width: 1) |
          (
              sig(:dec_gp_fault, width: 1) |
              sig(:dec_pf_fault, width: 1)
          )
      )
    )
  assign :instr_prefix,
    (
        sig(:enable, width: 1) &
        (
            (
              ~sig(:dec_prefix_2byte, width: 1)
            ) &
            (
                sig(:is_prefix, width: 1) &
                (
                    lit(0, width: 4, base: "h", signed: false) <
                    sig(:decoder_count, width: 4)
                )
            )
        )
    )
  assign :dec_ready,
    (
        (
          ~sig(:dec_reset, width: 1)
        ) &
        (
            sig(:enable, width: 1) &
            (
                sig(:__VdfgRegularize_h87cdc9d2_0_0, width: 1) &
                (
                    (
                      ~sig(:micro_busy, width: 1)
                    ) &
                    (
                        lit(0, width: 4, base: "h", signed: false) <
                        sig(:consume_count_local, width: 4)
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h87cdc9d2_0_0,
    (
      ~sig(:instr_prefix, width: 1)
    )
  assign :instr_finished,
    (
        sig(:dec_ready, width: 1) |
        sig(:dec_reset, width: 1)
    )
  assign :consume_count,
    mux(
      sig(:instr_prefix, width: 1),
      lit(1, width: 4, base: "h", signed: false),
      mux(
        sig(:dec_reset, width: 1),
        lit(0, width: 4, base: "h", signed: false),
        mux(
          sig(:micro_busy, width: 1),
          lit(0, width: 4, base: "h", signed: false),
          sig(:consume_count_local, width: 4)
        )
      )
    )
  assign :dec_consumed,
    mux(
      sig(:dec_ready, width: 1),
      (
          sig(:consume_count_local, width: 4) +
          sig(:prefix_count, width: 4)
      ),
      lit(0, width: 4, base: "h", signed: false)
    )
  assign :gp_fault,
    (
        sig(:__VdfgRegularize_h87cdc9d2_0_2, width: 1) &
        (
            (
                sig(:__VdfgRegularize_h87cdc9d2_0_1, width: 1) &
                sig(:fetch_limit, width: 1)
            ) |
            (
                lit(0, width: 4, base: "h", signed: false) ==
                sig(:dec_acceptable, width: 4)
            )
        )
    )
  assign :__VdfgRegularize_h87cdc9d2_0_2,
    (
        sig(:enable, width: 1) &
        (
            sig(:__VdfgRegularize_h87cdc9d2_0_0, width: 1) &
            (
                lit(0, width: 4, base: "h", signed: false) ==
                sig(:consume_count_local, width: 4)
            )
        )
    )
  assign :__VdfgRegularize_h87cdc9d2_0_1,
    (
        lit(0, width: 4, base: "h", signed: false) ==
        sig(:fetch_valid, width: 4)
    )
  assign :pf_fault,
    (
        sig(:__VdfgRegularize_h87cdc9d2_0_2, width: 1) &
        (
            sig(:__VdfgRegularize_h87cdc9d2_0_1, width: 1) &
            sig(:fetch_page_fault, width: 1)
        )
    )
  assign :dec_eip,
    (
        sig(:eip, width: 32) +
        lit(0, width: 28, base: "d", signed: false).concat(
        sig(:dec_consumed, width: 4)
      )
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :gp_fault_last,
      (
          sig(:rst_n, width: 1) &
          sig(:gp_fault, width: 1)
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
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:dec_reset, width: 1)) do
        assign(
          :dec_gp_fault,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:gp_fault, width: 1) & sig(:gp_fault_last, width: 1))) do
            assign(
              :dec_gp_fault,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :dec_gp_fault,
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
      if_stmt(sig(:dec_reset, width: 1)) do
        assign(
          :dec_ud_fault,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:dec_exception_ud, width: 1)) do
            assign(
              :dec_ud_fault,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :dec_ud_fault,
          lit(0, width: 1, base: "h", signed: false),
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
    assign(
      :pf_fault_last,
      (
          sig(:rst_n, width: 1) &
          sig(:pf_fault, width: 1)
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
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:dec_reset, width: 1)) do
        assign(
          :dec_pf_fault,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:pf_fault, width: 1) & sig(:pf_fault_last, width: 1))) do
            assign(
              :dec_pf_fault,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :dec_pf_fault,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:pr_reset, width: 1)) do
        assign(
          :eip,
          sig(:prefetch_eip, width: 32),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:dec_ready, width: 1)) do
            assign(
              :eip,
              sig(:dec_eip, width: 32),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :eip,
          lit(65520, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  # Instances

  instance :decode_ready_inst, "decode_ready"
  instance :decode_prefix_inst, "decode_prefix"
  instance :decode_regs_inst, "decode_regs"
  instance :decode_commands_inst, "decode_commands"

end
