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
            patch_prefetch_reference_flow!(modules)
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

            ensure_reg(mod, 'parity_readcode_burst_active', 1, 0)
            ensure_reg(mod, 'parity_readcode_beat_index', 4, 0)

            cpu_valid_name = output_signal_name!(inst, 'CPU_VALID')
            cpu_done_name = output_signal_name!(inst, 'CPU_DONE')
            cpu_data_name = output_signal_name!(inst, 'CPU_DATA')
            mem_req_name = output_signal_name!(inst, 'MEM_REQ')
            mem_addr_name = output_signal_name!(inst, 'MEM_ADDR')
            rst_n_expr = CpuTracePackage.signal('rst_n', 1)
            pr_reset_expr = CpuTracePackage.signal('pr_reset', 1)

            cpu_req_expr = connection_expr!(inst, 'CPU_REQ')
            cpu_addr_expr = connection_expr!(inst, 'CPU_ADDR')
            prefetched_length_expr = CpuTracePackage.signal('prefetched_length', 5)
            remaining_length_expr = CpuTracePackage.signal('length', 5)
            readcode_burst_active = CpuTracePackage.signal('parity_readcode_burst_active', 1)
            readcode_beat_index = CpuTracePackage.signal('parity_readcode_beat_index', 4)
            has_pending_words = CpuTracePackage.binop(:!=, prefetched_length_expr, ir::Literal.new(value: 0, width: 5), 1)
            final_word = CpuTracePackage.binop(:<=, remaining_length_expr, prefetched_length_expr, 1)
            readcode_word_valid = CpuTracePackage.signal('readcode_done', 1)
            in_cpu_window = CpuTracePackage.binop(
              :<,
              readcode_beat_index,
              ir::Literal.new(value: 4, width: 4),
              1
            )
            cpu_visible_word = CpuTracePackage.binop(
              :&,
              readcode_word_valid,
              CpuTracePackage.binop(:&, in_cpu_window, has_pending_words, 1),
              1
            )
            burst_active_next = ir::Mux.new(
              condition: CpuTracePackage.binop(
                :|,
                CpuTracePackage.binop(:^, rst_n_expr, ir::Literal.new(value: 1, width: 1), 1),
                pr_reset_expr,
                1
              ),
              when_true: ir::Literal.new(value: 0, width: 1),
              when_false: ir::Mux.new(
                condition: readcode_word_valid,
                when_true: ir::Mux.new(
                  condition: readcode_burst_active,
                  when_true: ir::Mux.new(
                    condition: CpuTracePackage.binop(:==, readcode_beat_index, ir::Literal.new(value: 7, width: 4), 1),
                    when_true: ir::Literal.new(value: 0, width: 1),
                    when_false: ir::Literal.new(value: 1, width: 1),
                    width: 1
                  ),
                  when_false: ir::Literal.new(value: 1, width: 1),
                  width: 1
                ),
                when_false: ir::Literal.new(value: 0, width: 1),
                width: 1
              ),
              width: 1
            )
            beat_index_next = ir::Mux.new(
              condition: CpuTracePackage.binop(
                :|,
                CpuTracePackage.binop(:^, rst_n_expr, ir::Literal.new(value: 1, width: 1), 1),
                pr_reset_expr,
                1
              ),
              when_true: ir::Literal.new(value: 0, width: 4),
              when_false: ir::Mux.new(
                condition: readcode_word_valid,
                when_true: ir::Mux.new(
                  condition: readcode_burst_active,
                  when_true: ir::Mux.new(
                    condition: CpuTracePackage.binop(:==, readcode_beat_index, ir::Literal.new(value: 7, width: 4), 1),
                    when_true: ir::Literal.new(value: 0, width: 4),
                    when_false: CpuTracePackage.binop(:+, readcode_beat_index, ir::Literal.new(value: 1, width: 4), 4),
                    width: 4
                  ),
                  when_false: ir::Literal.new(value: 1, width: 4),
                  width: 4
                ),
                when_false: ir::Literal.new(value: 0, width: 4),
                width: 4
              ),
              width: 4
            )

            mod.instances.reject! { |entry| entry.name.to_s == 'l1_icache_inst' }
            mod.assigns << CpuTracePackage.assign(mem_req_name, cpu_req_expr)
            mod.assigns << CpuTracePackage.assign(mem_addr_name, cpu_addr_expr)
            mod.assigns << CpuTracePackage.assign(cpu_valid_name, cpu_visible_word)
            mod.assigns << CpuTracePackage.assign(cpu_data_name, CpuTracePackage.signal('readcode_partial', 32))
            mod.assigns << CpuTracePackage.assign(
              cpu_done_name,
              CpuTracePackage.binop(
                :|,
                CpuTracePackage.binop(:&, cpu_visible_word, final_word, 1),
                pr_reset_expr,
                1
              )
            )
            mod.processes << ir::Process.new(
              name: 'parity_icache_burst_window',
              clocked: true,
              clock: 'clk',
              statements: [
                ir::SeqAssign.new(target: 'parity_readcode_burst_active', expr: burst_active_next),
                ir::SeqAssign.new(target: 'parity_readcode_beat_index', expr: beat_index_next)
              ]
            )
          end

          def patch_prefetch_fifo_passthrough!(modules)
            mod = CpuTracePackage.find_module!(modules, 'prefetch_fifo')
            ir = RHDL::Codegen::CIRCT::IR

            mod.instances.clear

            ensure_reg(mod, 'parity_fifo_valid', 1, 0)
            ensure_reg(mod, 'parity_fifo_data', 68, 0)

            write_do = CpuTracePackage.signal('prefetchfifo_write_do', 1)
            limit_do = CpuTracePackage.signal('prefetchfifo_signal_limit_do', 1)
            pf_do = CpuTracePackage.signal('prefetchfifo_signal_pf_do', 1)
            write_data = CpuTracePackage.signal('prefetchfifo_write_data', 36)
            accept_do = CpuTracePackage.signal('prefetchfifo_accept_do', 1)
            fifo_valid = CpuTracePackage.signal('parity_fifo_valid', 1)
            fifo_data = CpuTracePackage.signal('parity_fifo_data', 68)
            rst_n = CpuTracePackage.signal('rst_n', 1)
            pr_reset = CpuTracePackage.signal('pr_reset', 1)
            one = ir::Literal.new(value: 1, width: 1)
            zero1 = ir::Literal.new(value: 0, width: 1)
            zero5 = ir::Literal.new(value: 0, width: 5)
            one5 = ir::Literal.new(value: 1, width: 5)
            zero68 = ir::Literal.new(value: 0, width: 68)

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
            incoming_payload = ir::Mux.new(
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
            accept_data = ir::Mux.new(
              condition: fifo_valid,
              when_true: fifo_data,
              when_false: incoming_payload,
              width: 68
            )
            accept_empty = CpuTracePackage.binop(
              :^,
              CpuTracePackage.binop(:|, fifo_valid, any_valid, 1),
              one,
              1
            )
            next_fifo_valid = ir::Mux.new(
              condition: CpuTracePackage.binop(:^, rst_n, one, 1),
              when_true: zero1,
              when_false: ir::Mux.new(
                condition: pr_reset,
                when_true: zero1,
                when_false: ir::Mux.new(
                  condition: fifo_valid,
                  when_true: ir::Mux.new(
                    condition: accept_do,
                    when_true: any_valid,
                    when_false: fifo_valid,
                    width: 1
                  ),
                  when_false: any_valid,
                  width: 1
                ),
                width: 1
              ),
              width: 1
            )
            next_fifo_data = ir::Mux.new(
              condition: CpuTracePackage.binop(:^, rst_n, one, 1),
              when_true: zero68,
              when_false: ir::Mux.new(
                condition: pr_reset,
                when_true: zero68,
                when_false: ir::Mux.new(
                  condition: fifo_valid,
                  when_true: ir::Mux.new(
                    condition: accept_do,
                    when_true: ir::Mux.new(
                      condition: any_valid,
                      when_true: incoming_payload,
                      when_false: fifo_data,
                      width: 68
                    ),
                    when_false: fifo_data,
                    width: 68
                  ),
                  when_false: ir::Mux.new(
                    condition: any_valid,
                    when_true: incoming_payload,
                    when_false: fifo_data,
                    width: 68
                  ),
                  width: 68
                ),
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
                condition: CpuTracePackage.binop(:|, fifo_valid, any_valid, 1),
                when_true: one5,
                when_false: zero5,
                width: 5
              )
            )
            mod.assigns << CpuTracePackage.assign('prefetchfifo_accept_data', accept_data)
            mod.assigns << CpuTracePackage.assign('prefetchfifo_accept_empty', accept_empty)
            mod.processes << ir::Process.new(
              name: 'parity_prefetch_fifo',
              clocked: true,
              clock: 'clk',
              statements: [
                ir::SeqAssign.new(target: 'parity_fifo_valid', expr: next_fifo_valid),
                ir::SeqAssign.new(target: 'parity_fifo_data', expr: next_fifo_data)
              ]
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

          def patch_prefetch_reference_flow!(modules)
            mod = CpuTracePackage.find_module!(modules, 'prefetch')
            ir = RHDL::Codegen::CIRCT::IR

            rst_n = CpuTracePackage.signal('rst_n', 1)
            pr_reset = CpuTracePackage.signal('pr_reset', 1)
            reset_prefetch = CpuTracePackage.signal('reset_prefetch', 1)
            prefetch_cpl = CpuTracePackage.signal('prefetch_cpl', 2)
            prefetch_eip = CpuTracePackage.signal('prefetch_eip', 32)
            cs_cache = CpuTracePackage.signal('cs_cache', 64)
            prefetched_do = CpuTracePackage.signal('prefetched_do', 1)
            prefetched_length = CpuTracePackage.signal('prefetched_length', 5)
            prefetched_accept_do = CpuTracePackage.signal('prefetched_accept_do', 1)
            prefetched_accept_length = CpuTracePackage.signal('prefetched_accept_length', 4)
            limit = CpuTracePackage.signal('limit', 32)
            linear = CpuTracePackage.signal('linear', 32)
            delivered_eip = CpuTracePackage.signal('delivered_eip', 32)
            limit_signaled = CpuTracePackage.signal('limit_signaled', 1)
            prefetched_accept_do_1 = CpuTracePackage.signal('prefetched_accept_do_1', 1)
            prefetched_accept_length_1 = CpuTracePackage.signal('prefetched_accept_length_1', 4)

            one1 = ir::Literal.new(value: 1, width: 1)
            one32 = ir::Literal.new(value: 1, width: 32)
            zero1 = ir::Literal.new(value: 0, width: 1)
            zero32 = ir::Literal.new(value: 0, width: 32)
            startup_linear = ir::Literal.new(value: 0xFFFF0, width: 32)
            startup_limit = ir::Literal.new(value: 65_535, width: 32)
            max_fetch_len32 = ir::Literal.new(value: 16, width: 32)
            max_fetch_len5 = ir::Literal.new(value: 16, width: 5)
            user_cpl = ir::Literal.new(value: 3, width: 2)

            cs_base = ir::Concat.new(
              parts: [
                ir::Slice.new(base: cs_cache, range: 56..63, width: 8),
                ir::Slice.new(base: cs_cache, range: 16..39, width: 24)
              ],
              width: 32
            )
            cs_limit_high = ir::Slice.new(base: cs_cache, range: 48..51, width: 4)
            cs_limit_low = ir::Slice.new(base: cs_cache, range: 0..15, width: 16)
            cs_limit = ir::Mux.new(
              condition: ir::Slice.new(base: cs_cache, range: 55..55, width: 1),
              when_true: ir::Concat.new(
                parts: [
                  cs_limit_high,
                  cs_limit_low,
                  ir::Literal.new(value: 0xFFF, width: 12)
                ],
                width: 32
              ),
              when_false: ir::Concat.new(
                parts: [
                  ir::Literal.new(value: 0, width: 12),
                  cs_limit_high,
                  cs_limit_low
                ],
                width: 32
              ),
              width: 32
            )
            prefetched_length_ext = ir::Concat.new(
              parts: [
                ir::Literal.new(value: 0, width: 27),
                prefetched_length
              ],
              width: 32
            )
            accepted_length_ext = ir::Concat.new(
              parts: [
                ir::Literal.new(value: 0, width: 28),
                prefetched_accept_length_1
              ],
              width: 32
            )
            current_length = ir::Mux.new(
              condition: CpuTracePackage.binop(:<, limit, prefetched_length_ext, 1),
              when_true: ir::Slice.new(base: limit, range: 0..4, width: 5),
              when_false: prefetched_length,
              width: 5
            )
            current_length_ext = ir::Concat.new(
              parts: [
                ir::Literal.new(value: 0, width: 27),
                current_length
              ],
              width: 32
            )
            reset_limit = ir::Mux.new(
              condition: CpuTracePackage.binop(:>=, cs_limit, prefetch_eip, 1),
              when_true: CpuTracePackage.binop(
                :+,
                CpuTracePackage.binop(:-, cs_limit, prefetch_eip, 32),
                one32,
                32
              ),
              when_false: zero32,
              width: 32
            )
            limit_next = ir::Mux.new(
              condition: CpuTracePackage.binop(:^, rst_n, one1, 1),
              when_true: startup_limit,
              when_false: ir::Mux.new(
                condition: pr_reset,
                when_true: reset_limit,
                when_false: ir::Mux.new(
                  condition: reset_prefetch,
                  when_true: reset_limit,
                  when_false: ir::Mux.new(
                    condition: prefetched_do,
                    when_true: CpuTracePackage.binop(:-, limit, current_length_ext, 32),
                    when_false: limit,
                    width: 32
                  ),
                  width: 32
                ),
                width: 32
              ),
              width: 32
            )
            reset_linear = CpuTracePackage.binop(:+, cs_base, prefetch_eip, 32)
            linear_reset_prefetch = ir::Mux.new(
              condition: prefetched_accept_do_1,
              when_true: CpuTracePackage.binop(:+, delivered_eip, accepted_length_ext, 32),
              when_false: delivered_eip,
              width: 32
            )
            linear_pr_reset = linear_reset_prefetch
            linear_next = ir::Mux.new(
              condition: CpuTracePackage.binop(:^, rst_n, one1, 1),
              when_true: startup_linear,
              when_false: ir::Mux.new(
                condition: pr_reset,
                when_true: linear_pr_reset,
                when_false: ir::Mux.new(
                  condition: reset_prefetch,
                  when_true: linear_reset_prefetch,
                  when_false: ir::Mux.new(
                    condition: prefetched_do,
                    when_true: CpuTracePackage.binop(:+, linear, current_length_ext, 32),
                    when_false: linear,
                    width: 32
                  ),
                  width: 32
                ),
                width: 32
              ),
              width: 32
            )
            delivered_eip_pr_reset = linear_reset_prefetch
            delivered_eip_next = ir::Mux.new(
              condition: CpuTracePackage.binop(:^, rst_n, one1, 1),
              when_true: startup_linear,
              when_false: ir::Mux.new(
                condition: pr_reset,
                when_true: delivered_eip_pr_reset,
                when_false: ir::Mux.new(
                  condition: prefetched_accept_do_1,
                  when_true: CpuTracePackage.binop(:+, delivered_eip, accepted_length_ext, 32),
                  when_false: delivered_eip,
                  width: 32
                ),
                width: 32
              ),
              width: 32
            )
            signal_limit_do = CpuTracePackage.binop(
              :&,
              CpuTracePackage.binop(:==, limit, zero32, 1),
              CpuTracePackage.binop(:^, limit_signaled, one1, 1),
              1
            )
            limit_signaled_next = ir::Mux.new(
              condition: CpuTracePackage.binop(
                :|,
                CpuTracePackage.binop(:^, rst_n, one1, 1),
                pr_reset,
                1
              ),
              when_true: zero1,
              when_false: ir::Mux.new(
                condition: signal_limit_do,
                when_true: one1,
                when_false: limit_signaled,
                width: 1
              ),
              width: 1
            )

            mod.processes.clear
            mod.processes.concat(
              [
                ir::Process.new(
                  name: 'parity_prefetch_limit',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'limit', expr: limit_next)]
                ),
                ir::Process.new(
                  name: 'parity_prefetch_accept_do',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'prefetched_accept_do_1', expr: prefetched_accept_do)]
                ),
                ir::Process.new(
                  name: 'parity_prefetch_accept_length',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'prefetched_accept_length_1', expr: prefetched_accept_length)]
                ),
                ir::Process.new(
                  name: 'parity_prefetch_linear',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'linear', expr: linear_next)]
                ),
                ir::Process.new(
                  name: 'parity_prefetch_delivered_eip',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'delivered_eip', expr: delivered_eip_next)]
                ),
                ir::Process.new(
                  name: 'parity_prefetch_limit_signaled',
                  clocked: true,
                  clock: 'clk',
                  statements: [ir::SeqAssign.new(target: 'limit_signaled', expr: limit_signaled_next)]
                )
              ]
            )

            mod.assigns.reject! do |assign|
              %w[prefetch_address prefetch_length prefetch_su prefetchfifo_signal_limit_do delivered_eip].include?(assign.target.to_s)
            end
            mod.assigns << CpuTracePackage.assign('prefetch_address', linear)
            mod.assigns << CpuTracePackage.assign(
              'prefetch_length',
              ir::Mux.new(
                condition: CpuTracePackage.binop(:>, limit, max_fetch_len32, 1),
                when_true: max_fetch_len5,
                when_false: ir::Slice.new(base: limit, range: 0..4, width: 5),
                width: 5
              )
            )
            mod.assigns << CpuTracePackage.assign(
              'prefetch_su',
              CpuTracePackage.binop(:==, prefetch_cpl, user_cpl, 1)
            )
            mod.assigns << CpuTracePackage.assign('prefetchfifo_signal_limit_do', signal_limit_do)
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

          def ensure_reg(mod, name, width, reset_value = nil)
            return if mod.regs.any? { |reg| reg.name.to_s == name.to_s }
            return if mod.nets.any? { |net| net.name.to_s == name.to_s }
            return if mod.ports.any? { |port| port.name.to_s == name.to_s }

            mod.regs << RHDL::Codegen::CIRCT::IR::Reg.new(
              name: name.to_sym,
              width: width,
              reset_value: reset_value
            )
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
