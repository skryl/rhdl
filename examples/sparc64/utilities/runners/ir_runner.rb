# frozen_string_literal: true

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

        attr_reader :sim, :clock_count, :backend

        def initialize(backend: :compile, import_dir: nil, top: 'S1Top', component_class: nil,
                       sim_factory: nil, strict_runner_kind: true, trace_reader: nil, fault_reader: nil,
                       fast_boot: false)
          @backend = backend.to_sym
          @component_class = component_class || Integration::ImportLoader.load_component_class(
            top: top,
            import_dir: import_dir,
            fast_boot: fast_boot
          )
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
          refresh_runtime_state!
          result
        end

        def load_images(boot_image:, program_image:)
          reset!
          load_flash(boot_image, base_addr: Integration::FLASH_BOOT_BASE)
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
            return completion_result if completed? || unmapped_accesses.any?
          end

          completion_result(timeout: true)
        end

        def wishbone_trace
          refresh_runtime_state!
          Integration.normalize_wishbone_trace(@wishbone_trace)
        end

        def unmapped_accesses
          refresh_runtime_state!
          Array(@unmapped_accesses).dup
        end

        private

        def build_simulator(component_class, backend)
          nodes = component_class.to_flat_circt_nodes
          validate_compiler_width_support!(nodes) if backend.to_sym == :compile
          json = RHDL::Sim::Native::IR.sim_json(nodes, backend: backend)
          RHDL::Sim::Native::IR::Simulator.new(json, backend: backend)
        end

        def validate_compiler_width_support!(nodes_or_package)
          scan = scan_overwide_runtime_ir(nodes_or_package)
          return if scan[:max_width] <= COMPILER_MAX_SIGNAL_WIDTH && scan[:literal].nil?

          message = +"Native IR compiler backend currently supports signals up to #{COMPILER_MAX_SIGNAL_WIDTH} bits"
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
          trace = wishbone_trace
          faults = unmapped_accesses
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
      end
    end
  end
end
