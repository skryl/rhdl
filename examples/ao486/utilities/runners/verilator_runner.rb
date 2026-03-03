# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

require "rhdl/import/checks/ao486_program_parity_harness"
require_relative "dos_boot_shim"

module RHDL
  module Examples
    module AO486
      class VerilatorRunner
        DEFAULT_TOP = "ao486"
        DEFAULT_PROGRAM_BASE_ADDRESS = RHDL::Import::Checks::Ao486ProgramParityHarness::PROGRAM_BASE_ADDRESS
        DEFAULT_DATA_CHECK_ADDRESSES = [RHDL::Import::Checks::Ao486ProgramParityHarness::DATA_CHECK_ADDRESS].freeze
        DOS_BOOT_MAX_CYCLES = 131_072
        MAX_MEMORY_ENTRIES = 8192
        MAX_FETCH_ENTRIES = 8192
        MAX_TRACK_ENTRIES = 8192

        attr_reader :out_dir, :vendor_root, :cwd, :top, :source_mode

        def initialize(out_dir:, vendor_root:, cwd: Dir.pwd, top: DEFAULT_TOP, source_mode: :generated, **_kwargs)
          @cwd = File.expand_path(cwd)
          @out_dir = File.expand_path(out_dir, @cwd)
          @vendor_root = File.expand_path(vendor_root, @cwd)
          @top = top.to_s
          @source_mode = normalize_source_mode(source_mode)
          @compile_mutex = Mutex.new
          @compile_dir = nil
          @binary_path = nil
          @run_sequence = 0
        end

        def run_program(
          program_binary:,
          cycles: RHDL::Import::Checks::Ao486ProgramParityHarness::DEFAULT_CYCLES,
          program_base_address: DEFAULT_PROGRAM_BASE_ADDRESS,
          data_check_addresses: DEFAULT_DATA_CHECK_ADDRESSES
        )
          source_root = source_mode == :vendor ? vendor_root : ""
          harness = build_harness(
            program_binary: program_binary,
            cycles: cycles,
            data_check_addresses: data_check_addresses,
            program_base_address: program_base_address,
            source_root: source_root
          )

          ensure_backend_compiled!(harness: harness)
          run_files = write_runtime_input_files(harness: harness)
          result = run_compiled_binary(cycles: cycles, run_files: run_files)
          unless result.fetch(:status).success?
            raise ArgumentError, "#{source_mode} verilator simulation failed: #{first_error_line(result.fetch(:stderr))}"
          end

          harness.send(:parse_program_trace, stdout: result.fetch(:stdout))
        end

        def run_dos_boot(
          bios_system: nil,
          bios_video: nil,
          dos_image: nil,
          bios_system_path: nil,
          bios_video_path: nil,
          dos_image_path: nil,
          disk_image: nil,
          disk: nil,
          cycles: DOS_BOOT_MAX_CYCLES
        )
          _resolved_bios_system = resolve_boot_asset_path(
            explicit: bios_system || bios_system_path,
            fallback: File.join(cwd, "examples", "ao486", "software", "bin", "boot0.rom"),
            label: "BIOS system ROM"
          )
          _resolved_bios_video = resolve_boot_asset_path(
            explicit: bios_video || bios_video_path,
            fallback: File.join(cwd, "examples", "ao486", "software", "bin", "boot1.rom"),
            label: "BIOS video ROM"
          )
          _resolved_dos_image = resolve_boot_asset_path(
            explicit: dos_image || dos_image_path || disk_image || disk,
            fallback: File.join(cwd, "examples", "ao486", "software", "images", "dos4.img"),
            label: "DOS disk image"
          )
          _requested_cycles = Integer(cycles)
          raise NotImplementedError, "real DOS boot on Verilator runner is not implemented yet; use mode=ir"
        end

        private

        def resolve_boot_asset_path(explicit:, fallback:, label:)
          candidate = explicit.to_s.strip
          candidate = fallback if candidate.empty?
          path = File.expand_path(candidate, cwd)
          raise ArgumentError, "#{label} not found: #{path}" unless File.file?(path)

          path
        end

        def normalize_source_mode(value)
          mode = value.to_sym
          return mode if %i[vendor generated].include?(mode)

          raise ArgumentError, "unknown source mode #{value.inspect}; expected :vendor or :generated"
        end

        def ensure_backend_compiled!(harness:)
          return if backend_ready?

          @compile_mutex.synchronize do
            return if backend_ready?

            @compile_dir ||= Dir.mktmpdir("ao486_verilator_runner_#{source_mode}")
            mode = source_mode == :vendor ? "reference" : "converted"
            source_work_dir = File.join(@compile_dir, "#{mode}_sources")
            run_dir = File.join(@compile_dir, mode)
            FileUtils.mkdir_p(run_dir)

            contract = harness.send(:source_contract, mode: mode, work_dir: source_work_dir)
            include_dirs = Array(contract.fetch(:include_dirs))
            include_dirs += vendor_include_fallback_dirs if source_mode == :vendor
            include_dirs = include_dirs.map(&:to_s).uniq

            testbench_path = File.join(run_dir, "tb_ao486_runner.sv")
            File.write(testbench_path, runtime_testbench_source(top: top))

            selected_sources = Array(contract.fetch(:source_files)).map(&:to_s).reject(&:empty?).uniq.sort
            stub_paths = []
            compile_result = compile_verilog(
              work_dir: run_dir,
              source_files: selected_sources,
              include_dirs: include_dirs,
              testbench_path: testbench_path,
              stub_paths: stub_paths
            )
            attempts = 0
            max_attempts = RHDL::Import::Checks::Ao486ProgramParityHarness::MAX_COMPILE_ATTEMPTS
            while !compile_success?(compile_result: compile_result, run_dir: run_dir) && attempts < max_attempts
              attempts += 1
              missing = harness.send(:extract_missing_modules, compile_result.fetch(:stderr))
              break if missing.empty?

              discovered = harness.send(
                :resolve_missing_module_sources,
                missing_modules: missing,
                include_dirs: include_dirs,
                selected_sources: selected_sources
              )
              unless discovered.empty?
                selected_sources = (selected_sources + discovered.values).uniq.sort
                compile_result = compile_verilog(
                  work_dir: run_dir,
                  source_files: selected_sources,
                  include_dirs: include_dirs,
                  testbench_path: testbench_path,
                  stub_paths: stub_paths
                )
                next
              end

              signatures = RHDL::Import::MissingModuleSignatureExtractor.augment(
                signatures: missing.map { |name| { name: name, ports: [], parameters: [] } },
                source_files: selected_sources
              )
              stub_paths = harness.send(:write_stub_sources, work_dir: run_dir, signatures: signatures)
              compile_result = compile_verilog(
                work_dir: run_dir,
                source_files: selected_sources,
                include_dirs: include_dirs,
                testbench_path: testbench_path,
                stub_paths: stub_paths
              )
            end

            unless compile_success?(compile_result: compile_result, run_dir: run_dir)
              raise ArgumentError, "#{source_mode} verilator compile failed: #{first_error_line(compile_result.fetch(:stderr))}"
            end

            @binary_path = File.join(run_dir, "obj_dir", "Vtb_ao486_runner")
            unless File.file?(@binary_path)
              raise ArgumentError, "#{source_mode} verilator compile produced no executable #{@binary_path}"
            end
          end
        end

        def backend_ready?
          path = @binary_path.to_s
          !path.empty? && File.file?(path)
        end

        def compile_success?(compile_result:, run_dir:)
          return true if compile_result.fetch(:status).success?

          File.file?(File.join(run_dir, "obj_dir", "Vtb_ao486_runner"))
        end

        def run_compiled_binary(cycles:, run_files:)
          command = [
            @binary_path.to_s,
            "+cycles=#{Integer(cycles)}",
            "+mem_file=#{run_files.fetch(:memory_file)}",
            "+fetch_file=#{run_files.fetch(:fetch_file)}",
            "+track_file=#{run_files.fetch(:track_file)}"
          ]
          run_command(command: command, chdir: @compile_dir)
        end

        def write_runtime_input_files(harness:)
          @run_sequence += 1
          run_dir = File.join(@compile_dir, "runs")
          FileUtils.mkdir_p(run_dir)

          memory_path = File.join(run_dir, format("memory_%06d.txt", @run_sequence))
          fetch_path = File.join(run_dir, format("fetch_%06d.txt", @run_sequence))
          track_path = File.join(run_dir, format("track_%06d.txt", @run_sequence))

          write_memory_file(path: memory_path, memory_words: harness.program_memory_words)
          write_address_file(path: fetch_path, addresses: harness.program_fetch_addresses)
          write_address_file(path: track_path, addresses: harness.program_tracked_addresses)

          {
            memory_file: memory_path,
            fetch_file: fetch_path,
            track_file: track_path
          }
        end

        def write_memory_file(path:, memory_words:)
          lines = Array(memory_words)
            .map { |address, value| [Integer(address) & 0xFFFF_FFFF, Integer(value) & 0xFFFF_FFFF] }
            .sort_by(&:first)
            .map { |address, value| format("%08x %08x", address, value) }
          File.write(path, "#{lines.join("\n")}\n")
        end

        def write_address_file(path:, addresses:)
          lines = Array(addresses).map { |address| format("%08x", Integer(address) & 0xFFFF_FFFF) }
          File.write(path, "#{lines.join("\n")}\n")
        end

        def vendor_include_fallback_dirs
          fallback_root = File.expand_path(File.join("examples", "ao486", "reference", "rtl"), cwd)
          return [] unless Dir.exist?(fallback_root)

          [fallback_root] + Dir.glob(File.join(fallback_root, "**", "*")).select { |path| File.directory?(path) }
        end

        def compile_verilog(work_dir:, source_files:, include_dirs:, testbench_path:, stub_paths:)
          include_args = Array(include_dirs).map { |entry| "-I#{entry}" }
          command = [
            "verilator",
            "-Wall",
            "-Wno-fatal",
            "-Wno-PINMISSING",
            "-Wno-UNUSEDSIGNAL",
            "--binary",
            "--sv",
            "--top-module",
            "tb_ao486_runner",
            *include_args,
            *Array(source_files).map(&:to_s),
            *Array(stub_paths).map(&:to_s),
            testbench_path.to_s
          ]
          run_command(command: command, chdir: work_dir)
        end

        def run_command(command:, chdir:)
          stdout, stderr, status = Open3.capture3(*Array(command).map(&:to_s), chdir: chdir.to_s)
          { stdout: stdout.to_s, stderr: stderr.to_s, status: status }
        end

        def first_error_line(stderr)
          line = stderr.to_s.each_line.find { |entry| !entry.strip.empty? }
          message = line.to_s.strip
          message.empty? ? "unknown error" : message
        end

        def build_harness(
          program_binary:,
          cycles:,
          data_check_addresses:,
          program_base_address: DEFAULT_PROGRAM_BASE_ADDRESS,
          source_root:
        )
          RHDL::Import::Checks::Ao486ProgramParityHarness.new(
            out: out_dir,
            top: top,
            cycles: Integer(cycles),
            source_root: source_root.to_s,
            cwd: cwd,
            program_binary: program_binary,
            program_binary_data_addresses: normalize_data_check_addresses(data_check_addresses),
            program_base_address: Integer(program_base_address),
            verilog_tool: "verilator"
          )
        end

        def normalize_data_check_addresses(data_check_addresses)
          values = Array(data_check_addresses).map { |entry| Integer(entry) }
          values.empty? ? DEFAULT_DATA_CHECK_ADDRESSES : values
        end

        def runtime_testbench_source(top:)
          <<~VERILOG
            `timescale 1ns/1ps

            module tb_ao486_runner;
              localparam integer MAX_MEM_ENTRIES = #{MAX_MEMORY_ENTRIES};
              localparam integer MAX_FETCH_ENTRIES = #{MAX_FETCH_ENTRIES};
              localparam integer MAX_TRACK_ENTRIES = #{MAX_TRACK_ENTRIES};

              reg clk = 1'b0;
              reg rst_n = 1'b0;

              reg a20_enable = 1'b1;
              reg cache_disable = 1'b1;
              reg interrupt_do = 1'b0;
              reg [7:0] interrupt_vector = 8'h00;
              wire interrupt_done;

              wire [29:0] avm_address;
              wire [31:0] avm_writedata;
              wire [3:0] avm_byteenable;
              wire [3:0] avm_burstcount;
              wire avm_write;
              wire avm_read;
              reg avm_waitrequest = 1'b0;
              reg avm_readdatavalid = 1'b0;
              reg [31:0] avm_readdata = 32'h0;

              reg [23:0] dma_address = 24'h0;
              reg dma_16bit = 1'b0;
              reg dma_write = 1'b0;
              reg [15:0] dma_writedata = 16'h0;
              reg dma_read = 1'b0;
              wire [15:0] dma_readdata;
              wire dma_readdatavalid;
              wire dma_waitrequest;

              wire io_read_do;
              wire [15:0] io_read_address;
              wire [2:0] io_read_length;
              reg [31:0] io_read_data = 32'h0;
              reg io_read_done = 1'b0;

              wire io_write_do;
              wire [15:0] io_write_address;
              wire [2:0] io_write_length;
              wire [31:0] io_write_data;
              reg io_write_done = 1'b0;

              integer run_cycles = 0;
              reg [2047:0] mem_file;
              reg [2047:0] fetch_file;
              reg [2047:0] track_file;

              integer mem_count = 0;
              reg [31:0] mem_addr [0:MAX_MEM_ENTRIES-1];
              reg [31:0] mem_word [0:MAX_MEM_ENTRIES-1];

              integer fetch_count = 0;
              reg [31:0] fetch_addr [0:MAX_FETCH_ENTRIES-1];

              integer track_count = 0;
              reg [31:0] track_addr [0:MAX_TRACK_ENTRIES-1];

              integer cycle = 0;
              reg [31:0] read_addr;
              reg [31:0] read_data;
              integer pending_read_words = 0;
              integer pending_read_delay = 0;
              reg [31:0] pending_read_addr = 32'h0;

              #{top} dut (
                .clk(clk),
                .rst_n(rst_n),
                .a20_enable(a20_enable),
                .cache_disable(cache_disable),
                .interrupt_do(interrupt_do),
                .interrupt_vector(interrupt_vector),
                .interrupt_done(interrupt_done),
                .avm_address(avm_address),
                .avm_writedata(avm_writedata),
                .avm_byteenable(avm_byteenable),
                .avm_burstcount(avm_burstcount),
                .avm_write(avm_write),
                .avm_read(avm_read),
                .avm_waitrequest(avm_waitrequest),
                .avm_readdatavalid(avm_readdatavalid),
                .avm_readdata(avm_readdata),
                .dma_address(dma_address),
                .dma_16bit(dma_16bit),
                .dma_write(dma_write),
                .dma_writedata(dma_writedata),
                .dma_read(dma_read),
                .dma_readdata(dma_readdata),
                .dma_readdatavalid(dma_readdatavalid),
                .dma_waitrequest(dma_waitrequest),
                .io_read_do(io_read_do),
                .io_read_address(io_read_address),
                .io_read_length(io_read_length),
                .io_read_data(io_read_data),
                .io_read_done(io_read_done),
                .io_write_do(io_write_do),
                .io_write_address(io_write_address),
                .io_write_length(io_write_length),
                .io_write_data(io_write_data),
                .io_write_done(io_write_done)
              );

              task automatic clear_runtime_tables;
                integer i;
                begin
                  mem_count = 0;
                  fetch_count = 0;
                  track_count = 0;
                  for (i = 0; i < MAX_MEM_ENTRIES; i = i + 1) begin
                    mem_addr[i] = 32'h0;
                    mem_word[i] = 32'h0;
                  end
                  for (i = 0; i < MAX_FETCH_ENTRIES; i = i + 1) begin
                    fetch_addr[i] = 32'h0;
                  end
                  for (i = 0; i < MAX_TRACK_ENTRIES; i = i + 1) begin
                    track_addr[i] = 32'h0;
                  end
                end
              endtask

              function automatic integer find_memory_index;
                input [31:0] address;
                integer i;
                begin
                  find_memory_index = -1;
                  for (i = 0; i < mem_count; i = i + 1) begin
                    if (mem_addr[i] == address) begin
                      find_memory_index = i;
                      i = mem_count;
                    end
                  end
                end
              endfunction

              function automatic [31:0] mem_read_word;
                input [31:0] address;
                integer idx;
                begin
                  idx = find_memory_index(address);
                  if (idx >= 0) begin
                    mem_read_word = mem_word[idx];
                  end else begin
                    mem_read_word = 32'h00000000;
                  end
                end
              endfunction

              task automatic mem_store_word;
                input [31:0] address;
                input [31:0] data_word;
                integer idx;
                begin
                  idx = find_memory_index(address);
                  if (idx >= 0) begin
                    mem_word[idx] = data_word;
                  end else if (mem_count < MAX_MEM_ENTRIES) begin
                    mem_addr[mem_count] = address;
                    mem_word[mem_count] = data_word;
                    mem_count = mem_count + 1;
                  end
                end
              endtask

              task automatic mem_write_word;
                input [31:0] address;
                input [31:0] data_word;
                input [3:0] byteenable;
                reg [31:0] merged_word;
                begin
                  merged_word = mem_read_word(address);
                  if (byteenable[0]) merged_word[7:0] = data_word[7:0];
                  if (byteenable[1]) merged_word[15:8] = data_word[15:8];
                  if (byteenable[2]) merged_word[23:16] = data_word[23:16];
                  if (byteenable[3]) merged_word[31:24] = data_word[31:24];
                  mem_store_word(address, merged_word);
                end
              endtask

              function automatic is_program_address;
                input [31:0] address;
                integer i;
                begin
                  is_program_address = 1'b0;
                  for (i = 0; i < fetch_count; i = i + 1) begin
                    if (fetch_addr[i] == address) begin
                      is_program_address = 1'b1;
                      i = fetch_count;
                    end
                  end
                end
              endfunction

              task automatic load_memory_file;
                integer fd;
                integer rc;
                reg [31:0] file_addr;
                reg [31:0] file_word;
                begin
                  fd = $fopen(mem_file, "r");
                  if (fd == 0) begin
                    $display("TB ERROR unable to open memory file");
                    $finish;
                  end
                  while (!$feof(fd)) begin
                    rc = $fscanf(fd, "%h %h\\n", file_addr, file_word);
                    if (rc == 2) begin
                      mem_store_word(file_addr, file_word);
                    end
                  end
                  $fclose(fd);
                end
              endtask

              task automatic load_fetch_file;
                integer fd;
                integer rc;
                reg [31:0] file_addr;
                begin
                  fd = $fopen(fetch_file, "r");
                  if (fd == 0) begin
                    $display("TB ERROR unable to open fetch file");
                    $finish;
                  end
                  while (!$feof(fd)) begin
                    rc = $fscanf(fd, "%h\\n", file_addr);
                    if (rc == 1 && fetch_count < MAX_FETCH_ENTRIES) begin
                      fetch_addr[fetch_count] = file_addr;
                      fetch_count = fetch_count + 1;
                    end
                  end
                  $fclose(fd);
                end
              endtask

              task automatic load_track_file;
                integer fd;
                integer rc;
                reg [31:0] file_addr;
                begin
                  fd = $fopen(track_file, "r");
                  if (fd == 0) begin
                    $display("TB ERROR unable to open track file");
                    $finish;
                  end
                  while (!$feof(fd)) begin
                    rc = $fscanf(fd, "%h\\n", file_addr);
                    if (rc == 1 && track_count < MAX_TRACK_ENTRIES) begin
                      track_addr[track_count] = file_addr;
                      track_count = track_count + 1;
                    end
                  end
                  $fclose(fd);
                end
              endtask

              task automatic dump_tracked_memory;
                integer i;
                begin
                  for (i = 0; i < track_count; i = i + 1) begin
                    $display("EV MEM %08x %08x", track_addr[i], mem_read_word(track_addr[i]));
                  end
                end
              endtask

              initial begin
                if (!$value$plusargs("cycles=%d", run_cycles)) begin
                  run_cycles = 256;
                end
                if (!$value$plusargs("mem_file=%s", mem_file)) begin
                  $display("TB ERROR missing +mem_file=<path>");
                  $finish;
                end
                if (!$value$plusargs("fetch_file=%s", fetch_file)) begin
                  $display("TB ERROR missing +fetch_file=<path>");
                  $finish;
                end
                if (!$value$plusargs("track_file=%s", track_file)) begin
                  $display("TB ERROR missing +track_file=<path>");
                  $finish;
                end

                clear_runtime_tables();
                load_memory_file();
                load_fetch_file();
                load_track_file();

                rst_n = 1'b0;
                clk = 1'b0;
                avm_readdatavalid = 1'b0;
                io_read_done = 1'b0;
                io_write_done = 1'b0;
                avm_readdata = 32'h0;

                for (cycle = 0; cycle <= run_cycles; cycle = cycle + 1) begin
                  if (cycle == 3) begin
                    rst_n = 1'b1;
                  end
                  io_read_done = 1'b0;
                  io_write_done = 1'b0;
                  avm_waitrequest = 1'b0;

                  avm_readdatavalid = 1'b0;
                  if (pending_read_delay > 0) begin
                    pending_read_delay = pending_read_delay - 1;
                  end else if (pending_read_words > 0) begin
                    read_addr = pending_read_addr;
                    read_data = mem_read_word(read_addr);
                    avm_readdata = read_data;
                    avm_readdatavalid = 1'b1;
                    if (is_program_address(read_addr)) begin
                      $display("EV IF %0d %08x %08x", cycle, read_addr, read_data);
                    end
                    pending_read_addr = pending_read_addr + 32'h00000004;
                    pending_read_words = pending_read_words - 1;
                  end

                  clk = 1'b0;
                  #1;
                  clk = 1'b1;
                  #1;

                  if (avm_read && !avm_waitrequest && pending_read_words == 0 && pending_read_delay == 0) begin
                    read_addr = {avm_address, 2'b00};
                    pending_read_addr = read_addr;
                    pending_read_words = (avm_burstcount == 4'b0000) ? 1 : avm_burstcount;
                    pending_read_delay = 1;
                    $display("EV RD %0d %08x %1x %1x", cycle, read_addr, avm_burstcount, avm_byteenable);
                  end

                  if (avm_write && !avm_waitrequest) begin
                    read_addr = {avm_address, 2'b00};
                    mem_write_word(read_addr, avm_writedata, avm_byteenable);
                    $display("EV WR %0d %08x %08x %1x", cycle, read_addr, avm_writedata, avm_byteenable);
                  end

                  if (io_read_do) begin
                    io_read_data = 32'h0;
                    io_read_done = 1'b1;
                  end
                  if (io_write_do) begin
                    io_write_done = 1'b1;
                  end

                  if (cycle < 220) begin
                    $display(
                      "DBG %0d avm_r=%0d avm_w=%0d addr=%08x burst=%0d rv=%0d wait=%0d am_state=%0d am_ctr=%0d l1_state=%0d l1_mem_req=%0d l1_mem_done=%0d l1_force=%0d l1_force_n=%0d l1_mux=%b l1_tg_w0=%b l1_dirty=%0x l1_tag_we=%0d l1_idx=%b l1_raddr=%08x l1_tag0=%08x l1_tag1=%08x l1_tag2=%08x l1_tag3=%08x eip=%08x fv=%0d pf_empty=%0d ic_do=%0d ic_state=%0d ic_valid=%0d pf_wr=%0d rc_do=%0d rc_dn=%0d am_rc_dn=%0d rd_do=%0d rd_done=%0d",
                      cycle,
                      avm_read,
                      avm_write,
                      {avm_address, 2'b00},
                      avm_burstcount,
                      avm_readdatavalid,
                      avm_waitrequest,
                      dut.memory_inst.avalon_mem_inst.state,
                      dut.memory_inst.avalon_mem_inst.counter,
                      dut.memory_inst.icache_inst.l1_icache_inst.state,
                      dut.memory_inst.icache_inst.l1_icache_inst.MEM_REQ,
                      dut.memory_inst.icache_inst.l1_icache_inst.MEM_DONE,
                      dut.memory_inst.icache_inst.l1_icache_inst.force_fetch,
                      dut.memory_inst.icache_inst.l1_icache_inst.force_next,
                      dut.memory_inst.icache_inst.l1_icache_inst.cache_mux,
                      (dut.memory_inst.icache_inst.l1_icache_inst.state == 3'd5) &&
                        (dut.memory_inst.icache_inst.l1_icache_inst.cache_mux == 2'd0),
                      dut.memory_inst.icache_inst.l1_icache_inst.tags_dirty_out,
                      dut.memory_inst.icache_inst.l1_icache_inst.update_tag_we,
                      dut.memory_inst.icache_inst.l1_icache_inst.read_addr[9:3],
                      dut.memory_inst.icache_inst.l1_icache_inst.read_addr,
                      dut.memory_inst.icache_inst.l1_icache_inst.tags_read[0],
                      dut.memory_inst.icache_inst.l1_icache_inst.tags_read[1],
                      dut.memory_inst.icache_inst.l1_icache_inst.tags_read[2],
                      dut.memory_inst.icache_inst.l1_icache_inst.tags_read[3],
                      dut.pipeline_inst.write_inst.wr_eip,
                      dut.pipeline_inst.fetch_inst.fetch_valid,
                      dut.pipeline_inst.prefetchfifo_accept_empty,
                      dut.memory_inst.icacheread_do,
                      dut.memory_inst.icache_inst.state,
                      dut.memory_inst.icache_inst.readcode_cache_valid,
                      dut.memory_inst.prefetchfifo_write_do,
                      dut.memory_inst.icache_inst.readcode_do,
                      dut.memory_inst.icache_inst.readcode_done,
                      dut.memory_inst.avalon_mem_inst.readcode_done,
                      dut.pipeline_inst.read_do,
                      dut.pipeline_inst.read_done
                    );
                  end

                  clk = 1'b0;
                  #1;
                end

                dump_tracked_memory();
                $finish;
              end
            endmodule
          VERILOG
        end
      end
    end
  end
end
