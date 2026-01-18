# frozen_string_literal: true

# HDL Register File Component
# Multiple registers with read/write ports
# Synthesizable via MemoryDSL

require_relative '../../dsl/memory_dsl'

module RHDL
  module HDL
    # Register File (multiple registers with read/write ports)
    # Sequential write, combinational read - typical FPGA register file
    class RegisterFile < SimComponent
      include RHDL::DSL::MemoryDSL

      input :clk
      input :we
      input :waddr, width: 3
      input :raddr1, width: 3
      input :raddr2, width: 3
      input :wdata, width: 8
      output :rdata1, width: 8
      output :rdata2, width: 8

      # Define register array (8 x 8-bit registers)
      memory :registers, depth: 8, width: 8

      # Synchronous write
      sync_write :registers, clock: :clk, enable: :we, addr: :waddr, data: :wdata

      # Asynchronous reads from both ports
      async_read :rdata1, from: :registers, addr: :raddr1
      async_read :rdata2, from: :registers, addr: :raddr2

      # Direct register access for debugging
      def read_reg(addr)
        mem_read(:registers, addr & 0x7)
      end

      def write_reg(addr, data)
        mem_write(:registers, addr & 0x7, data, 8)
      end

      # Override to_ir to generate proper memory IR
      def self.to_ir(top_name: nil)
        name = top_name || 'register_file'

        # Ports
        ports = _ports.map do |p|
          RHDL::Export::IR::Port.new(name: p.name, direction: p.direction, width: p.width)
        end

        # Register array
        mem_def = _memories[:registers]
        memories = [
          RHDL::Export::IR::Memory.new(
            name: 'registers',
            depth: mem_def.depth,
            width: mem_def.width,
            read_ports: [],
            write_ports: []
          )
        ]

        # Async read assigns
        assigns = [
          RHDL::Export::IR::Assign.new(
            target: :rdata1,
            expr: RHDL::Export::IR::MemoryRead.new(
              memory: :registers,
              addr: RHDL::Export::IR::Signal.new(name: :raddr1, width: 3),
              width: 8
            )
          ),
          RHDL::Export::IR::Assign.new(
            target: :rdata2,
            expr: RHDL::Export::IR::MemoryRead.new(
              memory: :registers,
              addr: RHDL::Export::IR::Signal.new(name: :raddr2, width: 3),
              width: 8
            )
          )
        ]

        # Write port
        write_port = RHDL::Export::IR::MemoryWritePort.new(
          memory: :registers,
          clock: :clk,
          addr: RHDL::Export::IR::Signal.new(name: :waddr, width: 3),
          data: RHDL::Export::IR::Signal.new(name: :wdata, width: 8),
          enable: RHDL::Export::IR::Signal.new(name: :we, width: 1)
        )

        RHDL::Export::IR::ModuleDef.new(
          name: name,
          ports: ports,
          nets: [],
          regs: [],
          assigns: assigns,
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
