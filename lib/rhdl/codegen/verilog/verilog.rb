# Verilog-2001 code generator

require_relative "../ir/ir"
require "set"

module RHDL
  module Codegen
    module Verilog
      VERILOG_KEYWORDS = %w[
        always and assign begin buf case casex casez cmos deassign default defparam
        disable edge else end endcase endfunction endmodule endprimitive endspecify
        endtable endtask event for force forever fork function if initial inout input
        integer join macromodule module nand negedge nmos nor not notif0 notif1 or output
        parameter pmos posedge primitive pull0 pull1 pulldown pullup rcmos real realtime
        reg release repeat rnmos rpmos rtran rtranif0 rtranif1 scalared signed specify
        specparam strong0 strong1 supply0 supply1 table task time tran tranif0 tranif1
        tri tri0 tri1 triand trior trireg unsigned vectored wait wand weak0 weak1 while
        wire wor xnor xor
      ].freeze

      module_function

      TEMP_SLICE_CTX_KEY = :rhdl_verilog_temp_slice_ctx

      # Consolidate multiple assigns to the same target into a single assign.
      # When the DSL has:
      #   x <= mux(cond1, val1, x)
      #   x <= mux(cond2, val2, x)
      # This consolidates them into:
      #   x = mux(cond2, val2, mux(cond1, val1, default))
      # Later assigns have priority over earlier ones.
      def consolidate_assigns(assigns)
        # Group assigns by target
        by_target = assigns.group_by { |a| a.target.to_s }

        consolidated = []
        by_target.each do |target, target_assigns|
          if target_assigns.length == 1
            consolidated << target_assigns.first
          else
            # Multiple assigns to same target - need to merge
            merged_expr = merge_conditional_assigns(target, target_assigns)
            consolidated << IR::Assign.new(target: target, expr: merged_expr)
          end
        end

        consolidated
      end

      # Merge multiple conditional assigns into a single expression.
      # Each assign should be in the form: target = mux(cond, val, target) or target = expr
      # The result is a nested mux where later conditions have priority.
      def merge_conditional_assigns(target, assigns)
        # Start with a default value (first non-conditional assign or zero)
        # Work through assigns in order, building a mux chain where later assigns
        # wrap earlier ones, giving them priority.

        # Find the width from the first assign's expression
        width = assigns.first.expr.width

        # Build from the first assign, then layer subsequent ones on top
        result = nil
        assigns.each do |assign|
          expr = assign.expr

          if expr.is_a?(IR::Mux) && is_self_reference?(expr.when_false, target)
            # This is a conditional assign: x = mux(cond, val, x)
            # Replace the self-reference with our accumulated result
            if result.nil?
              # First conditional - need a default value
              # Try to find a non-conditional assign, otherwise use 0
              default = find_default_value(assigns, target, width)
              result = IR::Mux.new(
                condition: expr.condition,
                when_true: expr.when_true,
                when_false: default,
                width: width
              )
            else
              # Layer this condition on top of previous result
              result = IR::Mux.new(
                condition: expr.condition,
                when_true: expr.when_true,
                when_false: result,
                width: width
              )
            end
          elsif expr.is_a?(IR::Mux) && is_self_reference?(expr.when_true, target)
            # Inverted conditional: x = mux(cond, x, val)
            # This means: when cond is false, assign val
            if result.nil?
              default = find_default_value(assigns, target, width)
              # Invert: when !cond, use val; else use default
              result = IR::Mux.new(
                condition: expr.condition,
                when_true: default,
                when_false: expr.when_false,
                width: width
              )
            else
              result = IR::Mux.new(
                condition: expr.condition,
                when_true: result,
                when_false: expr.when_false,
                width: width
              )
            end
          else
            # Unconditional assign - this becomes the new base
            result = expr
          end
        end

        result || IR::Literal.new(value: 0, width: width)
      end

      # Check if an expression is a reference to the target signal
      def is_self_reference?(expr, target)
        case expr
        when IR::Signal
          sanitize(expr.name) == sanitize(target)
        when IR::Resize
          is_self_reference?(expr.expr, target)
        else
          false
        end
      end

      # Find a suitable default value from the assigns
      def find_default_value(assigns, target, width)
        # Look for an unconditional assign
        assigns.each do |assign|
          expr = assign.expr
          next if expr.is_a?(IR::Mux) && (is_self_reference?(expr.when_false, target) ||
                                           is_self_reference?(expr.when_true, target))
          # Found an unconditional assign
          return expr
        end

        # No unconditional assign found - use zero as default
        IR::Literal.new(value: 0, width: width)
      end

      def generate(module_def)
        previous_ctx = Thread.current[TEMP_SLICE_CTX_KEY]
        declared_widths = build_declared_signal_width_map(module_def)
        implicit_memories = build_implicit_memory_map(module_def, declared_widths)
        implicit_memories.each do |name, meta|
          register_declared_width(declared_widths, name, meta.fetch(:width))
        end
        ctx = {
          slice_counter: 0,
          slice_map: {},
          slice_decls: [],
          slice_assigns: [],
          signal_widths: declared_widths,
          implicit_memories: implicit_memories,
          memory_names: build_memory_name_lookup(module_def, implicit_memories)
        }
        Thread.current[TEMP_SLICE_CTX_KEY] = ctx

        lines = []

        # Module declaration with optional parameters
        if module_def.parameters.empty?
          lines << "module #{sanitize(module_def.name)}("
        else
          lines << "module #{sanitize(module_def.name)} #("
          param_lines = module_def.parameters.map do |name, value|
            "  parameter #{sanitize(name)} = #{value}"
          end
          lines << param_lines.join(",\n")
          lines << ") ("
        end

        port_lines = module_def.ports.map do |port|
          "  #{port_decl(port, module_def.reg_ports.include?(port.name))}"
        end
        lines << port_lines.join(",\n")
        lines << ");"
        lines << ""

        # Skip regs that are already declared as output reg in the port list
        output_reg_names = module_def.reg_ports.map { |n| n.to_s }
        module_def.regs.each do |reg|
          next if output_reg_names.include?(reg.name.to_s)
          next if memory_declared_name?(reg.name)

          declaration_kind = declared_signal_kind(module_def, reg.name)
          case declaration_kind
          when :logic
            lines << "  logic #{width_decl(reg.width)}#{sanitize(reg.name)};"
          when :integer, :int
            lines << "  integer #{sanitize(reg.name)};"
          else
            lines << "  reg #{width_decl(reg.width)}#{sanitize(reg.name)};"
          end
        end
        module_def.nets.each do |net|
          next if memory_declared_name?(net.name)

          declaration_kind = declared_signal_kind(module_def, net.name)
          keyword = declaration_kind == :logic ? "logic" : "wire"
          lines << "  #{keyword} #{width_decl(net.width)}#{sanitize(net.name)};"
        end

        # Memory array declarations
        module_def.memories.each do |mem|
          lines << "  reg #{width_decl(mem.width)}#{sanitize(mem.name)} [0:#{mem.depth - 1}];"
        end
        implicit_memories.each_value do |mem|
          lines << "  reg #{width_decl(mem.fetch(:width))}#{sanitize(mem.fetch(:name))} [0:#{mem.fetch(:depth) - 1}];"
        end
        lines << "" unless module_def.regs.empty? && module_def.nets.empty? && module_def.memories.empty?

        temp_slice_insert_idx = lines.length

        # Generate initial block for regs with reset_values (for simulation)
        # This is needed for Verilator and other simulators when there's no reset signal
        regs_with_init = module_def.regs.select { |reg| !reg.reset_value.nil? }
        output_reg_defaults = module_def.ports.select do |port|
          module_def.reg_ports.include?(port.name) && !port.default.nil?
        end
        unless regs_with_init.empty? && output_reg_defaults.empty?
          lines << "  initial begin"
          regs_with_init.each do |reg|
            lines << "    #{sanitize(reg.name)} = #{literal(reg.reset_value, reg.width)};"
          end
          output_reg_defaults.each do |port|
            lines << "    #{sanitize(port.name)} = #{literal(port.default, port.width)};"
          end
          lines << "  end"
          lines << ""
        end

        # Generate initial blocks for memories with initial_data (RAM/ROM/tables)
        #
        # Notes:
        # - The DSL initializes memories to 0 unless explicitly set; Verilog does not.
        # - We keep output compact by clearing to 0 in a loop and then applying only
        #   the non-zero initial values.
        # - This avoids huge generated Verilog for large memories while still
        #   matching Ruby/IR simulator semantics.
        module_def.memories.each do |mem|
          init_data = mem.initial_data
          next unless init_data

          mask = (1 << mem.width) - 1
          non_zero_inits = []
          init_data.each_with_index do |raw, idx|
            value = (raw || 0).to_i & mask
            next if value == 0
            non_zero_inits << [idx, value]
          end

          mem_name = sanitize(mem.name)
          block_name = sanitize("init_#{mem.name}")

          lines << "  initial begin : #{block_name}"
          lines << "    integer i;"
          lines << "    for (i = 0; i < #{mem.depth}; i = i + 1) begin"
          lines << "      #{mem_name}[i] = #{literal(0, mem.width)};"
          lines << "    end"

          non_zero_inits.each do |idx, value|
            lines << "    #{mem_name}[#{idx}] = #{literal(value, mem.width)};"
          end

          lines << "  end"
          lines << ""
        end

        implicit_memories.each_value do |mem|
          next unless mem.key?(:initial_data)

          init_data = mem[:initial_data]
          next unless init_data

          mask = (1 << mem.fetch(:width)) - 1
          non_zero_inits = []
          init_data.each_with_index do |raw, idx|
            value = (raw || 0).to_i & mask
            next if value == 0
            non_zero_inits << [idx, value]
          end

          mem_name = sanitize(mem.fetch(:name))
          block_name = sanitize("init_#{mem.fetch(:name)}")

          lines << "  initial begin : #{block_name}"
          lines << "    integer i;"
          lines << "    for (i = 0; i < #{mem.fetch(:depth)}; i = i + 1) begin"
          lines << "      #{mem_name}[i] = #{literal(0, mem.fetch(:width))};"
          lines << "    end"

          non_zero_inits.each do |idx, value|
            lines << "    #{mem_name}[#{idx}] = #{literal(value, mem.fetch(:width))};"
          end

          lines << "  end"
          lines << ""
        end

        # Consolidate multiple assigns to the same target into a single assign
        consolidated = consolidate_assigns(module_def.assigns)
        consolidated.each do |assign|
          # Skip circular assignments (assign x = x) which can happen with unconditional mux fallbacks
          next if circular_assign?(assign)

          lines << "  assign #{sanitize(assign.target)} = #{expr(assign.expr)};"
        end

        # Memory write processes
        module_def.write_ports.each do |wp|
          lines << ""
          lines << "  always @(posedge #{sanitize(wp.clock)}) begin"
          lines << "    if (#{expr(wp.enable)}) begin"
          lines << "      #{sanitize(wp.memory)}[#{expr(wp.addr)}] <= #{expr(wp.data)};"
          lines << "    end"
          lines << "  end"
        end

        # Memory synchronous read processes (for BRAM inference)
        module_def.sync_read_ports.each do |rp|
          lines << ""
          lines << "  always @(posedge #{sanitize(rp.clock)}) begin"
          if rp.enable
            lines << "    if (#{expr(rp.enable)}) begin"
            lines << "      #{sanitize(rp.data)} <= #{sanitize(rp.memory)}[#{expr(rp.addr)}];"
            lines << "    end"
          else
            lines << "    #{sanitize(rp.data)} <= #{sanitize(rp.memory)}[#{expr(rp.addr)}];"
          end
          lines << "  end"
        end

        module_def.processes.each do |process|
          lines << "" unless module_def.assigns.empty?
          lines << process_block(process)
        end

        # Generate module instances
        module_def.instances.each do |instance|
          lines << ""
          lines << instance_block(instance)
        end

        # Insert temporary wires/assigns for complex slices, if any.
        #
        # Verilog-2001 does not allow part-selects on arbitrary expressions, so we lower
        # complex slices into shift operations assigned to a sized temporary wire. The
        # net declaration width provides the required truncation.
        temp_decls = ctx[:slice_decls]
        temp_assigns = ctx[:slice_assigns]
        unless temp_decls.empty? && temp_assigns.empty?
          temp_lines = [*temp_decls, *temp_assigns, ""]
          lines.insert(temp_slice_insert_idx, *temp_lines)
        end

        lines << ""
        lines << "endmodule"
        lines.join("\n")
      ensure
        Thread.current[TEMP_SLICE_CTX_KEY] = previous_ctx
      end

      # Generate module instantiation
      def instance_block(instance)
        lines = []
        if instance.parameters.empty?
          param_list = instance.parameters.map { |k, v| ".#{sanitize(k)}(#{v})" }.join(", ")
        end

        raw_port_lines = instance.connections.map do |conn|
          if conn.signal == :__rhdl_unconnected
            nil
          else
            signal_str = conn.signal.is_a?(String) ? sanitize(conn.signal) : expr(conn.signal)
            next if signal_str.nil? || signal_str.to_s.strip.empty?

            "    .#{sanitize(conn.port_name)}(#{signal_str})"
          end
        end.compact

        if raw_port_lines.empty?
          if instance.parameters.empty?
            lines << "  #{sanitize(instance.module_name)} #{sanitize(instance.name)} ();"
          else
            param_list = instance.parameters.map { |k, v| ".#{sanitize(k)}(#{v})" }.join(", ")
            lines << "  #{sanitize(instance.module_name)} #(#{param_list}) #{sanitize(instance.name)} ();"
          end
          return lines.join("\n")
        end

        if instance.parameters.empty?
          lines << "  #{sanitize(instance.module_name)} #{sanitize(instance.name)} ("
        else
          param_list = instance.parameters.map { |k, v| ".#{sanitize(k)}(#{v})" }.join(", ")
          lines << "  #{sanitize(instance.module_name)} #(#{param_list}) #{sanitize(instance.name)} ("
        end

        lines << raw_port_lines.join(",\n")

        lines << "  );"
        lines.join("\n")
      end

      def port_decl(port, reg_output)
        dir = case port.direction
              when :in then "input"
              when :out then reg_output ? "output reg" : "output"
              when :inout then "inout"
              else "input"
              end
        "#{dir} #{width_decl(port.width)}#{sanitize(port.name)}"
      end

      def width_decl(width)
        return "" if scalar_width?(width)

        high, low = width_bounds(width)
        "[#{high}:#{low}] "
      end

      def process_block(process)
        lines = []
        if process.respond_to?(:initial) && process.initial
          lines << "  initial begin"
          process.statements.each { |stmt| lines.concat(statement(stmt, nonblocking: false, indent: 2)) }
          lines << "  end"
        elsif process.clocked
          sensitivity_items = clocked_sensitivity_items(process)
          lines << "  always @(#{sensitivity_items.join(' or ')}) begin"
          process.statements.each { |stmt| lines.concat(statement(stmt, nonblocking: true, indent: 2)) }
          lines << "  end"
        else
          sensitivity = process.sensitivity_list.map { |sig| sanitize(sig) }
          sens_clause = sensitivity.empty? ? "*" : sensitivity.join(" or ")
          lines << "  always @(#{sens_clause}) begin"
          process.statements.each { |stmt| lines.concat(statement(stmt, nonblocking: false, indent: 2)) }
          lines << "  end"
        end
        lines.join("\n")
      end

      def statement(stmt, nonblocking:, indent: 0)
        pad = " " * indent
        case stmt
        when IR::SeqAssign
          assign_nonblocking = stmt.nonblocking.nil? ? nonblocking : stmt.nonblocking
          op = assign_nonblocking ? "<=" : "="
          recovered_target, recovered_expr = recover_indexed_seqassign(stmt)
          if recovered_target
            target_text = recovered_target
            expr_node = recovered_expr || stmt.expr
          else
            target_text = seqassign_target_to_verilog(stmt.target) || seqassign_target_fallback(stmt.target)
            expr_node = stmt.expr
          end
          ["#{pad}#{target_text} #{op} #{expr(expr_node)};"]
        when IR::MemoryWrite
          op = nonblocking ? "<=" : "="
          ["#{pad}#{sanitize(stmt.memory)}[#{expr(stmt.addr)}] #{op} #{expr(stmt.data)};"]
        when IR::If
          cond = expr_bool(stmt.condition)
          lines = ["#{pad}if (#{cond}) begin"]
          stmt.then_statements.each { |s| lines.concat(statement(s, nonblocking: nonblocking, indent: indent + 2)) }
          lines << "#{pad}end"
          unless stmt.else_statements.empty?
            lines << "#{pad}else begin"
            stmt.else_statements.each { |s| lines.concat(statement(s, nonblocking: nonblocking, indent: indent + 2)) }
            lines << "#{pad}end"
          end
          lines
        when IR::CaseStmt
          lines = ["#{pad}case (#{expr(stmt.selector)})"]
          Array(stmt.branches).each do |branch|
            values = Array(branch.values)
            next if values.empty?

            rendered_values = values.map { |value| expr(value) }.join(", ")
            lines << "#{pad}  #{rendered_values}: begin"
            Array(branch.statements).each do |inner|
              lines.concat(statement(inner, nonblocking: nonblocking, indent: indent + 4))
            end
            lines << "#{pad}  end"
          end
          unless Array(stmt.default_statements).empty?
            lines << "#{pad}  default: begin"
            Array(stmt.default_statements).each do |inner|
              lines.concat(statement(inner, nonblocking: nonblocking, indent: indent + 4))
            end
            lines << "#{pad}  end"
          end
          lines << "#{pad}endcase"
          lines
        else
          []
        end
      end

      def expr_bool(expr_node)
        rendered = expr(expr_node)
        return rendered if expr_node.width == 1

        "(|#{rendered})"
      end

      def seqassign_target_to_verilog(target)
        case target
        when Symbol, String
          sanitize(target)
        else
          return nil unless target.respond_to?(:to_verilog)
          return nil unless hir_seqassign_target_legal?(target)

          rendered = target.to_verilog
          rendered = rendered.to_s.strip
          rendered.empty? ? nil : rendered
        end
      rescue StandardError
        nil
      end

      def recover_indexed_seqassign(stmt)
        target_name = stmt.target.to_s
        return [nil, nil] if target_name.empty?
        target_width = declared_signal_width(target_name)
        return [nil, nil] unless target_width.is_a?(Integer) && target_width > 1

        recovered = recover_bit_select_rmw_assignment(target_name: target_name, expr_node: stmt.expr)
        return recovered unless recovered.nil?

        recover_static_slice_rmw_assignment(target_name: target_name, expr_node: stmt.expr) || [nil, nil]
      end

      def seqassign_target_fallback(target)
        base = target_base_name(target)
        return sanitize(base) unless base.nil? || base.empty?

        sanitize(target)
      end

      def hir_seqassign_target_legal?(target)
        case target
        when RHDL::DSL::BitSelect
          base_width = declared_vector_target_base_width(target.signal)
          return base_width.is_a?(Integer) && base_width > 1
        when RHDL::DSL::BitSlice
          return false unless target.range.is_a?(Range)
          return false unless target.range.begin.is_a?(Integer) && target.range.end.is_a?(Integer)

          base_width = declared_vector_target_base_width(target.signal)
          return false unless base_width.is_a?(Integer) && base_width > 1

          high = [target.range.begin, target.range.end].max
          low = [target.range.begin, target.range.end].min
          return false if low.negative?
          return false if high >= base_width

          true
        else
          true
        end
      rescue StandardError
        false
      end

      def declared_vector_target_base_width(target_base)
        base_name = target_base_name(target_base)
        return nil if base_name.nil? || base_name.empty?

        declared_signal_width(base_name)
      end

      def target_base_name(target)
        case target
        when nil
          nil
        when Symbol
          target.to_s
        when String
          token = target.strip
          token.empty? ? nil : token
        when RHDL::DSL::SignalRef
          target.name.to_s
        when RHDL::DSL::BitSelect, RHDL::DSL::BitSlice
          target_base_name(target.signal)
        else
          if target.respond_to?(:name) && !target.name.nil?
            target.name.to_s
          else
            nil
          end
        end
      rescue StandardError
        nil
      end

      def declared_signal_width(name)
        ctx = Thread.current[TEMP_SLICE_CTX_KEY]
        return nil unless ctx.is_a?(Hash)

        widths = ctx[:signal_widths]
        return nil unless widths.is_a?(Hash)

        key = name.to_s
        widths[key] || widths[sanitize(key)]
      end

      def build_declared_signal_width_map(module_def)
        map = {}
        Array(module_def.ports).each { |port| register_declared_width(map, port.name, port.width) }
        Array(module_def.regs).each { |reg| register_declared_width(map, reg.name, reg.width) }
        Array(module_def.nets).each { |net| register_declared_width(map, net.name, net.width) }
        Array(module_def.memories).each { |mem| register_declared_width(map, mem.name, mem.width) }
        map
      end

      def register_declared_width(map, name, width)
        resolved = resolve_width_to_integer(width)
        return if resolved.nil?

        key = name.to_s
        map[key] = resolved
        map[sanitize(key)] = resolved
      end

      def resolve_width_to_integer(width)
        case width
        when Integer
          width
        when Range
          if width.begin.is_a?(Integer) && width.end.is_a?(Integer)
            high, low = range_bounds(width)
            high - low + 1
          end
        else
          nil
        end
      end

      def build_memory_name_lookup(module_def, implicit_memories)
        lookup = {}

        Array(module_def.memories).each do |mem|
          key = mem.name.to_s
          lookup[key] = true
          lookup[sanitize(key)] = true
        end

        implicit_memories.each_key do |name|
          key = name.to_s
          lookup[key] = true
          lookup[sanitize(key)] = true
        end

        lookup
      end

      def memory_declared_name?(name)
        ctx = Thread.current[TEMP_SLICE_CTX_KEY]
        return false unless ctx.is_a?(Hash)

        memory_names = ctx[:memory_names]
        return false unless memory_names.is_a?(Hash)

        key = name.to_s
        memory_names[key] || memory_names[sanitize(key)] || false
      end

      def build_implicit_memory_map(module_def, signal_widths)
        explicit_names = Array(module_def.memories).map { |mem| mem.name.to_s }.to_set
        inferred = {}

        Array(module_def.assigns).each do |assign|
          collect_implicit_memories_from_expr(assign.expr, inferred, signal_widths)
        end

        Array(module_def.processes).each do |process|
          Array(process.statements).each do |stmt|
            collect_implicit_memories_from_statement(stmt, inferred, signal_widths)
          end
        end

        inferred.reject { |name, _meta| explicit_names.include?(name.to_s) }
      end

      def collect_implicit_memories_from_statement(stmt, inferred, signal_widths)
        case stmt
        when IR::SeqAssign
          if implicit_memory_seqassign_target?(stmt.target, signal_widths)
            memory_name = target_base_name(stmt.target)
            register_implicit_memory(
              inferred,
              name: memory_name,
              width: expr_width_value(stmt.expr),
              addr_width: dsl_expression_width(stmt.target.index, signal_widths)
            )
          end
          collect_implicit_memories_from_expr(stmt.expr, inferred, signal_widths)
        when IR::MemoryWrite
          register_implicit_memory(
            inferred,
            name: stmt.memory,
            width: expr_width_value(stmt.data),
            addr_width: expr_width_value(stmt.addr)
          )
          collect_implicit_memories_from_expr(stmt.addr, inferred, signal_widths)
          collect_implicit_memories_from_expr(stmt.data, inferred, signal_widths)
        when IR::If
          collect_implicit_memories_from_expr(stmt.condition, inferred, signal_widths)
          Array(stmt.then_statements).each do |inner|
            collect_implicit_memories_from_statement(inner, inferred, signal_widths)
          end
          Array(stmt.else_statements).each do |inner|
            collect_implicit_memories_from_statement(inner, inferred, signal_widths)
          end
        when IR::CaseStmt
          collect_implicit_memories_from_expr(stmt.selector, inferred, signal_widths)
          Array(stmt.branches).each do |branch|
            Array(branch.values).each do |value|
              collect_implicit_memories_from_expr(value, inferred, signal_widths)
            end
            Array(branch.statements).each do |inner|
              collect_implicit_memories_from_statement(inner, inferred, signal_widths)
            end
          end
          Array(stmt.default_statements).each do |inner|
            collect_implicit_memories_from_statement(inner, inferred, signal_widths)
          end
        end
      end

      def collect_implicit_memories_from_expr(expr_node, inferred, signal_widths)
        case expr_node
        when IR::MemoryRead
          register_implicit_memory(
            inferred,
            name: expr_node.memory,
            width: expr_node.width,
            addr_width: expr_width_value(expr_node.addr)
          )
          collect_implicit_memories_from_expr(expr_node.addr, inferred, signal_widths)
        when IR::UnaryOp
          collect_implicit_memories_from_expr(expr_node.operand, inferred, signal_widths)
        when IR::BinaryOp
          collect_implicit_memories_from_expr(expr_node.left, inferred, signal_widths)
          collect_implicit_memories_from_expr(expr_node.right, inferred, signal_widths)
        when IR::Mux
          collect_implicit_memories_from_expr(expr_node.condition, inferred, signal_widths)
          collect_implicit_memories_from_expr(expr_node.when_true, inferred, signal_widths)
          collect_implicit_memories_from_expr(expr_node.when_false, inferred, signal_widths)
        when IR::Concat
          Array(expr_node.parts).each do |part|
            collect_implicit_memories_from_expr(part, inferred, signal_widths)
          end
        when IR::Slice
          collect_implicit_memories_from_expr(expr_node.base, inferred, signal_widths)
        when IR::DynamicSlice
          collect_implicit_memories_from_expr(expr_node.base, inferred, signal_widths)
          collect_implicit_memories_from_expr(expr_node.msb, inferred, signal_widths)
          collect_implicit_memories_from_expr(expr_node.lsb, inferred, signal_widths)
        when IR::Resize
          collect_implicit_memories_from_expr(expr_node.expr, inferred, signal_widths)
        end
      end

      def implicit_memory_seqassign_target?(target, signal_widths)
        return false unless target.is_a?(RHDL::DSL::BitSelect)
        return false if target.index.is_a?(Integer)

        base_name = target_base_name(target)
        return false if base_name.nil? || base_name.empty?

        declared_width = signal_widths[base_name.to_s] || signal_widths[sanitize(base_name.to_s)]
        declared_width.is_a?(Integer) && declared_width <= 1
      rescue StandardError
        false
      end

      def register_implicit_memory(inferred, name:, width:, addr_width:)
        token = name.to_s
        return if token.empty?

        resolved_width = normalize_positive_integer(width)
        return if resolved_width.nil? || resolved_width <= 1

        resolved_addr_width = normalize_positive_integer(addr_width) || 1
        depth_width = [resolved_addr_width, 20].min
        depth = 1 << depth_width
        depth = 2 if depth < 2

        current = inferred[token]
        if current.nil?
          inferred[token] = {
            name: token,
            width: resolved_width,
            addr_width: resolved_addr_width,
            depth: depth
          }
        else
          current[:width] = [current[:width], resolved_width].max
          current[:addr_width] = [current[:addr_width], resolved_addr_width].max
          current[:depth] = [current[:depth], depth].max
        end
      rescue StandardError
        nil
      end

      def expr_width_value(expr_node)
        return nil unless expr_node.respond_to?(:width)

        normalize_positive_integer(expr_node.width)
      rescue StandardError
        nil
      end

      def normalize_positive_integer(value)
        case value
        when Integer
          value.positive? ? value : nil
        when Range
          if value.begin.is_a?(Integer) && value.end.is_a?(Integer)
            width = (value.begin - value.end).abs + 1
            width.positive? ? width : nil
          end
        when String
          token = value.strip
          return nil if token.empty?

          integer = Integer(token)
          integer.positive? ? integer : nil
        else
          nil
        end
      rescue ArgumentError, TypeError
        nil
      end

      def dsl_expression_width(expr_node, signal_widths)
        case expr_node
        when Integer
          [expr_node.bit_length, 1].max
        when RHDL::DSL::Literal
          normalize_positive_integer(expr_node.width) || [expr_node.value.to_i.bit_length, 1].max
        when RHDL::DSL::SignalRef
          normalize_positive_integer(expr_node.width) ||
            signal_widths[expr_node.name.to_s] ||
            signal_widths[sanitize(expr_node.name.to_s)] ||
            1
        when RHDL::DSL::BitSlice
          range = expr_node.range
          if range.is_a?(Range) && range.begin.is_a?(Integer) && range.end.is_a?(Integer)
            (range.begin - range.end).abs + 1
          else
            dsl_expression_width(expr_node.signal, signal_widths)
          end
        when RHDL::DSL::BitSelect
          1
        when RHDL::DSL::UnaryOp
          dsl_expression_width(expr_node.operand, signal_widths)
        when RHDL::DSL::BinaryOp
          left = dsl_expression_width(expr_node.left, signal_widths)
          right = dsl_expression_width(expr_node.right, signal_widths)
          [left, right].compact.max || 1
        when RHDL::DSL::TernaryOp
          true_width = dsl_expression_width(expr_node.when_true, signal_widths)
          false_width = dsl_expression_width(expr_node.when_false, signal_widths)
          [true_width, false_width].compact.max || 1
        when RHDL::DSL::Concatenation
          widths = Array(expr_node.signals).map { |part| dsl_expression_width(part, signal_widths) }
          return nil if widths.any?(&:nil?)

          widths.sum
        when RHDL::DSL::Replication
          value_width = dsl_expression_width(expr_node.signal, signal_widths)
          times =
            case expr_node.times
            when Integer
              expr_node.times
            when RHDL::DSL::Literal
              expr_node.times.value.to_i
            else
              nil
            end
          return nil if value_width.nil? || times.nil? || times <= 0

          value_width * times
        else
          if expr_node.respond_to?(:width)
            normalize_positive_integer(expr_node.width)
          else
            nil
          end
        end
      rescue StandardError
        nil
      end

      def recover_bit_select_rmw_assignment(target_name:, expr_node:)
        merged = expr_node
        return nil unless merged.is_a?(IR::BinaryOp) && merged.op == :|

        cleared = merged.left
        shifted_value = merged.right
        return nil unless cleared.is_a?(IR::BinaryOp) && cleared.op == :&
        return nil unless shifted_value.is_a?(IR::BinaryOp) && shifted_value.op == :<<

        base_signal = cleared.left
        clear_mask = cleared.right
        return nil unless base_signal.is_a?(IR::Signal)
        return nil unless sanitize(base_signal.name) == sanitize(target_name)
        return nil unless clear_mask.is_a?(IR::UnaryOp) && clear_mask.op == :~

        bit_mask = clear_mask.operand
        return nil unless bit_mask.is_a?(IR::BinaryOp) && bit_mask.op == :<<
        return nil unless literal_one?(bit_mask.left)

        mask_index = bit_mask.right
        value_index = shifted_value.right
        return nil unless equivalent_expr?(mask_index, value_index)

        value_term = shifted_value.left
        if value_term.is_a?(IR::BinaryOp) && value_term.op == :&
          left_one = literal_one?(value_term.left)
          right_one = literal_one?(value_term.right)
          if left_one ^ right_one
            value_term = left_one ? value_term.right : value_term.left
          end
        end

        [
          "#{sanitize(base_signal.name)}[#{expr(mask_index)}]",
          value_term
        ]
      end

      def recover_static_slice_rmw_assignment(target_name:, expr_node:)
        merged = expr_node
        return nil unless merged.is_a?(IR::BinaryOp) && merged.op == :|

        cleared = merged.left
        masked = merged.right
        return nil unless cleared.is_a?(IR::BinaryOp) && cleared.op == :&
        return nil unless masked.is_a?(IR::BinaryOp) && masked.op == :&

        base_signal = cleared.left
        keep_mask = cleared.right
        shifted = masked.left
        update_mask = masked.right
        return nil unless base_signal.is_a?(IR::Signal)
        return nil unless sanitize(base_signal.name) == sanitize(target_name)
        return nil unless keep_mask.is_a?(IR::Literal)
        return nil unless shifted.is_a?(IR::BinaryOp) && shifted.op == :<<
        return nil unless update_mask.is_a?(IR::Literal)

        shift_amount = shifted.right
        return nil unless shift_amount.is_a?(IR::Literal)
        low = shift_amount.value
        mask_value = update_mask.value
        keep_value = keep_mask.value
        return nil unless low.is_a?(Integer) && low >= 0
        return nil unless mask_value.is_a?(Integer) && mask_value.positive?
        return nil unless keep_value.is_a?(Integer)

        high = mask_value.bit_length - 1
        slice_width = high - low + 1
        expected_mask = ((1 << slice_width) - 1) << low
        return nil unless expected_mask == mask_value

        base_width = base_signal.width
        if base_width.is_a?(Integer) && base_width.positive?
          full_mask = (1 << base_width) - 1
          return nil unless keep_value == (full_mask ^ mask_value)
        end

        [
          "#{sanitize(base_signal.name)}[#{high}:#{low}]",
          shifted.left
        ]
      end

      def literal_one?(node)
        node.is_a?(IR::Literal) && node.value == 1
      end

      def equivalent_expr?(left, right)
        expr(left) == expr(right)
      rescue StandardError
        false
      end

      def expr(expr_node)
        case expr_node
        when IR::Signal
          sanitize(expr_node.name)
        when IR::Literal
          literal(
            expr_node.value,
            expr_node.width,
            base: expr_node.base,
            signed: expr_node.signed
          )
        when IR::UnaryOp
          "#{unary_op(expr_node.op)}#{expr(expr_node.operand)}"
        when IR::BinaryOp
          "(#{expr(expr_node.left)} #{binary_op(expr_node.op)} #{expr(expr_node.right)})"
        when IR::Mux
          "(#{expr_bool(expr_node.condition)} ? #{expr(expr_node.when_true)} : #{expr(expr_node.when_false)})"
        when IR::Concat
          "{#{expr_node.parts.map { |part| expr(part) }.join(', ')}}"
        when IR::Slice
          base = expr(expr_node.base)
          high, low = range_bounds(expr_node.range)

          # Check if base is a simple signal (can use direct indexing) or complex expression
          is_simple = expr_node.base.is_a?(IR::Signal)

          if is_simple
            # Simple signal - use direct indexing
            if high == low
              "#{base}[#{low}]"
            else
              "#{base}[#{high}:#{low}]"
            end
          else
            # Use inline shift/mask lowering for expression slices to keep output
            # Verilator-compatible without introducing synthetic temp wires.
            numeric_range = high.is_a?(Integer) && low.is_a?(Integer)
            if !numeric_range
              if high == low
                "(#{base})[#{low}]"
              else
                "(#{base})[#{high}:#{low}]"
              end
            elsif high == low
              "((#{base} >> #{low}) & 1'b1)"
            else
              slice_width = high - low + 1
              mask = (1 << slice_width) - 1
              "((#{base} >> #{low}) & #{slice_width}'d#{mask})"
            end
          end
        when IR::DynamicSlice
          dynamic_slice_expr(expr_node)
        when IR::Resize
          resize(expr_node)
        when IR::Case
          case_expr(expr_node)
        when IR::MemoryRead
          "#{sanitize(expr_node.memory)}[#{expr(expr_node.addr)}]"
        else
          raise ArgumentError, "Unsupported expression: #{expr_node.inspect}"
        end
      end

      # Case expression as nested ternary (for combinational use)
      # For use in assign statements: assign y = case_expr
      def case_expr(case_node)
        selector = expr(case_node.selector)
        default_expr = case_node.default ? expr(case_node.default) : literal(0, case_node.width)

        # Build nested ternary from case branches
        result = default_expr
        case_node.cases.reverse_each do |values, branch|
          conditions = values.map { |v| "(#{selector} == #{literal(v, case_node.selector.width)})" }
          cond = conditions.join(" || ")
          result = "(#{cond}) ? #{expr(branch)} : #{result}"
        end
        result
      end

      # Generate sequential block (always @(posedge clk))
      def sequential_block(seq)
        lines = []
        if seq.reset
          lines << "  always @(posedge #{sanitize(seq.clock)} or posedge #{sanitize(seq.reset)}) begin"
          lines << "    if (#{sanitize(seq.reset)}) begin"
          seq.reset_values.each do |name, value|
            lines << "      #{sanitize(name)} <= #{literal(value, 8)};"
          end
          lines << "    end else begin"
          seq.assignments.each do |assign|
            lines << "      #{sanitize(assign.target)} <= #{expr(assign.expr)};"
          end
          lines << "    end"
        else
          lines << "  always @(posedge #{sanitize(seq.clock)}) begin"
          seq.assignments.each do |assign|
            lines << "    #{sanitize(assign.target)} <= #{expr(assign.expr)};"
          end
        end
        lines << "  end"
        lines.join("\n")
      end

      # Generate case statement for process blocks
      def case_statement(case_node, target:, nonblocking:, indent:)
        pad = " " * indent
        op = nonblocking ? "<=" : "="
        lines = []
        lines << "#{pad}case (#{expr(case_node.selector)})"

        case_node.cases.each do |values, branch|
          value_str = values.map { |v| literal(v, case_node.selector.width) }.join(", ")
          lines << "#{pad}  #{value_str}: #{sanitize(target)} #{op} #{expr(branch)};"
        end

        if case_node.default
          lines << "#{pad}  default: #{sanitize(target)} #{op} #{expr(case_node.default)};"
        end

        lines << "#{pad}endcase"
        lines
      end

      # Generate memory declaration
      def memory_decl(mem)
        addr_width = Math.log2(mem.depth).ceil
        "  reg #{width_decl(mem.width)}#{sanitize(mem.name)} [0:#{mem.depth - 1}];"
      end

      # Generate memory write port (in always block)
      def memory_write_block(write_port)
        lines = []
        lines << "  always @(posedge #{sanitize(write_port.clock)}) begin"
        lines << "    if (#{sanitize(write_port.enable)}) begin"
        lines << "      #{sanitize(write_port.memory)}[#{sanitize(write_port.addr)}] <= #{sanitize(write_port.data)};"
        lines << "    end"
        lines << "  end"
        lines.join("\n")
      end

      # Generate memory synchronous read port (in always block, for BRAM inference)
      def memory_sync_read_block(read_port)
        lines = []
        lines << "  always @(posedge #{sanitize(read_port.clock)}) begin"
        if read_port.enable
          lines << "    if (#{sanitize(read_port.enable)}) begin"
          lines << "      #{sanitize(read_port.data)} <= #{sanitize(read_port.memory)}[#{sanitize(read_port.addr)}];"
          lines << "    end"
        else
          lines << "    #{sanitize(read_port.data)} <= #{sanitize(read_port.memory)}[#{sanitize(read_port.addr)}];"
        end
        lines << "  end"
        lines.join("\n")
      end

      def resize(resize_node)
        target_width = resize_node.width
        inner = resize_node.expr
        rendered = expr(inner)
        return rendered if target_width == inner.width
        return rendered unless target_width.is_a?(Integer) && inner.width.is_a?(Integer)

        if target_width < inner.width
          mask = literal((1 << target_width) - 1, inner.width)
          "(#{rendered} & #{mask})"
        else
          pad = target_width - inner.width
          "{{#{pad}{1'b0}}, #{rendered}}"
        end
      end

      def literal(value, width, base: nil, signed: false)
        literal_width = literal_size(width)
        base_token = normalize_literal_base(base)

        if base_token.nil?
          if literal_width == 1
            return value.to_i == 0 ? "1'b0" : "1'b1"
          end

          if literal_width
            sign_token = signed ? "s" : ""
            return "#{literal_width}'#{sign_token}d#{value}"
          end

          return value.to_s
        end

        digits = literal_digits(value, base_token)
        prefix = literal_width.nil? ? "" : literal_width.to_s
        sign_token = signed ? "s" : ""
        "#{prefix}'#{sign_token}#{base_token}#{digits}"
      end

      def normalize_literal_base(base)
        token = base.to_s.strip.downcase
        return nil if token.empty?

        case token
        when "2", "b", "bin", "binary"
          "b"
        when "8", "o", "oct", "octal"
          "o"
        when "10", "d", "dec", "decimal"
          "d"
        when "16", "h", "hex", "hexadecimal"
          "h"
        else
          token
        end
      end

      def literal_digits(value, base)
        integer = value.to_i
        case base
        when "b"
          integer.to_s(2)
        when "o"
          integer.to_s(8)
        when "d"
          integer.to_s(10)
        when "h"
          integer.to_s(16)
        else
          value.to_s
        end
      end

      def unary_op(op)
        case op
        when :~ then "~"
        when :! then "!"
        when :reduce_or then "|"
        when :reduce_and then "&"
        when :reduce_xor then "^"
        else op.to_s
        end
      end

      def binary_op(op)
        {
          :+ => "+",
          :- => "-",
          :& => "&",
          :| => "|",
          :^ => "^",
          :<< => "<<",
          :>> => ">>",
          :== => "==",
          :!= => "!=",
          :< => "<",
          :> => ">",
          :<= => "<=",
          :>= => ">=",
          :* => "*",
          :/ => "/",
          :% => "%"
        }.fetch(op)
      end

      def dynamic_slice_expr(node)
        base_rendered = expr(node.base)
        indexed = indexed_part_select(node)
        unless indexed.nil?
          index_base = expr(indexed.fetch(:index_base))
          width = indexed.fetch(:width)
          direction = indexed.fetch(:direction)
          return "#{base_rendered}[#{index_base} #{direction}: #{width}]"
        end

        msb_rendered = expr(node.msb)
        lsb_rendered = expr(node.lsb)
        width = literal_integer(node.width)

        if width && width.positive?
          mask = (1 << width) - 1
          return "((#{base_rendered} >> #{lsb_rendered}) & #{width}'d#{mask})"
        end

        width_expr = "((#{msb_rendered}) - (#{lsb_rendered}) + 1)"
        mask_expr = "((1 << #{width_expr}) - 1)"
        "((#{base_rendered} >> #{lsb_rendered}) & #{mask_expr})"
      end

      def indexed_part_select(node)
        return nil unless node.base.is_a?(IR::Signal)

        up_delta = constant_offset(upper: node.msb, lower: node.lsb)
        if up_delta && up_delta >= 0
          return {
            index_base: node.lsb,
            width: up_delta + 1,
            direction: "+"
          }
        end

        down_delta = constant_offset(upper: node.lsb, lower: node.msb)
        if down_delta && down_delta >= 0
          return {
            index_base: node.msb,
            width: down_delta + 1,
            direction: "-"
          }
        end

        nil
      end

      def constant_offset(upper:, lower:)
        upper = unwrap_resize_expr(upper)
        lower = unwrap_resize_expr(lower)
        return 0 if expr_structural_equal?(upper, lower)

        return nil unless upper.is_a?(IR::BinaryOp)

        case upper.op
        when :+
          left = unwrap_resize_expr(upper.left)
          right = unwrap_resize_expr(upper.right)
          right_literal = literal_integer(right)
          return right_literal if right_literal && expr_structural_equal?(left, lower)

          left_literal = literal_integer(left)
          return left_literal if left_literal && expr_structural_equal?(right, lower)
        when :-
          left = unwrap_resize_expr(upper.left)
          right = unwrap_resize_expr(upper.right)
          right_literal = literal_integer(right)
          return right_literal if right_literal && expr_structural_equal?(left, lower)
        end

        nil
      end

      def literal_integer(expr_node)
        expr_node = unwrap_resize_expr(expr_node)
        return nil unless expr_node.is_a?(IR::Literal)

        Integer(expr_node.value)
      rescue ArgumentError, TypeError
        nil
      end

      def unwrap_resize_expr(expr_node)
        while expr_node.is_a?(IR::Resize)
          expr_node = expr_node.expr
        end
        expr_node
      end

      def expr_structural_equal?(left, right)
        left = unwrap_resize_expr(left)
        right = unwrap_resize_expr(right)
        return false unless left.class == right.class

        case left
        when IR::Signal
          left.name.to_s == right.name.to_s
        when IR::Literal
          left.value == right.value &&
            left.width == right.width &&
            left.base == right.base &&
            left.signed == right.signed
        when IR::UnaryOp
          left.op == right.op && expr_structural_equal?(left.operand, right.operand)
        when IR::BinaryOp
          left.op == right.op &&
            expr_structural_equal?(left.left, right.left) &&
            expr_structural_equal?(left.right, right.right)
        when IR::Concat
          left.parts.length == right.parts.length &&
            left.parts.zip(right.parts).all? { |l_part, r_part| expr_structural_equal?(l_part, r_part) }
        when IR::Slice
          left.range == right.range && expr_structural_equal?(left.base, right.base)
        else
          false
        end
      end

      # Check if an assignment is circular (assign x = x)
      # This can happen when mux fallback references the target
      def circular_assign?(assign)
        target = assign.target.to_s
        is_self_ref?(assign.expr, target)
      end

      # Recursively check if an expression is just a reference to the target
      # or a mux where both branches are the target (condition ? x : x = x)
      def is_self_ref?(expr_node, target_name)
        case expr_node
        when IR::Signal
          sanitize(expr_node.name) == sanitize(target_name)
        when IR::Resize
          is_self_ref?(expr_node.expr, target_name)
        when IR::Mux
          # A mux is self-referential if both branches are self-referential
          is_self_ref?(expr_node.when_true, target_name) &&
            is_self_ref?(expr_node.when_false, target_name)
        else
          false
        end
      end

      def sanitize(name)
        raw = name.to_s
        if raw.start_with?("\\")
          return raw.end_with?(" ") ? raw : "#{raw} "
        end

        base = raw.gsub(/[^a-zA-Z0-9_]/, "_")
        base = "_#{base}" if base.match?(/\A\d/)
        return "#{base}_rhdl" if VERILOG_KEYWORDS.include?(base)

        base
      end

      def clocked_sensitivity_items(process)
        sensitivity = process.sensitivity_list
        sensitivity = [process.clock] if sensitivity.empty? && process.clock

        sensitivity.map do |sig|
          rendered = sig.to_s
          if rendered.start_with?("posedge ", "negedge ")
            edge, signal = rendered.split(/\s+/, 2)
            "#{edge} #{sanitize(signal)}"
          else
            "posedge #{sanitize(rendered)}"
          end
        end
      end

      def scalar_width?(width)
        case width
        when Integer
          width <= 1
        when Range
          false
        else
          width.to_s == "1"
        end
      end

      def width_bounds(width)
        case width
        when Integer
          [width - 1, 0]
        when Range
          [width.begin, width.end]
        else
          ["#{width}-1", 0]
        end
      end

      def declared_signal_kind(module_def, signal_name)
        return nil unless module_def.respond_to?(:declaration_kinds)

        kinds = module_def.declaration_kinds
        return nil unless kinds.is_a?(Hash)

        key = signal_name.to_sym
        value = kinds[key]
        return value.to_sym unless value.nil?

        string_value = kinds[signal_name.to_s]
        string_value&.to_sym
      rescue StandardError
        nil
      end

      def range_bounds(range)
        if range.begin.is_a?(Integer) && range.end.is_a?(Integer)
          [[range.begin, range.end].max, [range.begin, range.end].min]
        else
          [range.begin, range.end]
        end
      end

      def literal_size(width)
        case width
        when Integer
          width
        when Range
          if width.begin.is_a?(Integer) && width.end.is_a?(Integer)
            high, low = range_bounds(width)
            high - low + 1
          end
        else
          width
        end
      end
    end
  end
end
