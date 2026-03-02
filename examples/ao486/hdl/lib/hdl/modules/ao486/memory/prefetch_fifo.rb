# frozen_string_literal: true

class PrefetchFifo < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: prefetch_fifo

  def self._import_decl_kinds
    {
      bypass: :wire,
      empty: :wire,
      q: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :pr_reset
  input :prefetchfifo_signal_limit_do
  input :prefetchfifo_signal_pf_do
  input :prefetchfifo_write_do
  input :prefetchfifo_write_data, width: 36
  output :prefetchfifo_used, width: 5
  input :prefetchfifo_accept_do
  output :prefetchfifo_accept_data, width: 68
  output :prefetchfifo_accept_empty

  # Signals

  signal :bypass
  signal :empty
  signal :q, width: 36

  # Assignments

  assign :bypass,
    (
        sig(:empty, width: 1) &
        sig(:prefetchfifo_write_do, width: 1)
    )
  assign :prefetchfifo_accept_data,
    mux(
      sig(:bypass, width: 1),
      sig(:prefetchfifo_write_data, width: 36)[35..32].concat(
        lit(0, width: 32, base: "d", signed: false).concat(
          sig(:prefetchfifo_write_data, width: 36)[31..0]
        )
      ),
      sig(:q, width: 36)[35..32].concat(
        lit(0, width: 32, base: "d", signed: false).concat(
          sig(:q, width: 36)[31..0]
        )
      )
    )
  assign :prefetchfifo_accept_empty,
    (
        (
          ~sig(:bypass, width: 1)
        ) &
        sig(:empty, width: 1)
    )

  # Instances

  instance :prefetch_fifo_inst, "simple_fifo_mlab__W24_WB4",
    ports: {
      sclr: :pr_reset,
      rdreq: :prefetchfifo_accept_do,
      wrreq: (((sig(:prefetchfifo_write_do, width: 1) & ((~sig(:empty, width: 1)) | (~sig(:prefetchfifo_accept_do, width: 1)))) | sig(:prefetchfifo_signal_limit_do, width: 1)) | sig(:prefetchfifo_signal_pf_do, width: 1)),
      data: mux(sig(:prefetchfifo_signal_limit_do, width: 1), lit(64424509440, width: 36, base: "h", signed: false), mux(sig(:prefetchfifo_signal_pf_do, width: 1), lit(60129542144, width: 36, base: "h", signed: false), sig(:prefetchfifo_write_data, width: 36))),
      full: sig(:prefetchfifo_used, width: 5)[4],
      usedw: sig(:prefetchfifo_used, width: 5)[3..0]
    }

end
