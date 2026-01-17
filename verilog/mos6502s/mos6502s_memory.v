// MOS 6502 Memory - Synthesizable Verilog
// 64KB total: 32KB RAM (0x0000-0x7FFF), 32KB ROM (0x8000-0xFFFF)
// Generated from RHDL DSL

module mos6502s_memory (
  input         clk,
  input  [15:0] addr,
  input  [7:0]  data_in,
  input         rw,      // 1 = read, 0 = write
  input         cs,      // Chip select (active high)
  output reg [7:0] data_out
);

  // Memory arrays - synthesize as BRAM
  reg [7:0] ram [0:32767];  // 32KB RAM
  reg [7:0] rom [0:32767];  // 32KB ROM

  // Address decoding
  wire is_rom = addr[15];
  wire [14:0] ram_addr = addr[14:0];
  wire [14:0] rom_addr = addr[14:0];

  // Synchronous write to RAM
  always @(posedge clk) begin
    if (cs && !rw && !is_rom) begin
      ram[ram_addr] <= data_in;
    end
  end

  // Asynchronous read
  always @* begin
    if (cs) begin
      if (is_rom) begin
        data_out = rom[rom_addr];
      end else begin
        data_out = ram[ram_addr];
      end
    end else begin
      data_out = 8'h00;
    end
  end

  // ROM initialization would be done via $readmemh in testbench
  // or via FPGA-specific initialization

endmodule
