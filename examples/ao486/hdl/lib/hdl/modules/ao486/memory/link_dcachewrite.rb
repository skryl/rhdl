# frozen_string_literal: true

class LinkDcachewrite < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: link_dcachewrite

  def self._import_decl_kinds
    {
      address: :reg,
      cache_disable: :reg,
      current_do: :reg,
      data: :reg,
      done_delayed: :reg,
      length: :reg,
      save: :wire,
      write_through: :reg
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :req_dcachewrite_do
  output :req_dcachewrite_done
  input :req_dcachewrite_length, width: 3
  input :req_dcachewrite_cache_disable
  input :req_dcachewrite_address, width: 32
  input :req_dcachewrite_write_through
  input :req_dcachewrite_data, width: 32
  output :resp_dcachewrite_do
  input :resp_dcachewrite_done
  output :resp_dcachewrite_length, width: 3
  output :resp_dcachewrite_cache_disable
  output :resp_dcachewrite_address, width: 32
  output :resp_dcachewrite_write_through
  output :resp_dcachewrite_data, width: 32

  # Signals

  signal :address, width: 32
  signal :cache_disable
  signal :current_do
  signal :data, width: 32
  signal :done_delayed
  signal :length, width: 3
  signal :save
  signal :write_through

  # Assignments

  assign :save,
    (
        (
          ~(
              sig(:done_delayed, width: 1) |
              sig(:resp_dcachewrite_done, width: 1)
          )
        ) &
        sig(:req_dcachewrite_do, width: 1)
    )
  assign :req_dcachewrite_done,
    sig(:done_delayed, width: 1)
  assign :resp_dcachewrite_do,
    (
        sig(:current_do, width: 1) |
        sig(:req_dcachewrite_do, width: 1)
    )
  assign :resp_dcachewrite_length,
    mux(
      sig(:req_dcachewrite_do, width: 1),
      sig(:req_dcachewrite_length, width: 3),
      sig(:length, width: 3)
    )
  assign :resp_dcachewrite_cache_disable,
    mux(
      sig(:req_dcachewrite_do, width: 1),
      sig(:req_dcachewrite_cache_disable, width: 1),
      sig(:cache_disable, width: 1)
    )
  assign :resp_dcachewrite_address,
    mux(
      sig(:req_dcachewrite_do, width: 1),
      sig(:req_dcachewrite_address, width: 32),
      sig(:address, width: 32)
    )
  assign :resp_dcachewrite_write_through,
    mux(
      sig(:req_dcachewrite_do, width: 1),
      sig(:req_dcachewrite_write_through, width: 1),
      sig(:write_through, width: 1)
    )
  assign :resp_dcachewrite_data,
    mux(
      sig(:req_dcachewrite_do, width: 1),
      sig(:req_dcachewrite_data, width: 32),
      sig(:data, width: 32)
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:save, width: 1)) do
        assign(
          :current_do,
          sig(:req_dcachewrite_do, width: 1),
          kind: :nonblocking
        )
        elsif_block(sig(:resp_dcachewrite_done, width: 1)) do
          assign(
            :current_do,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :current_do,
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
      if_stmt(sig(:save, width: 1)) do
        assign(
          :length,
          sig(:req_dcachewrite_length, width: 3),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :length,
          lit(0, width: 3, base: "h", signed: false),
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
      if_stmt(sig(:save, width: 1)) do
        assign(
          :cache_disable,
          sig(:req_dcachewrite_cache_disable, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :cache_disable,
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
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:save, width: 1)) do
        assign(
          :address,
          sig(:req_dcachewrite_address, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :address,
          lit(0, width: 32, base: "h", signed: false),
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
      if_stmt(sig(:save, width: 1)) do
        assign(
          :write_through,
          sig(:req_dcachewrite_write_through, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :write_through,
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
      if_stmt(sig(:save, width: 1)) do
        assign(
          :data,
          sig(:req_dcachewrite_data, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :data,
          lit(0, width: 32, base: "h", signed: false),
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
    assign(
      :done_delayed,
      (
          sig(:rst_n, width: 1) &
          sig(:resp_dcachewrite_done, width: 1)
      ),
      kind: :nonblocking
    )
  end

end
