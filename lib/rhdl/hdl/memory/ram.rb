# frozen_string_literal: true

# HDL RAM Component
# Synchronous RAM with single port
# Synthesizable via MemoryDSL

require_relative '../../dsl/memory_dsl'

module RHDL
  module HDL
    # Synchronous RAM with single port
    # Sequential write on rising clock edge, combinational read
    class RAM < SimComponent
      include RHDL::DSL::MemoryDSL

      port_input :clk
      port_input :we       # Write enable
      port_input :addr, width: 8
      port_input :din, width: 8
      port_output :dout, width: 8

      # Define memory array (256 x 8-bit)
      memory :mem, depth: 256, width: 8

      # Synchronous write
      sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din

      # Asynchronous read
      async_read :dout, from: :mem, addr: :addr

      # Direct memory access for initialization/debugging
      def read_mem(addr)
        mem_read(:mem, addr & 0xFF)
      end

      def write_mem(addr, data)
        mem_write(:mem, addr & 0xFF, data, 8)
      end

      def load_program(program, start_addr = 0)
        program.each_with_index do |byte, i|
          write_mem(start_addr + i, byte)
        end
      end

      # Override to_ir to generate proper memory IR
      def self.to_ir(top_name: nil)
        name = top_name || 'ram'

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

        # Async read assign: dout = mem[addr]
        read_assign = RHDL::Export::IR::Assign.new(
          target: :dout,
          expr: RHDL::Export::IR::MemoryRead.new(
            memory: :mem,
            addr: RHDL::Export::IR::Signal.new(name: :addr, width: 8),
            width: 8
          )
        )

        # Write port
        write_port = RHDL::Export::IR::MemoryWritePort.new(
          memory: :mem,
          clock: :clk,
          addr: RHDL::Export::IR::Signal.new(name: :addr, width: 8),
          data: RHDL::Export::IR::Signal.new(name: :din, width: 8),
          enable: RHDL::Export::IR::Signal.new(name: :we, width: 1)
        )

        RHDL::Export::IR::ModuleDef.new(
          name: name,
          ports: ports,
          nets: [],
          regs: [],
          assigns: [read_assign],
          processes: [],
          instances: [],
          memories: memories,
          write_ports: [write_port]
        )
      end

      def self.to_verilog
        RHDL::Export::Verilog.generate(to_ir)
      end
    end
  end
end
