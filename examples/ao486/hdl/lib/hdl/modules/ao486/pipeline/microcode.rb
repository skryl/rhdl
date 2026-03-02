# frozen_string_literal: true

class Microcode < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: microcode

  def self._import_decl_kinds
    {
      _unused_ok: :wire,
      m_load: :wire,
      m_overlay: :wire,
      mc_address_32bit: :reg,
      mc_cmd: :reg,
      mc_cmd_current: :wire,
      mc_cmd_next: :wire,
      mc_cmdex: :reg,
      mc_cmdex_current: :wire,
      mc_cmdex_last: :reg,
      mc_consumed: :reg,
      mc_decoder: :reg,
      mc_eip: :reg,
      mc_is_8bit: :reg,
      mc_modregrm_len: :reg,
      mc_operand_32bit: :reg,
      mc_prefix_2byte: :reg,
      mc_prefix_group_1_lock: :reg,
      mc_prefix_group_1_rep: :reg,
      mc_prefix_group_2_seg: :reg,
      mc_step: :reg,
      task_start: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :micro_reset
  input :exc_init
  input :exc_load
  input :exc_eip, width: 32
  input :task_eip, width: 32
  input :real_mode
  input :v8086_mode
  input :protected_mode
  input :io_allow_check_needed
  input :exc_push_error
  input :cr0_pg
  input :oflag
  input :ntflag
  input :cpl, width: 2
  input :glob_param_1, width: 32
  input :glob_param_3, width: 32
  input :glob_descriptor, width: 64
  output :micro_busy
  input :dec_ready
  input :decoder, width: 96
  input :dec_eip, width: 32
  input :dec_operand_32bit
  input :dec_address_32bit
  input :dec_prefix_group_1_rep, width: 2
  input :dec_prefix_group_1_lock
  input :dec_prefix_group_2_seg, width: 3
  input :dec_prefix_2byte
  input :dec_consumed, width: 4
  input :dec_modregrm_len, width: 3
  input :dec_is_8bit
  input :dec_cmd, width: 7
  input :dec_cmdex, width: 4
  input :dec_is_complex
  input :rd_busy
  output :micro_ready
  output :micro_decoder, width: 88
  output :micro_eip, width: 32
  output :micro_operand_32bit
  output :micro_address_32bit
  output :micro_prefix_group_1_rep, width: 2
  output :micro_prefix_group_1_lock
  output :micro_prefix_group_2_seg, width: 3
  output :micro_prefix_2byte
  output :micro_consumed, width: 4
  output :micro_modregrm_len, width: 3
  output :micro_is_8bit
  output :micro_cmd, width: 7
  output :micro_cmdex, width: 4

  # Signals

  signal :_unused_ok
  signal :m_load
  signal :m_overlay
  signal :mc_address_32bit
  signal :mc_cmd, width: 7
  signal :mc_cmd_current, width: 7
  signal :mc_cmd_next, width: 7
  signal :mc_cmdex, width: 4
  signal :mc_cmdex_current, width: 4
  signal :mc_cmdex_last, width: 4
  signal :mc_consumed, width: 4
  signal :mc_decoder, width: 88
  signal :mc_eip, width: 32
  signal :mc_is_8bit
  signal :mc_modregrm_len, width: 3
  signal :mc_operand_32bit
  signal :mc_prefix_2byte
  signal :mc_prefix_group_1_lock
  signal :mc_prefix_group_1_rep, width: 2
  signal :mc_prefix_group_2_seg, width: 3
  signal :mc_step, width: 6
  signal :task_start

  # Assignments

  assign :micro_busy,
    (
        sig(:rd_busy, width: 1) |
        sig(:m_overlay, width: 1)
    )
  assign :m_overlay,
    (
        lit(0, width: 7, base: "h", signed: false) !=
        sig(:mc_cmd, width: 7)
    )
  assign :micro_ready,
    (
        (
          ~sig(:micro_reset, width: 1)
        ) &
        (
            (
                (
                  ~sig(:m_overlay, width: 1)
                ) &
                sig(:dec_ready, width: 1)
            ) |
            (
                (
                  ~sig(:rd_busy, width: 1)
                ) &
                sig(:m_overlay, width: 1)
            )
        )
    )
  assign :m_load,
    (
        sig(:dec_is_complex, width: 1) &
        sig(:dec_ready, width: 1)
    )
  assign :task_start,
    (
        (
            lit(102, width: 7, base: "h", signed: false) ==
            sig(:micro_cmd, width: 7)
        ) &
        (
            (
                lit(1, width: 4, base: "h", signed: false) ==
                sig(:micro_cmdex, width: 4)
            ) &
            sig(:micro_ready, width: 1)
        )
    )
  assign :micro_cmd,
    mux(
      sig(:exc_load, width: 1),
      sig(:mc_cmd, width: 7),
      mux(
        sig(:m_overlay, width: 1),
        sig(:mc_cmd_current, width: 7),
        sig(:dec_cmd, width: 7)
      )
    )
  assign :micro_cmdex,
    mux(
      sig(:exc_load, width: 1),
      sig(:mc_cmdex, width: 4),
      mux(
        sig(:m_overlay, width: 1),
        sig(:mc_cmdex_current, width: 4),
        sig(:dec_cmdex, width: 4)
      )
    )
  assign :micro_operand_32bit,
    mux(
      sig(:m_overlay, width: 1),
      sig(:mc_operand_32bit, width: 1),
      sig(:dec_operand_32bit, width: 1)
    )
  assign :micro_address_32bit,
    mux(
      sig(:m_overlay, width: 1),
      sig(:mc_address_32bit, width: 1),
      sig(:dec_address_32bit, width: 1)
    )
  assign :micro_prefix_group_1_rep,
    mux(
      sig(:m_overlay, width: 1),
      sig(:mc_prefix_group_1_rep, width: 2),
      sig(:dec_prefix_group_1_rep, width: 2)
    )
  assign :micro_prefix_group_1_lock,
    mux(
      sig(:m_overlay, width: 1),
      sig(:mc_prefix_group_1_lock, width: 1),
      sig(:dec_prefix_group_1_lock, width: 1)
    )
  assign :micro_prefix_group_2_seg,
    mux(
      sig(:m_overlay, width: 1),
      sig(:mc_prefix_group_2_seg, width: 3),
      sig(:dec_prefix_group_2_seg, width: 3)
    )
  assign :micro_prefix_2byte,
    mux(
      sig(:m_overlay, width: 1),
      sig(:mc_prefix_2byte, width: 1),
      sig(:dec_prefix_2byte, width: 1)
    )
  assign :micro_decoder,
    mux(
      sig(:m_overlay, width: 1),
      sig(:mc_decoder, width: 88),
      sig(:decoder, width: 96)[87..0]
    )
  assign :micro_modregrm_len,
    mux(
      sig(:m_overlay, width: 1),
      sig(:mc_modregrm_len, width: 3),
      sig(:dec_modregrm_len, width: 3)
    )
  assign :micro_is_8bit,
    mux(
      sig(:m_overlay, width: 1),
      sig(:mc_is_8bit, width: 1),
      sig(:dec_is_8bit, width: 1)
    )
  assign :micro_consumed,
    mux(
      sig(:task_start, width: 1),
      lit(0, width: 4, base: "h", signed: false),
      mux(
        sig(:exc_load, width: 1),
        lit(0, width: 4, base: "h", signed: false),
        mux(
          sig(:m_overlay, width: 1),
          sig(:mc_consumed, width: 4),
          sig(:dec_consumed, width: 4)
        )
      )
    )
  assign :micro_eip,
    mux(
      sig(:task_start, width: 1),
      sig(:task_eip, width: 32),
      mux(
        sig(:exc_load, width: 1),
        sig(:exc_eip, width: 32),
        mux(
          sig(:m_overlay, width: 1),
          sig(:mc_eip, width: 32),
          sig(:dec_eip, width: 32)
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
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_operand_32bit,
          sig(:dec_operand_32bit, width: 1),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_operand_32bit,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_operand_32bit,
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
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_address_32bit,
          sig(:dec_address_32bit, width: 1),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_address_32bit,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_address_32bit,
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
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_prefix_group_1_rep,
          sig(:dec_prefix_group_1_rep, width: 2),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_prefix_group_1_rep,
              lit(0, width: 2, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_prefix_group_1_rep,
          lit(0, width: 2, base: "h", signed: false),
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
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_prefix_group_1_lock,
          sig(:dec_prefix_group_1_lock, width: 1),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_prefix_group_1_lock,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_prefix_group_1_lock,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_prefix_group_2_seg,
          sig(:dec_prefix_group_2_seg, width: 3),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_prefix_group_2_seg,
              lit(3, width: 3, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_prefix_group_2_seg,
          lit(3, width: 3, base: "h", signed: false),
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
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_prefix_2byte,
          sig(:dec_prefix_2byte, width: 1),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_prefix_2byte,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_prefix_2byte,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_decoder,
          sig(:decoder, width: 96)[87..0],
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_decoder,
              lit(0, width: 88, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_decoder,
          lit(0, width: 88, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_8,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_modregrm_len,
          sig(:dec_modregrm_len, width: 3),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_modregrm_len,
              lit(0, width: 3, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_modregrm_len,
          lit(0, width: 3, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_9,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_is_8bit,
          sig(:dec_is_8bit, width: 1),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_is_8bit,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_is_8bit,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_10,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exc_init, width: 1)) do
        assign(
          :mc_cmd,
          lit(28, width: 7, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:micro_reset, width: 1)) do
            assign(
              :mc_cmd,
              lit(0, width: 7, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:m_load, width: 1)) do
                assign(
                  :mc_cmd,
                  sig(:dec_cmd, width: 7),
                  kind: :nonblocking
                )
                else_block do
                  if_stmt(sig(:micro_ready, width: 1)) do
                    assign(
                      :mc_cmd,
                      sig(:mc_cmd_next, width: 7),
                      kind: :nonblocking
                    )
                  end
                end
              end
            end
          end
        end
      end
      else_block do
        assign(
          :mc_cmd,
          lit(0, width: 7, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_11,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_cmdex,
          sig(:dec_cmdex, width: 4),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_cmdex,
              lit(0, width: 4, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_cmdex,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_12,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_consumed,
          sig(:dec_consumed, width: 4),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:task_start, width: 1)) do
            assign(
              :mc_consumed,
              lit(0, width: 4, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:exc_load, width: 1)) do
                assign(
                  :mc_consumed,
                  lit(0, width: 4, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
            end
          end
        end
      end
      else_block do
        assign(
          :mc_consumed,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_13,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_eip,
          sig(:dec_eip, width: 32),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:task_start, width: 1)) do
            assign(
              :mc_eip,
              sig(:task_eip, width: 32),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:exc_load, width: 1)) do
                assign(
                  :mc_eip,
                  sig(:exc_eip, width: 32),
                  kind: :nonblocking
                )
              end
            end
          end
        end
      end
      else_block do
        assign(
          :mc_eip,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_14,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:m_load, width: 1)) do
        assign(
          :mc_step,
          lit(1, width: 6, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:micro_ready, width: 1)) do
            assign(
              :mc_step,
              (
                  lit(1, width: 6, base: "h", signed: false) +
                  sig(:mc_step, width: 6)
              ),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:exc_init, width: 1)) do
                assign(
                  :mc_step,
                  lit(1, width: 6, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
            end
          end
        end
      end
      else_block do
        assign(
          :mc_step,
          lit(0, width: 6, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_15,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :mc_cmdex_last,
          sig(:micro_cmdex, width: 4),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exc_init, width: 1)) do
            assign(
              :mc_cmdex_last,
              lit(0, width: 4, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :mc_cmdex_last,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_15,
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

  # Instances

  instance :microcode_commands_inst, "microcode_commands"

end
