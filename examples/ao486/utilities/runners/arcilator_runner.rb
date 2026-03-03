# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "fiddle"
require "json"
require "set"
require "shellwords"
require "rbconfig"

require "rhdl/import/checks/ao486_trace_harness"
require "rhdl/codegen/circt/firrtl"
require "rhdl/import/checks/ao486_program_parity_harness"

require_relative "native_memory"
require_relative "dos_boot_shim"

module RHDL
  module Examples
    module AO486
      class ArcilatorRunner
        BUILD_DIR = File.expand_path("../../../.arcilator_build_ao486", __dir__)
        DEFAULT_TOP = "ao486"
        DEFAULT_PROGRAM_BASE_ADDRESS = RHDL::Import::Checks::Ao486ProgramParityHarness::PROGRAM_BASE_ADDRESS
        DEFAULT_DATA_CHECK_ADDRESSES = [RHDL::Import::Checks::Ao486ProgramParityHarness::DATA_CHECK_ADDRESS].freeze
        DOS_BOOT_MAX_CYCLES = 131_072

        attr_reader :out_dir, :vendor_root, :cwd, :top

        def initialize(out_dir:, vendor_root:, cwd: Dir.pwd, top: DEFAULT_TOP)
          @cwd = File.expand_path(cwd)
          @out_dir = File.expand_path(out_dir, @cwd)
          @vendor_root = File.expand_path(vendor_root, @cwd)
          @top = top.to_s
          @sim_functions = nil
          @signal_names = Set.new
          @input_signal_names = Set.new
          @io_signals = []
        end

        def run_program(
          program_binary:,
          cycles: RHDL::Import::Checks::Ao486ProgramParityHarness::DEFAULT_CYCLES,
          program_base_address: DEFAULT_PROGRAM_BASE_ADDRESS,
          data_check_addresses: DEFAULT_DATA_CHECK_ADDRESSES
        )
          ensure_backend_ready!

          harness = build_harness(
            program_binary: program_binary,
            cycles: cycles,
            data_check_addresses: data_check_addresses,
            program_base_address: program_base_address,
            source_root: vendor_root
          )
          memory = build_trace_memory(harness)

          sim = @sim_functions.fetch(:create).call
          begin
            trace = run_program_via_native(
              sim: sim,
              harness: harness,
              cycles: Integer(cycles)
            )
          ensure
            @sim_functions.fetch(:destroy).call(sim)
          end
          apply_memory_writes(memory: memory, writes: trace.fetch("memory_writes"))
          trace["memory_contents"] = memory_snapshot(memory: memory, harness: harness)
          trace
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
          raise NotImplementedError, "real DOS boot on Arcilator runner is not implemented yet; use mode=ir"
        end

        private

        def resolve_boot_asset_path(explicit:, fallback:, label:)
          candidate = explicit.to_s.strip
          candidate = fallback if candidate.empty?
          path = File.expand_path(candidate, cwd)
          raise ArgumentError, "#{label} not found: #{path}" unless File.file?(path)

          path
        end

        def build_trace_memory(harness)
          RHDL::Examples::AO486::NativeMemory.from_words(harness.program_memory_words)
        end

        def apply_memory_writes(memory:, writes:)
          Array(writes).each do |entry|
            memory.write_word(
              address: entry.fetch("address"),
              data: entry.fetch("data"),
              byteenable: entry.fetch("byteenable", 0xF)
            )
          end
        end

        def memory_snapshot(memory:, harness:)
          memory.snapshot(harness.program_tracked_addresses)
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

        def ensure_backend_ready!
          return if @sim_functions

          check_tools_available!
          build_arcilator_library!
          load_simulation_functions!
        end

        def check_tools_available!
          %w[firtool arcilator].each do |tool|
            next if command_available?(tool)

            raise "#{tool} not found in PATH"
          end

          return if command_available?("llc") || command_available?("clang")

          raise "Neither llc nor clang found in PATH"
        end

        def command_available?(command)
          system("which #{command} > /dev/null 2>&1")
        end

        def build_arcilator_library!
          FileUtils.mkdir_p(BUILD_DIR)
          files = build_paths

          flat_module = lowered_flat_module
          firrtl = RHDL::Codegen::CIRCT::FIRRTL.generate(flat_module)
          File.write(files.fetch(:fir), firrtl)

          run_or_raise("firtool #{shell(files.fetch(:fir))} --ir-hw -o #{shell(files.fetch(:mlir))}", "firtool failed")
          run_or_raise("arcilator #{shell(files.fetch(:mlir))} --state-file=#{shell(files.fetch(:state))} -o #{shell(files.fetch(:ll))}", "arcilator failed")
          compile_object(files: files)
          state = JSON.parse(File.read(files.fetch(:state)))
          module_entry = Array(state).first || {}
          module_name = module_entry.fetch("name")
          @io_signals = Array(module_entry.fetch("states")).select { |entry| %w[input output].include?(entry["type"].to_s) }
          @signal_names = @io_signals.map { |entry| entry.fetch("name").to_s }.to_set
          @input_signal_names = @io_signals
            .select { |entry| entry.fetch("type").to_s == "input" }
            .map { |entry| entry.fetch("name").to_s }
            .to_set
          write_wrapper(files: files, module_name: module_name, io_signals: @io_signals, state_bytes: Integer(module_entry.fetch("numStateBytes")))
          link_library(files: files)
        end

        def lowered_flat_module
          helper = RHDL::Import::Checks::Ao486TraceHarness.new(
            mode: "converted_ir",
            top: top,
            out: out_dir,
            cycles: 1,
            source_root: vendor_root,
            converted_export_mode: nil,
            cwd: cwd
          )
          components = helper.send(:load_converted_components)
          index = components.each_with_object({}) { |entry, memo| memo[entry.fetch(:source_module_name)] = entry }
          component = index.fetch(top)
          module_def = RHDL::Codegen::LIR::Lower.new(component.fetch(:component_class), top_name: top).build
          flattened = helper.send(:flatten_ir_module, module_def: module_def, component_index: index)
          helper.send(:populate_missing_sensitivity_lists!, flattened)
          flattened
        end

        def compile_object(files:)
          if command_available?("clang")
            run_or_raise("clang -c -O2 -x ir #{shell(files.fetch(:ll))} -o #{shell(files.fetch(:obj))}", "clang IR compile failed")
            return
          end

          run_or_raise("llc -O2 -filetype=obj #{shell(files.fetch(:ll))} -o #{shell(files.fetch(:obj))}", "llc failed")
        end

        def write_wrapper(files:, module_name:, io_signals:, state_bytes:)
          entries = io_signals.map do |entry|
            name = entry.fetch("name").to_s
            offset = Integer(entry.fetch("offset"))
            bits = Integer(entry.fetch("numBits"))
            is_input = entry.fetch("type").to_s == "input" ? 1 : 0
            %(  {"#{escape_cpp_string(name)}", #{offset}, #{bits}, #{is_input}})
          end

          source = <<~CPP
            #include <cstdint>
            #include <cstring>
            #include <cstddef>
            #include <cstdlib>
            #include <cstdio>
            #include <unordered_map>
            #include <unordered_set>

            extern "C" void #{module_name}_eval(void* state);

            struct SignalInfo {
              const char* name;
              uint32_t offset;
              uint32_t bits;
              uint8_t is_input;
            };

            static const SignalInfo SIGNALS[] = {
            #{entries.join(",\n")}
            };
            static const size_t SIGNAL_COUNT = sizeof(SIGNALS) / sizeof(SIGNALS[0]);
            static const uint32_t STATE_SIZE = #{state_bytes};

            struct SimContext {
              uint8_t state[STATE_SIZE];
              std::unordered_map<uint32_t, uint32_t> memory;
            };

            static uint32_t bit_mask(uint32_t bits) {
              if(bits == 0) return 0u;
              if(bits >= 32) return 0xFFFFFFFFu;
              return ((1u << bits) - 1u);
            }

            static const SignalInfo* find_signal(const char* name) {
              for(size_t i = 0; i < SIGNAL_COUNT; i++) {
                if(std::strcmp(SIGNALS[i].name, name) == 0) {
                  return &SIGNALS[i];
                }
              }
              return nullptr;
            }

            static void write_signal(SimContext* ctx, const SignalInfo* signal, uint32_t value) {
              uint32_t masked = value & bit_mask(signal->bits);
              uint8_t* base = &ctx->state[signal->offset];

              if(signal->bits <= 8) {
                base[0] = static_cast<uint8_t>(masked & 0xFFu);
                return;
              }
              if(signal->bits <= 16) {
                uint16_t v16 = static_cast<uint16_t>(masked & 0xFFFFu);
                std::memcpy(base, &v16, sizeof(uint16_t));
                return;
              }
              uint32_t v32 = masked;
              std::memcpy(base, &v32, sizeof(uint32_t));
            }

            static uint32_t read_signal(SimContext* ctx, const SignalInfo* signal) {
              uint8_t* base = &ctx->state[signal->offset];

              if(signal->bits <= 8) {
                return static_cast<uint32_t>(base[0]) & bit_mask(signal->bits);
              }
              if(signal->bits <= 16) {
                uint16_t value = 0;
                std::memcpy(&value, base, sizeof(uint16_t));
                return static_cast<uint32_t>(value) & bit_mask(signal->bits);
              }
              uint32_t value = 0;
              std::memcpy(&value, base, sizeof(uint32_t));
              return value & bit_mask(signal->bits);
            }

            static void write_signal_if_input(SimContext* ctx, const SignalInfo* signal, uint32_t value) {
              if(signal == nullptr) return;
              if(!signal->is_input) return;
              write_signal(ctx, signal, value);
            }

            static uint32_t read_memory_word(const std::unordered_map<uint32_t, uint32_t>& memory, uint32_t address) {
              auto it = memory.find(address);
              return it == memory.end() ? 0u : it->second;
            }

            static void write_memory_word(std::unordered_map<uint32_t, uint32_t>& memory, uint32_t address, uint32_t data, uint32_t byteenable) {
              uint32_t current = read_memory_word(memory, address);
              uint32_t merged = current;
              if((byteenable & 0x1u) != 0u) {
                merged = (merged & ~0x000000FFu) | (data & 0x000000FFu);
              }
              if((byteenable & 0x2u) != 0u) {
                merged = (merged & ~0x0000FF00u) | (data & 0x0000FF00u);
              }
              if((byteenable & 0x4u) != 0u) {
                merged = (merged & ~0x00FF0000u) | (data & 0x00FF0000u);
              }
              if((byteenable & 0x8u) != 0u) {
                merged = (merged & ~0xFF000000u) | (data & 0xFF000000u);
              }
              memory[address] = merged & 0xFFFFFFFFu;
            }

            static void init_inputs(SimContext* ctx) {
              for(size_t i = 0; i < SIGNAL_COUNT; i++) {
                if(SIGNALS[i].is_input) {
                  write_signal(ctx, &SIGNALS[i], 0u);
                }
              }
            }

            static uint32_t read_signal_value(const SimContext* ctx, const SignalInfo* signal) {
              if(signal == nullptr) return 0u;
              return read_signal(const_cast<SimContext*>(ctx), signal);
            }

            static void write_trace_fetch(
              FILE* trace,
              uint32_t cycle,
              uint32_t address,
              uint32_t data
            ) {
              std::fprintf(trace, "EV IF %u %08x %08x\\n", cycle, address, data);
            }

            static void write_trace_write(
              FILE* trace,
              uint32_t cycle,
              uint32_t address,
              uint32_t data,
              uint32_t byteenable
            ) {
              std::fprintf(trace, "EV WR %u %08x %08x %x\\n", cycle, address, data, byteenable);
            }

            extern "C" {
              void* sim_create(void) {
                SimContext* ctx = new SimContext();
                std::memset(ctx->state, 0, sizeof(ctx->state));
                ctx->memory = {};
                return ctx;
              }

              void sim_destroy(void* sim) {
                delete static_cast<SimContext*>(sim);
              }

              void sim_eval(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                #{module_name}_eval(ctx->state);
              }

              int sim_has_signal(void* sim, const char* name) {
                (void)sim;
                return find_signal(name) == nullptr ? 0 : 1;
              }

              void sim_poke(void* sim, const char* name, uint32_t value) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                const SignalInfo* signal = find_signal(name);
                if(signal == nullptr) return;
                write_signal(ctx, signal, value);
              }

              uint32_t sim_peek(void* sim, const char* name) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                const SignalInfo* signal = find_signal(name);
                if(signal == nullptr) return 0u;
                return read_signal(ctx, signal);
              }

              int sim_run_program(
                void* sim,
                const uint32_t* program_addresses,
                const uint32_t* program_words,
                uint32_t program_count,
                const uint32_t* fetch_addresses,
                uint32_t fetch_count,
                uint32_t cycles,
                const char* trace_path
              ) {
                if(sim == nullptr) return 1;
                if((program_count > 0u && (program_addresses == nullptr || program_words == nullptr))) return 2;
                if((fetch_count > 0u && fetch_addresses == nullptr)) return 3;
                if(trace_path == nullptr) return 4;

                SimContext* ctx = static_cast<SimContext*>(sim);
                ctx->memory.clear();

                for(uint32_t i = 0; i < program_count; i++) {
                  ctx->memory[program_addresses[i]] = program_words[i];
                }

                std::unordered_set<uint32_t> fetch_set;
                for(uint32_t i = 0; i < fetch_count; i++) {
                  fetch_set.insert(fetch_addresses[i]);
                }

                FILE* trace = std::fopen(trace_path, "w");
                if(trace == nullptr) return 5;

                init_inputs(ctx);

                const SignalInfo* sig_a20_enable = find_signal("a20_enable");
                const SignalInfo* sig_cache_disable = find_signal("cache_disable");
                const SignalInfo* sig_interrupt_do = find_signal("interrupt_do");
                const SignalInfo* sig_interrupt_vector = find_signal("interrupt_vector");
                const SignalInfo* sig_rst_n = find_signal("rst_n");
                const SignalInfo* sig_avm_waitrequest = find_signal("avm_waitrequest");
                const SignalInfo* sig_avm_readdatavalid = find_signal("avm_readdatavalid");
                const SignalInfo* sig_avm_readdata = find_signal("avm_readdata");
                const SignalInfo* sig_dma_address = find_signal("dma_address");
                const SignalInfo* sig_dma_16bit = find_signal("dma_16bit");
                const SignalInfo* sig_dma_write = find_signal("dma_write");
                const SignalInfo* sig_dma_writedata = find_signal("dma_writedata");
                const SignalInfo* sig_dma_read = find_signal("dma_read");
                const SignalInfo* sig_io_read_data = find_signal("io_read_data");
                const SignalInfo* sig_io_read_done = find_signal("io_read_done");
                const SignalInfo* sig_io_write_done = find_signal("io_write_done");
                const SignalInfo* sig_clk = find_signal("clk");

                const SignalInfo* sig_avm_read = find_signal("avm_read");
                const SignalInfo* sig_avm_write = find_signal("avm_write");
                const SignalInfo* sig_avm_address = find_signal("avm_address");
                const SignalInfo* sig_avm_writedata = find_signal("avm_writedata");
                const SignalInfo* sig_avm_byteenable = find_signal("avm_byteenable");
                const SignalInfo* sig_avm_burstcount = find_signal("avm_burstcount");
                const SignalInfo* sig_io_read_do = find_signal("io_read_do");
                const SignalInfo* sig_io_write_do = find_signal("io_write_do");

                write_signal_if_input(ctx, sig_a20_enable, 1u);
                write_signal_if_input(ctx, sig_cache_disable, 1u);
                write_signal_if_input(ctx, sig_interrupt_do, 0u);
                write_signal_if_input(ctx, sig_interrupt_vector, 0u);
                write_signal_if_input(ctx, sig_avm_waitrequest, 0u);
                write_signal_if_input(ctx, sig_avm_readdatavalid, 0u);
                write_signal_if_input(ctx, sig_avm_readdata, 0u);
                write_signal_if_input(ctx, sig_dma_address, 0u);
                write_signal_if_input(ctx, sig_dma_16bit, 0u);
                write_signal_if_input(ctx, sig_dma_write, 0u);
                write_signal_if_input(ctx, sig_dma_writedata, 0u);
                write_signal_if_input(ctx, sig_dma_read, 0u);
                write_signal_if_input(ctx, sig_io_read_data, 0u);
                write_signal_if_input(ctx, sig_io_read_done, 0u);
                write_signal_if_input(ctx, sig_io_write_done, 0u);
                write_signal_if_input(ctx, sig_rst_n, 0u);
                write_signal_if_input(ctx, sig_clk, 0u);

                uint32_t state_avm_waitrequest = read_signal_value(ctx, sig_avm_waitrequest);
                uint32_t state_avm_readdata = read_signal_value(ctx, sig_avm_readdata);
                uint32_t state_avm_readdatavalid = 0u;
                uint32_t state_io_read_done = 0u;
                uint32_t state_io_write_done = 0u;
                uint32_t state_io_read_data = read_signal_value(ctx, sig_io_read_data);
                uint32_t state_rst_n = 0u;

                if(sig_rst_n != nullptr) {
                  state_rst_n = read_signal_value(ctx, sig_rst_n);
                }

                #{module_name}_eval(ctx->state);

                uint32_t cycle = 0u;
                uint32_t pending_read_words = 0u;
                uint32_t pending_read_address = 0u;

                while(cycle <= cycles) {
                  if(sig_rst_n != nullptr && cycle == 4u) {
                    state_rst_n = 1u;
                  }

                  state_avm_readdatavalid = 0u;
                  state_io_read_done = 0u;
                  state_io_write_done = 0u;

                  write_signal_if_input(ctx, sig_rst_n, state_rst_n);
                  write_signal_if_input(ctx, sig_avm_readdatavalid, state_avm_readdatavalid);
                  write_signal_if_input(ctx, sig_avm_readdata, state_avm_readdata);
                  write_signal_if_input(ctx, sig_io_read_done, state_io_read_done);
                  write_signal_if_input(ctx, sig_io_write_done, state_io_write_done);

                  write_signal_if_input(ctx, sig_io_read_data, state_io_read_data);

                  if(pending_read_words > 0u) {
                    uint32_t read_value = read_memory_word(ctx->memory, pending_read_address);
                    write_signal_if_input(ctx, sig_avm_readdata, read_value);
                    write_signal_if_input(ctx, sig_avm_readdatavalid, 1u);
                    state_avm_readdatavalid = 1u;
                    state_avm_readdata = read_value;
                    if(fetch_set.find(pending_read_address) != fetch_set.end()) {
                      write_trace_fetch(trace, cycle, pending_read_address, read_value);
                    }
                    pending_read_address = (pending_read_address + 4u) & 0xFFFFFFFFu;
                    pending_read_words -= 1u;
                  }

                  if(state_avm_readdatavalid == 0u && sig_avm_readdatavalid != nullptr) {
                    write_signal(ctx, sig_avm_readdatavalid, 0u);
                  }

                  write_signal_if_input(ctx, sig_clk, 0u);
                  #{module_name}_eval(ctx->state);

                  uint32_t output_avm_read = read_signal_value(ctx, sig_avm_read) & 1u;
                  uint32_t output_avm_write = read_signal_value(ctx, sig_avm_write) & 1u;
                  uint32_t output_avm_address = read_signal_value(ctx, sig_avm_address);
                  uint32_t output_avm_writedata = read_signal_value(ctx, sig_avm_writedata);
                  uint32_t output_avm_burstcount = read_signal_value(ctx, sig_avm_burstcount);
                  uint32_t output_avm_byteenable = read_signal_value(ctx, sig_avm_byteenable);
                  uint32_t output_io_read_do = read_signal_value(ctx, sig_io_read_do);
                  uint32_t output_io_write_do = read_signal_value(ctx, sig_io_write_do);

                  if(pending_read_words == 0u && output_avm_read != 0u && state_avm_waitrequest == 0u) {
                    pending_read_address = (output_avm_address & 0x3FFFFFFFu) << 2u;
                    uint32_t burst_words = output_avm_burstcount & bit_mask(4);
                    pending_read_words = burst_words == 0u ? 1u : burst_words;
                  }

                  if(output_avm_write != 0u && state_avm_waitrequest == 0u) {
                    uint32_t address = (output_avm_address & 0x3FFFFFFFu) << 2u;
                    write_memory_word(ctx->memory, address, output_avm_writedata, output_avm_byteenable);
                    write_trace_write(
                      trace,
                      cycle,
                      address,
                      output_avm_writedata,
                      output_avm_byteenable
                    );
                  }

                  if(output_io_read_do != 0u) {
                    if(sig_io_read_data != nullptr) {
                      state_io_read_data = 0u;
                    }
                    if(sig_io_read_done != nullptr) {
                      state_io_read_done = 1u;
                    }
                  }

                  state_io_write_done = output_io_write_do != 0u ? 1u : 0u;
                  if(pending_read_words > 0u) {
                    state_avm_readdatavalid = 1u;
                  }

                  write_signal_if_input(ctx, sig_rst_n, state_rst_n);
                  write_signal_if_input(ctx, sig_avm_readdatavalid, state_avm_readdatavalid);
                  write_signal_if_input(ctx, sig_io_read_done, state_io_read_done);
                  write_signal_if_input(ctx, sig_io_write_done, state_io_write_done);
                  write_signal_if_input(ctx, sig_io_read_data, state_io_read_data);
                  write_signal_if_input(ctx, sig_clk, 1u);
                  #{module_name}_eval(ctx->state);

                  write_signal_if_input(ctx, sig_clk, 0u);
                  #{module_name}_eval(ctx->state);

                  cycle += 1u;
                }

                std::fclose(trace);
                return 0;
              }
            }
          CPP

          File.write(files.fetch(:wrapper), source)
        end

        def link_library(files:)
          cxx = if command_available?("clang++")
            "clang++"
          else
            "g++"
          end

          cmd = "#{cxx} -shared -fPIC -O2 -o #{shell(files.fetch(:lib))} #{shell(files.fetch(:wrapper))} #{shell(files.fetch(:obj))}"
          run_or_raise(cmd, "wrapper link failed")
        end

        def load_simulation_functions!
          files = build_paths
          handle = Fiddle::Handle.new(files.fetch(:lib))
          @sim_functions = {
            handle: handle,
            create: Fiddle::Function.new(handle["sim_create"], [], Fiddle::TYPE_VOIDP),
            destroy: Fiddle::Function.new(handle["sim_destroy"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID),
            eval: Fiddle::Function.new(handle["sim_eval"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID),
            has_signal: Fiddle::Function.new(handle["sim_has_signal"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT),
            poke: Fiddle::Function.new(handle["sim_poke"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT], Fiddle::TYPE_VOID),
            peek: Fiddle::Function.new(handle["sim_peek"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_UINT),
            run_program: Fiddle::Function.new(
              handle["sim_run_program"],
              [
                Fiddle::TYPE_VOIDP,
                Fiddle::TYPE_VOIDP,
                Fiddle::TYPE_VOIDP,
                Fiddle::TYPE_UINT,
                Fiddle::TYPE_VOIDP,
                Fiddle::TYPE_UINT,
                Fiddle::TYPE_UINT,
                Fiddle::TYPE_VOIDP
              ],
              Fiddle::TYPE_INT
            )
          }
        end

        def run_program_via_native(sim:, harness:, cycles:)
          program_memory = harness.program_memory_words
          fetch_addresses = harness.program_fetch_addresses.map { |entry| Integer(entry) & bit_mask(32) }
          tracked_addresses = harness.program_tracked_addresses

          trace = Dir.mktmpdir("ao486_arcilator_trace") do |tmp_dir|
            trace_path = File.join(tmp_dir, "program.trace")
            memory_ptrs = memory_pairs_to_pointer_pairs(program_memory)
            fetch_ptrs = fetch_addresses_to_pointer(fetch_addresses)

            status = sim_run_program(
              sim,
              memory_ptrs.fetch(:addresses_ptr),
              memory_ptrs.fetch(:words_ptr),
              program_memory.length,
              fetch_ptrs.fetch(:fetch_ptr),
              fetch_addresses.length,
              Integer(cycles) + 1,
              trace_path
            )
            raise "Arcilator trace generation failed (status #{status})" unless status.zero?

            harness.send(:parse_program_trace, stdout: File.read(trace_path))
          end

          {
            "pc_sequence" => Array(trace.fetch("pc_sequence")),
            "instruction_sequence" => Array(trace.fetch("instruction_sequence")),
            "memory_writes" => Array(trace.fetch("memory_writes")),
            "memory_contents" => tracked_addresses.each_with_object({}) do |address, memo|
              key = format("%08x", Integer(address) & bit_mask(32))
              memo[key] = snapshot_memory_word(program_memory, address)
            end
          }
        end

        def memory_pairs_to_pointer_pairs(program_memory)
          addresses = []
          words = []

          program_memory.each do |address, value|
            addresses << (Integer(address) & bit_mask(32))
            words << (Integer(value) & bit_mask(32))
          end

          address_bytes = addresses.pack("L<*")
          word_bytes = words.pack("L<*")

          {
            addresses_ptr: addresses.empty? ? Fiddle::Pointer::NULL : Fiddle::Pointer.to_ptr(address_bytes),
            words_ptr: words.empty? ? Fiddle::Pointer::NULL : Fiddle::Pointer.to_ptr(word_bytes),
            address_cache: address_bytes,
            word_cache: word_bytes
          }
        end

        def fetch_addresses_to_pointer(fetch_addresses)
          normalized_fetch = Array(fetch_addresses).map { |entry| Integer(entry) & bit_mask(32) }
          fetch_bytes = normalized_fetch.pack("L<*")
          {
            fetch_ptr: normalized_fetch.empty? ? Fiddle::Pointer::NULL : Fiddle::Pointer.to_ptr(fetch_bytes),
            fetch_cache: fetch_bytes
          }
        end

        def sim_run_program(sim, program_addresses, program_words, program_count, fetch_addresses, fetch_count, cycles, trace_path)
          pointer = Fiddle::Pointer.to_ptr("#{trace_path}\0")
          status = @sim_functions.fetch(:run_program).call(
            sim,
            program_addresses,
            program_words,
            program_count,
            fetch_addresses,
            fetch_count,
            cycles,
            pointer
          )
          status.to_i
        end

        def snapshot_memory_word(program_memory, address)
          Integer(program_memory.fetch(Integer(address) & bit_mask(32), 0)) & bit_mask(32)
        rescue StandardError
          0
        end

        def initial_input_state(input_names)
          state = {}
          input_names.each { |name| state[name] = 0 }
          state["a20_enable"] = 1 if input_names.include?("a20_enable")
          state["cache_disable"] = 1 if input_names.include?("cache_disable")
          state["interrupt_do"] = 0 if input_names.include?("interrupt_do")
          state["interrupt_vector"] = 0 if input_names.include?("interrupt_vector")
          state["rst_n"] = 0 if input_names.include?("rst_n")
          state["avm_waitrequest"] = 0 if input_names.include?("avm_waitrequest")
          state["avm_readdatavalid"] = 0 if input_names.include?("avm_readdatavalid")
          state["avm_readdata"] = 0 if input_names.include?("avm_readdata")
          state["dma_address"] = 0 if input_names.include?("dma_address")
          state["dma_16bit"] = 0 if input_names.include?("dma_16bit")
          state["dma_write"] = 0 if input_names.include?("dma_write")
          state["dma_writedata"] = 0 if input_names.include?("dma_writedata")
          state["dma_read"] = 0 if input_names.include?("dma_read")
          state["io_read_data"] = 0 if input_names.include?("io_read_data")
          state["io_read_done"] = 0 if input_names.include?("io_read_done")
          state["io_write_done"] = 0 if input_names.include?("io_write_done")
          state
        end

        def sample_outputs(sim:)
          {
            avm_read: read_signal(sim: sim, name: "avm_read", width: 1),
            avm_write: read_signal(sim: sim, name: "avm_write", width: 1),
            avm_address: read_signal(sim: sim, name: "avm_address", width: 30),
            avm_writedata: read_signal(sim: sim, name: "avm_writedata", width: 32),
            avm_byteenable: read_signal(sim: sim, name: "avm_byteenable", width: 4),
            avm_burstcount: read_signal(sim: sim, name: "avm_burstcount", width: 4),
            io_read_do: read_signal(sim: sim, name: "io_read_do", width: 1),
            io_write_do: read_signal(sim: sim, name: "io_write_do", width: 1)
          }
        end

        def read_signal(sim:, name:, width:)
          return 0 unless @signal_names.include?(name)

          value = peek(sim: sim, name: name)
          value & bit_mask(width)
        end

        def apply_inputs(sim:, inputs:)
          inputs.each do |name, value|
            next if name.to_s == "clk"
            next unless @signal_names.include?(name.to_s)

            poke(sim: sim, name: name.to_s, value: Integer(value))
          end
        end

        def read_memory_word(memory_words, address)
          Integer(memory_words.fetch(Integer(address) & bit_mask(32), 0)) & bit_mask(32)
        rescue StandardError
          0
        end

        def write_memory_word(memory_words, address:, data:, byteenable:)
          normalized = Integer(address) & bit_mask(32)
          current = read_memory_word(memory_words, normalized)
          merged = current
          merged = (merged & ~0x0000_00FF) | (data & 0x0000_00FF) if (byteenable & 0x1) != 0
          merged = (merged & ~0x0000_FF00) | (data & 0x0000_FF00) if (byteenable & 0x2) != 0
          merged = (merged & ~0x00FF_0000) | (data & 0x00FF_0000) if (byteenable & 0x4) != 0
          merged = (merged & ~0xFF00_0000) | (data & 0xFF00_0000) if (byteenable & 0x8) != 0
          memory_words[normalized] = merged & bit_mask(32)
        end

        def bit_mask(width)
          normalized = Integer(width)
          return 0 if normalized <= 0
          return 0xFFFF_FFFF if normalized >= 32

          (1 << normalized) - 1
        end

        def evaluate(sim)
          @sim_functions.fetch(:eval).call(sim)
        end

        def poke(sim:, name:, value:)
          ptr = Fiddle::Pointer["#{name}\0"]
          @sim_functions.fetch(:poke).call(sim, ptr, Integer(value) & 0xFFFF_FFFF)
        end

        def peek(sim:, name:)
          ptr = Fiddle::Pointer["#{name}\0"]
          Integer(@sim_functions.fetch(:peek).call(sim, ptr))
        end

        def build_paths
          ext = RbConfig::CONFIG.fetch("host_os").include?("darwin") ? "dylib" : "so"
          {
            fir: File.join(BUILD_DIR, "ao486.fir"),
            mlir: File.join(BUILD_DIR, "ao486_hw.mlir"),
            ll: File.join(BUILD_DIR, "ao486_arc.ll"),
            state: File.join(BUILD_DIR, "ao486_state.json"),
            obj: File.join(BUILD_DIR, "ao486_arc.o"),
            wrapper: File.join(BUILD_DIR, "ao486_wrapper.cpp"),
            lib: File.join(BUILD_DIR, "libao486_arcilator.#{ext}")
          }
        end

        def run_or_raise(command, error_message)
          success = system(command)
          return if success

          raise error_message
        end

        def shell(path)
          Shellwords.escape(path.to_s)
        end

        def escape_cpp_string(text)
          text.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
        end
      end
    end
  end
end
