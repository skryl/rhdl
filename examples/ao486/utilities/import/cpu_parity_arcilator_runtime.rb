# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require 'etc'

require 'rhdl/codegen'
require_relative 'cpu_parity_package'
require_relative 'cpu_parity_runtime'
require_relative '../../../../lib/rhdl/codegen/circt/tooling'

module RHDL
  module Examples
    module AO486
      module Import
        # Arcilator-side runtime helper for the parity-oriented imported AO486 CPU package.
        #
        # This runner mirrors the Verilator parity harness, but drives the
        # flattened ARC artifact through the generated Arcilator state layout.
        class CpuParityArcilatorRuntime
          DEFAULT_MAX_CYCLES = CpuParityRuntime::DEFAULT_MAX_CYCLES
          FINAL_STATE_SIGNALS = CpuParityRuntime::FINAL_STATE_SIGNALS.freeze

          FetchWordEvent = Struct.new(:address, :word, keyword_init: true)
          FetchGroupEvent = Struct.new(:address, :bytes, keyword_init: true)
          FetchPcGroupEvent = Struct.new(:pc, :bytes, keyword_init: true)
          StepEvent = Struct.new(:eip, :consumed, :bytes, keyword_init: true)

          attr_reader :memory

          def self.build_from_cleaned_mlir(mlir_text, work_dir:)
            parity = CpuParityPackage.from_cleaned_mlir(mlir_text)
            raise ArgumentError, Array(parity[:diagnostics]).join("\n") unless parity[:success]

            new(work_dir: work_dir).tap do |runner|
              runner.send(:build!, parity.fetch(:mlir))
            end
          end

          def initialize(work_dir:)
            @work_dir = File.expand_path(work_dir)
            @memory = Hash.new(0)
            @binary_path = nil
            @linked_bc_path = nil
          end

          def clear_memory!
            @memory.clear
          end

          def load_bytes(base, bytes)
            Array(bytes).each_with_index do |byte, idx|
              @memory[base + idx] = byte.to_i & 0xFF
            end
          end

          def read_bytes(base, length)
            Array.new(length) { |idx| @memory[base + idx] || 0 }
          end

          def run_fetch_words(max_cycles: DEFAULT_MAX_CYCLES)
            run_fetch_trace(max_cycles: max_cycles).map(&:word)
          end

          def run_fetch_trace(max_cycles: DEFAULT_MAX_CYCLES)
            output = run_harness(max_cycles: max_cycles)
            parse_fetch_trace(output)
          end

          def run_fetch_groups(max_cycles: DEFAULT_MAX_CYCLES)
            run_fetch_trace(max_cycles: max_cycles).map do |event|
              FetchGroupEvent.new(
                address: event.address,
                bytes: word_to_bytes(event.word)
              )
            end
          end

          def run_fetch_pc_groups(max_cycles: DEFAULT_MAX_CYCLES)
            run_fetch_groups(max_cycles: max_cycles).map do |event|
              next if event.address < CpuParityRuntime::STARTUP_CS_BASE

              FetchPcGroupEvent.new(
                pc: event.address - CpuParityRuntime::STARTUP_CS_BASE,
                bytes: event.bytes
              )
            end.compact
          end

          def run_step_trace(max_cycles: DEFAULT_MAX_CYCLES)
            parse_step_trace(run_harness(max_cycles: max_cycles))
          end

          def run_final_state(max_cycles: DEFAULT_MAX_CYCLES)
            parse_final_state(run_harness(max_cycles: max_cycles))
          end

          private

          def build!(mlir_text)
            FileUtils.mkdir_p(@work_dir)

            mlir_path = File.join(@work_dir, 'cpu_parity.mlir')
            state_path = File.join(@work_dir, 'cpu_parity.state.json')
            ll_path = File.join(@work_dir, 'cpu_parity.ll')
            harness_path = File.join(@work_dir, 'cpu_parity_arc_tb.cpp')
            obj_path = File.join(@work_dir, 'cpu_parity_arc.o')
            bin_path = File.join(@work_dir, 'cpu_parity_arc')
            linked_bc_path = File.join(@work_dir, 'cpu_parity_arc.bc')

            File.write(mlir_path, mlir_text)

            prepared = RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_circt_mlir(
              mlir_path: mlir_path,
              work_dir: File.join(@work_dir, 'arc'),
              base_name: 'cpu_parity',
              top: 'ao486'
            )
            raise "ARC preparation failed:\n#{prepared.dig(:arc, :stderr)}" unless prepared[:success]

            stdout, stderr, status = Open3.capture3(
              'arcilator',
              prepared.fetch(:arc_mlir_path),
              '--observe-ports',
              '--observe-wires',
              '--observe-registers',
              "--state-file=#{state_path}",
              '-o',
              ll_path
            )
            raise "Arcilator compile failed:\n#{stdout}\n#{stderr}" unless status.success?

            state_info = parse_state_file!(state_path)
            write_arcilator_trace_harness(
              path: harness_path,
              module_name: state_info.fetch(:module_name),
              state_size: state_info.fetch(:state_size),
              offsets: state_info.fetch(:offsets)
            )
            prepare_harness_executable!(
              ll_path: ll_path,
              harness_path: harness_path,
              obj_path: obj_path,
              bin_path: bin_path,
              linked_bc_path: linked_bc_path
            )
          end

          def parse_state_file!(path)
            state = JSON.parse(File.read(path))
            mod = state.find { |entry| entry['name'].to_s == 'ao486' } || state.first
            raise "Arcilator state file missing module entries: #{path}" unless mod

            states = Array(mod['states'])
            offsets = {
              clk: state_offset(states, 'clk', preferred_type: 'input'),
              rst_n: state_offset(states, 'rst_n', preferred_type: 'input'),
              a20_enable: state_offset(states, 'a20_enable', preferred_type: 'input'),
              cache_disable: state_offset(states, 'cache_disable', preferred_type: 'input'),
              interrupt_do: state_offset(states, 'interrupt_do', preferred_type: 'input'),
              interrupt_vector: state_offset(states, 'interrupt_vector', preferred_type: 'input'),
              avm_waitrequest: state_offset(states, 'avm_waitrequest', preferred_type: 'input'),
              avm_readdatavalid: state_offset(states, 'avm_readdatavalid', preferred_type: 'input'),
              avm_readdata: state_offset(states, 'avm_readdata', preferred_type: 'input'),
              dma_address: state_offset(states, 'dma_address', preferred_type: 'input'),
              dma_16bit: state_offset(states, 'dma_16bit', preferred_type: 'input'),
              dma_write: state_offset(states, 'dma_write', preferred_type: 'input'),
              dma_writedata: state_offset(states, 'dma_writedata', preferred_type: 'input'),
              dma_read: state_offset(states, 'dma_read', preferred_type: 'input'),
              io_read_data: state_offset(states, 'io_read_data', preferred_type: 'input'),
              io_read_done: state_offset(states, 'io_read_done', preferred_type: 'input'),
              io_write_done: state_offset(states, 'io_write_done', preferred_type: 'input'),
              avm_read: state_offset(states, 'avm_read', preferred_type: 'output'),
              avm_write: state_offset(states, 'avm_write', preferred_type: 'output'),
              avm_address: state_offset(states, 'avm_address', preferred_type: 'output'),
              avm_burstcount: state_offset(states, 'avm_burstcount', preferred_type: 'output'),
              avm_writedata: state_offset(states, 'avm_writedata', preferred_type: 'output'),
              avm_byteenable: state_offset(states, 'avm_byteenable', preferred_type: 'output'),
              trace_retired: state_offset(states, 'trace_retired', preferred_type: 'output'),
              trace_wr_eip: state_offset(states, 'trace_wr_eip', preferred_type: 'output'),
              trace_wr_consumed: state_offset(states, 'trace_wr_consumed', preferred_type: 'output'),
              trace_arch_new_export: state_offset(states, 'trace_arch_new_export', preferred_type: 'output'),
              trace_arch_eax: state_offset(states, 'trace_arch_eax', preferred_type: 'output'),
              trace_arch_ebx: state_offset(states, 'trace_arch_ebx', preferred_type: 'output'),
              trace_arch_ecx: state_offset(states, 'trace_arch_ecx', preferred_type: 'output'),
              trace_arch_edx: state_offset(states, 'trace_arch_edx', preferred_type: 'output'),
              trace_arch_esi: state_offset(states, 'trace_arch_esi', preferred_type: 'output'),
              trace_arch_edi: state_offset(states, 'trace_arch_edi', preferred_type: 'output'),
              trace_arch_esp: state_offset(states, 'trace_arch_esp', preferred_type: 'output'),
              trace_arch_ebp: state_offset(states, 'trace_arch_ebp', preferred_type: 'output'),
              trace_arch_eip: state_offset(states, 'trace_arch_eip', preferred_type: 'output'),
              trace_wr_hlt_in_progress: state_offset(states, 'trace_wr_hlt_in_progress', preferred_type: 'output'),
              trace_wr_finished: state_offset(states, 'trace_wr_finished', preferred_type: 'output'),
              trace_wr_ready: state_offset(states, 'trace_wr_ready', preferred_type: 'output')
            }

            required = offsets.select { |key, _| !FINAL_STATE_SIGNALS.include?(key.to_s) }
                              .keys
            missing = required.select { |key| offsets[key].nil? }
            unless missing.empty?
              raise "Arcilator state layout missing required signals: #{missing.join(', ')}"
            end

            {
              module_name: mod.fetch('name'),
              state_size: mod.fetch('numStateBytes').to_i,
              offsets: offsets
            }
          end

          def state_offset(states, *names, preferred_type: nil)
            by_name = states.each_with_object({}) do |entry, acc|
              (acc[entry.fetch('name')] ||= []) << entry
            end
            names.each do |name|
              entries = by_name[name]
              next unless entries

              preferred_entry = preferred_type && entries.find { |entry| entry['type'] == preferred_type }
              return (preferred_entry || entries.last).fetch('offset')
            end

            states.each do |entry|
              entry_name = entry.fetch('name').to_s
              return entry.fetch('offset') if names.any? { |name| entry_name.end_with?(name) || entry_name.include?(name) }
            end

            nil
          end

          def prepare_harness_executable!(ll_path:, harness_path:, obj_path:, bin_path:, linked_bc_path:)
            if llvm_lli_available?
              harness_ll_path = harness_path.sub(/\.cpp\z/, '.harness.ll')
              run_cmd!(['clang++', '-std=c++17', '-O0', '-S', '-emit-llvm', harness_path, '-o', harness_ll_path])
              run_cmd!(['llvm-link', ll_path, harness_ll_path, '-o', linked_bc_path])
              @linked_bc_path = linked_bc_path
              @binary_path = nil
            else
              compile_llvm_ir_object!(ll_path: ll_path, obj_path: obj_path)
              run_cmd!(['c++', '-std=c++17', '-O0', harness_path, obj_path, '-o', bin_path])
              @binary_path = bin_path
              @linked_bc_path = nil
            end
          end

          def llvm_lli_available?
            tool_available?('lli') && tool_available?('llvm-link') && tool_available?('clang++')
          end

          def compile_llvm_ir_object!(ll_path:, obj_path:)
            if tool_available?('clang')
              run_cmd!(['clang', '-c', '-O0', '-fPIC', ll_path, '-o', obj_path])
            elsif tool_available?('llc')
              run_cmd!(['llc', '-filetype=obj', '-O0', '-relocation-model=pic', ll_path, '-o', obj_path])
            else
              raise 'Neither clang nor llc is available for Arcilator harness object compilation'
            end
          end

          def run_harness(max_cycles:)
            memory_path = File.join(@work_dir, 'memory_init.txt')
            write_memory_file(memory_path)

            stdout, stderr, status =
              if @linked_bc_path
                compile_threads = [Etc.nprocessors, 8].compact.min
                Open3.capture3(
                  'lli',
                  '--jit-kind=orc-lazy',
                  "--compile-threads=#{compile_threads}",
                  '-O0',
                  @linked_bc_path,
                  memory_path,
                  max_cycles.to_i.to_s
                )
              else
                Open3.capture3(@binary_path, memory_path, max_cycles.to_i.to_s)
              end
            raise "Arcilator parity runtime failed:\n#{stdout}\n#{stderr}" unless status.success?

            @memory = read_memory_file(memory_path)
            stdout
          end

          def write_memory_file(path)
            lines = @memory.keys.sort.map do |addr|
              format('%08X %02X', addr, @memory.fetch(addr))
            end
            File.write(path, lines.join("\n") + "\n")
          end

          def read_memory_file(path)
            mem = Hash.new(0)
            File.readlines(path, chomp: true).each do |line|
              next if line.empty?

              addr_hex, byte_hex = line.split(/\s+/, 2)
              next unless addr_hex && byte_hex

              mem[addr_hex.to_i(16)] = byte_hex.to_i(16) & 0xFF
            end
            mem
          end

          def parse_fetch_trace(stdout)
            stdout.lines.filter_map do |line|
              match = line.to_s.strip.match(/\Afetch_word 0x([0-9A-Fa-f]+) 0x([0-9A-Fa-f]+)\z/)
              next unless match

              FetchWordEvent.new(
                address: match[1].to_i(16),
                word: match[2].to_i(16)
              )
            end
          end

          def parse_step_trace(stdout)
            stdout.lines.filter_map do |line|
              match = line.to_s.strip.match(/\Astep_trace 0x([0-9A-Fa-f]+) 0x([0-9A-Fa-f]+)\z/)
              next unless match

              wr_eip = match[1].to_i(16)
              consumed = match[2].to_i(16)
              start_eip = wr_eip - consumed

              StepEvent.new(
                eip: start_eip,
                consumed: consumed,
                bytes: read_bytes(CpuParityRuntime::STARTUP_CS_BASE + start_eip, consumed)
              )
            end
          end

          def parse_final_state(stdout)
            stdout.lines.each_with_object({}) do |line, state|
              match = line.to_s.strip.match(/\Afinal_state ([A-Za-z0-9_]+) 0x([0-9A-Fa-f]+)\z/)
              next unless match

              state[match[1]] = match[2].to_i(16)
            end
          end

          def word_to_bytes(word)
            Array.new(4) { |idx| (word >> (idx * 8)) & 0xFF }
          end

          def run_cmd!(cmd)
            stdout, stderr, status = Open3.capture3(*cmd)
            return if status.success?

            detail = [stdout, stderr].join("\n").lines.first(120).join
            raise "Command failed: #{cmd.join(' ')}\n#{detail}"
          end

          def tool_available?(cmd)
            if defined?(HdlToolchain) && HdlToolchain.respond_to?(:which)
              return !HdlToolchain.which(cmd).nil?
            end

            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
              path = File.join(dir, cmd)
              File.file?(path) && File.executable?(path)
            end
          end

          def write_arcilator_trace_harness(path:, module_name:, state_size:, offsets:)
            eval_symbol = "#{module_name}_eval"
            source = <<~CPP
              #include <cstdint>
              #include <cstdio>
              #include <cstdlib>
              #include <cstring>
              #include <fstream>
              #include <iomanip>
              #include <string>
              #include <unordered_map>
              #include <vector>

              extern "C" void #{eval_symbol}(void* state);

              static constexpr int STATE_SIZE = #{state_size};
              static constexpr int OFF_CLK = #{offsets[:clk] || -1};
              static constexpr int OFF_RST_N = #{offsets[:rst_n] || -1};
              static constexpr int OFF_A20_ENABLE = #{offsets[:a20_enable] || -1};
              static constexpr int OFF_CACHE_DISABLE = #{offsets[:cache_disable] || -1};
              static constexpr int OFF_INTERRUPT_DO = #{offsets[:interrupt_do] || -1};
              static constexpr int OFF_INTERRUPT_VECTOR = #{offsets[:interrupt_vector] || -1};
              static constexpr int OFF_AVM_WAITREQUEST = #{offsets[:avm_waitrequest] || -1};
              static constexpr int OFF_AVM_READDATAVALID = #{offsets[:avm_readdatavalid] || -1};
              static constexpr int OFF_AVM_READDATA = #{offsets[:avm_readdata] || -1};
              static constexpr int OFF_DMA_ADDRESS = #{offsets[:dma_address] || -1};
              static constexpr int OFF_DMA_16BIT = #{offsets[:dma_16bit] || -1};
              static constexpr int OFF_DMA_WRITE = #{offsets[:dma_write] || -1};
              static constexpr int OFF_DMA_WRITEDATA = #{offsets[:dma_writedata] || -1};
              static constexpr int OFF_DMA_READ = #{offsets[:dma_read] || -1};
              static constexpr int OFF_IO_READ_DATA = #{offsets[:io_read_data] || -1};
              static constexpr int OFF_IO_READ_DONE = #{offsets[:io_read_done] || -1};
              static constexpr int OFF_IO_WRITE_DONE = #{offsets[:io_write_done] || -1};
              static constexpr int OFF_AVM_READ = #{offsets[:avm_read] || -1};
              static constexpr int OFF_AVM_WRITE = #{offsets[:avm_write] || -1};
              static constexpr int OFF_AVM_ADDRESS = #{offsets[:avm_address] || -1};
              static constexpr int OFF_AVM_BURSTCOUNT = #{offsets[:avm_burstcount] || -1};
              static constexpr int OFF_AVM_WRITEDATA = #{offsets[:avm_writedata] || -1};
              static constexpr int OFF_AVM_BYTEENABLE = #{offsets[:avm_byteenable] || -1};
              static constexpr int OFF_TRACE_RETIRED = #{offsets[:trace_retired] || -1};
              static constexpr int OFF_TRACE_WR_EIP = #{offsets[:trace_wr_eip] || -1};
              static constexpr int OFF_TRACE_WR_CONSUMED = #{offsets[:trace_wr_consumed] || -1};
              static constexpr int OFF_TRACE_ARCH_NEW_EXPORT = #{offsets[:trace_arch_new_export] || -1};
              static constexpr int OFF_TRACE_ARCH_EAX = #{offsets[:trace_arch_eax] || -1};
              static constexpr int OFF_TRACE_ARCH_EBX = #{offsets[:trace_arch_ebx] || -1};
              static constexpr int OFF_TRACE_ARCH_ECX = #{offsets[:trace_arch_ecx] || -1};
              static constexpr int OFF_TRACE_ARCH_EDX = #{offsets[:trace_arch_edx] || -1};
              static constexpr int OFF_TRACE_ARCH_ESI = #{offsets[:trace_arch_esi] || -1};
              static constexpr int OFF_TRACE_ARCH_EDI = #{offsets[:trace_arch_edi] || -1};
              static constexpr int OFF_TRACE_ARCH_ESP = #{offsets[:trace_arch_esp] || -1};
              static constexpr int OFF_TRACE_ARCH_EBP = #{offsets[:trace_arch_ebp] || -1};
              static constexpr int OFF_TRACE_ARCH_EIP = #{offsets[:trace_arch_eip] || -1};
              static constexpr int OFF_TRACE_WR_HLT_IN_PROGRESS = #{offsets[:trace_wr_hlt_in_progress] || -1};
              static constexpr int OFF_TRACE_WR_FINISHED = #{offsets[:trace_wr_finished] || -1};
              static constexpr int OFF_TRACE_WR_READY = #{offsets[:trace_wr_ready] || -1};

              struct BurstState {
                bool active = false;
                bool started = false;
                uint32_t base = 0;
                int beat_index = 0;
                int beats_total = 8;
              };

              static std::unordered_map<uint32_t, uint8_t> load_memory(const char* path) {
                std::unordered_map<uint32_t, uint8_t> mem;
                std::ifstream in(path);
                if (!in) {
                  std::fprintf(stderr, "failed to open memory file: %s\\n", path);
                  std::exit(2);
                }

                uint32_t addr = 0;
                unsigned value = 0;
                while (in >> std::hex >> addr >> value) {
                  mem[addr] = static_cast<uint8_t>(value & 0xFFu);
                }
                return mem;
              }

              static uint32_t little_endian_word(const std::unordered_map<uint32_t, uint8_t>& mem, uint32_t addr) {
                uint32_t word = 0;
                for (int idx = 0; idx < 4; ++idx) {
                  auto it = mem.find(addr + static_cast<uint32_t>(idx));
                  uint32_t byte = (it == mem.end()) ? 0u : static_cast<uint32_t>(it->second);
                  word |= (byte << (idx * 8));
                }
                return word;
              }

              static void write_word(std::unordered_map<uint32_t, uint8_t>& mem, uint32_t addr, uint32_t word, uint32_t byteenable) {
                for (int idx = 0; idx < 4; ++idx) {
                  if (((byteenable >> idx) & 1u) == 0u) continue;
                  mem[addr + static_cast<uint32_t>(idx)] = static_cast<uint8_t>((word >> (idx * 8)) & 0xFFu);
                }
              }

              static void save_memory(const char* path, const std::unordered_map<uint32_t, uint8_t>& mem) {
                std::ofstream out(path, std::ios::trunc);
                if (!out) {
                  std::fprintf(stderr, "failed to write memory file: %s\\n", path);
                  std::exit(3);
                }

                out << std::uppercase << std::hex << std::setfill('0');
                for (const auto& entry : mem) {
                  out << std::setw(8) << static_cast<unsigned>(entry.first)
                      << ' '
                      << std::setw(2) << static_cast<unsigned>(entry.second)
                      << "\\n";
                }
              }

              static inline bool has(int off) {
                return off >= 0;
              }

              static inline void set_bit(std::vector<uint8_t>& state, int off, uint8_t value) {
                if (has(off)) state[off] = value & 0x1;
              }

              static inline void set_u8(std::vector<uint8_t>& state, int off, uint8_t value) {
                if (has(off)) state[off] = value;
              }

              static inline void set_u16(std::vector<uint8_t>& state, int off, uint16_t value) {
                if (has(off)) std::memcpy(&state[off], &value, sizeof(uint16_t));
              }

              static inline void set_u24(std::vector<uint8_t>& state, int off, uint32_t value) {
                if (!has(off)) return;
                state[off] = static_cast<uint8_t>(value & 0xFFu);
                state[off + 1] = static_cast<uint8_t>((value >> 8) & 0xFFu);
                state[off + 2] = static_cast<uint8_t>((value >> 16) & 0xFFu);
              }

              static inline void set_u32(std::vector<uint8_t>& state, int off, uint32_t value) {
                if (has(off)) std::memcpy(&state[off], &value, sizeof(uint32_t));
              }

              static inline uint8_t get_u8(const std::vector<uint8_t>& state, int off) {
                return has(off) ? state[off] : 0;
              }

              static inline uint8_t get_bit(const std::vector<uint8_t>& state, int off) {
                return get_u8(state, off) & 0x1;
              }

              static inline uint32_t get_u32(const std::vector<uint8_t>& state, int off) {
                if (!has(off)) return 0;
                uint32_t value = 0;
                std::memcpy(&value, &state[off], sizeof(uint32_t));
                return value;
              }

              static void apply_defaults(std::vector<uint8_t>& state) {
                set_bit(state, OFF_A20_ENABLE, 1);
                set_bit(state, OFF_CACHE_DISABLE, 1);
                set_bit(state, OFF_INTERRUPT_DO, 0);
                set_u8(state, OFF_INTERRUPT_VECTOR, 0);
                set_bit(state, OFF_AVM_WAITREQUEST, 0);
                set_bit(state, OFF_AVM_READDATAVALID, 0);
                set_u32(state, OFF_AVM_READDATA, 0);
                set_u24(state, OFF_DMA_ADDRESS, 0);
                set_bit(state, OFF_DMA_16BIT, 0);
                set_bit(state, OFF_DMA_WRITE, 0);
                set_u16(state, OFF_DMA_WRITEDATA, 0);
                set_bit(state, OFF_DMA_READ, 0);
                set_u32(state, OFF_IO_READ_DATA, 0);
                set_bit(state, OFF_IO_READ_DONE, 0);
                set_bit(state, OFF_IO_WRITE_DONE, 0);
              }

              int main(int argc, char** argv) {
                if (argc < 3) {
                  std::fprintf(stderr, "usage: %s <memory_init.txt> <max_cycles>\\n", argv[0]);
                  return 2;
                }

                auto mem = load_memory(argv[1]);
                int max_cycles = std::atoi(argv[2]);
                std::vector<uint8_t> state(STATE_SIZE, 0);
                apply_defaults(state);

                auto eval = [&]() { #{eval_symbol}(state.data()); };

                set_bit(state, OFF_CLK, 0);
                set_bit(state, OFF_RST_N, 0);
                eval();
                set_bit(state, OFF_CLK, 1);
                eval();

                BurstState burst;
                uint32_t prev_trace_wr_eip = 0;
                uint32_t prev_trace_wr_consumed = 0;

                auto emit_step_trace = [&]() {
                  uint32_t trace_wr_eip = get_u32(state, OFF_TRACE_WR_EIP);
                  uint32_t trace_wr_consumed = get_u8(state, OFF_TRACE_WR_CONSUMED) & 0xF;
                  if (get_bit(state, OFF_TRACE_RETIRED) &&
                      !(trace_wr_eip == 0 && trace_wr_consumed == 0) &&
                      !(trace_wr_eip == prev_trace_wr_eip && trace_wr_consumed == prev_trace_wr_consumed)) {
                    std::printf("step_trace 0x%08X 0x%08X\\n", trace_wr_eip, trace_wr_consumed);
                    prev_trace_wr_eip = trace_wr_eip;
                    prev_trace_wr_consumed = trace_wr_consumed;
                  }
                };

                for (int cycle = 0; cycle < max_cycles; ++cycle) {
                  bool deliver_read_beat = burst.active && burst.started;
                  if (deliver_read_beat) {
                    uint32_t addr = burst.base + static_cast<uint32_t>(burst.beat_index * 4);
                    set_bit(state, OFF_AVM_READDATAVALID, 1);
                    set_u32(state, OFF_AVM_READDATA, little_endian_word(mem, addr));
                  } else {
                    set_bit(state, OFF_AVM_READDATAVALID, 0);
                    set_u32(state, OFF_AVM_READDATA, 0);
                  }

                  set_bit(state, OFF_CLK, 0);
                  set_bit(state, OFF_RST_N, 1);
                  eval();

                  if (!burst.active && get_bit(state, OFF_AVM_READ)) {
                    burst.active = true;
                    burst.started = false;
                    burst.base = get_u32(state, OFF_AVM_ADDRESS) << 2;
                    burst.beat_index = 0;
                    uint32_t burstcount = get_u8(state, OFF_AVM_BURSTCOUNT) & 0xF;
                    burst.beats_total = burstcount > 0 ? static_cast<int>(burstcount) : 1;
                  }

                  set_bit(state, OFF_CLK, 1);
                  set_bit(state, OFF_RST_N, 1);
                  eval();
                  emit_step_trace();

                  if (get_bit(state, OFF_AVM_WRITE)) {
                    uint32_t addr = get_u32(state, OFF_AVM_ADDRESS) << 2;
                    write_word(mem, addr, get_u32(state, OFF_AVM_WRITEDATA), get_u8(state, OFF_AVM_BYTEENABLE) & 0xF);
                  }

                  if (burst.active) {
                    if (deliver_read_beat) {
                      uint32_t addr = burst.base + static_cast<uint32_t>(burst.beat_index * 4);
                      std::printf("fetch_word 0x%08X 0x%08X\\n", addr, get_u32(state, OFF_AVM_READDATA));
                      burst.beat_index += 1;
                      if (burst.beat_index >= burst.beats_total) burst.active = false;
                    } else {
                      burst.started = true;
                    }
                  }
                }

                save_memory(argv[1], mem);
                std::printf("final_state trace_arch_new_export 0x%08X\\n", get_bit(state, OFF_TRACE_ARCH_NEW_EXPORT));
                std::printf("final_state trace_arch_eax 0x%08X\\n", get_u32(state, OFF_TRACE_ARCH_EAX));
                std::printf("final_state trace_arch_ebx 0x%08X\\n", get_u32(state, OFF_TRACE_ARCH_EBX));
                std::printf("final_state trace_arch_ecx 0x%08X\\n", get_u32(state, OFF_TRACE_ARCH_ECX));
                std::printf("final_state trace_arch_edx 0x%08X\\n", get_u32(state, OFF_TRACE_ARCH_EDX));
                std::printf("final_state trace_arch_esi 0x%08X\\n", get_u32(state, OFF_TRACE_ARCH_ESI));
                std::printf("final_state trace_arch_edi 0x%08X\\n", get_u32(state, OFF_TRACE_ARCH_EDI));
                std::printf("final_state trace_arch_esp 0x%08X\\n", get_u32(state, OFF_TRACE_ARCH_ESP));
                std::printf("final_state trace_arch_ebp 0x%08X\\n", get_u32(state, OFF_TRACE_ARCH_EBP));
                std::printf("final_state trace_arch_eip 0x%08X\\n", get_u32(state, OFF_TRACE_ARCH_EIP));
                std::printf("final_state trace_wr_eip 0x%08X\\n", get_u32(state, OFF_TRACE_WR_EIP));
                std::printf("final_state trace_wr_consumed 0x%08X\\n", get_u8(state, OFF_TRACE_WR_CONSUMED) & 0xF);
                std::printf("final_state trace_wr_hlt_in_progress 0x%08X\\n", get_bit(state, OFF_TRACE_WR_HLT_IN_PROGRESS));
                std::printf("final_state trace_wr_finished 0x%08X\\n", get_bit(state, OFF_TRACE_WR_FINISHED));
                std::printf("final_state trace_wr_ready 0x%08X\\n", get_bit(state, OFF_TRACE_WR_READY));
                std::printf("final_state trace_retired 0x%08X\\n", get_bit(state, OFF_TRACE_RETIRED));
                return 0;
              }
            CPP

            File.write(path, source)
          end
        end
      end
    end
  end
end
