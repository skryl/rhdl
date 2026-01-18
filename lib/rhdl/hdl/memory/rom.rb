# frozen_string_literal: true

# HDL ROM Component
# Read-Only Memory with enable
# Synthesizable via MemoryDSL

require_relative '../../dsl/memory_dsl'

module RHDL
  module HDL
    # ROM (Read-Only Memory)
    # Combinational read with enable - can be synthesized as LUT or block ROM
    class ROM < SimComponent
      include RHDL::DSL::MemoryDSL

      input :addr, width: 8
      input :en
      output :dout, width: 8

      # Define memory array (256 x 8-bit)
      memory :mem, depth: 256, width: 8

      # Asynchronous read with enable
      async_read :dout, from: :mem, addr: :addr, enable: :en

      def initialize(name = nil, contents: [])
        super(name)
        initialize_memories
        # Load initial contents
        contents.each_with_index { |v, i| mem_write(:mem, i, v, 8) if i < 256 }
      end

      # Direct memory access for initialization
      def read_mem(addr)
        mem_read(:mem, addr & 0xFF)
      end

      def write_mem(addr, data)
        mem_write(:mem, addr & 0xFF, data, 8)
      end

      def load_contents(contents, start_addr = 0)
        contents.each_with_index do |byte, i|
          write_mem(start_addr + i, byte)
        end
      end

      # Override to_ir to generate proper memory IR
      def self.to_ir(top_name: nil)
        name = top_name || 'rom'

        # Ports
        ports = _ports.map do |p|
          RHDL::Export::IR::Port.new(name: p.name, direction: p.direction, width: p.width)
        end

        # Memory array
        mem_def = _memories[:mem]
        memories = [
          RHDL::Export::IR::Memory.new(
            name: 'mem',
            depth: mem_def.depth,
            width: mem_def.width,
            read_ports: [],
            write_ports: []
          )
        ]

        # Async read with enable: dout = en ? mem[addr] : 0
        read_expr = RHDL::Export::IR::Mux.new(
          condition: RHDL::Export::IR::Signal.new(name: :en, width: 1),
          when_true: RHDL::Export::IR::MemoryRead.new(
            memory: :mem,
            addr: RHDL::Export::IR::Signal.new(name: :addr, width: 8),
            width: 8
          ),
          when_false: RHDL::Export::IR::Literal.new(value: 0, width: 8),
          width: 8
        )

        assigns = [
          RHDL::Export::IR::Assign.new(target: :dout, expr: read_expr)
        ]

        RHDL::Export::IR::ModuleDef.new(
          name: name,
          ports: ports,
          nets: [],
          regs: [],
          assigns: assigns,
          processes: [],
          instances: [],
          memories: memories,
          write_ports: []
        )
      end

      def self.to_verilog
        RHDL::Export::Verilog.generate(to_ir)
      end
    end
  end
end
