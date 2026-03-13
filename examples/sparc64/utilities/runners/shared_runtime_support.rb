# frozen_string_literal: true

require 'fiddle'
require 'rbconfig'

require_relative '../integration/constants'

module RHDL
  module Examples
    module SPARC64
      module SharedRuntimeSupport
        TRACE_WORDS = 6
        FAULT_WORDS = 4

        module AdapterMethods
          include Integration

          def reset!
            ensure_runtime_built! if respond_to?(:ensure_runtime_built!, true)
            @sim_reset.call(@sim_ctx)
            self
          end

          def load_images(boot_image:, program_image:)
            ensure_runtime_built! if respond_to?(:ensure_runtime_built!, true)
            @sim_clear_memory_fn.call(@sim_ctx)
            load_flash(boot_image, base_addr: Integration::FLASH_BOOT_BASE)
            load_memory(boot_image, base_addr: 0)
            load_memory(boot_image, base_addr: Integration::BOOT_PROM_ALIAS_BASE)
            load_memory(program_image, base_addr: Integration::PROGRAM_BASE)
            reset!
            self
          end

          def load_flash(bytes, base_addr:)
            ensure_runtime_built! if respond_to?(:ensure_runtime_built!, true)
            payload = pack_bytes(bytes)
            @sim_load_flash_fn.call(@sim_ctx, Fiddle::Pointer[payload], base_addr.to_i, payload.bytesize)
          end

          def load_memory(bytes, base_addr:)
            ensure_runtime_built! if respond_to?(:ensure_runtime_built!, true)
            payload = pack_bytes(bytes)
            @sim_load_memory_fn.call(@sim_ctx, Fiddle::Pointer[payload], base_addr.to_i, payload.bytesize)
          end

          def read_memory(addr, length)
            ensure_runtime_built! if respond_to?(:ensure_runtime_built!, true)
            len = length.to_i
            return [] if len <= 0

            buffer = Fiddle::Pointer.malloc(len)
            copied = @sim_read_memory_fn.call(@sim_ctx, addr.to_i, buffer, len).to_i
            buffer.to_s(copied).bytes
          end

          def write_memory(addr, bytes)
            ensure_runtime_built! if respond_to?(:ensure_runtime_built!, true)
            payload = pack_bytes(bytes)
            @sim_write_memory_fn.call(@sim_ctx, addr.to_i, Fiddle::Pointer[payload], payload.bytesize).to_i
          end

          def mailbox_status
            decode_u64_be(read_memory(Integration::MAILBOX_STATUS, 8))
          end

          def mailbox_value
            decode_u64_be(read_memory(Integration::MAILBOX_VALUE, 8))
          end

          def wishbone_trace
            ensure_runtime_built! if respond_to?(:ensure_runtime_built!, true)
            count = @sim_wishbone_trace_count_fn.call(@sim_ctx).to_i
            return [] if count <= 0

            buffer = Fiddle::Pointer.malloc(count * TRACE_WORDS * 8)
            copied = @sim_copy_wishbone_trace_fn.call(@sim_ctx, buffer, count).to_i
            unpack_u64_words(buffer, copied * TRACE_WORDS).each_slice(TRACE_WORDS).map do |cycle, op, addr, sel, write_data, read_data|
              write = !op.zero?
              {
                cycle: cycle,
                op: write ? :write : :read,
                addr: addr,
                sel: sel,
                write_data: write ? write_data : nil,
                read_data: write ? nil : read_data
              }
            end
          end

          def unmapped_accesses
            ensure_runtime_built! if respond_to?(:ensure_runtime_built!, true)
            count = @sim_unmapped_access_count_fn.call(@sim_ctx).to_i
            return [] if count <= 0

            buffer = Fiddle::Pointer.malloc(count * FAULT_WORDS * 8)
            copied = @sim_copy_unmapped_accesses_fn.call(@sim_ctx, buffer, count).to_i
            unpack_u64_words(buffer, copied * FAULT_WORDS).each_slice(FAULT_WORDS).map do |cycle, op, addr, sel|
              {
                cycle: cycle,
                op: op.zero? ? :read : :write,
                addr: addr,
                sel: sel
              }
            end
          end

          def decode_u64_be(bytes)
            Array(bytes).first(8).reduce(0) { |acc, byte| (acc << 8) | (byte.to_i & 0xFF) }
          end

          def pack_bytes(bytes)
            if bytes.is_a?(String)
              bytes.b
            elsif bytes.respond_to?(:pack)
              Array(bytes).pack('C*')
            else
              Array(bytes).pack('C*')
            end
          end

          def unpack_u64_words(pointer, count)
            pointer.to_s(count * 8).unpack('Q<*')
          end

          def sanitize_identifier(value)
            value.to_s.gsub(/[^A-Za-z0-9_]/, '_')
          end

          def write_file_if_changed(path, content)
            return false if File.exist?(path) && File.read(path) == content

            File.write(path, content)
            true
          end

          def bind_runtime_library(handle, include_debug_snapshot: false)
            @lib = handle
            @sim_create = Fiddle::Function.new(@lib['sim_create'], [], Fiddle::TYPE_VOIDP)
            @sim_destroy = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_clear_memory_fn = Fiddle::Function.new(@lib['sim_clear_memory'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_reset = Fiddle::Function.new(@lib['sim_reset'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
            @sim_load_flash_fn = Fiddle::Function.new(
              @lib['sim_load_flash'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_UINT],
              Fiddle::TYPE_VOID
            )
            @sim_load_memory_fn = Fiddle::Function.new(
              @lib['sim_load_memory'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_UINT],
              Fiddle::TYPE_VOID
            )
            @sim_read_memory_fn = Fiddle::Function.new(
              @lib['sim_read_memory'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_write_memory_fn = Fiddle::Function.new(
              @lib['sim_write_memory'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_run_cycles_fn = Fiddle::Function.new(
              @lib['sim_run_cycles'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_wishbone_trace_count_fn = Fiddle::Function.new(
              @lib['sim_wishbone_trace_count'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )
            @sim_copy_wishbone_trace_fn = Fiddle::Function.new(
              @lib['sim_copy_wishbone_trace'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            @sim_unmapped_access_count_fn = Fiddle::Function.new(
              @lib['sim_unmapped_access_count'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_UINT
            )
            @sim_copy_unmapped_accesses_fn = Fiddle::Function.new(
              @lib['sim_copy_unmapped_accesses'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
              Fiddle::TYPE_UINT
            )
            if include_debug_snapshot
              @sim_copy_debug_snapshot_fn = Fiddle::Function.new(
                @lib['sim_copy_debug_snapshot'],
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
                Fiddle::TYPE_UINT
              )
            end
            @sim_ctx = @sim_create.call
          end

          def load_runtime_library!(lib_path, include_debug_snapshot: false)
            raise LoadError, "SPARC64 runtime shared library not found: #{lib_path}" unless File.exist?(lib_path)

            bind_runtime_library(SharedRuntimeSupport.dlopen_library(lib_path), include_debug_snapshot: include_debug_snapshot)
          end
        end

        module_function

        def dlopen_library(lib_path)
          sign_darwin_shared_library(lib_path)
          Fiddle.dlopen(lib_path)
        rescue Fiddle::DLError
          raise unless RbConfig::CONFIG['host_os'] =~ /darwin/

          sign_darwin_shared_library(lib_path)
          sleep 0.1
          Fiddle.dlopen(lib_path)
        end

        def sign_darwin_shared_library(lib_path)
          return unless RbConfig::CONFIG['host_os'] =~ /darwin/
          return unless File.exist?(lib_path)
          return unless command_available?('codesign')

          system('codesign', '--force', '--sign', '-', '--timestamp=none', lib_path, out: File::NULL, err: File::NULL)
        end

        def command_available?(tool)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            exe = File.join(path, tool)
            File.executable?(exe) && !File.directory?(exe)
          end
        end

        def wrapper_header(include_debug_snapshot: false)
          debug_decl = include_debug_snapshot ? "unsigned int sim_copy_debug_snapshot(void* sim, unsigned long long* out_words, unsigned int max_words);\n" : ''
          <<~HEADER
            #ifndef SPARC64_SIM_WRAPPER_H
            #define SPARC64_SIM_WRAPPER_H

            #ifdef __cplusplus
            extern "C" {
            #endif

            void* sim_create(void);
            void sim_destroy(void* sim);
            void sim_clear_memory(void* sim);
            void sim_reset(void* sim);
            void sim_load_flash(void* sim, const unsigned char* data, unsigned long long base_addr, unsigned int len);
            void sim_load_memory(void* sim, const unsigned char* data, unsigned long long base_addr, unsigned int len);
            unsigned int sim_read_memory(void* sim, unsigned long long addr, unsigned char* out, unsigned int len);
            unsigned int sim_write_memory(void* sim, unsigned long long addr, const unsigned char* data, unsigned int len);
            unsigned int sim_run_cycles(void* sim, unsigned int n_cycles);
            unsigned int sim_wishbone_trace_count(void* sim);
            unsigned int sim_copy_wishbone_trace(void* sim, unsigned long long* out_words, unsigned int max_records);
            unsigned int sim_unmapped_access_count(void* sim);
            unsigned int sim_copy_unmapped_accesses(void* sim, unsigned long long* out_words, unsigned int max_records);
            #{debug_decl}#ifdef __cplusplus
            }
            #endif

            #endif
          HEADER
        end

        def build_wrapper_cpp(includes:, context_fields:, backend_helpers:, sim_create_impl:, sim_destroy_impl:,
                              sim_reset_impl:, include_debug_snapshot: false, debug_words: 0, debug_copy_impl: nil)
          debug_const = include_debug_snapshot ? "constexpr unsigned int kDebugWords = #{debug_words};\n" : ''
          debug_copy = include_debug_snapshot ? "#{debug_copy_impl}\n\nunsigned int sim_copy_debug_snapshot(void* sim, unsigned long long* out_words, unsigned int max_words) {\n  SimContext* ctx = static_cast<SimContext*>(sim);\n  return copy_debug_snapshot(ctx, out_words, max_words);\n}\n" : ''

          <<~CPP
            #{includes}

            namespace {
            constexpr std::uint64_t kFlashBootBase = 0x#{Integration::FLASH_BOOT_BASE.to_s(16).upcase}ULL;
            constexpr std::uint64_t kMailboxStatus = 0x#{Integration::MAILBOX_STATUS.to_s(16).upcase}ULL;
            constexpr std::uint64_t kMailboxValue = 0x#{Integration::MAILBOX_VALUE.to_s(16).upcase}ULL;
            constexpr std::uint64_t kPhysicalAddrMask = 0x#{Integration::PHYSICAL_ADDR_MASK.to_s(16).upcase}ULL;
            constexpr std::uint64_t kTraceOpRead = 0;
            constexpr std::uint64_t kTraceOpWrite = 1;
            constexpr std::size_t kResetCycles = 4;
            #{debug_const}struct WishboneTraceRecord {
              std::uint64_t cycle;
              std::uint64_t op;
              std::uint64_t addr;
              std::uint64_t sel;
              std::uint64_t write_data;
              std::uint64_t read_data;
            };

            struct FaultRecord {
              std::uint64_t cycle;
              std::uint64_t op;
              std::uint64_t addr;
              std::uint64_t sel;
            };

            struct PendingResponse {
              bool valid = false;
              bool write = false;
              bool unmapped = false;
              std::uint64_t addr = 0;
              std::uint64_t data = 0;
              std::uint64_t read_data = 0;
              std::uint64_t sel = 0;
            };

            static inline size_t signal_num_bytes(unsigned int num_bits) {
              return (num_bits + 7u) / 8u;
            }

            static inline void write_bits(std::uint8_t* state, unsigned int offset, unsigned int num_bits, std::uint64_t value) {
              size_t num_bytes = signal_num_bytes(num_bits);
              memset(&state[offset], 0, num_bytes);
              size_t copy_bytes = num_bytes < sizeof(value) ? num_bytes : sizeof(value);
              memcpy(&state[offset], &value, copy_bytes);
              if (num_bits != 0u && (num_bits & 7u) != 0u) {
                std::uint8_t mask = static_cast<std::uint8_t>((1u << (num_bits & 7u)) - 1u);
                state[offset + num_bytes - 1u] &= mask;
              }
            }

            static inline std::uint64_t read_bits(const std::uint8_t* state, unsigned int offset, unsigned int num_bits) {
              std::uint64_t value = 0;
              size_t num_bytes = signal_num_bytes(num_bits);
              size_t copy_bytes = num_bytes < sizeof(value) ? num_bytes : sizeof(value);
              memcpy(&value, &state[offset], copy_bytes);
              if (num_bits < 64u && num_bits != 0u) {
                value &= ((std::uint64_t{1} << num_bits) - 1u);
              }
              return value;
            }

            struct SimContext {
              #{context_fields}
              std::unordered_map<std::uint64_t, std::uint8_t> flash;
              std::unordered_map<std::uint64_t, std::uint8_t> dram;
              std::unordered_map<std::uint64_t, std::uint8_t> mailbox_mmio;
              std::vector<WishboneTraceRecord> trace;
              std::vector<FaultRecord> faults;
              PendingResponse pending_response;
              std::uint64_t protected_dram_limit = 0;
              std::size_t reset_cycles_remaining = kResetCycles;
              std::uint64_t cycles = 0;
            };

            std::uint64_t canonical_bus_addr(std::uint64_t addr) {
              return addr & kPhysicalAddrMask;
            }

            bool is_flash_addr(std::uint64_t addr) {
              return canonical_bus_addr(addr) >= kFlashBootBase;
            }

            bool is_mailbox_mmio_addr(std::uint64_t addr) {
              const std::uint64_t physical = canonical_bus_addr(addr);
              return (physical >= kMailboxStatus && physical < (kMailboxStatus + 8ULL)) ||
                     (physical >= kMailboxValue && physical < (kMailboxValue + 8ULL));
            }

            bool is_dram_addr(std::uint64_t addr) {
              return canonical_bus_addr(addr) < kFlashBootBase;
            }

            bool lane_selected(std::uint64_t sel, int lane) {
              return (sel & (0x80ULL >> lane)) != 0;
            }

            std::uint8_t read_dram_byte(SimContext* ctx, std::uint64_t addr) {
              auto it = ctx->dram.find(addr);
              return it == ctx->dram.end() ? 0 : it->second;
            }

            std::uint8_t read_mailbox_mmio_byte(SimContext* ctx, std::uint64_t addr) {
              auto it = ctx->mailbox_mmio.find(addr);
              return it == ctx->mailbox_mmio.end() ? 0 : it->second;
            }

            bool read_mapped_byte(SimContext* ctx, std::uint64_t addr, std::uint8_t* out) {
              const std::uint64_t physical = canonical_bus_addr(addr);
              if (is_mailbox_mmio_addr(physical)) {
                *out = read_mailbox_mmio_byte(ctx, physical);
                return true;
              }
              if (is_flash_addr(physical)) {
                auto it = ctx->flash.find(physical);
                *out = it == ctx->flash.end() ? 0 : it->second;
                return true;
              }
              if (is_dram_addr(physical)) {
                *out = read_dram_byte(ctx, physical);
                return true;
              }
              return false;
            }

            std::uint64_t read_wishbone_word(SimContext* ctx, std::uint64_t addr, std::uint64_t sel, bool* mapped) {
              std::uint64_t value = 0;
              bool any_selected = false;
              for (int lane = 0; lane < 8; ++lane) {
                std::uint8_t byte = 0;
                if (!read_mapped_byte(ctx, addr + static_cast<std::uint64_t>(lane), &byte)) {
                  if (lane_selected(sel, lane)) {
                    if (mapped) *mapped = false;
                    return 0;
                  }
                  byte = 0;
                }
                value |= static_cast<std::uint64_t>(byte) << ((7 - lane) * 8);
                any_selected = any_selected || lane_selected(sel, lane);
              }
              if (mapped) *mapped = any_selected;
              return value;
            }

            bool write_wishbone_word(SimContext* ctx, std::uint64_t addr, std::uint64_t data, std::uint64_t sel) {
              bool any_mapped = false;
              for (int lane = 0; lane < 8; ++lane) {
                if (!lane_selected(sel, lane)) {
                  continue;
                }
                std::uint64_t byte_addr = canonical_bus_addr(addr + static_cast<std::uint64_t>(lane));
                if (is_mailbox_mmio_addr(byte_addr)) {
                  std::uint8_t byte = static_cast<std::uint8_t>((data >> ((7 - lane) * 8)) & 0xFFULL);
                  ctx->mailbox_mmio[byte_addr] = byte;
                  any_mapped = true;
                  continue;
                }
                if (is_flash_addr(byte_addr)) {
                  return false;
                }
                if (!is_dram_addr(byte_addr)) {
                  return false;
                }
                if (byte_addr < ctx->protected_dram_limit) {
                  any_mapped = true;
                  continue;
                }
                std::uint8_t byte = static_cast<std::uint8_t>((data >> ((7 - lane) * 8)) & 0xFFULL);
                ctx->dram[byte_addr] = byte;
                any_mapped = true;
              }
              return any_mapped;
            }

            void clear_runtime_state(SimContext* ctx) {
              ctx->trace.clear();
              ctx->faults.clear();
              ctx->pending_response = PendingResponse{};
              ctx->reset_cycles_remaining = kResetCycles;
              ctx->cycles = 0;
            }

            bool requests_equal(const PendingResponse& lhs, const PendingResponse& rhs) {
              return lhs.valid == rhs.valid &&
                     lhs.write == rhs.write &&
                     lhs.addr == rhs.addr &&
                     lhs.data == rhs.data &&
                     lhs.sel == rhs.sel;
            }

            PendingResponse service_request(SimContext* ctx, const PendingResponse& request) {
              PendingResponse response = request;
              if (!request.valid) {
                return response;
              }
              if (request.write) {
                response.read_data = 0;
                response.unmapped = !write_wishbone_word(ctx, request.addr, request.data, request.sel);
              } else {
                bool mapped = false;
                response.read_data = read_wishbone_word(ctx, request.addr, request.sel, &mapped);
                response.unmapped = !mapped;
              }
              return response;
            }

            void record_acknowledged_response(SimContext* ctx, const PendingResponse& response) {
              if (!response.valid) {
                return;
              }

              if (response.unmapped) {
                ctx->faults.push_back(FaultRecord{
                  ctx->cycles,
                  response.write ? kTraceOpWrite : kTraceOpRead,
                  response.addr,
                  response.sel
                });
              }

              ctx->trace.push_back(WishboneTraceRecord{
                ctx->cycles,
                response.write ? kTraceOpWrite : kTraceOpRead,
                response.addr,
                response.sel,
                response.write ? response.data : 0ULL,
                response.write ? 0ULL : response.read_data
              });
            }

            #{backend_helpers}
            }  // namespace

            extern "C" {
            #{sim_create_impl}

            #{sim_destroy_impl}

            void sim_clear_memory(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              ctx->flash.clear();
              ctx->dram.clear();
              ctx->mailbox_mmio.clear();
              ctx->protected_dram_limit = 0;
              clear_runtime_state(ctx);
            }

            #{sim_reset_impl}

            void sim_load_flash(void* sim, const unsigned char* data, unsigned long long base_addr, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len; ++i) {
                ctx->flash[canonical_bus_addr(base_addr + i)] = data[i];
              }
            }

            void sim_load_memory(void* sim, const unsigned char* data, unsigned long long base_addr, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len; ++i) {
                ctx->dram[canonical_bus_addr(base_addr + i)] = data[i];
              }
              if (canonical_bus_addr(base_addr) == 0ULL) {
                ctx->protected_dram_limit = std::max<std::uint64_t>(ctx->protected_dram_limit, static_cast<std::uint64_t>(len));
              }
            }

            unsigned int sim_read_memory(void* sim, unsigned long long addr, unsigned char* out, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len; ++i) {
                std::uint8_t byte = 0;
                read_mapped_byte(ctx, addr + i, &byte);
                out[i] = byte;
              }
              return len;
            }

            unsigned int sim_write_memory(void* sim, unsigned long long addr, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len; ++i) {
                ctx->dram[addr + i] = data[i];
              }
              return len;
            }

            unsigned int sim_run_cycles(void* sim, unsigned int n_cycles) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int ran = 0; ran < n_cycles; ++ran) {
                step_cycle(ctx);
              }
              return n_cycles;
            }

            unsigned int sim_wishbone_trace_count(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return static_cast<unsigned int>(ctx->trace.size());
            }

            unsigned int sim_copy_wishbone_trace(void* sim, unsigned long long* out_words, unsigned int max_records) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              unsigned int count = std::min<unsigned int>(max_records, static_cast<unsigned int>(ctx->trace.size()));
              for (unsigned int i = 0; i < count; ++i) {
                const auto& record = ctx->trace[i];
                out_words[i * 6 + 0] = record.cycle;
                out_words[i * 6 + 1] = record.op;
                out_words[i * 6 + 2] = record.addr;
                out_words[i * 6 + 3] = record.sel;
                out_words[i * 6 + 4] = record.write_data;
                out_words[i * 6 + 5] = record.read_data;
              }
              return count;
            }

            unsigned int sim_unmapped_access_count(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return static_cast<unsigned int>(ctx->faults.size());
            }

            unsigned int sim_copy_unmapped_accesses(void* sim, unsigned long long* out_words, unsigned int max_records) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              unsigned int count = std::min<unsigned int>(max_records, static_cast<unsigned int>(ctx->faults.size()));
              for (unsigned int i = 0; i < count; ++i) {
                const auto& record = ctx->faults[i];
                out_words[i * 4 + 0] = record.cycle;
                out_words[i * 4 + 1] = record.op;
                out_words[i * 4 + 2] = record.addr;
                out_words[i * 4 + 3] = record.sel;
              }
              return count;
            }

            #{debug_copy}}  // extern "C"
          CPP
        end
      end
    end
  end
end
