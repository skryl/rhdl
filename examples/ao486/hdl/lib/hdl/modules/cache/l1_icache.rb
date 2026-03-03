# frozen_string_literal: true

class L1Icache < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: l1_icache

  def self._import_decl_kinds
    {
      CPU_REQ_hold: :reg,
      Fifo_dout: :wire,
      Fifo_empty: :wire,
      LRU_addr: :reg,
      LRU_in: :reg,
      LRU_out: :reg,
      LRU_we: :reg,
      burstleft: :reg,
      cache_mux: :reg,
      fillcount: :reg,
      force_fetch: :reg,
      force_next: :reg,
      i: :reg,
      match: :reg,
      memory_addr_a: :reg,
      memory_be: :reg,
      memory_datain: :reg,
      memory_we: :reg,
      read_addr: :reg,
      readdata_cache: :wire,
      state: :reg,
      tags_dirty_in: :reg,
      tags_dirty_out: :reg,
      tags_read: :wire,
      update_tag_addr: :reg,
      update_tag_we: :reg
    }
  end

  # Parameters

  generic :LINES, default: "32'sh80"
  generic :LINESIZE, default: "32'sh8"
  generic :ASSOCIATIVITY, default: "32'sh4"
  generic :ADDRBITS, default: "32'sh1d"
  generic :CACHEBURST, default: "32'sh4"
  generic :ASSO_BITS, default: "32'h2"
  generic :LINESIZE_BITS, default: "32'h3"
  generic :LINE_BITS, default: "32'h7"
  generic :CACHEBURST_BITS, default: "32'h2"
  generic :RAMSIZEBITS, default: "32'ha"
  generic :LINEMASKLSB, default: "32'h3"
  generic :LINEMASKMSB, default: "32'h9"
  generic :START, default: "3'h0"
  generic :IDLE, default: "3'h1"
  generic :WRITEONE, default: "3'h2"
  generic :READONE, default: "3'h3"
  generic :FILLCACHE, default: "3'h4"
  generic :READCACHE_OUT, default: "3'h5"

  # Ports

  input :CLK
  input :RESET
  input :pr_reset
  input :DISABLE
  input :CPU_REQ
  input :CPU_ADDR, width: 32
  output :CPU_VALID
  output :CPU_DONE
  output :CPU_DATA, width: 32
  output :MEM_REQ
  output :MEM_ADDR, width: 32
  input :MEM_DONE
  input :MEM_DATA, width: 32
  input :snoop_addr, width: (27..2)
  input :snoop_data, width: 32
  input :snoop_be, width: 4
  input :snoop_we

  # Signals

  signal :CPU_REQ_hold
  signal :Fifo_dout, width: 62
  signal :Fifo_empty
  signal :LRU_addr, width: 7
  signal :LRU_in, width: 8
  signal :LRU_out, width: 8
  signal :LRU_we
  signal :burstleft, width: 2
  signal :cache_mux, width: 2
  signal :fillcount, width: 3
  signal :force_fetch
  signal :force_next
  signal :i, width: 2
  signal :match
  signal :memory_addr_a, width: 10
  signal :memory_be, width: 4
  signal :memory_datain, width: 32
  signal :memory_we, width: (0..3)
  signal :read_addr, width: 30
  signal :readdata_cache, width: 128
  signal :state, width: 3
  signal :tags_dirty_in, width: 4
  signal :tags_dirty_out, width: 4
  signal :tags_read, width: 80
  signal :update_tag_addr, width: 7
  signal :update_tag_we

  # Assignments

  assign :CPU_DATA,
    sig(:readdata_cache, width: 128)[((sig(:cache_mux, width: 2) * lit(32, width: nil, base: "d", signed: false)) + lit(31, width: nil, base: "d", signed: false))..(sig(:cache_mux, width: 2) * lit(32, width: nil, base: "d", signed: false))]

  # Processes

  process :sequential_posedge_CLK,
    sensitivity: [
      { edge: "posedge", signal: sig(:CLK, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :memory_we,
      lit(0, width: 4, base: "h", signed: false),
      kind: :nonblocking
    )
    assign(
      :CPU_DONE,
      lit(0, width: 1, base: "h", signed: false),
      kind: :nonblocking
    )
    assign(
      :CPU_VALID,
      lit(0, width: 1, base: "h", signed: false),
      kind: :nonblocking
    )
    if_stmt(sig(:RESET, width: 1)) do
      assign(
        :state,
        lit(0, width: 3, base: "h", signed: false),
        kind: :nonblocking
      )
      assign(
        :update_tag_addr,
        lit(0, width: 7, base: "h", signed: false),
        kind: :nonblocking
      )
      assign(
        :update_tag_we,
        lit(1, width: 1, base: "h", signed: false),
        kind: :nonblocking
      )
      assign(
        :tags_dirty_in,
        lit(15, width: 4, base: "h", signed: false),
        kind: :nonblocking
      )
      assign(
        :MEM_REQ,
        lit(0, width: 1, base: "h", signed: false),
        kind: :nonblocking
      )
      assign(
        :CPU_REQ_hold,
        lit(0, width: 1, base: "h", signed: false),
        kind: :nonblocking
      )
      else_block do
        if_stmt(sig(:CPU_REQ, width: 1)) do
          assign(
            :CPU_REQ_hold,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
        assign(
          :LRU_we,
          (
              sig(:CPU_VALID, width: 1) &
              (
                ~sig(:LRU_we, width: 1)
              )
          ),
          kind: :nonblocking
        )
        for_loop(:i, 0..3) do
          assign(
            sig(:LRU_in, width: 8)[((sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false)) + lit(1, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false))],
            sig(:LRU_out, width: 8)[((sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false)) + lit(1, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false))],
            kind: :nonblocking
          )
          if_stmt((sig(:cache_mux, width: 2) == sig(:i, width: 2)[1..0])) do
            assign(
              :match,
              sig(:LRU_out, width: 8)[((sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false)) + lit(1, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false))],
              kind: :blocking
            )
            assign(
              sig(:LRU_in, width: 8)[((sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false)) + lit(1, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false))],
              lit(0, width: 2, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
        for_loop(:i, 0..3) do
          if_stmt((sig(:LRU_out, width: 8)[((sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false)) + lit(1, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false))] < sig(:match, width: 1))) do
            assign(
              sig(:LRU_in, width: 8)[((sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false)) + lit(1, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false))],
              (
                  lit(1, width: 2, base: "h", signed: false) +
                  sig(:LRU_out, width: 8)[((sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false)) + lit(1, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false))]
              ),
              kind: :nonblocking
            )
          end
        end
        case_stmt(sig(:state, width: 3)) do
          when_value(lit(0, width: 3, base: "h", signed: false)) do
            assign(
              :update_tag_addr,
              (
                  lit(1, width: 7, base: "h", signed: false) +
                  sig(:update_tag_addr, width: 7)
              ),
              kind: :nonblocking
            )
            for_loop(:i, 0..3) do
              assign(
                sig(:LRU_in, width: 8)[((sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false)) + lit(1, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false))],
                sig(:i, width: 2)[1..0],
                kind: :nonblocking
              )
            end
            assign(
              :LRU_addr,
              sig(:update_tag_addr, width: 7),
              kind: :nonblocking
            )
            assign(
              :LRU_we,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
            if_stmt((lit(127, width: 7, base: "h", signed: false) == sig(:update_tag_addr, width: 7))) do
              assign(
                :state,
                lit(1, width: 3, base: "h", signed: false),
                kind: :nonblocking
              )
              assign(
                :update_tag_we,
                lit(0, width: 1, base: "h", signed: false),
                kind: :nonblocking
              )
            end
          end
          when_value(lit(1, width: 3, base: "h", signed: false)) do
            if_stmt(sig(:Fifo_empty, width: 1)) do
              if_stmt((sig(:CPU_REQ, width: 1) | sig(:CPU_REQ_hold, width: 1))) do
                assign(
                  :force_fetch,
                  sig(:DISABLE, width: 1),
                  kind: :nonblocking
                )
                assign(
                  :force_next,
                  sig(:DISABLE, width: 1),
                  kind: :nonblocking
                )
                assign(
                  :state,
                  lit(3, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
                assign(
                  :read_addr,
                  sig(:CPU_ADDR, width: 32)[31..2],
                  kind: :nonblocking
                )
                assign(
                  :CPU_REQ_hold,
                  lit(0, width: 1, base: "h", signed: false),
                  kind: :nonblocking
                )
                assign(
                  :burstleft,
                  lit(3, width: 2, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
              else_block do
                assign(
                  :state,
                  lit(2, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
                assign(
                  :read_addr,
                  lit(0, width: 4, base: "d", signed: false).concat(
                    sig(:Fifo_dout, width: 62)[25..0]
                  ),
                  kind: :nonblocking
                )
                assign(
                  :memory_addr_a,
                  sig(:Fifo_dout, width: 62)[9..0],
                  kind: :nonblocking
                )
                assign(
                  :memory_datain,
                  sig(:Fifo_dout, width: 62)[57..26],
                  kind: :nonblocking
                )
                assign(
                  :memory_be,
                  sig(:Fifo_dout, width: 62)[61..58],
                  kind: :nonblocking
                )
              end
            end
          end
          when_value(lit(2, width: 3, base: "h", signed: false)) do
            assign(
              :state,
              lit(1, width: 3, base: "h", signed: false),
              kind: :nonblocking
            )
            for_loop(:i, 0..3) do
              if_stmt((~sig(:tags_dirty_out, width: 4)[sig(:i, width: 2)[1..0]])) do
                if_stmt((sig(:tags_read, width: 80)[((sig(:i, width: 2)[1..0] * lit(20, width: nil, base: "d", signed: false)) + lit(19, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(20, width: nil, base: "d", signed: false))] == sig(:read_addr, width: 30)[29..10])) do
                  assign(
                    sig(:memory_we, width: 4)[(lit(3, width: 2, base: "h", signed: false) - ((lit(0, width: 29, base: "d", signed: false).concat(sig(:i, width: 2)) >> lit(0, width: 32, base: "h", signed: false)) & ((lit(1, width: 32, base: "d") << (((lit(0, width: 32, base: "h", signed: false) + lit(1, width: nil, base: "d", signed: false))) - (lit(0, width: 32, base: "h", signed: false)) + lit(1, width: 32, base: "d"))) - lit(1, width: 32, base: "d"))))],
                    lit(1, width: 1, base: "h", signed: false),
                    kind: :nonblocking
                  )
                end
              end
            end
          end
          when_value(lit(3, width: 3, base: "h", signed: false)) do
            if_stmt(sig(:pr_reset, width: 1)) do
              assign(
                :state,
                lit(1, width: 3, base: "h", signed: false),
                kind: :nonblocking
              )
              assign(
                :CPU_DONE,
                lit(1, width: 1, base: "h", signed: false),
                kind: :nonblocking
              )
              else_block do
                assign(
                  :state,
                  lit(4, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
                assign(
                  :MEM_REQ,
                  lit(1, width: 1, base: "h", signed: false),
                  kind: :nonblocking
                )
                assign(
                  :MEM_ADDR,
                  sig(:read_addr, width: 30)[29..3].concat(
                    lit(0, width: 5, base: "h", signed: false)
                  ),
                  kind: :nonblocking
                )
                assign(
                  :fillcount,
                  lit(0, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
                assign(
                  :memory_addr_a,
                  sig(:read_addr, width: 30)[9..3].concat(
                    lit(0, width: 3, base: "h", signed: false)
                  ),
                  kind: :nonblocking
                )
                assign(
                  :tags_dirty_in,
                  sig(:tags_dirty_out, width: 4),
                  kind: :nonblocking
                )
                assign(
                  :update_tag_addr,
                  sig(:read_addr, width: 30)[9..3],
                  kind: :nonblocking
                )
                assign(
                  :LRU_addr,
                  sig(:read_addr, width: 30)[9..3],
                  kind: :nonblocking
                )
                if_stmt(sig(:force_fetch, width: 1)) do
                  assign(
                    :force_next,
                    (
                      ~sig(:force_next, width: 1)
                    ),
                    kind: :nonblocking
                  )
                end
                if_stmt(sig(:force_next, width: 1)) do
                  assign(
                    :tags_dirty_in,
                    lit(15, width: 4, base: "h", signed: false),
                    kind: :nonblocking
                  )
                  assign(
                    :update_tag_we,
                    lit(1, width: 1, base: "h", signed: false),
                    kind: :nonblocking
                  )
                  else_block do
                    for_loop(:i, 0..3) do
                      if_stmt((~sig(:tags_dirty_out, width: 4)[sig(:i, width: 2)[1..0]])) do
                        if_stmt((sig(:tags_read, width: 80)[((sig(:i, width: 2)[1..0] * lit(20, width: nil, base: "d", signed: false)) + lit(19, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(20, width: nil, base: "d", signed: false))] == sig(:read_addr, width: 30)[29..10])) do
                          assign(
                            :MEM_REQ,
                            lit(0, width: 1, base: "h", signed: false),
                            kind: :nonblocking
                          )
                          assign(
                            :cache_mux,
                            sig(:i, width: 2)[1..0],
                            kind: :nonblocking
                          )
                          assign(
                            :CPU_VALID,
                            lit(1, width: 1, base: "h", signed: false),
                            kind: :nonblocking
                          )
                          if_stmt(u(:|, sig(:burstleft, width: 2))) do
                            assign(
                              :state,
                              lit(3, width: 3, base: "h", signed: false),
                              kind: :nonblocking
                            )
                            assign(
                              :burstleft,
                              (
                                  sig(:burstleft, width: 2) -
                                  lit(1, width: 2, base: "h", signed: false)
                              ),
                              kind: :nonblocking
                            )
                            assign(
                              :read_addr,
                              (
                                  lit(1, width: 30, base: "h", signed: false) +
                                  sig(:read_addr, width: 30)
                              ),
                              kind: :nonblocking
                            )
                            else_block do
                              assign(
                                :state,
                                lit(1, width: 3, base: "h", signed: false),
                                kind: :nonblocking
                              )
                              assign(
                                :CPU_DONE,
                                lit(1, width: 1, base: "h", signed: false),
                                kind: :nonblocking
                              )
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
          when_value(lit(4, width: 3, base: "h", signed: false)) do
            for_loop(:i, 0..3) do
              if_stmt((lit(3, width: 2, base: "h", signed: false) == sig(:LRU_out, width: 8)[((sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false)) + lit(1, width: nil, base: "d", signed: false))..(sig(:i, width: 2)[1..0] * lit(2, width: nil, base: "d", signed: false))])) do
                assign(
                  :cache_mux,
                  sig(:i, width: 2)[1..0],
                  kind: :nonblocking
                )
              end
            end
            if_stmt(sig(:MEM_DONE, width: 1)) do
              assign(
                :MEM_REQ,
                lit(0, width: 1, base: "h", signed: false),
                kind: :nonblocking
              )
              assign(
                :memory_datain,
                sig(:MEM_DATA, width: 32),
                kind: :nonblocking
              )
              assign(
                sig(:memory_we, width: 4)[(lit(3, width: 2, base: "h", signed: false) - sig(:cache_mux, width: 2))],
                lit(1, width: 1, base: "h", signed: false),
                kind: :nonblocking
              )
              assign(
                :memory_be,
                lit(15, width: 4, base: "h", signed: false),
                kind: :nonblocking
              )
              assign(
                sig(:tags_dirty_in, width: 4)[sig(:cache_mux, width: 2)],
                lit(0, width: 1, base: "h", signed: false),
                kind: :nonblocking
              )
              if_stmt((lit(0, width: 3, base: "h", signed: false) < sig(:fillcount, width: 3))) do
                assign(
                  :memory_addr_a,
                  (
                      lit(1, width: 10, base: "h", signed: false) +
                      sig(:memory_addr_a, width: 10)
                  ),
                  kind: :nonblocking
                )
              end
              if_stmt((lit(7, width: 3, base: "h", signed: false) > sig(:fillcount, width: 3))) do
                assign(
                  :fillcount,
                  (
                      lit(1, width: 3, base: "h", signed: false) +
                      sig(:fillcount, width: 3)
                  ),
                  kind: :nonblocking
                )
                else_block do
                  assign(
                    :state,
                    lit(5, width: 3, base: "h", signed: false),
                    kind: :nonblocking
                  )
                  assign(
                    :update_tag_we,
                    lit(1, width: 1, base: "h", signed: false),
                    kind: :nonblocking
                  )
                end
              end
            end
          end
          when_value(lit(5, width: 3, base: "h", signed: false)) do
            assign(
              :state,
              lit(3, width: 3, base: "h", signed: false),
              kind: :nonblocking
            )
            assign(
              :update_tag_we,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
    end
  end

  # Instances

  instance :isimple_fifo, "simple_fifo_mlab__WB4_W3e",
    ports: {
      clk: :CLK,
      rst_n: lit(1, width: 1, base: "h", signed: false),
      sclr: :RESET,
      data: sig(:snoop_be, width: 4).concat(sig(:snoop_data, width: 32).concat(sig(:snoop_addr, width: 26))),
      wrreq: :snoop_we,
      q: :Fifo_dout,
      rdreq: ((lit(1, width: 3, base: "h", signed: false) == sig(:state, width: 3)) & (~sig(:Fifo_empty, width: 1))),
      empty: :Fifo_empty,
      full: :__rhdl_unconnected,
      usedw: :__rhdl_unconnected
    }
  instance :dirtyram, "altdpram__W4_WB7",
    ports: {
      inclock: :CLK,
      outclock: :CLK,
      data: :tags_dirty_in,
      rdaddress: sig(:read_addr, width: 30)[9..3],
      wraddress: :update_tag_addr,
      wren: :update_tag_we,
      q: :tags_dirty_out,
      aclr: :__rhdl_unconnected,
      byteena: :__rhdl_unconnected,
      inclocken: :__rhdl_unconnected,
      outclocken: :__rhdl_unconnected,
      rdaddressstall: :__rhdl_unconnected,
      rden: :__rhdl_unconnected,
      sclr: :__rhdl_unconnected,
      wraddressstall: :__rhdl_unconnected
    }
  instance :tagram, "altdpram__W14_WB7",
    ports: {
      inclock: :CLK,
      outclock: :CLK,
      data: sig(:read_addr, width: 30)[29..10],
      rdaddress: sig(:read_addr, width: 30)[9..3],
      wraddress: sig(:read_addr, width: 30)[9..3],
      wren: ((lit(5, width: 3, base: "h", signed: false) == sig(:state, width: 3)) & (lit(0, width: 2, base: "h", signed: false) == sig(:cache_mux, width: 2))),
      q: sig(:tags_read, width: 80)[19..0],
      aclr: :__rhdl_unconnected,
      byteena: :__rhdl_unconnected,
      inclocken: :__rhdl_unconnected,
      outclocken: :__rhdl_unconnected,
      rdaddressstall: :__rhdl_unconnected,
      rden: :__rhdl_unconnected,
      sclr: :__rhdl_unconnected,
      wraddressstall: :__rhdl_unconnected
    }
  instance :LRUram, "altdpram__W2_WB7",
    ports: {
      inclock: :CLK,
      outclock: :CLK,
      data: sig(:LRU_in, width: 8)[1..0],
      rdaddress: :LRU_addr,
      wraddress: :LRU_addr,
      wren: :LRU_we,
      q: sig(:LRU_out, width: 8)[1..0],
      aclr: :__rhdl_unconnected,
      byteena: :__rhdl_unconnected,
      inclocken: :__rhdl_unconnected,
      outclocken: :__rhdl_unconnected,
      rdaddressstall: :__rhdl_unconnected,
      rden: :__rhdl_unconnected,
      sclr: :__rhdl_unconnected,
      wraddressstall: :__rhdl_unconnected
    }
  instance :ram, "altsyncram__Az1",
    ports: {
      clock0: :CLK,
      address_a: :memory_addr_a,
      byteena_a: :memory_be,
      data_a: :memory_datain,
      wren_a: sig(:memory_we, width: 4)[3],
      address_b: sig(:read_addr, width: 30)[9..0],
      q_b: sig(:readdata_cache, width: 128)[31..0],
      aclr0: lit(0, width: 1, base: "h", signed: false),
      aclr1: lit(0, width: 1, base: "h", signed: false),
      addressstall_a: lit(0, width: 1, base: "h", signed: false),
      addressstall_b: lit(0, width: 1, base: "h", signed: false),
      byteena_b: lit(1, width: 4, base: "h", signed: false),
      clock1: lit(1, width: 1, base: "h", signed: false),
      clocken0: lit(1, width: 1, base: "h", signed: false),
      clocken1: lit(1, width: 1, base: "h", signed: false),
      clocken2: lit(1, width: 1, base: "h", signed: false),
      clocken3: lit(1, width: 1, base: "h", signed: false),
      data_b: lit(0, width: 32, base: "h", signed: false),
      eccstatus: :__rhdl_unconnected,
      q_a: :__rhdl_unconnected,
      rden_a: lit(1, width: 1, base: "h", signed: false),
      rden_b: lit(1, width: 1, base: "h", signed: false),
      wren_b: lit(0, width: 1, base: "h", signed: false)
    }
  instance :tagram__1, "altdpram__W14_WB7",
    ports: {
      inclock: :CLK,
      outclock: :CLK,
      data: sig(:read_addr, width: 30)[29..10],
      rdaddress: sig(:read_addr, width: 30)[9..3],
      wraddress: sig(:read_addr, width: 30)[9..3],
      wren: ((lit(5, width: 3, base: "h", signed: false) == sig(:state, width: 3)) & (lit(1, width: 2, base: "h", signed: false) == sig(:cache_mux, width: 2))),
      q: sig(:tags_read, width: 80)[39..20],
      aclr: :__rhdl_unconnected,
      byteena: :__rhdl_unconnected,
      inclocken: :__rhdl_unconnected,
      outclocken: :__rhdl_unconnected,
      rdaddressstall: :__rhdl_unconnected,
      rden: :__rhdl_unconnected,
      sclr: :__rhdl_unconnected,
      wraddressstall: :__rhdl_unconnected
    }
  instance :LRUram__1, "altdpram__W2_WB7",
    ports: {
      inclock: :CLK,
      outclock: :CLK,
      data: sig(:LRU_in, width: 8)[3..2],
      rdaddress: :LRU_addr,
      wraddress: :LRU_addr,
      wren: :LRU_we,
      q: sig(:LRU_out, width: 8)[3..2],
      aclr: :__rhdl_unconnected,
      byteena: :__rhdl_unconnected,
      inclocken: :__rhdl_unconnected,
      outclocken: :__rhdl_unconnected,
      rdaddressstall: :__rhdl_unconnected,
      rden: :__rhdl_unconnected,
      sclr: :__rhdl_unconnected,
      wraddressstall: :__rhdl_unconnected
    }
  instance :ram__1, "altsyncram__Az1",
    ports: {
      clock0: :CLK,
      address_a: :memory_addr_a,
      byteena_a: :memory_be,
      data_a: :memory_datain,
      wren_a: sig(:memory_we, width: 4)[2],
      address_b: sig(:read_addr, width: 30)[9..0],
      q_b: sig(:readdata_cache, width: 128)[63..32],
      aclr0: lit(0, width: 1, base: "h", signed: false),
      aclr1: lit(0, width: 1, base: "h", signed: false),
      addressstall_a: lit(0, width: 1, base: "h", signed: false),
      addressstall_b: lit(0, width: 1, base: "h", signed: false),
      byteena_b: lit(1, width: 4, base: "h", signed: false),
      clock1: lit(1, width: 1, base: "h", signed: false),
      clocken0: lit(1, width: 1, base: "h", signed: false),
      clocken1: lit(1, width: 1, base: "h", signed: false),
      clocken2: lit(1, width: 1, base: "h", signed: false),
      clocken3: lit(1, width: 1, base: "h", signed: false),
      data_b: lit(0, width: 32, base: "h", signed: false),
      eccstatus: :__rhdl_unconnected,
      q_a: :__rhdl_unconnected,
      rden_a: lit(1, width: 1, base: "h", signed: false),
      rden_b: lit(1, width: 1, base: "h", signed: false),
      wren_b: lit(0, width: 1, base: "h", signed: false)
    }
  instance :tagram__2, "altdpram__W14_WB7",
    ports: {
      inclock: :CLK,
      outclock: :CLK,
      data: sig(:read_addr, width: 30)[29..10],
      rdaddress: sig(:read_addr, width: 30)[9..3],
      wraddress: sig(:read_addr, width: 30)[9..3],
      wren: ((lit(5, width: 3, base: "h", signed: false) == sig(:state, width: 3)) & (lit(2, width: 2, base: "h", signed: false) == sig(:cache_mux, width: 2))),
      q: sig(:tags_read, width: 80)[59..40],
      aclr: :__rhdl_unconnected,
      byteena: :__rhdl_unconnected,
      inclocken: :__rhdl_unconnected,
      outclocken: :__rhdl_unconnected,
      rdaddressstall: :__rhdl_unconnected,
      rden: :__rhdl_unconnected,
      sclr: :__rhdl_unconnected,
      wraddressstall: :__rhdl_unconnected
    }
  instance :LRUram__2, "altdpram__W2_WB7",
    ports: {
      inclock: :CLK,
      outclock: :CLK,
      data: sig(:LRU_in, width: 8)[5..4],
      rdaddress: :LRU_addr,
      wraddress: :LRU_addr,
      wren: :LRU_we,
      q: sig(:LRU_out, width: 8)[5..4],
      aclr: :__rhdl_unconnected,
      byteena: :__rhdl_unconnected,
      inclocken: :__rhdl_unconnected,
      outclocken: :__rhdl_unconnected,
      rdaddressstall: :__rhdl_unconnected,
      rden: :__rhdl_unconnected,
      sclr: :__rhdl_unconnected,
      wraddressstall: :__rhdl_unconnected
    }
  instance :ram__2, "altsyncram__Az1",
    ports: {
      clock0: :CLK,
      address_a: :memory_addr_a,
      byteena_a: :memory_be,
      data_a: :memory_datain,
      wren_a: sig(:memory_we, width: 4)[1],
      address_b: sig(:read_addr, width: 30)[9..0],
      q_b: sig(:readdata_cache, width: 128)[95..64],
      aclr0: lit(0, width: 1, base: "h", signed: false),
      aclr1: lit(0, width: 1, base: "h", signed: false),
      addressstall_a: lit(0, width: 1, base: "h", signed: false),
      addressstall_b: lit(0, width: 1, base: "h", signed: false),
      byteena_b: lit(1, width: 4, base: "h", signed: false),
      clock1: lit(1, width: 1, base: "h", signed: false),
      clocken0: lit(1, width: 1, base: "h", signed: false),
      clocken1: lit(1, width: 1, base: "h", signed: false),
      clocken2: lit(1, width: 1, base: "h", signed: false),
      clocken3: lit(1, width: 1, base: "h", signed: false),
      data_b: lit(0, width: 32, base: "h", signed: false),
      eccstatus: :__rhdl_unconnected,
      q_a: :__rhdl_unconnected,
      rden_a: lit(1, width: 1, base: "h", signed: false),
      rden_b: lit(1, width: 1, base: "h", signed: false),
      wren_b: lit(0, width: 1, base: "h", signed: false)
    }
  instance :tagram__3, "altdpram__W14_WB7",
    ports: {
      inclock: :CLK,
      outclock: :CLK,
      data: sig(:read_addr, width: 30)[29..10],
      rdaddress: sig(:read_addr, width: 30)[9..3],
      wraddress: sig(:read_addr, width: 30)[9..3],
      wren: ((lit(5, width: 3, base: "h", signed: false) == sig(:state, width: 3)) & (lit(3, width: 2, base: "h", signed: false) == sig(:cache_mux, width: 2))),
      q: sig(:tags_read, width: 80)[79..60],
      aclr: :__rhdl_unconnected,
      byteena: :__rhdl_unconnected,
      inclocken: :__rhdl_unconnected,
      outclocken: :__rhdl_unconnected,
      rdaddressstall: :__rhdl_unconnected,
      rden: :__rhdl_unconnected,
      sclr: :__rhdl_unconnected,
      wraddressstall: :__rhdl_unconnected
    }
  instance :LRUram__3, "altdpram__W2_WB7",
    ports: {
      inclock: :CLK,
      outclock: :CLK,
      data: sig(:LRU_in, width: 8)[7..6],
      rdaddress: :LRU_addr,
      wraddress: :LRU_addr,
      wren: :LRU_we,
      q: sig(:LRU_out, width: 8)[7..6],
      aclr: :__rhdl_unconnected,
      byteena: :__rhdl_unconnected,
      inclocken: :__rhdl_unconnected,
      outclocken: :__rhdl_unconnected,
      rdaddressstall: :__rhdl_unconnected,
      rden: :__rhdl_unconnected,
      sclr: :__rhdl_unconnected,
      wraddressstall: :__rhdl_unconnected
    }
  instance :ram__3, "altsyncram__Az1",
    ports: {
      clock0: :CLK,
      address_a: :memory_addr_a,
      byteena_a: :memory_be,
      data_a: :memory_datain,
      wren_a: sig(:memory_we, width: 4)[0],
      address_b: sig(:read_addr, width: 30)[9..0],
      q_b: sig(:readdata_cache, width: 128)[127..96],
      aclr0: lit(0, width: 1, base: "h", signed: false),
      aclr1: lit(0, width: 1, base: "h", signed: false),
      addressstall_a: lit(0, width: 1, base: "h", signed: false),
      addressstall_b: lit(0, width: 1, base: "h", signed: false),
      byteena_b: lit(1, width: 4, base: "h", signed: false),
      clock1: lit(1, width: 1, base: "h", signed: false),
      clocken0: lit(1, width: 1, base: "h", signed: false),
      clocken1: lit(1, width: 1, base: "h", signed: false),
      clocken2: lit(1, width: 1, base: "h", signed: false),
      clocken3: lit(1, width: 1, base: "h", signed: false),
      data_b: lit(0, width: 32, base: "h", signed: false),
      eccstatus: :__rhdl_unconnected,
      q_a: :__rhdl_unconnected,
      rden_a: lit(1, width: 1, base: "h", signed: false),
      rden_b: lit(1, width: 1, base: "h", signed: false),
      wren_b: lit(0, width: 1, base: "h", signed: false)
    }

end
