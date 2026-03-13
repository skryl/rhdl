# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'

require 'rhdl/codegen'
require 'rhdl/sim/native/ir/simulator'

require_relative '../integration/constants'
require_relative '../integration/image_builder'
require_relative '../integration/import_loader'

module RHDL
  module Examples
    module SPARC64
      class IrRunner
        include Integration
        COMPILER_MAX_SIGNAL_WIDTH = 128

        attr_reader :sim, :clock_count, :backend, :compiler_mode, :import_dir

        def initialize(backend: :compile, import_dir: nil, top: 'S1Top', component_class: nil,
                       sim_factory: nil, strict_runner_kind: true, trace_reader: nil, fault_reader: nil,
                       fast_boot: false, compiler_mode: :rustc)
          @backend = backend.to_sym
          @compiler_mode = normalize_compiler_mode(compiler_mode)
          @import_dir = import_dir && Integration::ImportLoader.resolve_import_dir(import_dir: import_dir)
          @component_class = component_class || Integration::ImportLoader.load_component_class(
            top: top,
            import_dir: @import_dir,
            fast_boot: fast_boot
          )
          @import_dir ||= Integration::ImportLoader.loaded_from if component_class.nil?
          @sim = sim_factory ? sim_factory.call : build_simulator(@component_class, @backend)
          @trace_reader = trace_reader || default_trace_reader
          @fault_reader = fault_reader || default_fault_reader
          @clock_count = 0
          @wishbone_trace = []
          @unmapped_accesses = []
          ensure_sparc64_runner! if strict_runner_kind
        end

        def native?
          @sim.native?
        end

        def simulator_type
          @sim.simulator_type
        end

        def reset!
          @sim.reset
          @clock_count = 0
          @wishbone_trace = []
          @unmapped_accesses = []
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
          # Match the staged-Verilog harness: the boot shim is mirrored into
          # low DRAM as well as the 0x8000 boot-prom alias so early uncached
          # startup fetches see the same bytes on both runner paths.
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

            @unmapped_accesses = Array(@fault_reader.call(@sim))
            return completion_result if @unmapped_accesses.any?
          end

          completion_result(timeout: true)
        end

        def wishbone_trace
          @wishbone_trace = Array(@trace_reader.call(@sim))
          Integration.normalize_wishbone_trace(@wishbone_trace)
        end

        def unmapped_accesses
          @unmapped_accesses = Array(@fault_reader.call(@sim))
          Array(@unmapped_accesses).dup
        end

        def debug_snapshot
          {
            reset: {
              cycle_counter: clock_count,
              mailbox_status: mailbox_status,
              mailbox_value: mailbox_value
            },
            bridge: compact_hash({
              state: peek_first('os2wb_inst__state', 'os2wb_inst_state'),
              cpu: peek_first('os2wb_inst__cpu', 'os2wb_inst_cpu'),
              cpx_ready: peek_bool('os2wb_inst__cpx_ready', 'os2wb_inst_cpx_ready'),
              pcx_req_d: peek_first('os2wb_inst__pcx_req_d', 'os2wb_inst_pcx_req_d'),
              wb_cycle: peek_bool('os2wb_inst__wb_cycle', 'os2wb_inst_wb_cycle'),
              wb_strobe: peek_bool('os2wb_inst__wb_strobe', 'os2wb_inst_wb_strobe'),
              wb_we: peek_bool('os2wb_inst__wb_we', 'os2wb_inst_wb_we'),
              wb_sel: peek_first('os2wb_inst__wb_sel', 'os2wb_inst_wb_sel'),
              wb_addr: peek_first('os2wb_inst__wb_addr', 'os2wb_inst_wb_addr'),
              wb_data_o: peek_first('os2wb_inst__wb_data_o', 'os2wb_inst_wb_data_o')
            }),
            thread0: thread_debug_snapshot(0),
            thread1: thread_debug_snapshot(1),
            ifq: compact_hash({
              lsu_ifu_pcxpkt_ack_d: peek_bool(
                'sparc_0__ifu__ifqctl__lsu_ifu_pcxpkt_ack_d',
                'sparc_0__ifu__lsu_ifu_pcxpkt_ack_d',
                'sparc_0__lsu__qctl1__lsu_ifu_pcxpkt_ack_d'
              ),
              ifu_lsu_pcxreq_d: peek_bool(
                'sparc_0__ifu__ifqctl__ifu_lsu_pcxreq_d',
                'sparc_0__ifu__ifu_lsu_pcxreq_d',
                'sparc_0__lsu__qctl1__ifu_lsu_pcxreq_d'
              ),
              mil0_state: peek_first(
                'sparc_0__ifu__ifqctl__mil0_state',
                'sparc_0__ifu__ifqdp__mil0_state'
              )
            }),
            irf: compact_hash({
              old_agp: peek_first(
                'sparc_0__exu__irf__old_agp_d1',
                'sparc_0__exu__irf__bw_r_irf_core__old_agp_d1'
              ),
              new_agp: peek_first(
                'sparc_0__exu__irf__new_agp_d2',
                'sparc_0__exu__irf__bw_r_irf_core__new_agp_d2'
              ),
              register02: register_debug_snapshot(2),
              register03: register_debug_snapshot(3)
            })
          }
        end

        private

        def build_simulator(component_class, backend)
          with_compiler_env do
            json = cached_runtime_json_payload(component_class) ||
                   RHDL::Sim::Native::IR.sim_json(component_class.to_flat_circt_nodes, backend: backend)
            RHDL::Sim::Native::IR::Simulator.new(json, backend: backend)
          end
        end

        def cached_runtime_json_payload(component_class)
          path = ensure_runtime_json_cache_path!(component_class)
          return nil unless path && File.file?(path)

          File.read(path)
        end

        def ensure_runtime_json_cache_path!(component_class)
          return nil unless import_dir

          artifact_path = runtime_json_path_from_report
          return artifact_path if artifact_path && File.file?(artifact_path)

          verilog_name = component_class.respond_to?(:verilog_module_name) ? component_class.verilog_module_name.to_s : nil
          return nil if verilog_name.nil? || verilog_name.empty?

          runtime_json_path = File.join(import_dir, '.mixed_import', "#{verilog_name}.runtime.json")
          require 'rhdl/codegen/circt/runtime_json' unless defined?(RHDL::Codegen::CIRCT::RuntimeJSON)
          FileUtils.mkdir_p(File.dirname(runtime_json_path))
          File.open(runtime_json_path, 'w') do |io|
            RHDL::Codegen::CIRCT::RuntimeJSON.dump_to_io(component_class.to_flat_circt_nodes, io, compact_exprs: true)
          end
          update_runtime_json_path_in_report(runtime_json_path)
          runtime_json_path
        end

        def runtime_json_path_from_report
          report = read_import_report
          artifact_path = report.dig('artifacts', 'runtime_json_path')
          return nil if artifact_path.nil? || artifact_path.empty?
          signature = report.dig('artifacts', 'runtime_json_export_signature')
          return File.expand_path(artifact_path, import_dir) if signature.nil? || signature.empty?
          return nil unless signature == runtime_json_export_signature

          File.expand_path(artifact_path, import_dir)
        end

        def update_runtime_json_path_in_report(runtime_json_path)
          report_path = import_report_path
          return unless report_path && File.file?(report_path)

          report = read_import_report
          report['artifacts'] ||= {}
          report['artifacts']['runtime_json_path'] = runtime_json_path
          report['artifacts']['runtime_json_export_signature'] = runtime_json_export_signature
          File.write(report_path, JSON.pretty_generate(report))
        rescue JSON::GeneratorError
          nil
        end

        def read_import_report
          report_path = import_report_path
          return {} unless report_path && File.file?(report_path)

          JSON.parse(File.read(report_path))
        rescue JSON::ParserError
          {}
        end

        def import_report_path
          return nil unless import_dir

          File.join(import_dir, 'import_report.json')
        end

        def runtime_json_export_signature
          @runtime_json_export_signature ||= begin
            runtime_json_file = File.expand_path('../../../../lib/rhdl/codegen/circt/runtime_json.rb', __dir__)
            Digest::SHA256.hexdigest([
              Digest::SHA256.file(runtime_json_file).hexdigest,
              'compact_exprs=true'
            ].join("\n"))
          end
        end

        def normalize_runtime_modules_for_validation(nodes_or_package)
          require 'rhdl/codegen/circt/runtime_json' unless defined?(RHDL::Codegen::CIRCT::RuntimeJSON)
          RHDL::Codegen::CIRCT::RuntimeJSON.normalized_runtime_modules_from_input(
            nodes_or_package,
            compact_exprs: true
          )
        end

        def validate_compiler_width_support!(nodes_or_package)
          scan = scan_overwide_runtime_ir(nodes_or_package)
          return if scan[:literal].nil?

          message = +"Native IR compiler backend currently rejects non-zero literals wider than #{COMPILER_MAX_SIGNAL_WIDTH} bits"
          if scan[:max_width] > COMPILER_MAX_SIGNAL_WIDTH
            message << "; imported design reaches #{scan[:max_width]} bits"
            message << " at #{scan[:max_width_context]}" if scan[:max_width_context]
          end
          if scan[:literal]
            literal = scan[:literal]
            message << "; first non-zero overwide literal is #{literal[:width]} bits"
            message << " at #{literal[:context]}"
          end
          raise RuntimeError, "#{message}. Compiler-backed SPARC64 integration requires >#{COMPILER_MAX_SIGNAL_WIDTH}-bit compiler support."
        end

        def scan_overwide_runtime_ir(nodes_or_package)
          modules = case nodes_or_package
                    when RHDL::Codegen::CIRCT::IR::Package
                      nodes_or_package.modules
                    when Array
                      nodes_or_package
                    else
                      [nodes_or_package]
                    end

          result = {
            max_width: 0,
            max_width_context: nil,
            literal: nil
          }

          modules.each do |mod|
            scan_named_widths(Array(mod.ports), result) { |port| "#{mod.name}.port(#{port.name})" }
            scan_named_widths(Array(mod.nets), result) { |net| "#{mod.name}.net(#{net.name})" }
            scan_named_widths(Array(mod.regs), result) { |reg| "#{mod.name}.reg(#{reg.name})" }
            scan_named_widths(Array(mod.memories), result) { |mem| "#{mod.name}.memory(#{mem.name})" }

            Array(mod.assigns).each_with_index do |assign, index|
              scan_expr_widths(assign.expr, result, context: "#{mod.name}.assign[#{index}](#{assign.target})")
            end

            Array(mod.processes).each_with_index do |process, process_index|
              Array(process.statements).each_with_index do |stmt, stmt_index|
                scan_process_stmt_widths(
                  stmt,
                  result,
                  context: "#{mod.name}.process[#{process_index}](#{process.name}).stmt[#{stmt_index}]"
                )
              end
            end
          end

          result
        end

        def scan_named_widths(items, result)
          items.each do |item|
            width = item.respond_to?(:width) ? item.width.to_i : 0
            next unless width > result[:max_width]

            result[:max_width] = width
            result[:max_width_context] = yield(item)
          end
        end

        def scan_process_stmt_widths(stmt, result, context:)
          case stmt
          when RHDL::Codegen::CIRCT::IR::SeqAssign
            scan_expr_widths(stmt.expr, result, context: "#{context}.expr")
          when RHDL::Codegen::CIRCT::IR::If
            scan_expr_widths(stmt.condition, result, context: "#{context}.condition")
            Array(stmt.then_statements).each_with_index do |child, index|
              scan_process_stmt_widths(child, result, context: "#{context}.then[#{index}]")
            end
            Array(stmt.else_statements).each_with_index do |child, index|
              scan_process_stmt_widths(child, result, context: "#{context}.else[#{index}]")
            end
          end
        end

        def scan_expr_widths(expr, result, context:)
          return if expr.nil?

          width = expr.respond_to?(:width) ? expr.width.to_i : 0
          if width > result[:max_width]
            result[:max_width] = width
            result[:max_width_context] = context
          end

          if result[:literal].nil? &&
             expr.is_a?(RHDL::Codegen::CIRCT::IR::Literal) &&
             width > COMPILER_MAX_SIGNAL_WIDTH &&
             expr.value.to_i != 0
            result[:literal] = {
              width: width,
              context: context,
              value: expr.value
            }
          end

          case expr
          when RHDL::Codegen::CIRCT::IR::UnaryOp
            scan_expr_widths(expr.operand, result, context: "#{context}.operand")
          when RHDL::Codegen::CIRCT::IR::BinaryOp
            scan_expr_widths(expr.left, result, context: "#{context}.left")
            scan_expr_widths(expr.right, result, context: "#{context}.right")
          when RHDL::Codegen::CIRCT::IR::Mux
            scan_expr_widths(expr.condition, result, context: "#{context}.condition")
            scan_expr_widths(expr.when_true, result, context: "#{context}.when_true")
            scan_expr_widths(expr.when_false, result, context: "#{context}.when_false")
          when RHDL::Codegen::CIRCT::IR::Slice
            scan_expr_widths(expr.base, result, context: "#{context}.base")
          when RHDL::Codegen::CIRCT::IR::Concat
            Array(expr.parts).each_with_index do |part, index|
              scan_expr_widths(part, result, context: "#{context}.parts[#{index}]")
            end
          when RHDL::Codegen::CIRCT::IR::Resize
            scan_expr_widths(expr.expr, result, context: "#{context}.expr")
          when RHDL::Codegen::CIRCT::IR::Case
            scan_expr_widths(expr.selector, result, context: "#{context}.selector")
            expr.cases.each do |key, value|
              scan_expr_widths(value, result, context: "#{context}.cases[#{key}]")
            end
            scan_expr_widths(expr.default, result, context: "#{context}.default")
          when RHDL::Codegen::CIRCT::IR::MemoryRead
            scan_expr_widths(expr.addr, result, context: "#{context}.addr")
          end
        end

        def normalize_compiler_mode(value)
          mode = (value || :rustc).to_sym
          return :rustc if mode == :rustc

          raise ArgumentError,
                "Unsupported SPARC64 compiler mode #{value.inspect}. The compiler backend is rustc-only; use :jit for fallback."
        end

        def with_compiler_env
          return yield unless backend.to_sym == :compile

          previous = ENV['RHDL_IR_COMPILER_FORCE_RUSTC']
          ENV['RHDL_IR_COMPILER_FORCE_RUSTC'] = '1'
          yield
        ensure
          if previous.nil?
            ENV.delete('RHDL_IR_COMPILER_FORCE_RUSTC')
          else
            ENV['RHDL_IR_COMPILER_FORCE_RUSTC'] = previous
          end
          ENV.delete('RHDL_IR_COMPILER_FORCE_RUNTIME_ONLY')
        end

        def ensure_sparc64_runner!
          return if @sim.respond_to?(:runner_kind) && @sim.runner_kind == :sparc64

          actual = @sim.respond_to?(:runner_kind) ? @sim.runner_kind.inspect : 'unavailable'
          raise RuntimeError, "SPARC64 IR runner requires native :sparc64 runner support (runner_kind=#{actual})"
        end

        def refresh_runtime_state!
          @wishbone_trace = Array(@trace_reader.call(@sim))
          @unmapped_accesses = Array(@fault_reader.call(@sim))
        end

        def completion_result(timeout: false)
          refresh_runtime_state!
          trace = Integration.normalize_wishbone_trace(@wishbone_trace)
          faults = Array(@unmapped_accesses).dup
          {
            completed: completed?,
            timeout: timeout,
            cycles: clock_count,
            boot_handoff_seen: trace.any? { |event| event.addr.to_i >= Integration::PROGRAM_BASE },
            secondary_core_parked: faults.empty?,
            mailbox_status: mailbox_status,
            mailbox_value: mailbox_value,
            unmapped_accesses: faults,
            wishbone_trace: trace
          }
        end

        def default_trace_reader
          lambda do |sim|
            if sim.respond_to?(:runner_sparc64_wishbone_trace)
              sim.runner_sparc64_wishbone_trace
            else
              []
            end
          end
        end

        def default_fault_reader
          lambda do |sim|
            if sim.respond_to?(:runner_sparc64_unmapped_accesses)
              sim.runner_sparc64_unmapped_accesses
            else
              []
            end
          end
        end

        def decode_u64_be(bytes)
          Array(bytes).first(8).reduce(0) { |acc, byte| (acc << 8) | (byte.to_i & 0xFF) }
        end

        def encode_u64_be(value)
          8.times.map do |index|
            shift = (7 - index) * 8
            (value.to_i >> shift) & 0xFF
          end
        end

        def thread_debug_snapshot(cpu_index)
          compact_hash({
            fetch_pc_f: peek_first(
              "sparc_#{cpu_index}__ifu__errdp__fdp_erb_pc_f",
              "sparc_#{cpu_index}__ifu__fdp__fdp_erb_pc_f",
              "sparc_#{cpu_index}__ifu__fdp_fdp_erb_pc_f"
            ),
            npc_w: peek_first(
              "sparc_#{cpu_index}__tlu__misctl__ifu_npc_w",
              "sparc_#{cpu_index}__tlu__tcl__ifu_npc_w",
              "sparc_#{cpu_index}__tlu__tcl_ifu_npc_w"
            ),
            thread_states: (0..3).map do |thread_idx|
              peek_first(
                "sparc_#{cpu_index}__ifu__swl__thrfsm#{thread_idx}__thr_state",
                "sparc_#{cpu_index}__ifu__swl__thrfsm#{thread_idx}_thr_state"
              )
            end.compact
          })
        end

        def register_debug_snapshot(register_index)
          base = format('sparc_0__exu__irf__bw_r_irf_core__register%02d', register_index)
          compact_hash({
            wrens: peek_first("#{base}__wrens"),
            rd_thread: peek_first("#{base}__rd_thread"),
            save: peek_bool("#{base}__save"),
            restore: peek_bool("#{base}__restore"),
            wr_data: peek_first("#{base}__wr_data"),
            rd_data: peek_first("#{base}__rd_data")
          })
        end

        def peek_first(*candidates)
          return nil unless sim.respond_to?(:has_signal?) && sim.respond_to?(:peek)

          name = candidates.find { |candidate| sim.has_signal?(candidate) }
          return nil unless name

          sim.peek(name)
        end

        def peek_bool(*candidates)
          value = peek_first(*candidates)
          return nil if value.nil?

          !value.to_i.zero?
        end

        def compact_hash(hash)
          hash.each_with_object({}) do |(key, value), acc|
            next if value.nil?
            next if value.respond_to?(:empty?) && value.empty?

            acc[key] =
              case value
              when Hash
                compact_hash(value)
              else
                value
              end
          end
        end
      end
    end
  end
end
