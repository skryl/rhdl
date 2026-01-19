# MOS 6502 CPU Verilog Program Execution Tests
# Tests that verify the synthesizable 6502 CPU executes programs correctly in Verilog simulation
# Compares Ruby behavioral simulation with Icarus Verilog simulation

require_relative 'spec_helper'
require_relative '../../../examples/mos6502/hdl/harness'
require_relative '../../../examples/mos6502/utilities/assembler'
require 'fileutils'

RSpec.describe 'MOS6502 Verilog Program Execution', if: HdlToolchain.iverilog_available? do
  # Run a program in both Ruby and Verilog, compare results
  def run_program_comparison(program:, initial_memory: {}, check_addrs: [], max_cycles: 500,
                             expected_a: nil, expected_x: nil, expected_y: nil)
    # Run in Ruby simulation first
    ruby_results = run_ruby_simulation(program: program, initial_memory: initial_memory,
                                       check_addrs: check_addrs, max_cycles: max_cycles)

    # Run in Verilog simulation
    verilog_results = run_verilog_simulation(
      program: program,
      initial_memory: initial_memory,
      check_addrs: check_addrs,
      max_cycles: max_cycles
    )

    expect(verilog_results[:success]).to be(true), "Verilog simulation failed: #{verilog_results[:error]}"

    # Compare A register
    expected_acc = expected_a || ruby_results[:a]
    expect(verilog_results[:a]).to eq(expected_acc),
      "A mismatch: Ruby=#{ruby_results[:a]}, Verilog=#{verilog_results[:a]}, expected=#{expected_acc}"

    # Compare X register if expected
    if expected_x
      expect(verilog_results[:x]).to eq(expected_x),
        "X mismatch: Ruby=#{ruby_results[:x]}, Verilog=#{verilog_results[:x]}, expected=#{expected_x}"
    end

    # Compare Y register if expected
    if expected_y
      expect(verilog_results[:y]).to eq(expected_y),
        "Y mismatch: Ruby=#{ruby_results[:y]}, Verilog=#{verilog_results[:y]}, expected=#{expected_y}"
    end

    # Compare memory locations
    check_addrs.each do |addr|
      expect(verilog_results[:memory][addr]).to eq(ruby_results[:memory][addr]),
        "Memory[0x#{addr.to_s(16)}] mismatch: Ruby=#{ruby_results[:memory][addr]}, Verilog=#{verilog_results[:memory][addr]}"
    end

    { ruby: ruby_results, verilog: verilog_results }
  end

  def run_ruby_simulation(program:, initial_memory:, check_addrs:, max_cycles:)
    harness = MOS6502::Harness.new

    # Load initial memory
    initial_memory.each do |addr, val|
      harness.write_mem(addr, val)
    end

    # Assemble and load program
    harness.assemble_and_load(program, 0x8000)
    harness.reset

    # Run until halted or max cycles
    cycles = 0
    while cycles < max_cycles && !harness.halted?
      harness.step
      cycles += 1
    end

    # Collect memory values - include both initial_memory and check_addrs
    memory = {}
    (initial_memory.keys + check_addrs).uniq.each do |addr|
      memory[addr] = harness.read_mem(addr)
    end

    {
      a: harness.a,
      x: harness.x,
      y: harness.y,
      sp: harness.sp,
      pc: harness.pc,
      p: harness.p,
      halted: harness.halted?,
      cycles: harness.clock_count,
      memory: memory
    }
  end

  def run_verilog_simulation(program:, initial_memory:, check_addrs:, max_cycles:)
    base_dir = File.join('tmp', 'iverilog', "mos6502_#{Time.now.to_i}_#{rand(10000)}")
    FileUtils.mkdir_p(base_dir)

    begin
      # Assemble program to bytes
      asm = MOS6502::Assembler.new
      program_bytes = asm.assemble(program, 0x8000)

      # Write all Verilog modules
      write_verilog_modules(base_dir)

      # Write testbench
      write_testbench(base_dir, program: program_bytes, initial_memory: initial_memory,
                      check_addrs: check_addrs, max_cycles: max_cycles)

      # Compile and run
      result = compile_and_run_verilog(base_dir)
      return result unless result[:success]

      # Parse output
      parse_verilog_output(result[:stdout], check_addrs)
    ensure
      FileUtils.rm_rf(base_dir) if ENV['KEEP_VERILOG_FILES'].nil?
    end
  end

  def write_verilog_modules(base_dir)
    # All 6502 CPU components - use class names for filenames to match module names
    components = {
      'mos6502_cpu.v' => MOS6502::CPU.to_verilog,
      'mos6502_registers.v' => MOS6502::Registers.to_verilog,
      'mos6502_status_register.v' => MOS6502::StatusRegister.to_verilog,
      'mos6502_program_counter.v' => MOS6502::ProgramCounter.to_verilog,
      'mos6502_stack_pointer.v' => MOS6502::StackPointer.to_verilog,
      'mos6502_instruction_register.v' => MOS6502::InstructionRegister.to_verilog,
      'mos6502_address_latch.v' => MOS6502::AddressLatch.to_verilog,
      'mos6502_data_latch.v' => MOS6502::DataLatch.to_verilog,
      'mos6502_control_unit.v' => MOS6502::ControlUnit.to_verilog,
      'mos6502_alu.v' => MOS6502::ALU.to_verilog,
      'mos6502_instruction_decoder.v' => MOS6502::InstructionDecoder.to_verilog,
      'mos6502_address_generator.v' => MOS6502::AddressGenerator.to_verilog,
      'mos6502_indirect_address_calc.v' => MOS6502::IndirectAddressCalc.to_verilog
    }

    components.each do |filename, content|
      File.write(File.join(base_dir, filename), content)
    end
  end

  def write_testbench(base_dir, program:, initial_memory:, check_addrs:, max_cycles:)
    # Build ROM initialization (program starts at 0x8000 in address space)
    rom_init = program.each_with_index.map do |byte, i|
      "    rom[#{i}] = 8'h#{byte.to_s(16).rjust(2, '0')};"
    end.join("\n")

    # Build RAM initialization
    ram_init = initial_memory.select { |addr, _| addr < 0x8000 }.map do |addr, val|
      "    ram[#{addr}] = 8'h#{val.to_s(16).rjust(2, '0')};"
    end.join("\n")

    # Reset vector setup (pointing to 0x8000)
    reset_vector_lo = 0x00  # Low byte of 0x8000
    reset_vector_hi = 0x80  # High byte of 0x8000

    # Memory check output code
    mem_checks = check_addrs.map do |addr|
      if addr < 0x8000
        "    $display(\"MEM[0x#{addr.to_s(16).upcase}]=%d\", ram[#{addr}]);"
      else
        "    $display(\"MEM[0x#{addr.to_s(16).upcase}]=%d\", rom[#{addr - 0x8000}]);"
      end
    end.join("\n")

    testbench = <<~VERILOG
      `timescale 1ns/1ps

      module tb;
        reg clk;
        reg rst;
        reg rdy;
        reg irq;
        reg nmi;
        reg [7:0] data_in;
        wire [7:0] data_out;
        wire [15:0] addr;
        wire rw;
        wire sync;
        wire [7:0] reg_a, reg_x, reg_y, reg_sp, reg_p;
        wire [15:0] reg_pc;
        wire halted;
        wire [31:0] cycle_count;

        // Memory arrays
        reg [7:0] ram [0:32767];  // 32KB RAM (0x0000-0x7FFF)
        reg [7:0] rom [0:32767];  // 32KB ROM (0x8000-0xFFFF)

        // External register load signals (directly connected to CPU)
        reg [15:0] ext_pc_load_data;
        reg ext_pc_load_en;
        reg [7:0] ext_a_load_data;
        reg ext_a_load_en;
        reg [7:0] ext_x_load_data;
        reg ext_x_load_en;
        reg [7:0] ext_y_load_data;
        reg ext_y_load_en;
        reg [7:0] ext_sp_load_data;
        reg ext_sp_load_en;

        // Instantiate CPU
        mos6502_cpu cpu (
          .clk(clk),
          .rst(rst),
          .rdy(rdy),
          .irq(irq),
          .nmi(nmi),
          .data_in(data_in),
          .data_out(data_out),
          .addr(addr),
          .rw(rw),
          .sync(sync),
          .ext_pc_load_data(ext_pc_load_data),
          .ext_pc_load_en(ext_pc_load_en),
          .ext_a_load_data(ext_a_load_data),
          .ext_a_load_en(ext_a_load_en),
          .ext_x_load_data(ext_x_load_data),
          .ext_x_load_en(ext_x_load_en),
          .ext_y_load_data(ext_y_load_data),
          .ext_y_load_en(ext_y_load_en),
          .ext_sp_load_data(ext_sp_load_data),
          .ext_sp_load_en(ext_sp_load_en),
          .reg_a(reg_a),
          .reg_x(reg_x),
          .reg_y(reg_y),
          .reg_sp(reg_sp),
          .reg_pc(reg_pc),
          .reg_p(reg_p),
          .halted(halted),
          .cycle_count(cycle_count)
        );

        // Clock generation
        initial clk = 0;
        always #5 clk = ~clk;

        // Memory read/write
        always @(*) begin
          if (addr[15] == 1'b1) begin
            // ROM read (0x8000-0xFFFF)
            data_in = rom[addr[14:0]];
          end else begin
            // RAM read (0x0000-0x7FFF)
            data_in = ram[addr[14:0]];
          end
        end

        // RAM write on clock edge
        always @(posedge clk) begin
          if (rw == 0 && addr[15] == 0) begin
            ram[addr[14:0]] <= data_out;
          end
        end

        // Test sequence
        integer cycle_counter;
        initial begin
          // Initialize memory
          integer i;
          for (i = 0; i < 32768; i = i + 1) begin
            ram[i] = 8'h00;
            rom[i] = 8'h00;
          end

          // Load program into ROM
      #{rom_init}

          // Load initial RAM values
      #{ram_init}

          // Set reset vector (0xFFFC-0xFFFD points to 0x8000)
          rom[16'h7FFC] = 8'h#{reset_vector_lo.to_s(16).rjust(2, '0')};
          rom[16'h7FFD] = 8'h#{reset_vector_hi.to_s(16).rjust(2, '0')};

          // Initialize control signals
          rdy = 1;
          irq = 1;
          nmi = 1;
          ext_pc_load_en = 0;
          ext_a_load_en = 0;
          ext_x_load_en = 0;
          ext_y_load_en = 0;
          ext_sp_load_en = 0;
          ext_pc_load_data = 16'h0000;
          ext_a_load_data = 8'h00;
          ext_x_load_data = 8'h00;
          ext_y_load_data = 8'h00;
          ext_sp_load_data = 8'h00;

          // Reset sequence
          rst = 1;
          @(posedge clk); #1;
          rst = 0;

          // Wait for reset sequence (5 cycles so reset_step reaches 5)
          // On cycle 6, we'll transition from RESET to FETCH
          repeat(5) begin
            @(posedge clk); #1;
          end

          // Load PC with program start address
          // This clock cycle will: transition RESET->FETCH AND load PC
          ext_pc_load_data = 16'h8000;
          ext_pc_load_en = 1;
          @(posedge clk); #1;
          ext_pc_load_en = 0;

          // Run simulation
          cycle_counter = 0;
          while (cycle_counter < #{max_cycles} && !halted) begin
            @(posedge clk); #1;
            cycle_counter = cycle_counter + 1;
          end

          // Output results
          $display("RESULTS:");
          $display("A=%d", reg_a);
          $display("X=%d", reg_x);
          $display("Y=%d", reg_y);
          $display("SP=%d", reg_sp);
          $display("PC=%d", reg_pc);
          $display("P=%d", reg_p);
          $display("HALTED=%d", halted);
          $display("CYCLES=%d", cycle_counter);
      #{mem_checks}
          $display("END_RESULTS");

          $finish;
        end
      endmodule
    VERILOG

    File.write(File.join(base_dir, 'tb.v'), testbench)
  end

  def compile_and_run_verilog(base_dir)
    verilog_files = Dir.glob(File.join(base_dir, '*.v'))

    # Compile with iverilog using SystemVerilog mode
    compile_cmd = ["iverilog", "-g2012", "-o", "sim.out"] + verilog_files.map { |f| File.basename(f) }
    compile_result = run_cmd(compile_cmd, cwd: base_dir)

    unless compile_result[:status].success?
      return { success: false, error: "Compilation failed: #{compile_result[:stderr]}" }
    end

    # Run simulation
    run_result = run_cmd(["vvp", "sim.out"], cwd: base_dir)

    unless run_result[:status].success?
      return { success: false, error: "Simulation failed: #{run_result[:stderr]}" }
    end

    { success: true, stdout: run_result[:stdout], stderr: run_result[:stderr] }
  end

  def run_cmd(cmd, cwd:)
    require 'open3'
    stdout, stderr, status = Open3.capture3(*cmd, chdir: cwd)
    { stdout: stdout, stderr: stderr, status: status }
  end

  def parse_verilog_output(stdout, check_addrs)
    result = {
      a: nil, x: nil, y: nil, sp: nil, pc: nil, p: nil,
      halted: false, cycles: 0, memory: {}
    }

    stdout.each_line do |line|
      case line
      when /^A=\s*(\d+)/
        result[:a] = $1.to_i
      when /^X=\s*(\d+)/
        result[:x] = $1.to_i
      when /^Y=\s*(\d+)/
        result[:y] = $1.to_i
      when /^SP=\s*(\d+)/
        result[:sp] = $1.to_i
      when /^PC=\s*(\d+)/
        result[:pc] = $1.to_i
      when /^P=\s*(\d+)/
        result[:p] = $1.to_i
      when /^HALTED=\s*(\d+)/
        result[:halted] = $1.to_i == 1
      when /^CYCLES=\s*(\d+)/
        result[:cycles] = $1.to_i
      when /^MEM\[0x([0-9A-Fa-f]+)\]=\s*(\d+)/
        addr = $1.to_i(16)
        result[:memory][addr] = $2.to_i
      end
    end

    { success: true }.merge(result)
  end

  # ==========================================
  # Test Programs
  # ==========================================

  describe 'Simple arithmetic' do
    it 'adds two numbers' do
      program = <<~'ASM'
        LDA #$03
        CLC
        ADC #$05
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 8
      )
    end

    it 'subtracts two numbers' do
      program = <<~'ASM'
        LDA #$10
        SEC
        SBC #$03
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 13
      )
    end
  end

  describe 'Load and store' do
    it 'loads and stores to zero page' do
      program = <<~'ASM'
        LDA #$42
        STA $10
        LDA #$00
        LDA $10
        BRK
      ASM

      run_program_comparison(
        program: program,
        check_addrs: [0x10],
        expected_a: 0x42
      )
    end

    it 'transfers between registers' do
      program = <<~'ASM'
        LDA #$55
        TAX
        LDA #$00
        TXA
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x55,
        expected_x: 0x55
      )
    end
  end

  describe 'Increment and decrement' do
    it 'increments X register' do
      program = <<~'ASM'
        LDX #$05
        INX
        INX
        TXA
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 7,
        expected_x: 7
      )
    end

    it 'decrements Y register' do
      program = <<~'ASM'
        LDY #$10
        DEY
        DEY
        DEY
        TYA
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 13,
        expected_y: 13
      )
    end

    it 'increments memory' do
      program = <<~'ASM'
        LDA #$05
        STA $20
        INC $20
        INC $20
        LDA $20
        BRK
      ASM

      run_program_comparison(
        program: program,
        check_addrs: [0x20],
        expected_a: 7
      )
    end
  end

  describe 'Branching' do
    it 'BEQ branches on zero' do
      program = <<~'ASM'
        LDA #$00
        BEQ skip
        LDA #$FF
      skip:
        LDA #$42
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x42
      )
    end

    it 'BNE branches on not zero' do
      program = <<~'ASM'
        LDA #$01
        BNE skip
        LDA #$FF
      skip:
        LDA #$55
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x55
      )
    end

    it 'BCS branches on carry set' do
      program = <<~'ASM'
        SEC
        BCS skip
        LDA #$FF
      skip:
        LDA #$33
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x33
      )
    end
  end

  describe 'Comparison' do
    it 'CMP sets zero flag when equal' do
      program = <<~'ASM'
        LDA #$42
        CMP #$42
        BEQ equal
        LDA #$00
        BRK
      equal:
        LDA #$FF
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0xFF
      )
    end

    it 'CMP sets carry when A >= operand' do
      program = <<~'ASM'
        LDA #$50
        CMP #$30
        BCS greater
        LDA #$00
        BRK
      greater:
        LDA #$AA
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0xAA
      )
    end
  end

  describe 'Logical operations' do
    it 'performs AND' do
      program = <<~'ASM'
        LDA #$FF
        AND #$0F
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x0F
      )
    end

    it 'performs ORA' do
      program = <<~'ASM'
        LDA #$F0
        ORA #$0F
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0xFF
      )
    end

    it 'performs EOR' do
      program = <<~'ASM'
        LDA #$AA
        EOR #$FF
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x55
      )
    end
  end

  describe 'Stack operations' do
    it 'pushes and pulls accumulator' do
      program = <<~'ASM'
        LDA #$42
        PHA
        LDA #$00
        PLA
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x42
      )
    end
  end

  describe 'Subroutines' do
    it 'JSR and RTS work correctly' do
      # Simple subroutine that adds 5 to A
      program = <<~'ASM'
        LDA #$10
        JSR add5
        BRK
      add5:
        CLC
        ADC #$05
        RTS
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x15
      )
    end
  end

  describe 'Loop countdown' do
    it 'counts down from 5 to 0' do
      program = <<~'ASM'
        LDA #$05
        STA $10
      loop:
        DEC $10
        LDA $10
        BNE loop
        BRK
      ASM

      run_program_comparison(
        program: program,
        check_addrs: [0x10],
        expected_a: 0
      )
    end
  end

  describe 'Multiplication by repeated addition' do
    it 'multiplies 3 * 4' do
      # Result = 3 * 4 = 12
      program = <<~'ASM'
        LDA #$00    ; result = 0
        STA $20
        LDX #$04    ; counter = 4
      loop:
        CLC
        LDA $20
        ADC #$03    ; add 3
        STA $20
        DEX
        BNE loop
        LDA $20
        BRK
      ASM

      run_program_comparison(
        program: program,
        check_addrs: [0x20],
        expected_a: 12
      )
    end
  end

  describe 'Shift operations' do
    it 'ASL doubles value' do
      program = <<~'ASM'
        LDA #$10
        ASL A
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x20
      )
    end

    it 'LSR halves value' do
      program = <<~'ASM'
        LDA #$20
        LSR A
        BRK
      ASM

      run_program_comparison(
        program: program,
        expected_a: 0x10
      )
    end
  end
end
