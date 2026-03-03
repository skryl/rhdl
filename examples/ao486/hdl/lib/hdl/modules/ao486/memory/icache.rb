# frozen_string_literal: true

class Icache < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: icache

  def self._import_decl_kinds
    {
      __VdfgRegularize_ha31dd077_0_0: :logic,
      length: :reg,
      length_burst: :wire,
      max_check: :reg,
      min_check: :reg,
      partial_length: :reg,
      prefetch_checkaddr: :reg,
      prefetch_checknext: :reg,
      readcode_cache_address: :wire,
      readcode_cache_data: :wire,
      readcode_cache_do: :wire,
      readcode_cache_done: :wire,
      readcode_cache_valid: :wire,
      reset_combined: :wire,
      reset_prefetch_count: :reg,
      reset_waiting: :reg,
      state: :reg
    }
  end

  # Parameters

  generic :STATE_IDLE, default: "1'h0"
  generic :STATE_READ, default: "1'h1"

  # Ports

  input :clk
  input :rst_n
  input :cache_disable
  input :pr_reset
  input :prefetch_address, width: 32
  input :delivered_eip, width: 32
  output :reset_prefetch
  input :icacheread_do
  input :icacheread_address, width: 32
  input :icacheread_length, width: 5
  output :readcode_do
  input :readcode_done
  output :readcode_address, width: 32
  input :readcode_partial, width: 32
  output :prefetchfifo_write_do
  output :prefetchfifo_write_data, width: 36
  output :prefetched_do
  output :prefetched_length, width: 5
  input :snoop_addr, width: (27..2)
  input :snoop_data, width: 32
  input :snoop_be, width: 4
  input :snoop_we

  # Signals

  signal :__VdfgRegularize_ha31dd077_0_0
  signal :length, width: 5
  signal :length_burst, width: 12
  signal :max_check, width: 32
  signal :min_check, width: 32
  signal :partial_length, width: 12
  signal :prefetch_checkaddr, width: 32
  signal :prefetch_checknext
  signal :readcode_cache_address, width: 32
  signal :readcode_cache_data, width: 32
  signal :readcode_cache_do
  signal :readcode_cache_done
  signal :readcode_cache_valid
  signal :reset_combined
  signal :reset_prefetch_count, width: 2
  signal :reset_waiting
  signal :state

  # Assignments

  assign :reset_combined,
    (
        sig(:pr_reset, width: 1) |
        sig(:reset_prefetch, width: 1)
    )
  assign :readcode_cache_do,
    (
        sig(:rst_n, width: 1) &
        (
            (
              ~sig(:state, width: 1)
            ) &
            (
                sig(:__VdfgRegularize_ha31dd077_0_0, width: 1) &
                (
                    sig(:icacheread_do, width: 1) &
                    (
                        lit(0, width: 5, base: "h", signed: false) <
                        sig(:icacheread_length, width: 5)
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_ha31dd077_0_0,
    (
      ~sig(:reset_combined, width: 1)
    )
  assign :prefetchfifo_write_do,
    (
        sig(:rst_n, width: 1) &
        (
            sig(:__VdfgRegularize_ha31dd077_0_0, width: 1) &
            (
                sig(:state, width: 1) &
                (
                    (
                      ~sig(:reset_waiting, width: 1)
                    ) &
                    sig(:readcode_cache_valid, width: 1)
                )
            )
        )
    )
  assign :prefetched_do,
    sig(:prefetchfifo_write_do, width: 1)
  assign :prefetchfifo_write_data,
    case_select(
      sig(:partial_length, width: 12)[2..0],
      cases: {
        1 => lit(16777216, width: 28, base: "h", signed: false).concat(sig(:readcode_cache_data, width: 32)[31..24]),
        2 => mux((lit(2, width: 5, base: "h", signed: false) < sig(:length, width: 5)), lit(2, width: 4, base: "h", signed: false), sig(:length, width: 5)[3..0]).concat((sig(:readcode_cache_data, width: 32) >> lit(16, width: 32, base: "h", signed: false))),
        3 => mux((lit(3, width: 5, base: "h", signed: false) < sig(:length, width: 5)), lit(3, width: 4, base: "h", signed: false), sig(:length, width: 5)[3..0]).concat((sig(:readcode_cache_data, width: 32) >> lit(8, width: 32, base: "h", signed: false)))
      },
      default: mux((lit(4, width: 5, base: "h", signed: false) < sig(:length, width: 5)), lit(4, width: 4, base: "h", signed: false), sig(:length, width: 5)[3..0]).concat(
        sig(:readcode_cache_data, width: 32)
      )
    )
  assign :prefetched_length,
    mux(
      (
          lit(0, width: 2, base: "d", signed: false).concat(
            sig(:partial_length, width: 12)[2..0]
          ) >
          sig(:length, width: 5)
      ),
      sig(:length, width: 5),
      lit(0, width: 2, base: "d", signed: false).concat(
        sig(:partial_length, width: 12)[2..0]
      )
    )
  assign :length_burst,
    case_select(
      sig(:icacheread_address, width: 32)[1..0],
      cases: {
        0 => lit(2340, width: 12, base: "h", signed: false),
        1 => lit(2339, width: 12, base: "h", signed: false),
        2 => lit(2338, width: 12, base: "h", signed: false)
      },
      default: lit(2337, width: 12, base: "h", signed: false)
    )
  assign :readcode_cache_address,
    sig(:icacheread_address, width: 32)[31..2].concat(
      lit(0, width: 2, base: "h", signed: false)
    )

  # Processes

  process :initial_block_0,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :reset_prefetch,
      lit(0, width: 1, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :initial_block_1,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :reset_prefetch_count,
      lit(0, width: 2, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :prefetch_checknext,
      lit(0, width: 1, base: "h", signed: false),
      kind: :nonblocking
    )
    assign(
      :prefetch_checkaddr,
      lit(0, width: 4, base: "d", signed: false).concat(
        sig(:snoop_addr, width: 26)
      ).concat(
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
    assign(
      :min_check,
      sig(:delivered_eip, width: 32),
      kind: :nonblocking
    )
    assign(
      :max_check,
      (
          lit(20, width: 32, base: "h", signed: false) +
          sig(:prefetch_address, width: 32)
      ),
      kind: :nonblocking
    )
    if_stmt(sig(:snoop_we, width: 1)) do
      assign(
        :prefetch_checknext,
        lit(1, width: 1, base: "h", signed: false),
        kind: :nonblocking
      )
    end
    if_stmt(((sig(:prefetch_checknext, width: 1) & (sig(:prefetch_checkaddr, width: 32) >= sig(:min_check, width: 32))) & (sig(:prefetch_checkaddr, width: 32) <= sig(:max_check, width: 32)))) do
      assign(
        :reset_prefetch,
        lit(1, width: 1, base: "h", signed: false),
        kind: :nonblocking
      )
      assign(
        :reset_prefetch_count,
        lit(2, width: 2, base: "h", signed: false),
        kind: :nonblocking
      )
    end
    if_stmt((lit(0, width: 2, base: "h", signed: false) < sig(:reset_prefetch_count, width: 2))) do
      assign(
        :reset_prefetch_count,
        (
            sig(:reset_prefetch_count, width: 2) -
            lit(1, width: 2, base: "h", signed: false)
        ),
        kind: :nonblocking
      )
      if_stmt((lit(1, width: 2, base: "h", signed: false) == sig(:reset_prefetch_count, width: 2))) do
        assign(
          :reset_prefetch,
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
      if_stmt((sig(:reset_combined, width: 1) & sig(:state, width: 1))) do
        assign(
          :reset_waiting,
          lit(1, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block((~sig(:state, width: 1))) do
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

  process :sequential_posedge_clk_3,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(((((~sig(:state, width: 1)) & (~sig(:reset_combined, width: 1))) & sig(:icacheread_do, width: 1)) & (lit(0, width: 5, base: "h", signed: false) < sig(:icacheread_length, width: 5)))) do
        assign(
          :state,
          lit(1, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        assign(
          :partial_length,
          sig(:length_burst, width: 12),
          kind: :nonblocking
        )
        assign(
          :length,
          sig(:icacheread_length, width: 5),
          kind: :nonblocking
        )
        elsif_block(sig(:state, width: 1)) do
          if_stmt(((~sig(:reset_combined, width: 1)) & (~sig(:reset_waiting, width: 1)))) do
            if_stmt(sig(:readcode_cache_valid, width: 1)) do
              if_stmt(((lit(0, width: 3, base: "h", signed: false) < sig(:partial_length, width: 12)[2..0]) & (lit(0, width: 5, base: "h", signed: false) < sig(:length, width: 5)))) do
                assign(
                  :length,
                  (
                      sig(:length, width: 5) -
                      sig(:prefetched_length, width: 5)
                  ),
                  kind: :nonblocking
                )
                assign(
                  :partial_length,
                  lit(0, width: 3, base: "d", signed: false).concat(
                    sig(:partial_length, width: 12)[11..3]
                  ),
                  kind: :nonblocking
                )
              end
            end
          end
          if_stmt(sig(:readcode_cache_done, width: 1)) do
            assign(
              :state,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :state,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        assign(
          :length,
          lit(0, width: 5, base: "h", signed: false),
          kind: :nonblocking
        )
        assign(
          :partial_length,
          lit(0, width: 12, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  # Instances

  instance :l1_icache_inst, "l1_icache",
    ports: {
      CLK: :clk,
      RESET: (~sig(:rst_n, width: 1)),
      pr_reset: :reset_combined,
      DISABLE: :cache_disable,
      CPU_REQ: :readcode_cache_do,
      CPU_ADDR: :readcode_cache_address,
      CPU_VALID: :readcode_cache_valid,
      CPU_DONE: :readcode_cache_done,
      CPU_DATA: :readcode_cache_data,
      MEM_REQ: :readcode_do,
      MEM_ADDR: :readcode_address,
      MEM_DONE: :readcode_done,
      MEM_DATA: :readcode_partial
    }

end
