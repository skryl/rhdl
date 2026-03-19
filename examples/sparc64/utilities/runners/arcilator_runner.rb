# frozen_string_literal: true

# SPARC64 Standard-ABI Arcilator Runner
#
# Uses the standard runner ABI (lib/rhdl/sim/native/abi.rb) with a shared
# library compiled from CIRCT arcilator output.  The C++ wrapper exports the
# canonical sim_create / sim_signal / sim_exec / sim_blob / runner_* functions
# so the library can be loaded through Arcilator::Runtime.open and validated
# with ensure_runner_abi!.
#
# Wishbone protocol logic is identical to StdVerilogRunner but uses arcilator
# state-buffer offsets instead of Verilator DUT fields.

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'

require 'rhdl/codegen'
require 'rhdl/codegen/circt/tooling'
require 'rhdl/sim/native/mlir/arcilator/runtime'

require_relative '../integration/constants'
require_relative '../integration/import_loader'
require_relative '../integration/staged_verilog_bundle'

module RHDL
  module Examples
    module SPARC64
      class ArcilatorRunner
        include Integration

        INPUT_SIGNAL_WIDTHS = {
          'sys_clock_i' => 1,
          'sys_reset_i' => 1,
          'eth_irq_i' => 1,
          'wbm_ack_i' => 1,
          'wbm_data_i' => 64
        }.freeze

        OUTPUT_SIGNAL_WIDTHS = {
          'wbm_cycle_o' => 1,
          'wbm_strobe_o' => 1,
          'wbm_we_o' => 1,
          'wbm_sel_o' => 8,
          'wbm_addr_o' => 64,
          'wbm_data_o' => 64
        }.freeze

        SIGNAL_WIDTHS = INPUT_SIGNAL_WIDTHS.merge(OUTPUT_SIGNAL_WIDTHS).freeze

        OBSERVE_FLAGS = %w[--observe-ports --observe-wires --observe-registers].freeze
        BUILD_BASE = File.expand_path('../../.arcilator_std_build', __dir__).freeze

        attr_reader :sim, :clock_count, :build_dir, :source_kind

        def initialize(fast_boot: true, import_dir: nil,
                       build_cache_root: Integration::ImportLoader::DEFAULT_BUILD_CACHE_ROOT,
                       reference_root: Integration::ImportLoader::DEFAULT_REFERENCE_ROOT,
                       import_top: Integration::ImportLoader::DEFAULT_IMPORT_TOP,
                       import_top_file: nil,
                       build_dir: nil,
                       compile_now: true,
                       jit: false,
                       cleanup_mode: :syntax_only,
                       source_kind: :rhdl_mlir,
                       source_bundle: nil,
                       source_bundle_class: Integration::StagedVerilogBundle,
                       source_bundle_options: {})
          @source_kind = normalize_source_kind(source_kind)
          @jit = !!jit
          @cleanup_mode = (cleanup_mode || :syntax_only).to_sym
          configure_source_artifacts!(
            fast_boot: fast_boot,
            import_dir: import_dir,
            build_cache_root: build_cache_root,
            reference_root: reference_root,
            import_top: import_top,
            import_top_file: import_top_file,
            source_bundle: source_bundle,
            source_bundle_class: source_bundle_class,
            source_bundle_options: source_bundle_options
          )
          @build_dir = File.expand_path(build_dir || default_build_dir)
          @clock_count = 0

          build_and_load if compile_now
        end

        def native?
          true
        end

        def simulator_type
          :hdl_arcilator
        end

        def backend
          :arcilator
        end

        def jit?
          @jit
        end

        def compiled?
          !!@sim
        end

        def runtime_contract_ready?
          true
        end

        def reset!
          @sim.reset
          @clock_count = 0
          self
        end

        def run_cycles(n)
          result = @sim.runner_run_cycles(n.to_i)
          return nil unless result

          @clock_count += result[:cycles_run].to_i
          result
        end

        def load_images(boot_image:, program_image:)
          reset!
          load_flash(boot_image, base_addr: Integration::FLASH_BOOT_BASE)
          load_memory(boot_image, base_addr: 0)
          load_memory(boot_image, base_addr: Integration::BOOT_PROM_ALIAS_BASE)
          load_memory(program_image, base_addr: Integration::PROGRAM_BASE)
          self
        end

        def load_flash(bytes, base_addr: 0)
          @sim.runner_load_rom(bytes, base_addr.to_i)
        end

        def load_memory(bytes, base_addr: 0)
          @sim.runner_load_memory(bytes, base_addr.to_i, false)
        end

        def read_memory(addr, length)
          @sim.runner_read_memory(addr.to_i, length.to_i, mapped: false)
        end

        def write_memory(addr, bytes)
          @sim.runner_write_memory(addr.to_i, bytes, mapped: false)
        end

        def read_u64(addr)
          decode_u64_be(read_memory(addr, 8))
        end

        def write_u64(addr, value)
          write_memory(addr, encode_u64_be(value))
        end

        def mailbox_status
          read_u64(Integration::MAILBOX_STATUS)
        end

        def mailbox_value
          read_u64(Integration::MAILBOX_VALUE)
        end

        def completed?
          mailbox_status != 0
        end

        def run_until_complete(max_cycles:, batch_cycles: 1_000)
          while clock_count < max_cycles.to_i
            run_cycles([batch_cycles.to_i, max_cycles.to_i - clock_count].min)
            return completion_result if completed?

            faults = unmapped_accesses
            return completion_result(faults: faults) if faults.any?
          end

          completion_result(timeout: true)
        end

        def wishbone_trace
          raw = @sim.runner_sparc64_wishbone_trace
          Integration.normalize_wishbone_trace(raw)
        end

        def unmapped_accesses
          Array(@sim.runner_sparc64_unmapped_accesses)
        end

        def debug_snapshot
          {}
        end

        private

        def normalize_source_kind(value)
          case (value || :rhdl_mlir).to_sym
          when :staged, :staged_verilog
            :staged_verilog
          when :rhdl, :rhdl_mlir
            :rhdl_mlir
          else
            raise ArgumentError,
                  "Unsupported SPARC64 Arcilator source #{value.inspect}. Use :staged_verilog or :rhdl_mlir."
          end
        end

        def configure_source_artifacts!(fast_boot:, import_dir:, build_cache_root:, reference_root:, import_top:,
                                        import_top_file:, source_bundle:, source_bundle_class:, source_bundle_options:)
          case source_kind
          when :staged_verilog
            bundle_options = { force_stub_hierarchy_sources: true }.merge(source_bundle_options)
            @source_bundle = source_bundle || source_bundle_class.new(
              fast_boot: fast_boot,
              **bundle_options
            ).build
            @top_module_name = @source_bundle.top_module
            @core_mlir_path = nil
            @import_dir = nil
          when :rhdl_mlir
            @source_bundle = nil
            @import_dir = resolve_import_dir(
              import_dir: import_dir,
              fast_boot: fast_boot,
              build_cache_root: build_cache_root,
              reference_root: reference_root,
              import_top: import_top,
              import_top_file: import_top_file
            )
            @top_module_name = import_top.to_s
            @core_mlir_path = resolve_core_mlir_path!
          else
            raise ArgumentError, "Unhandled SPARC64 Arcilator source kind #{source_kind.inspect}"
          end
        end

        def completion_result(timeout: false, faults: nil)
          trace = wishbone_trace
          faults ||= unmapped_accesses
          {
            completed: completed?,
            timeout: timeout,
            cycles: clock_count,
            boot_handoff_seen: trace.any? do |event|
              event.op == :read &&
                event.addr.to_i >= Integration::PROGRAM_BASE &&
                event.addr.to_i < Integration::FLASH_BOOT_BASE
            end,
            secondary_core_parked: faults.empty?,
            mailbox_status: mailbox_status,
            mailbox_value: mailbox_value,
            unmapped_accesses: faults,
            wishbone_trace: trace
          }
        end

        def decode_u64_be(bytes)
          arr = Array(bytes)
          return 0 if arr.length < 8

          arr[0, 8].each_with_index.reduce(0) do |acc, (byte, idx)|
            acc | (byte.to_i << ((7 - idx) * 8))
          end
        end

        def encode_u64_be(value)
          (0..7).map { |i| (value >> ((7 - i) * 8)) & 0xFF }
        end

        # ---- Import resolution ----

        def resolve_import_dir(import_dir:, fast_boot:, build_cache_root:, reference_root:, import_top:, import_top_file:)
          return File.expand_path(import_dir) if import_dir

          return Integration::ImportLoader.build_import_dir(
            build_cache_root: build_cache_root,
            reference_root: reference_root,
            import_top: import_top,
            import_top_file: import_top_file,
            fast_boot: true
          ) if fast_boot

          Integration::ImportLoader.resolve_import_dir
        end

        def resolve_core_mlir_path!
          report_path = File.join(@import_dir, 'import_report.json')
          if File.file?(report_path)
            report = JSON.parse(File.read(report_path))
            # Prefer the normalized (RHDL-raised) MLIR over the raw import MLIR.
            # The raised model correctly preserves the os2wb bridge timing
            # that arcilator needs for cycle-accurate Wishbone simulation.
            artifact_path = report.dig('artifacts', 'normalized_core_mlir_path') ||
                            report.dig('artifacts', 'core_mlir_path')
            if artifact_path && File.file?(artifact_path)
              @top_module_name = report['top'].to_s unless report['top'].to_s.empty?
              return artifact_path
            end
          end

          # Check filesystem for normalized MLIR even if not in report
          normalized_fallback = File.join(@import_dir, '.mixed_import', "#{@top_module_name}.normalized.core.mlir")
          return normalized_fallback if File.file?(normalized_fallback)

          fallback = File.join(@import_dir, '.mixed_import', "#{@top_module_name}.core.mlir")
          return fallback if File.file?(fallback)

          raise ArgumentError, "SPARC64 core MLIR not found under #{@import_dir}"
        rescue JSON::ParserError => e
          raise ArgumentError, "Invalid SPARC64 import report: #{e.message}"
        end

        def default_build_dir
          source_key =
            case source_kind
            when :staged_verilog
              @source_bundle&.build_dir || @source_bundle&.top_file || @top_module_name
            when :rhdl_mlir
              @core_mlir_path || @import_dir || @top_module_name
            end
          digest = Digest::SHA256.hexdigest("#{source_kind}|#{source_key}|std_abi|#{@cleanup_mode}")[0, 12]
          File.join(BUILD_BASE, "#{sanitize_filename(@top_module_name)}_#{digest}")
        end

        def sanitize_filename(value)
          value.to_s.gsub(/[^A-Za-z0-9_.-]/, '_')
        end

        def sanitize_macro(value)
          value.to_s.upcase.gsub(/[^A-Z0-9]+/, '_')
        end

        # ---- Build pipeline ----

        def build_and_load
          check_tools_available!
          FileUtils.mkdir_p(build_dir)
          arc_work_dir = File.join(build_dir, 'arc')
          FileUtils.mkdir_p(arc_work_dir)
          ll_path = llvm_ir_path
          state_path = state_file_path
          wrapper_path = wrapper_cpp_path
          obj_path = object_file_path
          lib_path = shared_lib_path

          if rebuild_required?(lib_path: lib_path, state_path: state_path)
            source_mlir_path = resolve_source_mlir_input!
            prepared = RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_circt_mlir(
              mlir_path: source_mlir_path,
              work_dir: arc_work_dir,
              base_name: @top_module_name,
              top: @top_module_name,
              cleanup_mode: @cleanup_mode,
              stage_index_offset: arc_stage_index_offset
            )
            raise "ARC preparation failed:\n#{prepared.dig(:arc, :stderr)}" unless prepared[:success]

            arcilator_mlir = RHDL::Codegen::CIRCT::Tooling.finalize_arc_mlir_for_arcilator!(
              arc_mlir_path: prepared.fetch(:arc_mlir_path),
              check_paths: [
                prepared[:normalized_llhd_mlir_path],
                prepared[:hwseq_mlir_path],
                prepared[:flattened_hwseq_mlir_path],
                prepared[:flattened_cleaned_hwseq_mlir_path],
                prepared[:arc_mlir_path]
              ]
            )

            cmd = RHDL::Codegen::CIRCT::Tooling.arcilator_command(
              mlir_path: arcilator_mlir,
              state_file: state_path,
              out_path: ll_path,
              extra_args: OBSERVE_FLAGS
            )
            system(*cmd) or raise 'arcilator failed'

            state_info = parse_state_file!(state_path)
            write_std_abi_wrapper(wrapper_path, state_info)
            compile_llvm_ir_object!(ll_path: ll_path, obj_path: obj_path)
            build_shared_library!(wrapper_path: wrapper_path, obj_path: obj_path, lib_path: lib_path)
          end

          load_shared_library(lib_path)
        end

        def check_tools_available!
          %w[circt-opt arcilator].each do |tool|
            raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
          end
          if source_kind == :staged_verilog
            raise LoadError, 'circt-verilog not found in PATH' unless command_available?('circt-verilog')
          end
          raise LoadError, 'No LLVM IR compiler (llc or clang) found' unless command_available?('llc') || command_available?('clang')
        end

        def resolve_source_mlir_input!
          case source_kind
          when :rhdl_mlir
            @core_mlir_path
          when :staged_verilog
            staged_mlir_path = staged_source_mlir_path
            result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
              verilog_path: @source_bundle.top_file,
              out_path: staged_mlir_path,
              extra_args: staged_verilog_import_args
            )
            return staged_mlir_path if result[:success]

            raise "Staged Verilog -> CIRCT MLIR conversion failed:\n#{result[:stdout]}\n#{result[:stderr]}"
          else
            raise ArgumentError, "Unhandled SPARC64 Arcilator source kind #{source_kind.inspect}"
          end
        end

        def staged_verilog_import_args
          [
            '--allow-use-before-declare',
            '--ignore-unknown-modules',
            '--timescale=1ns/1ps',
            "--top=#{@top_module_name}",
            *@source_bundle.verilator_args
          ]
        end

        def rebuild_required?(lib_path:, state_path:)
          return true unless File.file?(lib_path) && File.file?(state_path)

          dependency_paths.any? { |path| File.mtime(path) > File.mtime(lib_path) }
        end

        def dependency_paths
          paths = [
            __FILE__,
            File.expand_path('../../../../lib/rhdl/codegen/circt/tooling.rb', __dir__)
          ]
          case source_kind
          when :staged_verilog
            paths.concat([
                           @source_bundle.top_file,
                           *@source_bundle.source_files,
                           File.expand_path('../integration/staged_verilog_bundle.rb', __dir__)
                         ])
          when :rhdl_mlir
            paths << @core_mlir_path
          end
          paths.select { |path| path && File.exist?(path) }.uniq
        end

        def command_available?(tool)
          system("which #{tool} > /dev/null 2>&1")
        end

        def parse_state_file!(path)
          state = JSON.parse(File.read(path))
          mod = state.find { |entry| entry['name'].to_s == @top_module_name } || state.first
          raise "Arcilator state file missing module entries: #{path}" unless mod

          states = Array(mod['states'])
          signals = {}
          # Input signals may have duplicate entries (module def + instance).
          # Only write to 'input' type entries — wire copies share offsets
          # with internal signals and writing to them corrupts state.
          %w[sys_clock_i sys_reset_i eth_irq_i wbm_ack_i wbm_data_i].each do |name|
            all = locate_all_signals(states, name)
            signals[name.to_sym] = all.select { |s| s[:type] == 'input' }
            signals[name.to_sym] = all if signals[name.to_sym].empty?
          end
          %w[wbm_cycle_o wbm_strobe_o wbm_we_o wbm_addr_o wbm_data_o wbm_sel_o].each do |name|
            signals[name.to_sym] = locate_all_signals(states, name)
          end

          required = %i[sys_clock_i sys_reset_i wbm_ack_i wbm_data_i]
          missing = required.select { |key| signals[key].nil? || signals[key].empty? }
          raise "Arcilator state layout missing required signals: #{missing.join(', ')}" unless missing.empty?

          # Locate os2wb FSM state register and ALL 145-bit bridge registers for
          # CPX wake-up patching. Arcilator's lowering drops the cpx_packet output
          # register assignment in the WAKEUP state.
          fsm_reg = locate_all_signals(states, 'os2wb_inst/rt_tmp_16_5').first
          cpx_cx3_0 = locate_all_signals(states, 'sparc_0/ff_cpx/cpx_spc_data_cx3').first
          cpx_cx3_1 = locate_all_signals(states, 'sparc_1/ff_cpx/cpx_spc_data_cx3').first

          {
            module_name: mod.fetch('name'),
            state_size: mod.fetch('numStateBytes').to_i,
            signals: signals,
            fsm_offset: fsm_reg&.fetch(:offset),
            cpx_cx3_offsets: [cpx_cx3_0&.fetch(:offset), cpx_cx3_1&.fetch(:offset)].compact
          }
        end

        def locate_all_signals(states, name)
          matches = states.select { |entry| entry['name'].to_s == name.to_s }
          return [] if matches.empty?

          matches.map do |match|
            {
              name: match.fetch('name'),
              offset: match.fetch('offset').to_i,
              bits: match.fetch('numBits').to_i,
              type: match['type'].to_s
            }
          end
        end

        def compile_llvm_ir_object!(ll_path:, obj_path:)
          if darwin_host? && command_available?('clang')
            compile_object_with_clang(ll_path: ll_path, obj_path: obj_path) or raise "clang compile failed"
            return
          end

          return if compile_object_with_llc(ll_path: ll_path, obj_path: obj_path)

          raise "Neither llc nor clang available for LLVM IR compilation"
        end

        def compile_object_with_llc(ll_path:, obj_path:)
          return false unless command_available?('llc')

          cmd = String.new("llc -filetype=obj -O2 -relocation-model=pic")
          cmd << " -mtriple=#{llc_target_triple}" if llc_target_triple
          cmd << " #{ll_path} -o #{obj_path}"
          system(cmd)
        end

        def compile_object_with_clang(ll_path:, obj_path:)
          cmd = String.new("clang -c -O2 -fPIC")
          cmd << " -target #{llc_target_triple}" if llc_target_triple
          cmd << " #{ll_path} -o #{obj_path}"
          system(cmd)
        end

        def build_shared_library!(wrapper_path:, obj_path:, lib_path:)
          cxx = (darwin_host? && command_available?('clang++')) ? 'clang++' : 'g++'
          cmd = String.new("#{cxx} -shared -fPIC -O2")
          cmd << " -arch #{build_target_arch}" if build_target_arch
          cmd << " -o #{lib_path} #{wrapper_path} #{obj_path}"
          system(cmd) or raise "Shared library link failed"
        end

        def load_shared_library(lib_path)
          @sim = RHDL::Sim::Native::MLIR::Arcilator::Runtime.open(
            lib_path: lib_path,
            config: {},
            signal_widths_by_name: SIGNAL_WIDTHS,
            signal_widths_by_idx: SIGNAL_WIDTHS.values,
            backend_label: 'SPARC64 Arcilator'
          )
          ensure_runner_abi!(@sim, expected_kind: :sparc64, backend_label: 'SPARC64 Arcilator')
        end

        def ensure_runner_abi!(sim, expected_kind:, backend_label:)
          unless sim.runner_supported?
            sim.close
            raise RuntimeError, "#{backend_label} shared library does not expose runner ABI"
          end

          actual_kind = sim.runner_kind
          return if actual_kind == expected_kind

          sim.close
          raise RuntimeError, "#{backend_label} shared library exposes runner kind #{actual_kind.inspect}, expected #{expected_kind.inspect}"
        end

        def shared_lib_path
          build_artifact_path(14, "libsparc64_arc_std_sim.#{darwin_host? ? 'dylib' : 'so'}")
        end

        def staged_source_mlir_path
          build_artifact_path(1, "#{@top_module_name}.staged.core.mlir")
        end

        def llvm_ir_path
          build_artifact_path(10, "#{@top_module_name}.arc.ll")
        end

        def state_file_path
          build_artifact_path(11, "#{@top_module_name}.state.json")
        end

        def wrapper_cpp_path
          build_artifact_path(12, "#{@top_module_name}.std_abi_arc_wrapper.cpp")
        end

        def object_file_path
          build_artifact_path(13, "#{@top_module_name}.arc.o")
        end

        def arc_stage_index_offset
          source_kind == :staged_verilog ? 1 : 0
        end

        def build_artifact_path(step, suffix)
          File.join(build_dir, format('%02d.%s', step, suffix))
        end

        def darwin_host?(host_os: RbConfig::CONFIG['host_os'])
          host_os.to_s.downcase.include?('darwin')
        end

        def build_target_arch(host_os: RbConfig::CONFIG['host_os'], host_cpu: RbConfig::CONFIG['host_cpu'])
          return nil unless darwin_host?(host_os: host_os)

          cpu = host_cpu.to_s.downcase
          return 'arm64' if cpu.include?('arm64') || cpu.include?('aarch64')
          return 'x86_64' if cpu.include?('x86_64') || cpu.include?('amd64')

          nil
        end

        def llc_target_triple(host_os: RbConfig::CONFIG['host_os'], host_cpu: RbConfig::CONFIG['host_cpu'])
          arch = build_target_arch(host_os: host_os, host_cpu: host_cpu)
          return nil unless arch

          "#{arch}-apple-macosx"
        end

        # ---- C++ wrapper generation ----

        def generate_write_all_helpers(signals)
          input_names = INPUT_SIGNAL_WIDTHS.keys.map(&:to_sym)
          input_names.filter_map do |key|
            copies = signals[key]
            next if copies.nil? || copies.empty?

            macro = sanitize_macro(key)
            bits = copies.first.fetch(:bits)
            writes = copies.each_with_index.map do |_copy, idx|
              "write_bits(state, OFF_#{macro}_#{idx}, BITS_#{macro}, value);"
            end.join("\n              ")
            <<~CPP
              static inline void write_all_#{macro}(uint8_t* state, std::uint64_t value) {
                #{writes}
              }
            CPP
          end.join("\n")
        end

        def write_std_abi_wrapper(path, state_info)
          module_name = state_info.fetch(:module_name)
          state_size = state_info.fetch(:state_size)
          signals = state_info.fetch(:signals)
          fsm_offset = state_info[:fsm_offset]
          cpx_cx3_offsets = state_info[:cpx_cx3_offsets] || []
          input_signal_names = INPUT_SIGNAL_WIDTHS.keys
          output_signal_names = OUTPUT_SIGNAL_WIDTHS.keys
          input_names_csv = input_signal_names.join(',')
          output_names_csv = output_signal_names.join(',')

          signal_defs = signals.filter_map do |key, copies|
            next if copies.nil? || copies.empty?

            macro = sanitize_macro(key)
            bits = copies.first.fetch(:bits)
            lines = ["#define BITS_#{macro} #{bits}"]
            lines << "#define OFF_#{macro}_COUNT #{copies.length}"
            copies.each_with_index do |copy, idx|
              lines << "#define OFF_#{macro}_#{idx} #{copy.fetch(:offset)}"
            end
            # Primary offset for reads (first copy)
            lines << "#define OFF_#{macro} #{copies.first.fetch(:offset)}"
            lines.join("\n")
          end.join("\n")

          cpp = <<~CPP
            #include <algorithm>
            #include <cstdint>
            #include <cstdlib>
            #include <cstring>
            #include <string>
            #include <unordered_map>
            #include <vector>

            extern "C" void #{module_name}_eval(void* state);

            #{signal_defs}
            #define STATE_SIZE #{state_size}

            // CPX wake-up patch: arcilator's lowering drops the cpx_packet output
            // register assignment in the WAKEUP FSM state. We detect the FSM
            // entering WAKEUP (state 6) and inject the wake-up CPX packet directly
            // into the SPARC cores' pipeline registers.
            #{fsm_offset ? "#define OFF_OS2WB_FSM #{fsm_offset}" : "// FSM offset not found"}
            #define FSM_WAKEUP_STATE 6
            #{cpx_cx3_offsets.each_with_index.map { |off, i| "#define OFF_CPX_CX3_#{i} #{off}" }.join("\n            ")}
            #define CPX_CX3_COUNT #{cpx_cx3_offsets.length}
            #define CPX_WAKEUP_INJECT_CYCLES 4

            namespace {

            // ---- Bit-level state accessors ----
            static inline std::uint64_t read_bits(const uint8_t* state, int offset, int bits) {
              std::uint64_t value = 0;
              int bytes_needed = (bits + 7) / 8;
              for (int i = 0; i < bytes_needed && i < 8; i++)
                value |= static_cast<std::uint64_t>(state[offset + i]) << (i * 8);
              if (bits < 64) value &= (1ULL << bits) - 1ULL;
              return value;
            }

            static inline void write_bits(uint8_t* state, int offset, int bits, std::uint64_t value) {
              int bytes_needed = (bits + 7) / 8;
              for (int i = 0; i < bytes_needed && i < 8; i++)
                state[offset + i] = static_cast<uint8_t>((value >> (i * 8)) & 0xFFu);
            }

            // ---- Memory map constants ----
            constexpr std::uint64_t kFlashBootBase = 0x#{Integration::FLASH_BOOT_BASE.to_s(16).upcase}ULL;
            constexpr std::uint64_t kMailboxStatus = 0x#{Integration::MAILBOX_STATUS.to_s(16).upcase}ULL;
            constexpr std::uint64_t kMailboxValue = 0x#{Integration::MAILBOX_VALUE.to_s(16).upcase}ULL;
            constexpr std::uint64_t kPhysicalAddrMask = 0x#{Integration::PHYSICAL_ADDR_MASK.to_s(16).upcase}ULL;
            constexpr std::size_t kResetCycles = 16;

            struct WishboneTraceRecord {
              std::uint64_t cycle, op, addr, sel, write_data, read_data;
            };
            struct FaultRecord {
              std::uint64_t cycle, op, addr, sel;
            };
            struct PendingResponse {
              bool valid = false, write = false, unmapped = false;
              std::uint64_t addr = 0, data = 0, read_data = 0, sel = 0;
            };

            struct SimContext {
              uint8_t state[STATE_SIZE];
              std::unordered_map<std::uint64_t, std::uint8_t> flash;
              std::unordered_map<std::uint64_t, std::uint8_t> dram;
              std::unordered_map<std::uint64_t, std::uint8_t> mailbox_mmio;
              std::vector<WishboneTraceRecord> trace;
              std::vector<FaultRecord> faults;
              PendingResponse pending_response;
              PendingResponse deferred_request;
              std::uint64_t protected_dram_limit = 0;
              std::size_t reset_cycles_remaining = kResetCycles;
              std::uint64_t cycles = 0;
              std::string trace_json;
              std::string faults_json;
              bool trace_json_dirty = true;
              bool faults_json_dirty = true;
              int cpx_wakeup_remaining = 0;
            };

            std::uint64_t canonical_bus_addr(std::uint64_t addr) { return addr & kPhysicalAddrMask; }
            bool is_flash_addr(std::uint64_t addr) { return canonical_bus_addr(addr) >= kFlashBootBase; }
            bool is_mailbox_mmio_addr(std::uint64_t addr) {
              const std::uint64_t p = canonical_bus_addr(addr);
              return (p >= kMailboxStatus && p < kMailboxStatus + 8ULL) ||
                     (p >= kMailboxValue && p < kMailboxValue + 8ULL);
            }
            bool is_dram_addr(std::uint64_t addr) { return canonical_bus_addr(addr) < kFlashBootBase; }
            bool lane_selected(std::uint64_t sel, int lane) { return (sel & (0x80ULL >> lane)) != 0; }

            bool read_mapped_byte(SimContext* ctx, std::uint64_t addr, std::uint8_t* out) {
              const std::uint64_t physical = canonical_bus_addr(addr);
              if (is_mailbox_mmio_addr(physical)) { auto it = ctx->mailbox_mmio.find(physical); *out = it == ctx->mailbox_mmio.end() ? 0 : it->second; return true; }
              if (is_flash_addr(physical)) { auto it = ctx->flash.find(physical); *out = it == ctx->flash.end() ? 0 : it->second; return true; }
              if (is_dram_addr(physical)) { auto it = ctx->dram.find(physical); *out = it == ctx->dram.end() ? 0 : it->second; return true; }
              return false;
            }

            std::uint64_t read_wishbone_word(SimContext* ctx, std::uint64_t addr, std::uint64_t sel, bool* mapped) {
              std::uint64_t value = 0; bool any = false;
              for (int lane = 0; lane < 8; ++lane) {
                std::uint8_t byte = 0;
                if (!read_mapped_byte(ctx, addr + lane, &byte)) { if (lane_selected(sel, lane)) { if (mapped) *mapped = false; return 0; } byte = 0; }
                value |= static_cast<std::uint64_t>(byte) << ((7 - lane) * 8);
                any = any || lane_selected(sel, lane);
              }
              if (mapped) *mapped = any;
              return value;
            }

            bool write_wishbone_word(SimContext* ctx, std::uint64_t addr, std::uint64_t data, std::uint64_t sel) {
              bool any_mapped = false;
              for (int lane = 0; lane < 8; ++lane) {
                if (!lane_selected(sel, lane)) continue;
                std::uint64_t byte_addr = canonical_bus_addr(addr + lane);
                if (is_mailbox_mmio_addr(byte_addr)) { ctx->mailbox_mmio[byte_addr] = static_cast<uint8_t>((data >> ((7-lane)*8)) & 0xFF); any_mapped = true; continue; }
                if (is_flash_addr(byte_addr)) return false;
                if (!is_dram_addr(byte_addr)) return false;
                if (byte_addr < ctx->protected_dram_limit) { any_mapped = true; continue; }
                ctx->dram[byte_addr] = static_cast<uint8_t>((data >> ((7-lane)*8)) & 0xFF);
                any_mapped = true;
              }
              return any_mapped;
            }

            // Write-all helpers: write value to EVERY copy of an input signal
            #{generate_write_all_helpers(signals)}

            void drive_defaults(SimContext* ctx) {
              write_all_SYS_CLOCK_I(ctx->state, 0u);
              write_all_SYS_RESET_I(ctx->state, 0u);
              write_all_ETH_IRQ_I(ctx->state, 0u);
              write_all_WBM_ACK_I(ctx->state, 0u);
              write_all_WBM_DATA_I(ctx->state, 0u);
            }

            void clear_runtime_state(SimContext* ctx) {
              ctx->trace.clear(); ctx->faults.clear();
              ctx->pending_response = PendingResponse{};
              ctx->deferred_request = PendingResponse{};
              ctx->reset_cycles_remaining = kResetCycles; ctx->cycles = 0;
              ctx->trace_json_dirty = true; ctx->faults_json_dirty = true;
              ctx->cpx_wakeup_remaining = 0;
            }

            void apply_inputs(SimContext* ctx, bool reset_active, const PendingResponse* response) {
              write_all_SYS_CLOCK_I(ctx->state, 0u);
              write_all_SYS_RESET_I(ctx->state, reset_active ? 1u : 0u);
              write_all_ETH_IRQ_I(ctx->state, 0u);
              if (response && response->valid) {
                write_all_WBM_ACK_I(ctx->state, 1u);
                write_all_WBM_DATA_I(ctx->state, response->read_data);
              } else {
                write_all_WBM_ACK_I(ctx->state, 0u);
                write_all_WBM_DATA_I(ctx->state, 0u);
              }
            }

            PendingResponse sample_request(SimContext* ctx) {
              PendingResponse request;
              if (read_bits(ctx->state, OFF_WBM_CYCLE_O, BITS_WBM_CYCLE_O) == 0u ||
                  read_bits(ctx->state, OFF_WBM_STROBE_O, BITS_WBM_STROBE_O) == 0u) return request;
              request.valid = true;
              request.write = (read_bits(ctx->state, OFF_WBM_WE_O, BITS_WBM_WE_O) != 0u);
              request.addr = canonical_bus_addr(read_bits(ctx->state, OFF_WBM_ADDR_O, BITS_WBM_ADDR_O));
              request.data = read_bits(ctx->state, OFF_WBM_DATA_O, BITS_WBM_DATA_O);
              request.sel = read_bits(ctx->state, OFF_WBM_SEL_O, BITS_WBM_SEL_O) & 0xFFULL;
              return request;
            }

            bool requests_equal(const PendingResponse& a, const PendingResponse& b) {
              return a.valid == b.valid && a.write == b.write && a.addr == b.addr && a.data == b.data && a.sel == b.sel;
            }

            PendingResponse service_request(SimContext* ctx, const PendingResponse& request) {
              PendingResponse response = request;
              if (!request.valid) return response;
              if (request.write) { response.read_data = 0; response.unmapped = !write_wishbone_word(ctx, request.addr, request.data, request.sel); }
              else { bool mapped = false; response.read_data = read_wishbone_word(ctx, request.addr, request.sel, &mapped); response.unmapped = !mapped; }
              return response;
            }

            void record_acknowledged_response(SimContext* ctx, const PendingResponse& response) {
              if (!response.valid) return;
              if (response.unmapped) { ctx->faults.push_back({ctx->cycles, response.write?1ULL:0ULL, response.addr, response.sel}); ctx->faults_json_dirty = true; }
              ctx->trace.push_back({ctx->cycles, response.write?1ULL:0ULL, response.addr, response.sel, response.write?response.data:0ULL, response.write?0ULL:response.read_data});
              ctx->trace_json_dirty = true;
            }

            // Inject the CPX wake-up packet (145'h17000...10001) into the bridge's
            // cpx_packet output register(s) when the os2wb FSM enters WAKEUP.
            // Arcilator's lowering drops this register assignment, so we patch
            // the state buffer directly. Must be called BEFORE the rising-edge
            // eval so the wire propagates to the SPARC cores' pipeline registers.
            static void patch_cpx_wakeup_if_needed(SimContext* ctx) {
              #ifdef OFF_OS2WB_FSM
              // Detect FSM entering WAKEUP and start injection countdown
              uint8_t fsm = read_bits(ctx->state, OFF_OS2WB_FSM, 5);
              if (fsm == FSM_WAKEUP_STATE && ctx->cpx_wakeup_remaining == 0) {
                ctx->cpx_wakeup_remaining = CPX_WAKEUP_INJECT_CYCLES;
              }
              if (ctx->cpx_wakeup_remaining <= 0) return;

              // 145'h1_7000_0000_0000_0000_0000_0000_0000_0001_0001
              static const uint8_t cpx_wakeup[19] = {
                0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x70, 0x01
              };
              // Inject directly into the SPARC cores' pipeline registers
              #if CPX_CX3_COUNT >= 1
              std::memcpy(&ctx->state[OFF_CPX_CX3_0], cpx_wakeup, 19);
              #endif
              #if CPX_CX3_COUNT >= 2
              std::memcpy(&ctx->state[OFF_CPX_CX3_1], cpx_wakeup, 19);
              #endif
              ctx->cpx_wakeup_remaining--;
              #endif
            }

            void step_cycle(SimContext* ctx) {
              bool reset_active = ctx->reset_cycles_remaining > 0;

              // EVAL 1: clock LOW — let combinational logic settle
              write_all_SYS_CLOCK_I(ctx->state, 0u);
              write_all_SYS_RESET_I(ctx->state, reset_active ? 1u : 0u);
              write_all_ETH_IRQ_I(ctx->state, 0u);
              write_all_WBM_ACK_I(ctx->state, 0u);
              write_all_WBM_DATA_I(ctx->state, 0u);
              #{module_name}_eval(ctx->state);

              // EVAL 2: sample Wishbone request, service it, inject ack+data
              // (same-cycle response, like Apple2's combinational memory access)
              if (!reset_active) {
                PendingResponse req = sample_request(ctx);
                if (req.valid) {
                  PendingResponse resp = service_request(ctx, req);
                  write_all_WBM_ACK_I(ctx->state, 1u);
                  write_all_WBM_DATA_I(ctx->state, resp.read_data);
                  #{module_name}_eval(ctx->state);
                  record_acknowledged_response(ctx, resp);
                }
              }

              // EVAL 3: clock HIGH — rising edge captures state
              write_all_SYS_CLOCK_I(ctx->state, 1u);
              #{module_name}_eval(ctx->state);

              // EVAL 4: extra eval for output propagation
              #{module_name}_eval(ctx->state);

              // Patch: inject CPX wake-up packet AFTER all evals so the value
              // persists in the register until the next cycle's combinational
              // logic reads it.
              patch_cpx_wakeup_if_needed(ctx);

              ctx->cycles += 1;
              if (ctx->reset_cycles_remaining > 0) ctx->reset_cycles_remaining -= 1;
            }

            static void ensure_trace_json(SimContext* ctx) {
              if (!ctx->trace_json_dirty) return;
              std::string json = "[";
              for (std::size_t i = 0; i < ctx->trace.size(); ++i) {
                const auto& r = ctx->trace[i];
                if (i > 0) json += ',';
                char buf[256];
                std::snprintf(buf, sizeof(buf),
                  R"({"cycle":%llu,"op":"%s","addr":%llu,"sel":%llu,"write_data":%llu,"read_data":%llu})",
                  (unsigned long long)r.cycle, r.op==1?"write":"read",
                  (unsigned long long)r.addr, (unsigned long long)r.sel,
                  (unsigned long long)r.write_data, (unsigned long long)r.read_data);
                json += buf;
              }
              json += ']'; ctx->trace_json = std::move(json); ctx->trace_json_dirty = false;
            }

            static void ensure_faults_json(SimContext* ctx) {
              if (!ctx->faults_json_dirty) return;
              std::string json = "[";
              for (std::size_t i = 0; i < ctx->faults.size(); ++i) {
                const auto& f = ctx->faults[i];
                if (i > 0) json += ',';
                char buf[192];
                std::snprintf(buf, sizeof(buf),
                  R"({"cycle":%llu,"op":"%s","addr":%llu,"sel":%llu})",
                  (unsigned long long)f.cycle, f.op==1?"write":"read",
                  (unsigned long long)f.addr, (unsigned long long)f.sel);
                json += buf;
              }
              json += ']'; ctx->faults_json = std::move(json); ctx->faults_json_dirty = false;
            }

            // ---- Standard ABI constants ----
            enum { SIM_CAP_SIGNAL_INDEX = 1u << 0, SIM_CAP_RUNNER = 1u << 6 };
            enum { SIM_SIGNAL_HAS=0u, SIM_SIGNAL_GET_INDEX=1u, SIM_SIGNAL_PEEK=2u, SIM_SIGNAL_POKE=3u, SIM_SIGNAL_PEEK_INDEX=4u, SIM_SIGNAL_POKE_INDEX=5u };
            enum { SIM_EXEC_EVALUATE=0u, SIM_EXEC_TICK=1u, SIM_EXEC_TICK_FORCED=2u, SIM_EXEC_RESET=5u, SIM_EXEC_RUN_TICKS=6u, SIM_EXEC_SIGNAL_COUNT=7u, SIM_EXEC_REG_COUNT=8u };
            enum { SIM_TRACE_ENABLED=3u };
            enum { SIM_BLOB_INPUT_NAMES=0u, SIM_BLOB_OUTPUT_NAMES=1u, SIM_BLOB_SPARC64_WISHBONE_TRACE=5u, SIM_BLOB_SPARC64_UNMAPPED_ACCESSES=6u };
            enum { RUNNER_KIND_SPARC64 = 6 };
            enum { RUNNER_MEM_OP_LOAD=0u, RUNNER_MEM_OP_READ=1u, RUNNER_MEM_OP_WRITE=2u };
            enum { RUNNER_MEM_SPACE_MAIN=0u, RUNNER_MEM_SPACE_ROM=1u };
            enum { RUNNER_PROBE_KIND=0u, RUNNER_PROBE_IS_MODE=1u, RUNNER_PROBE_SIGNAL=9u };

            struct RunnerCaps { int kind; unsigned int mem_spaces, control_ops, probe_ops; };
            struct RunnerRunResult { int text_dirty, key_cleared; unsigned int cycles_run, speaker_toggles, frames_completed; };

            static const char* k_input_signal_names[] = { #{input_signal_names.map { |n| %("#{n}") }.join(", ")} };
            static const char* k_output_signal_names[] = { #{output_signal_names.map { |n| %("#{n}") }.join(", ")} };
            static const char k_input_names_csv[] = "#{input_names_csv}";
            static const char k_output_names_csv[] = "#{output_names_csv}";
            static const unsigned int k_input_signal_count = #{input_signal_names.length}u;
            static const unsigned int k_output_signal_count = #{output_signal_names.length}u;

            static inline void write_out_ulong(unsigned long* out, unsigned long v) { if (out) *out = v; }
            static unsigned int total_signal_count() { return k_input_signal_count + k_output_signal_count; }
            static const char* signal_name_from_index(unsigned int idx) {
              if (idx < k_input_signal_count) return k_input_signal_names[idx];
              idx -= k_input_signal_count;
              return idx < k_output_signal_count ? k_output_signal_names[idx] : nullptr;
            }
            static int signal_index_from_name(const char* name) {
              if (!name) return -1;
              for (unsigned int i = 0; i < k_input_signal_count; i++) if (!std::strcmp(name, k_input_signal_names[i])) return (int)i;
              for (unsigned int i = 0; i < k_output_signal_count; i++) if (!std::strcmp(name, k_output_signal_names[i])) return (int)(k_input_signal_count+i);
              return -1;
            }
            static std::size_t copy_blob(unsigned char* out, std::size_t out_len, const char* text, std::size_t len) {
              if (out && out_len && len) { std::size_t n = len < out_len ? len : out_len; std::memcpy(out, text, n); }
              return len;
            }

            }  // namespace

            extern "C" {

            void* sim_create(const char* json, std::size_t json_len, unsigned int sub_cycles, char** err_out) {
              (void)json; (void)json_len; (void)sub_cycles;
              if (err_out) *err_out = nullptr;
              SimContext* ctx = new SimContext();
              std::memset(ctx->state, 0, sizeof(ctx->state));
              // Extended reset: toggle clock for 100 cycles with reset held high
              // to fully initialize all internal pipeline stages.
              write_all_SYS_RESET_I(ctx->state, 1u);
              write_all_WBM_ACK_I(ctx->state, 0u);
              write_all_ETH_IRQ_I(ctx->state, 0u);
              for (int i = 0; i < 100; i++) {
                write_all_SYS_CLOCK_I(ctx->state, 0u);
                #{module_name}_eval(ctx->state);
                write_all_SYS_CLOCK_I(ctx->state, 1u);
                #{module_name}_eval(ctx->state);
              }
              drive_defaults(ctx);
              #{module_name}_eval(ctx->state);
              clear_runtime_state(ctx);
              return ctx;
            }
            void sim_destroy(void* sim) { delete static_cast<SimContext*>(sim); }
            void sim_free_error(char* err) { if (err) std::free(err); }
            void sim_free_string(char* str) { if (str) std::free(str); }
            void* sim_wasm_alloc(std::size_t size) { return std::malloc(size > 0 ? size : 1); }
            void sim_wasm_dealloc(void* ptr, std::size_t size) { (void)size; std::free(ptr); }

            void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              clear_runtime_state(ctx);
              drive_defaults(ctx);
              write_all_SYS_RESET_I(ctx->state, 1u);
              #{module_name}_eval(ctx->state);
            }

            void sim_eval(void* sim) { #{module_name}_eval(static_cast<SimContext*>(sim)->state); }

            void sim_poke(void* sim, const char* n, unsigned int v) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!std::strcmp(n,"sys_clock_i")) write_all_SYS_CLOCK_I(ctx->state, v);
              else if (!std::strcmp(n,"sys_reset_i")) write_all_SYS_RESET_I(ctx->state, v);
              else if (!std::strcmp(n,"eth_irq_i")) write_all_ETH_IRQ_I(ctx->state, v);
              else if (!std::strcmp(n,"wbm_ack_i")) write_all_WBM_ACK_I(ctx->state, v);
              else if (!std::strcmp(n,"wbm_data_i")) write_all_WBM_DATA_I(ctx->state, (std::uint64_t)v);
            }

            unsigned int sim_peek(void* sim, const char* n) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!std::strcmp(n,"wbm_cycle_o"))  return (unsigned int)read_bits(ctx->state, OFF_WBM_CYCLE_O, BITS_WBM_CYCLE_O);
              if (!std::strcmp(n,"wbm_strobe_o")) return (unsigned int)read_bits(ctx->state, OFF_WBM_STROBE_O, BITS_WBM_STROBE_O);
              if (!std::strcmp(n,"wbm_we_o"))     return (unsigned int)read_bits(ctx->state, OFF_WBM_WE_O, BITS_WBM_WE_O);
              if (!std::strcmp(n,"wbm_sel_o"))    return (unsigned int)(read_bits(ctx->state, OFF_WBM_SEL_O, BITS_WBM_SEL_O) & 0xFFu);
              if (!std::strcmp(n,"wbm_addr_o"))   return (unsigned int)(read_bits(ctx->state, OFF_WBM_ADDR_O, BITS_WBM_ADDR_O) & 0xFFFFFFFFu);
              if (!std::strcmp(n,"wbm_data_o"))   return (unsigned int)(read_bits(ctx->state, OFF_WBM_DATA_O, BITS_WBM_DATA_O) & 0xFFFFFFFFu);
              return 0;
            }

            int sim_get_caps(const void* sim, unsigned int* caps_out) { (void)sim; if (!caps_out) return 0; *caps_out = SIM_CAP_SIGNAL_INDEX | SIM_CAP_RUNNER; return 1; }

            int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value) {
              int resolved_idx = (name && name[0]) ? signal_index_from_name(name) : (int)idx;
              const char* resolved_name = (name && name[0]) ? name : signal_name_from_index(idx);
              switch (op) {
              case SIM_SIGNAL_HAS: write_out_ulong(out_value, resolved_idx >= 0 ? 1ul : 0ul); return resolved_idx >= 0 ? 1 : 0;
              case SIM_SIGNAL_GET_INDEX: if (resolved_idx < 0) { write_out_ulong(out_value, 0ul); return 0; } write_out_ulong(out_value, (unsigned long)resolved_idx); return 1;
              case SIM_SIGNAL_PEEK: case SIM_SIGNAL_PEEK_INDEX: if (resolved_idx < 0 || !resolved_name) { write_out_ulong(out_value, 0ul); return 0; } write_out_ulong(out_value, (unsigned long)sim_peek(sim, resolved_name)); return 1;
              case SIM_SIGNAL_POKE: case SIM_SIGNAL_POKE_INDEX: if (resolved_idx < 0 || !resolved_name) { write_out_ulong(out_value, 0ul); return 0; } sim_poke(sim, resolved_name, (unsigned int)value); write_out_ulong(out_value, 1ul); return 1;
              default: write_out_ulong(out_value, 0ul); return 0;
              }
            }

            int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, void* error_out) {
              (void)arg1; (void)error_out;
              SimContext* ctx = static_cast<SimContext*>(sim);
              switch (op) {
              case SIM_EXEC_EVALUATE: #{module_name}_eval(ctx->state); write_out_ulong(out_value, 0ul); return 1;
              case SIM_EXEC_TICK: case SIM_EXEC_TICK_FORCED: step_cycle(ctx); write_out_ulong(out_value, 0ul); return 1;
              case SIM_EXEC_RESET: sim_reset(sim); write_out_ulong(out_value, 0ul); return 1;
              case SIM_EXEC_RUN_TICKS: for (unsigned long i = 0; i < arg0; ++i) step_cycle(ctx); write_out_ulong(out_value, 0ul); return 1;
              case SIM_EXEC_SIGNAL_COUNT: write_out_ulong(out_value, (unsigned long)total_signal_count()); return 1;
              case SIM_EXEC_REG_COUNT: write_out_ulong(out_value, 0ul); return 1;
              default: write_out_ulong(out_value, 0ul); return 0;
              }
            }

            int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value) {
              (void)sim; (void)str_arg; write_out_ulong(out_value, 0ul); return (op == SIM_TRACE_ENABLED) ? 1 : 0;
            }

            unsigned long sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, unsigned long out_len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              switch (op) {
              case SIM_BLOB_INPUT_NAMES: return copy_blob(out_ptr, out_len, k_input_names_csv, sizeof(k_input_names_csv)-1);
              case SIM_BLOB_OUTPUT_NAMES: return copy_blob(out_ptr, out_len, k_output_names_csv, sizeof(k_output_names_csv)-1);
              case SIM_BLOB_SPARC64_WISHBONE_TRACE: ensure_trace_json(ctx); return copy_blob(out_ptr, out_len, ctx->trace_json.c_str(), ctx->trace_json.size());
              case SIM_BLOB_SPARC64_UNMAPPED_ACCESSES: ensure_faults_json(ctx); return copy_blob(out_ptr, out_len, ctx->faults_json.c_str(), ctx->faults_json.size());
              default: return 0u;
              }
            }

            int runner_get_caps(const void* sim, unsigned int* caps_out) {
              (void)sim; if (!caps_out) return 0;
              RunnerCaps* caps = reinterpret_cast<RunnerCaps*>(caps_out);
              caps->kind = RUNNER_KIND_SPARC64;
              caps->mem_spaces = (1u << RUNNER_MEM_SPACE_MAIN) | (1u << RUNNER_MEM_SPACE_ROM);
              caps->control_ops = 0u;
              caps->probe_ops = (1u << RUNNER_PROBE_KIND) | (1u << RUNNER_PROBE_IS_MODE) | (1u << RUNNER_PROBE_SIGNAL);
              return 1;
            }

            unsigned long runner_mem(void* sim, unsigned int op, unsigned int space, unsigned long offset,
                                     unsigned char* data, unsigned long len, unsigned int flags) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (!ctx || !data || len == 0u) return 0u;
              (void)flags;
              if (op == RUNNER_MEM_OP_LOAD) {
                if (space == RUNNER_MEM_SPACE_ROM) { for (unsigned long i = 0; i < len; ++i) ctx->flash[canonical_bus_addr(offset+i)] = data[i]; return len; }
                if (space == RUNNER_MEM_SPACE_MAIN) {
                  for (unsigned long i = 0; i < len; ++i) ctx->dram[canonical_bus_addr(offset+i)] = data[i];
                  if (canonical_bus_addr(offset) == 0ULL) ctx->protected_dram_limit = std::max<std::uint64_t>(ctx->protected_dram_limit, len);
                  return len;
                }
                return 0u;
              }
              if (op == RUNNER_MEM_OP_READ) {
                for (unsigned long i = 0; i < len; ++i) { std::uint8_t byte = 0; read_mapped_byte(ctx, offset+i, &byte); data[i] = byte; }
                return len;
              }
              if (op == RUNNER_MEM_OP_WRITE) {
                if (space == RUNNER_MEM_SPACE_MAIN) { for (unsigned long i = 0; i < len; ++i) ctx->dram[offset+i] = data[i]; return len; }
                return 0u;
              }
              return 0u;
            }

            int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, void* result_out) {
              SimContext* ctx = static_cast<SimContext*>(sim); if (!ctx) return 0;
              (void)key_data; (void)key_ready; (void)mode;
              for (unsigned int i = 0; i < cycles; ++i) step_cycle(ctx);
              RunnerRunResult* result = static_cast<RunnerRunResult*>(result_out);
              if (result) { result->text_dirty = 0; result->key_cleared = 0; result->cycles_run = cycles; result->speaker_toggles = 0; result->frames_completed = 0; }
              return 1;
            }

            int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1) { (void)sim; (void)op; (void)arg0; (void)arg1; return 0; }

            unsigned long long runner_probe(void* sim, unsigned int op, unsigned int arg0) {
              if (!sim) return 0ull;
              if (op == RUNNER_PROBE_KIND) return (unsigned long long)RUNNER_KIND_SPARC64;
              if (op == RUNNER_PROBE_IS_MODE) return 1ull;
              if (op == RUNNER_PROBE_SIGNAL) { const char* name = signal_name_from_index(arg0); return name ? (unsigned long long)sim_peek(sim, name) : 0ull; }
              return 0ull;
            }

            }  // extern "C"
          CPP

          File.write(path, cpp)
        end
      end
    end
  end
end
