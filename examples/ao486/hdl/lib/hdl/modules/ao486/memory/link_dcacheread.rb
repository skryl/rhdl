# frozen_string_literal: true

class LinkDcacheread < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: link_dcacheread

  def self._import_decl_kinds
    {
      address: :reg,
      cache_disable: :reg,
      current_do: :reg,
      length: :reg,
      save: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :req_dcacheread_do
  output :req_dcacheread_done
  input :req_dcacheread_length, width: 4
  input :req_dcacheread_cache_disable
  input :req_dcacheread_address, width: 32
  output :req_dcacheread_data, width: 64
  output :resp_dcacheread_do
  input :resp_dcacheread_done
  output :resp_dcacheread_length, width: 4
  output :resp_dcacheread_cache_disable
  output :resp_dcacheread_address, width: 32
  input :resp_dcacheread_data, width: 64

  # Signals

  signal :address, width: 32
  signal :cache_disable
  signal :current_do
  signal :length, width: 4
  signal :save

  # Assignments

  assign :save,
    (
        (
          ~sig(:resp_dcacheread_done, width: 1)
        ) &
        sig(:req_dcacheread_do, width: 1)
    )
  assign :req_dcacheread_done,
    sig(:resp_dcacheread_done, width: 1)
  assign :resp_dcacheread_do,
    (
        sig(:current_do, width: 1) |
        sig(:req_dcacheread_do, width: 1)
    )
  assign :resp_dcacheread_length,
    mux(
      sig(:req_dcacheread_do, width: 1),
      sig(:req_dcacheread_length, width: 4),
      sig(:length, width: 4)
    )
  assign :resp_dcacheread_cache_disable,
    mux(
      sig(:req_dcacheread_do, width: 1),
      sig(:req_dcacheread_cache_disable, width: 1),
      sig(:cache_disable, width: 1)
    )
  assign :resp_dcacheread_address,
    mux(
      sig(:req_dcacheread_do, width: 1),
      sig(:req_dcacheread_address, width: 32),
      sig(:address, width: 32)
    )
  assign :req_dcacheread_data,
    sig(:resp_dcacheread_data, width: 64)

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
          sig(:req_dcacheread_do, width: 1),
          kind: :nonblocking
        )
        elsif_block(sig(:resp_dcacheread_done, width: 1)) do
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
          sig(:req_dcacheread_length, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :length,
          lit(0, width: 4, base: "h", signed: false),
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
          sig(:req_dcacheread_cache_disable, width: 1),
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
          sig(:req_dcacheread_address, width: 32),
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

end
