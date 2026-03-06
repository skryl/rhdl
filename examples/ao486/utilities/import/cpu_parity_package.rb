# frozen_string_literal: true

require 'rhdl/codegen'
require_relative 'cpu_trace_package'

module RHDL
  module Examples
    module AO486
      module Import
        # Builds a parity-oriented imported AO486 CPU package.
        #
        # This helper is intentionally scoped to the CPU-top runtime parity
        # harness. It preserves the imported CPU top and imported pipeline
        # structure, adds stable retire-trace outputs, and replaces the imported
        # `l1_icache` behavior with a direct fetch model inside `icache`.
        #
        # The bypass is only valid for the parity harness configuration where
        # `cache_disable=1` is held high.
        module CpuParityPackage
          module_function

          def from_cleaned_mlir(mlir_text, top: 'ao486', strict: false)
            imported = RHDL::Codegen.import_circt_mlir(mlir_text, strict: strict, top: top)
            return CpuTracePackage.failure_from_import(imported) unless imported.success?

            modules = Array(imported.modules).map { |mod| CpuTracePackage.dup_module(mod) }
            patch_icache_bypass!(modules)
            patch_prefetch_fifo_passthrough!(modules)
            patch_prefetch_startup_limit!(modules)
            patch_fetch_threshold_logic!(modules)

            package = CpuTracePackage.build_from_modules(modules)

            {
              success: true,
              package: package,
              mlir: RHDL::Codegen::CIRCT::MLIR.generate(package),
              diagnostics: []
            }
          rescue StandardError => e
            {
              success: false,
              package: nil,
              mlir: nil,
              diagnostics: [e.message]
            }
          end

          def patch_icache_bypass!(modules)
            mod = CpuTracePackage.find_module!(modules, 'icache')
            inst = CpuTracePackage.find_instance!(mod, 'l1_icache_inst')
            ir = RHDL::Codegen::CIRCT::IR

            rewrite_icache_partial_length_literals!(mod)

            cpu_valid_name = output_signal_name!(inst, 'CPU_VALID')
            cpu_done_name = output_signal_name!(inst, 'CPU_DONE')
            cpu_data_name = output_signal_name!(inst, 'CPU_DATA')
            mem_req_name = output_signal_name!(inst, 'MEM_REQ')
            mem_addr_name = output_signal_name!(inst, 'MEM_ADDR')

            cpu_req_expr = connection_expr!(inst, 'CPU_REQ')
            cpu_addr_expr = connection_expr!(inst, 'CPU_ADDR')
            prefetched_length_expr = CpuTracePackage.signal('prefetched_length', 5)
            remaining_length_expr = CpuTracePackage.signal('length', 5)
            has_pending_words = CpuTracePackage.binop(:!=, prefetched_length_expr, ir::Literal.new(value: 0, width: 5), 1)
            final_word = CpuTracePackage.binop(:<=, remaining_length_expr, prefetched_length_expr, 1)

            mod.instances.reject! { |entry| entry.name.to_s == 'l1_icache_inst' }
            mod.assigns << CpuTracePackage.assign(mem_req_name, cpu_req_expr)
            mod.assigns << CpuTracePackage.assign(mem_addr_name, cpu_addr_expr)
            mod.assigns << CpuTracePackage.assign(
              cpu_valid_name,
              CpuTracePackage.binop(:&, CpuTracePackage.signal('readcode_done', 1), has_pending_words, 1)
            )
            mod.assigns << CpuTracePackage.assign(cpu_data_name, CpuTracePackage.signal('readcode_partial', 32))
            mod.assigns << CpuTracePackage.assign(
              cpu_done_name,
              CpuTracePackage.binop(:&, CpuTracePackage.signal('readcode_done', 1), final_word, 1)
            )
          end

          def patch_prefetch_fifo_passthrough!(modules)
            mod = CpuTracePackage.find_module!(modules, 'prefetch_fifo')
            ir = RHDL::Codegen::CIRCT::IR

            mod.instances.clear

            write_do = CpuTracePackage.signal('prefetchfifo_write_do', 1)
            limit_do = CpuTracePackage.signal('prefetchfifo_signal_limit_do', 1)
            pf_do = CpuTracePackage.signal('prefetchfifo_signal_pf_do', 1)
            write_data = CpuTracePackage.signal('prefetchfifo_write_data', 36)

            any_valid = CpuTracePackage.binop(
              :|,
              limit_do,
              CpuTracePackage.binop(:|, pf_do, write_do, 1),
              1
            )

            gp_payload = ir::Concat.new(
              parts: [
                ir::Literal.new(value: 15, width: 4),
                ir::Literal.new(value: 0, width: 32),
                ir::Literal.new(value: 0, width: 32)
              ],
              width: 68
            )
            pf_payload = ir::Concat.new(
              parts: [
                ir::Literal.new(value: 14, width: 4),
                ir::Literal.new(value: 0, width: 32),
                ir::Literal.new(value: 0, width: 32)
              ],
              width: 68
            )
            write_payload = ir::Concat.new(
              parts: [
                ir::Slice.new(base: write_data, range: 32..35, width: 4),
                ir::Literal.new(value: 0, width: 32),
                ir::Slice.new(base: write_data, range: 0..31, width: 32)
              ],
              width: 68
            )
            accept_data = ir::Mux.new(
              condition: limit_do,
              when_true: gp_payload,
              when_false: ir::Mux.new(
                condition: pf_do,
                when_true: pf_payload,
                when_false: write_payload,
                width: 68
              ),
              width: 68
            )

            mod.assigns.reject! do |assign|
              %w[prefetchfifo_used prefetchfifo_accept_data prefetchfifo_accept_empty].include?(assign.target.to_s)
            end
            mod.assigns << CpuTracePackage.assign(
              'prefetchfifo_used',
              ir::Mux.new(
                condition: any_valid,
                when_true: ir::Literal.new(value: 1, width: 5),
                when_false: ir::Literal.new(value: 0, width: 5),
                width: 5
              )
            )
            mod.assigns << CpuTracePackage.assign('prefetchfifo_accept_data', accept_data)
            mod.assigns << CpuTracePackage.assign(
              'prefetchfifo_accept_empty',
              CpuTracePackage.binop(:^, any_valid, ir::Literal.new(value: 1, width: 1), 1)
            )
          end

          def patch_prefetch_startup_limit!(modules)
            mod = CpuTracePackage.find_module!(modules, 'prefetch')
            proc = mod.processes.find do |entry|
              stmt = Array(entry.instance_variable_get(:@statements)).first
              stmt.is_a?(RHDL::Codegen::CIRCT::IR::SeqAssign) && stmt.target.to_s == 'limit'
            end
            raise KeyError, "SeqAssign target 'limit' not found in module '#{mod.name}'" unless proc

            stmt = proc.instance_variable_get(:@statements).first
            stmt.instance_variable_set(:@expr, rewrite_prefetch_limit_expr(stmt.expr))
          end

          def patch_fetch_threshold_logic!(modules)
            mod = CpuTracePackage.find_module!(modules, 'fetch')
            ir = RHDL::Codegen::CIRCT::IR

            accept_empty = CpuTracePackage.signal('prefetchfifo_accept_empty', 1)
            accept_data = CpuTracePackage.signal('prefetchfifo_accept_data', 68)
            fetch_count = CpuTracePackage.signal('fetch_count', 4)
            dec_acceptable = CpuTracePackage.signal('dec_acceptable', 4)
            rst_n = CpuTracePackage.signal('rst_n', 1)
            pr_reset = CpuTracePackage.signal('pr_reset', 1)
            one = ir::Literal.new(value: 1, width: 1)
            zero4 = ir::Literal.new(value: 0, width: 4)

            fetch_len = ir::Slice.new(base: accept_data, range: 64..67, width: 4)
            not_empty = CpuTracePackage.binop(:^, accept_empty, one, 1)
            normal_data = CpuTracePackage.binop(
              :&,
              not_empty,
              CpuTracePackage.binop(:<, fetch_len, ir::Literal.new(value: 9, width: 4), 1),
              1
            )
            fetch_valid_expr = ir::Mux.new(
              condition: normal_data,
              when_true: CpuTracePackage.binop(:-, fetch_len, fetch_count, 4),
              when_false: zero4,
              width: 4
            )
            accept_do_expr = CpuTracePackage.binop(
              :&,
              CpuTracePackage.binop(:>=, dec_acceptable, fetch_valid_expr, 1),
              normal_data,
              1
            )
            partial_expr = CpuTracePackage.binop(
              :&,
              CpuTracePackage.binop(:<, dec_acceptable, fetch_valid_expr, 1),
              normal_data,
              1
            )

            mod.assigns.reject! do |assign|
              %w[prefetchfifo_accept_do fetch_valid fetch_limit fetch_page_fault].include?(assign.target.to_s)
            end
            mod.assigns << CpuTracePackage.assign('prefetchfifo_accept_do', accept_do_expr)
            mod.assigns << CpuTracePackage.assign('fetch_valid', fetch_valid_expr)
            mod.assigns << CpuTracePackage.assign(
              'fetch_limit',
              CpuTracePackage.binop(
                :&,
                not_empty,
                CpuTracePackage.binop(:==, fetch_len, ir::Literal.new(value: 15, width: 4), 1),
                1
              )
            )
            mod.assigns << CpuTracePackage.assign(
              'fetch_page_fault',
              CpuTracePackage.binop(
                :&,
                not_empty,
                CpuTracePackage.binop(:==, fetch_len, ir::Literal.new(value: 14, width: 4), 1),
                1
              )
            )

            proc = mod.processes.find do |entry|
              stmt = Array(entry.instance_variable_get(:@statements)).first
              stmt.is_a?(RHDL::Codegen::CIRCT::IR::SeqAssign) && stmt.target.to_s == 'fetch_count'
            end
            raise KeyError, "SeqAssign target 'fetch_count' not found in module '#{mod.name}'" unless proc

            stmt = proc.instance_variable_get(:@statements).first
            fetch_count_expr = ir::Mux.new(
              condition: CpuTracePackage.binop(:^, rst_n, one, 1),
              when_true: zero4,
              when_false: ir::Mux.new(
                condition: pr_reset,
                when_true: zero4,
                when_false: ir::Mux.new(
                  condition: accept_do_expr,
                  when_true: zero4,
                  when_false: ir::Mux.new(
                    condition: partial_expr,
                    when_true: CpuTracePackage.binop(:+, fetch_count, dec_acceptable, 4),
                    when_false: fetch_count,
                    width: 4
                  ),
                  width: 4
                ),
                width: 4
              ),
              width: 4
            )
            stmt.instance_variable_set(:@expr, fetch_count_expr)
          end

          def rewrite_prefetch_limit_expr(expr)
            case expr
            when RHDL::Codegen::CIRCT::IR::Literal
              value = (expr.width == 32 && expr.value == 16) ? 65_535 : expr.value
              RHDL::Codegen::CIRCT::IR::Literal.new(value: value, width: expr.width)
            when RHDL::Codegen::CIRCT::IR::Signal
              expr
            when RHDL::Codegen::CIRCT::IR::UnaryOp
              RHDL::Codegen::CIRCT::IR::UnaryOp.new(
                op: expr.op,
                operand: rewrite_prefetch_limit_expr(expr.operand),
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::BinaryOp
              RHDL::Codegen::CIRCT::IR::BinaryOp.new(
                op: expr.op,
                left: rewrite_prefetch_limit_expr(expr.left),
                right: rewrite_prefetch_limit_expr(expr.right),
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Mux
              RHDL::Codegen::CIRCT::IR::Mux.new(
                condition: rewrite_prefetch_limit_expr(expr.condition),
                when_true: rewrite_prefetch_limit_expr(expr.when_true),
                when_false: rewrite_prefetch_limit_expr(expr.when_false),
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Concat
              RHDL::Codegen::CIRCT::IR::Concat.new(
                parts: expr.parts.map { |part| rewrite_prefetch_limit_expr(part) },
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Slice
              RHDL::Codegen::CIRCT::IR::Slice.new(
                base: rewrite_prefetch_limit_expr(expr.base),
                range: expr.range,
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Resize
              RHDL::Codegen::CIRCT::IR::Resize.new(
                expr: rewrite_prefetch_limit_expr(expr.expr),
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Case
              RHDL::Codegen::CIRCT::IR::Case.new(
                selector: rewrite_prefetch_limit_expr(expr.selector),
                cases: expr.cases.transform_values { |value| rewrite_prefetch_limit_expr(value) },
                default: rewrite_prefetch_limit_expr(expr.default),
                width: expr.width
              )
            else
              expr
            end
          end

          def rewrite_icache_partial_length_literals!(mod)
            proc = mod.processes.find do |entry|
              stmt = Array(entry.instance_variable_get(:@statements)).first
              stmt.is_a?(RHDL::Codegen::CIRCT::IR::SeqAssign) && stmt.target.to_s == 'partial_length'
            end
            raise KeyError, "SeqAssign target 'partial_length' not found in module '#{mod.name}'" unless proc

            stmt = proc.instance_variable_get(:@statements).first
            stmt.instance_variable_set(:@expr, rewrite_length_burst_expr(stmt.expr))
          end

          def rewrite_length_burst_expr(expr)
            case expr
            when RHDL::Codegen::CIRCT::IR::Literal
              rewrite_length_burst_literal(expr)
            when RHDL::Codegen::CIRCT::IR::Signal
              expr
            when RHDL::Codegen::CIRCT::IR::UnaryOp
              RHDL::Codegen::CIRCT::IR::UnaryOp.new(
                op: expr.op,
                operand: rewrite_length_burst_expr(expr.operand),
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::BinaryOp
              RHDL::Codegen::CIRCT::IR::BinaryOp.new(
                op: expr.op,
                left: rewrite_length_burst_expr(expr.left),
                right: rewrite_length_burst_expr(expr.right),
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Mux
              RHDL::Codegen::CIRCT::IR::Mux.new(
                condition: rewrite_length_burst_expr(expr.condition),
                when_true: rewrite_length_burst_expr(expr.when_true),
                when_false: rewrite_length_burst_expr(expr.when_false),
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Concat
              RHDL::Codegen::CIRCT::IR::Concat.new(
                parts: expr.parts.map { |part| rewrite_length_burst_expr(part) },
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Slice
              RHDL::Codegen::CIRCT::IR::Slice.new(
                base: rewrite_length_burst_expr(expr.base),
                range: expr.range,
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Resize
              RHDL::Codegen::CIRCT::IR::Resize.new(
                expr: rewrite_length_burst_expr(expr.expr),
                width: expr.width
              )
            when RHDL::Codegen::CIRCT::IR::Case
              RHDL::Codegen::CIRCT::IR::Case.new(
                selector: rewrite_length_burst_expr(expr.selector),
                cases: expr.cases.transform_values { |value| rewrite_length_burst_expr(value) },
                default: rewrite_length_burst_expr(expr.default),
                width: expr.width
              )
            else
              expr
            end
          end

          def rewrite_length_burst_literal(expr)
            mapping = {
              -1759 => -1756, # 12'h921 -> 12'h924
              -1758 => -1757, # 12'h922 -> 12'h923
              -1757 => -1758, # 12'h923 -> 12'h922
              -1756 => -1759  # 12'h924 -> 12'h921
            }
            mapped = mapping.fetch(expr.value, expr.value)
            RHDL::Codegen::CIRCT::IR::Literal.new(value: mapped, width: expr.width)
          end

          def output_signal_name!(inst, port_name)
            conn = inst.connections.find do |entry|
              entry.direction.to_s == 'out' && entry.port_name.to_s == port_name.to_s
            end
            raise KeyError, "Output connection '#{port_name}' not found on instance '#{inst.name}'" unless conn

            conn.signal.to_s
          end

          def connection_expr!(inst, port_name)
            conn = inst.connections.find { |entry| entry.port_name.to_s == port_name.to_s }
            raise KeyError, "Connection '#{port_name}' not found on instance '#{inst.name}'" unless conn

            case conn.signal
            when RHDL::Codegen::CIRCT::IR::Expr
              conn.signal
            else
              CpuTracePackage.signal(conn.signal.to_s, conn.width || 1)
            end
          end

        end
      end
    end
  end
end
