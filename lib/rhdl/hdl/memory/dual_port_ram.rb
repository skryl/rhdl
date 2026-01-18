# frozen_string_literal: true

# HDL Dual Port RAM Component
# True Dual-Port RAM with two independent read/write ports
# Synthesizable via MemoryDSL

require_relative '../../dsl/memory_dsl'

module RHDL
  module HDL
    # True Dual-Port RAM with two independent read/write ports
    # Sequential write on rising clock edge, combinational read
    class DualPortRAM < SimComponent
      include RHDL::DSL::MemoryDSL

      input :clk
      input :we_a
      input :we_b
      input :addr_a, width: 8
      input :addr_b, width: 8
      input :din_a, width: 8
      input :din_b, width: 8
      output :dout_a, width: 8
      output :dout_b, width: 8

      # Define memory array (256 x 8-bit)
      memory :mem, depth: 256, width: 8

      # Synchronous writes for both ports
      sync_write :mem, clock: :clk, enable: :we_a, addr: :addr_a, data: :din_a
      sync_write :mem, clock: :clk, enable: :we_b, addr: :addr_b, data: :din_b

      # Asynchronous reads for both ports
      async_read :dout_a, from: :mem, addr: :addr_a
      async_read :dout_b, from: :mem, addr: :addr_b

      # Direct memory access for initialization/debugging
      def read_mem(addr)
        mem_read(:mem, addr & 0xFF)
      end

      def write_mem(addr, data)
        mem_write(:mem, addr & 0xFF, data, 8)
      end

      # Override to_ir to generate proper memory IR
      def self.to_ir(top_name: nil)
        name = top_name || 'dual_port_ram'

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

        # Async read assigns
        assigns = [
          RHDL::Export::IR::Assign.new(
            target: :dout_a,
            expr: RHDL::Export::IR::MemoryRead.new(
              memory: :mem,
              addr: RHDL::Export::IR::Signal.new(name: :addr_a, width: 8),
              width: 8
            )
          ),
          RHDL::Export::IR::Assign.new(
            target: :dout_b,
            expr: RHDL::Export::IR::MemoryRead.new(
              memory: :mem,
              addr: RHDL::Export::IR::Signal.new(name: :addr_b, width: 8),
              width: 8
            )
          )
        ]

        # Write ports
        write_ports = [
          RHDL::Export::IR::MemoryWritePort.new(
            memory: :mem,
            clock: :clk,
            addr: RHDL::Export::IR::Signal.new(name: :addr_a, width: 8),
            data: RHDL::Export::IR::Signal.new(name: :din_a, width: 8),
            enable: RHDL::Export::IR::Signal.new(name: :we_a, width: 1)
          ),
          RHDL::Export::IR::MemoryWritePort.new(
            memory: :mem,
            clock: :clk,
            addr: RHDL::Export::IR::Signal.new(name: :addr_b, width: 8),
            data: RHDL::Export::IR::Signal.new(name: :din_b, width: 8),
            enable: RHDL::Export::IR::Signal.new(name: :we_b, width: 1)
          )
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
          write_ports: write_ports
        )
      end

      def self.to_verilog
        RHDL::Export::Verilog.generate(to_ir)
      end
    end
  end
end
