# frozen_string_literal: true

class Prefetch < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: prefetch

  def self._import_decl_kinds
    {
      _unused_ok: :wire,
      cs_base: :wire,
      cs_limit: :wire,
      length: :wire,
      limit: :reg,
      limit_signaled: :reg,
      linear: :reg,
      prefetched_accept_do_1: :reg,
      prefetched_accept_length_1: :reg
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :pr_reset
  input :reset_prefetch
  input :prefetch_cpl, width: 2
  input :prefetch_eip, width: 32
  input :cs_cache, width: 64
  output :prefetch_address, width: 32
  output :prefetch_length, width: 5
  output :prefetch_su
  input :prefetched_do
  input :prefetched_length, width: 5
  input :prefetched_accept_do
  input :prefetched_accept_length, width: 4
  output :prefetchfifo_signal_limit_do
  output :delivered_eip, width: 32

  # Signals

  signal :_unused_ok
  signal :cs_base, width: 32
  signal :cs_limit, width: 32
  signal :length, width: 5
  signal :limit, width: 32
  signal :limit_signaled
  signal :linear, width: 32
  signal :prefetched_accept_do_1
  signal :prefetched_accept_length_1, width: 4

  # Assignments

  assign :cs_base,
    sig(:cs_cache, width: 64)[63..56].concat(
      sig(:cs_cache, width: 64)[39..16]
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
  assign :prefetch_su,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:prefetch_cpl, width: 2)
    )
  assign :prefetch_address,
    sig(:linear, width: 32)
  assign :prefetch_length,
    mux(
      (
          lit(16, width: 32, base: "h", signed: false) <
          sig(:limit, width: 32)
      ),
      lit(16, width: 5, base: "h", signed: false),
      sig(:limit, width: 32)[4..0]
    )
  assign :length,
    mux(
      (
          sig(:limit, width: 32) <
          lit(0, width: 27, base: "d", signed: false).concat(
          sig(:prefetched_length, width: 5)
        )
      ),
      sig(:limit, width: 32)[4..0],
      sig(:prefetched_length, width: 5)
    )
  assign :prefetchfifo_signal_limit_do,
    (
        (
          ~sig(:limit_signaled, width: 1)
        ) &
        (
            lit(0, width: 32, base: "h", signed: false) ==
            sig(:limit, width: 32)
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
      if_stmt(sig(:pr_reset, width: 1)) do
        assign(
          :limit,
          mux(
            (
                sig(:cs_limit, width: 32) >=
                sig(:prefetch_eip, width: 32)
            ),
            (
                lit(1, width: 32, base: "h", signed: false) +
                (
                    sig(:cs_limit, width: 32) -
                    sig(:prefetch_eip, width: 32)
                )
            ),
            lit(0, width: 32, base: "h", signed: false)
          ),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:reset_prefetch, width: 1)) do
            assign(
              :limit,
              mux(
                (
                    sig(:cs_limit, width: 32) >=
                    sig(:prefetch_eip, width: 32)
                ),
                (
                    lit(1, width: 32, base: "h", signed: false) +
                    (
                        sig(:cs_limit, width: 32) -
                        sig(:prefetch_eip, width: 32)
                    )
                ),
                lit(0, width: 32, base: "h", signed: false)
              ),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:prefetched_do, width: 1)) do
                assign(
                  :limit,
                  (
                      sig(:limit, width: 32) -
                      lit(0, width: 27, base: "d", signed: false).concat(
                      sig(:length, width: 5)
                    )
                  ),
                  kind: :nonblocking
                )
              end
            end
          end
        end
      end
      else_block do
        assign(
          :limit,
          lit(16, width: 32, base: "h", signed: false),
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
    assign(
      :prefetched_accept_do_1,
      sig(:prefetched_accept_do, width: 1),
      kind: :nonblocking
    )
    assign(
      :prefetched_accept_length_1,
      sig(:prefetched_accept_length, width: 4),
      kind: :nonblocking
    )
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:pr_reset, width: 1)) do
        assign(
          :linear,
          (
              sig(:cs_base, width: 32) +
              sig(:prefetch_eip, width: 32)
          ),
          kind: :nonblocking
        )
        assign(
          :delivered_eip,
          (
              sig(:cs_base, width: 32) +
              sig(:prefetch_eip, width: 32)
          ),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:reset_prefetch, width: 1)) do
            assign(
              :linear,
              mux(
                sig(:prefetched_accept_do_1, width: 1),
                (
                    sig(:delivered_eip, width: 32) +
                    lit(0, width: 28, base: "d", signed: false).concat(
                    sig(:prefetched_accept_length_1, width: 4)
                  )
                ),
                sig(:delivered_eip, width: 32)
              ),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:prefetched_do, width: 1)) do
                assign(
                  :linear,
                  (
                      sig(:linear, width: 32) +
                      lit(0, width: 27, base: "d", signed: false).concat(
                      sig(:length, width: 5)
                    )
                  ),
                  kind: :nonblocking
                )
              end
            end
          end
          if_stmt(sig(:prefetched_accept_do_1, width: 1)) do
            assign(
              :delivered_eip,
              (
                  sig(:delivered_eip, width: 32) +
                  lit(0, width: 28, base: "d", signed: false).concat(
                  sig(:prefetched_accept_length_1, width: 4)
                )
              ),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :linear,
          lit(1048560, width: 32, base: "h", signed: false),
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
      if_stmt(sig(:pr_reset, width: 1)) do
        assign(
          :limit_signaled,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:prefetchfifo_signal_limit_do, width: 1)) do
            assign(
              :limit_signaled,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :limit_signaled,
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

end
