# frozen_string_literal: true

class TlbMemtype < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: tlb_memtype

  def self._import_decl_kinds
    {
      _unused_ok: :wire
    }
  end

  # Ports

  input :physical, width: 32
  output :cache_disable
  output :write_transparent

  # Signals

  signal :_unused_ok

  # Assignments

  assign :cache_disable,
    (
        (
            lit(40960, width: 28, base: "h", signed: false) <=
            sig(:physical, width: 32)[31..4]
        ) &
        (
            lit(49152, width: 28, base: "h", signed: false) >
            sig(:physical, width: 32)[31..4]
        )
    )
  assign :write_transparent,
    sig(:cache_disable, width: 1)

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
