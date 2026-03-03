# frozen_string_literal: true

class SimpleFifoMlabWB4W3e < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: simple_fifo_mlab__WB4_W3e

  def self._import_decl_kinds
    {
      mem: :reg,
      rd_index: :reg,
      wr_index: :reg
    }
  end

  # Parameters

  generic :width, default: "32'sh3e"
  generic :widthu, default: "32'sh4"

  # Ports

  input :clk
  input :rst_n
  input :sclr
  input :rdreq
  input :wrreq
  input :data, width: 62
  output :empty
  output :full
  output :q, width: 62
  output :usedw, width: 4

  # Signals

  signal :mem, width: 992
  signal :rd_index, width: 4
  signal :wr_index, width: 4

  # Assignments

  assign :empty,
    (
        (
          ~sig(:full, width: 1)
        ) &
        (
            lit(0, width: 4, base: "h", signed: false) ==
            sig(:usedw, width: 4)
        )
    )

  # Processes

  process :initial_block_0,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :rd_index,
      lit(0, width: 4, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :initial_block_1,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :wr_index,
      lit(0, width: 4, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:sclr, width: 1)) do
        assign(
          :rd_index,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block((sig(:rdreq, width: 1) & (~sig(:empty, width: 1)))) do
          assign(
            :rd_index,
            (
                lit(1, width: 4, base: "h", signed: false) +
                sig(:rd_index, width: 4)
            ),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :rd_index,
          lit(0, width: 4, base: "h", signed: false),
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
      if_stmt(sig(:sclr, width: 1)) do
        assign(
          :wr_index,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block((sig(:wrreq, width: 1) & ((~sig(:full, width: 1)) | sig(:rdreq, width: 1)))) do
          assign(
            :wr_index,
            (
                lit(1, width: 4, base: "h", signed: false) +
                sig(:wr_index, width: 4)
            ),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :wr_index,
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
      if_stmt(sig(:sclr, width: 1)) do
        assign(
          :full,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(((sig(:rdreq, width: 1) & (~sig(:wrreq, width: 1))) & sig(:full, width: 1))) do
          assign(
            :full,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
        elsif_block(((((~sig(:rdreq, width: 1)) & sig(:wrreq, width: 1)) & (~sig(:full, width: 1))) & (lit(15, width: 4, base: "h", signed: false) == sig(:usedw, width: 4)))) do
          assign(
            :full,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :full,
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
      if_stmt(sig(:sclr, width: 1)) do
        assign(
          :usedw,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(((sig(:rdreq, width: 1) & (~sig(:wrreq, width: 1))) & (~sig(:empty, width: 1)))) do
          assign(
            :usedw,
            (
                sig(:usedw, width: 4) -
                lit(1, width: 4, base: "h", signed: false)
            ),
            kind: :nonblocking
          )
        end
        elsif_block((((~sig(:rdreq, width: 1)) & sig(:wrreq, width: 1)) & (~sig(:full, width: 1)))) do
          assign(
            :usedw,
            (
                lit(1, width: 4, base: "h", signed: false) +
                sig(:usedw, width: 4)
            ),
            kind: :nonblocking
          )
        end
        elsif_block(((sig(:rdreq, width: 1) & sig(:wrreq, width: 1)) & sig(:empty, width: 1))) do
          assign(
            :usedw,
            lit(1, width: 4, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :usedw,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  # Instances

  instance :altdpram_component, "altdpram__W3e",
    ports: {
      inclock: :clk,
      outclock: :clk,
      rdaddress: :rd_index,
      wraddress: :wr_index,
      wren: (sig(:wrreq, width: 1) & ((~sig(:full, width: 1)) | sig(:rdreq, width: 1))),
      aclr: lit(0, width: 1, base: "h", signed: false),
      byteena: lit(1, width: 1, base: "h", signed: false),
      inclocken: lit(1, width: 1, base: "h", signed: false),
      outclocken: lit(1, width: 1, base: "h", signed: false),
      rdaddressstall: lit(0, width: 1, base: "h", signed: false),
      rden: lit(1, width: 1, base: "h", signed: false),
      sclr: lit(0, width: 1, base: "h", signed: false),
      wraddressstall: lit(0, width: 1, base: "h", signed: false)
    }

end
