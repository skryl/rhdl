# RV32I Register File - 32 x 32-bit registers
# Register x0 is hardwired to zero
# Two read ports, one write port
# Uses sequential DSL for synthesizable Verilog

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module RISCV
  class RegisterFile < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    port_input :clk
    port_input :rst

    # Read ports (asynchronous)
    port_input :rs1_addr, width: 5    # Source register 1 address
    port_input :rs2_addr, width: 5    # Source register 2 address
    port_output :rs1_data, width: 32  # Source register 1 data
    port_output :rs2_data, width: 32  # Source register 2 data

    # Write port (synchronous)
    port_input :rd_addr, width: 5     # Destination register address
    port_input :rd_data, width: 32    # Write data
    port_input :rd_we                 # Write enable

    # Debug outputs for testing
    port_output :debug_x1, width: 32
    port_output :debug_x2, width: 32
    port_output :debug_x10, width: 32
    port_output :debug_x11, width: 32

    def initialize(name = nil)
      super(name)
      # Internal register storage
      @regs = Array.new(32, 0)
      @regs[0] = 0  # x0 always 0
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      @prev_clk ||= 0

      # Handle reset
      if rst == 1
        @regs = Array.new(32, 0)
        update_outputs
        @prev_clk = clk
        return
      end

      # Rising edge detection for writes
      if @prev_clk == 0 && clk == 1
        rd_we = in_val(:rd_we)
        rd_addr = in_val(:rd_addr)
        rd_data = in_val(:rd_data)

        # Write to register if enabled and not x0
        if rd_we == 1 && rd_addr != 0
          @regs[rd_addr] = rd_data & 0xFFFFFFFF
        end
      end
      @prev_clk = clk

      # Asynchronous reads
      update_outputs
    end

    def update_outputs
      rs1_addr = in_val(:rs1_addr)
      rs2_addr = in_val(:rs2_addr)
      rd_addr = in_val(:rd_addr)
      rd_data = in_val(:rd_data)
      rd_we = in_val(:rd_we)

      # Internal forwarding: if reading the register being written, return write data
      # This handles the write-read hazard when WB and ID happen in the same cycle
      if rd_we == 1 && rd_addr != 0
        rs1_val = (rs1_addr == rd_addr) ? rd_data : (rs1_addr == 0 ? 0 : @regs[rs1_addr])
        rs2_val = (rs2_addr == rd_addr) ? rd_data : (rs2_addr == 0 ? 0 : @regs[rs2_addr])
      else
        rs1_val = rs1_addr == 0 ? 0 : @regs[rs1_addr]
        rs2_val = rs2_addr == 0 ? 0 : @regs[rs2_addr]
      end

      out_set(:rs1_data, rs1_val)
      out_set(:rs2_data, rs2_val)

      # Debug outputs
      out_set(:debug_x1, @regs[1])
      out_set(:debug_x2, @regs[2])
      out_set(:debug_x10, @regs[10])
      out_set(:debug_x11, @regs[11])
    end

    # Direct register access for testing
    def read_reg(index)
      index == 0 ? 0 : @regs[index]
    end

    def write_reg(index, value)
      @regs[index] = value & 0xFFFFFFFF unless index == 0
    end

    def self.verilog_module_name
      'riscv_register_file'
    end

    # Generate synthesizable Verilog with memory array
    def self.to_ir(top_name: nil)
      # For Verilog export, we generate an array-based register file
      name = top_name || verilog_module_name

      ports = _ports.map do |p|
        RHDL::Export::IR::Port.new(name: p.name, direction: p.direction, width: p.width)
      end

      # Register array declaration using Memory IR node
      memories = [
        RHDL::Export::IR::Memory.new(name: :regs, width: 32, depth: 32)
      ]

      # Asynchronous read assigns
      # rs1_data = (rs1_addr == 0) ? 0 : regs[rs1_addr]
      rs1_mux = RHDL::Export::IR::Mux.new(
        condition: RHDL::Export::IR::BinaryOp.new(
          op: :==,
          left: RHDL::Export::IR::Signal.new(name: :rs1_addr, width: 5),
          right: RHDL::Export::IR::Literal.new(value: 0, width: 5),
          width: 1
        ),
        when_true: RHDL::Export::IR::Literal.new(value: 0, width: 32),
        when_false: RHDL::Export::IR::MemoryRead.new(
          memory: :regs,
          addr: RHDL::Export::IR::Signal.new(name: :rs1_addr, width: 5),
          width: 32
        ),
        width: 32
      )

      rs2_mux = RHDL::Export::IR::Mux.new(
        condition: RHDL::Export::IR::BinaryOp.new(
          op: :==,
          left: RHDL::Export::IR::Signal.new(name: :rs2_addr, width: 5),
          right: RHDL::Export::IR::Literal.new(value: 0, width: 5),
          width: 1
        ),
        when_true: RHDL::Export::IR::Literal.new(value: 0, width: 32),
        when_false: RHDL::Export::IR::MemoryRead.new(
          memory: :regs,
          addr: RHDL::Export::IR::Signal.new(name: :rs2_addr, width: 5),
          width: 32
        ),
        width: 32
      )

      assigns = [
        RHDL::Export::IR::Assign.new(target: :rs1_data, expr: rs1_mux),
        RHDL::Export::IR::Assign.new(target: :rs2_data, expr: rs2_mux),
        RHDL::Export::IR::Assign.new(target: :debug_x1, expr: RHDL::Export::IR::MemoryRead.new(
          memory: :regs, addr: RHDL::Export::IR::Literal.new(value: 1, width: 5), width: 32)),
        RHDL::Export::IR::Assign.new(target: :debug_x2, expr: RHDL::Export::IR::MemoryRead.new(
          memory: :regs, addr: RHDL::Export::IR::Literal.new(value: 2, width: 5), width: 32)),
        RHDL::Export::IR::Assign.new(target: :debug_x10, expr: RHDL::Export::IR::MemoryRead.new(
          memory: :regs, addr: RHDL::Export::IR::Literal.new(value: 10, width: 5), width: 32)),
        RHDL::Export::IR::Assign.new(target: :debug_x11, expr: RHDL::Export::IR::MemoryRead.new(
          memory: :regs, addr: RHDL::Export::IR::Literal.new(value: 11, width: 5), width: 32))
      ]

      # Synchronous write process
      # always @(posedge clk) begin
      #   if (rst) begin
      #     // Reset all registers - optional
      #   end else if (rd_we && rd_addr != 0) begin
      #     regs[rd_addr] <= rd_data;
      #   end
      # end
      write_cond = RHDL::Export::IR::BinaryOp.new(
        op: :&,
        left: RHDL::Export::IR::Signal.new(name: :rd_we, width: 1),
        right: RHDL::Export::IR::BinaryOp.new(
          op: :!=,
          left: RHDL::Export::IR::Signal.new(name: :rd_addr, width: 5),
          right: RHDL::Export::IR::Literal.new(value: 0, width: 5),
          width: 1
        ),
        width: 1
      )

      write_stmt = RHDL::Export::IR::If.new(
        condition: RHDL::Export::IR::Signal.new(name: :rst, width: 1),
        then_statements: [],  # No-op on reset (registers can be reset via specific code)
        else_statements: [
          RHDL::Export::IR::If.new(
            condition: write_cond,
            then_statements: [
              RHDL::Export::IR::MemoryWrite.new(
                memory: :regs,
                addr: RHDL::Export::IR::Signal.new(name: :rd_addr, width: 5),
                data: RHDL::Export::IR::Signal.new(name: :rd_data, width: 32)
              )
            ],
            else_statements: []
          )
        ]
      )

      processes = [
        RHDL::Export::IR::Process.new(
          name: :write_process,
          statements: [write_stmt],
          clocked: true,
          clock: :clk
        )
      ]

      RHDL::Export::IR::ModuleDef.new(
        name: name,
        ports: ports,
        nets: [],
        regs: [],
        assigns: assigns,
        processes: processes,
        instances: [],
        reg_ports: [],
        memories: memories
      )
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
    end
  end
end
