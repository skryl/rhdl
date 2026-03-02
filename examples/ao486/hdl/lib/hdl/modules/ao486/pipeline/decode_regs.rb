# frozen_string_literal: true

class DecodeRegs < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: decode_regs

  def self._import_decl_kinds
    {
      acceptable_1: :wire,
      acceptable_2: :wire,
      accepted: :wire,
      after_consume: :wire,
      after_consume_count: :wire,
      decoder_next: :wire,
      total_count: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :dec_reset
  input :fetch_valid, width: 4
  input :fetch, width: 64
  input :prefix_count, width: 4
  input :consume_count, width: 4
  output :dec_acceptable, width: 4
  output :decoder, width: 96
  output :decoder_count, width: 4

  # Signals

  signal :acceptable_1, width: 4
  signal :acceptable_2, width: 4
  signal :accepted, width: 4
  signal :after_consume, width: 96
  signal :after_consume_count, width: 4
  signal :decoder_next, width: 96
  signal :total_count, width: 5

  # Assignments

  assign :after_consume_count,
    (
        sig(:decoder_count, width: 4) -
        sig(:consume_count, width: 4)
    )
  assign :total_count,
    (
        lit(0, width: 1, base: "d", signed: false).concat(
          sig(:prefix_count, width: 4)
        ) +
        lit(0, width: 1, base: "d", signed: false).concat(
        sig(:decoder_count, width: 4)
      )
    )
  assign :acceptable_1,
    (
        (
            lit(12, width: 4, base: "h", signed: false) -
            sig(:decoder_count, width: 4)
        ) +
        sig(:consume_count, width: 4)
    )
  assign :acceptable_2,
    mux(
      (
          lit(15, width: 5, base: "h", signed: false) >
          sig(:total_count, width: 5)
      ),
      (
          lit(15, width: 4, base: "h", signed: false) -
          sig(:total_count, width: 5)[3..0]
      ),
      lit(0, width: 4, base: "h", signed: false)
    )
  assign :dec_acceptable,
    mux(
      sig(:dec_reset, width: 1),
      lit(0, width: 4, base: "h", signed: false),
      mux(
        (
            sig(:acceptable_1, width: 4) <
            sig(:acceptable_2, width: 4)
        ),
        sig(:acceptable_1, width: 4),
        sig(:acceptable_2, width: 4)
      )
    )
  assign :accepted,
    mux(
      (
          sig(:dec_acceptable, width: 4) >
          sig(:fetch_valid, width: 4)
      ),
      sig(:fetch_valid, width: 4),
      sig(:dec_acceptable, width: 4)
    )
  assign :after_consume,
    case_select(
      sig(:consume_count, width: 4),
      cases: {
        0 => sig(:decoder, width: 96),
        1 => (sig(:decoder, width: 96) >> lit(8, width: 32, base: "h", signed: false)),
        2 => (sig(:decoder, width: 96) >> lit(16, width: 32, base: "h", signed: false)),
        3 => (sig(:decoder, width: 96) >> lit(24, width: 32, base: "h", signed: false)),
        4 => (sig(:decoder, width: 96) >> lit(32, width: 32, base: "h", signed: false)),
        5 => (sig(:decoder, width: 96) >> lit(40, width: 32, base: "h", signed: false)),
        6 => (sig(:decoder, width: 96) >> lit(48, width: 32, base: "h", signed: false)),
        7 => (sig(:decoder, width: 96) >> lit(56, width: 32, base: "h", signed: false)),
        8 => (sig(:decoder, width: 96) >> lit(64, width: 32, base: "h", signed: false)),
        9 => (sig(:decoder, width: 96) >> lit(72, width: 32, base: "h", signed: false)),
        10 => (sig(:decoder, width: 96) >> lit(80, width: 32, base: "h", signed: false))
      },
      default: (sig(:decoder, width: 96) >> lit(88, width: 32, base: "h", signed: false))
    )
  assign :decoder_next,
    case_select(
      sig(:after_consume_count, width: 4),
      cases: {
        0 => lit(0, width: 32, base: "d", signed: false).concat(sig(:fetch, width: 64)),
        1 => lit(0, width: 24, base: "d", signed: false).concat(sig(:fetch, width: 64).concat(sig(:after_consume, width: 96)[7..0])),
        2 => lit(0, width: 16, base: "d", signed: false).concat(sig(:fetch, width: 64).concat(sig(:after_consume, width: 96)[15..0])),
        3 => lit(0, width: 8, base: "d", signed: false).concat(sig(:fetch, width: 64).concat(sig(:after_consume, width: 96)[23..0])),
        4 => sig(:fetch, width: 64).concat(sig(:after_consume, width: 96)[31..0]),
        5 => sig(:fetch, width: 64)[55..0].concat(sig(:after_consume, width: 96)[39..0]),
        6 => sig(:fetch, width: 64)[47..0].concat(sig(:after_consume, width: 96)[47..0]),
        7 => sig(:fetch, width: 64)[39..0].concat(sig(:after_consume, width: 96)[55..0]),
        8 => sig(:fetch, width: 64)[31..0].concat(sig(:after_consume, width: 96)[63..0]),
        9 => sig(:fetch, width: 64)[23..0].concat(sig(:after_consume, width: 96)[71..0]),
        10 => sig(:fetch, width: 64)[15..0].concat(sig(:after_consume, width: 96)[79..0]),
        11 => sig(:fetch, width: 64)[7..0].concat(sig(:after_consume, width: 96)[87..0])
      },
      default: sig(:after_consume, width: 96)
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :decoder,
      mux(
        sig(:rst_n, width: 1),
        sig(:decoder_next, width: 96),
        lit(0, width: 96, base: "h", signed: false)
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
    assign(
      :decoder_count,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:dec_reset, width: 1),
          lit(0, width: 4, base: "h", signed: false),
          (
              sig(:after_consume_count, width: 4) +
              sig(:accepted, width: 4)
          )
        ),
        lit(0, width: 4, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

end
