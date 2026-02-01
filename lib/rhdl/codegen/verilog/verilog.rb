# Verilog-2001 code generator

require_relative "../ir/ir"

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
          lines << "  reg #{width_decl(reg.width)}#{sanitize(reg.name)};"
        end
        module_def.nets.each do |net|
          lines << "  wire #{width_decl(net.width)}#{sanitize(net.name)};"
        end

        # Memory array declarations
        module_def.memories.each do |mem|
          lines << "  reg #{width_decl(mem.width)}#{sanitize(mem.name)} [0:#{mem.depth - 1}];"
        end
        lines << "" unless module_def.regs.empty? && module_def.nets.empty? && module_def.memories.empty?

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

        lines << ""
        lines << "endmodule"
        lines.join("\n")
      end

      # Generate module instantiation
      def instance_block(instance)
        lines = []

        # Module name with optional parameters
        if instance.parameters.empty?
          lines << "  #{sanitize(instance.module_name)} #{sanitize(instance.name)} ("
        else
          param_list = instance.parameters.map { |k, v| ".#{sanitize(k)}(#{v})" }.join(", ")
          lines << "  #{sanitize(instance.module_name)} #(#{param_list}) #{sanitize(instance.name)} ("
        end

        # Port connections
        port_lines = instance.connections.map do |conn|
          signal_str = conn.signal.is_a?(String) ? sanitize(conn.signal) : expr(conn.signal)
          "    .#{sanitize(conn.port_name)}(#{signal_str})"
        end
        lines << port_lines.join(",\n")

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
        "#{dir} #{width_decl(port.width)}#{sanitize(port.name)}".strip
      end

      def width_decl(width)
        width > 1 ? "[#{width - 1}:0] " : ""
      end

      def process_block(process)
        lines = []
        if process.clocked
          lines << "  always @(posedge #{sanitize(process.clock)}) begin"
          process.statements.each { |stmt| lines.concat(statement(stmt, nonblocking: true, indent: 2)) }
          lines << "  end"
        else
          lines << "  always @* begin"
          process.statements.each { |stmt| lines.concat(statement(stmt, nonblocking: false, indent: 2)) }
          lines << "  end"
        end
        lines.join("\n")
      end

      def statement(stmt, nonblocking:, indent: 0)
        pad = " " * indent
        case stmt
        when IR::SeqAssign
          op = nonblocking ? "<=" : "="
          ["#{pad}#{sanitize(stmt.target)} #{op} #{expr(stmt.expr)};"]
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
        else
          []
        end
      end

      def expr_bool(expr_node)
        rendered = expr(expr_node)
        return rendered if expr_node.width == 1

        "(|#{rendered})"
      end

      def expr(expr_node)
        case expr_node
        when IR::Signal
          sanitize(expr_node.name)
        when IR::Literal
          literal(expr_node.value, expr_node.width)
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
          # Handle both ascending (0..7) and descending (7..0) ranges
          high = [expr_node.range.begin, expr_node.range.end].max
          low = [expr_node.range.begin, expr_node.range.end].min

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
            # Complex expression - use shift and mask to extract bits
            # (expr >> low) & mask
            slice_width = high - low + 1
            if low == 0
              if slice_width == 1
                "(#{base} & 1'b1)"
              else
                "(#{base} & #{slice_width}'d#{(1 << slice_width) - 1})"
              end
            else
              if slice_width == 1
                "((#{base} >> #{low}) & 1'b1)"
              else
                "((#{base} >> #{low}) & #{slice_width}'d#{(1 << slice_width) - 1})"
              end
            end
          end
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

        if target_width < inner.width
          mask = literal((1 << target_width) - 1, inner.width)
          "(#{rendered} & #{mask})"
        else
          pad = target_width - inner.width
          "{{#{pad}{1'b0}}, #{rendered}}"
        end
      end

      def literal(value, width)
        if width == 1
          value.to_i == 0 ? "1'b0" : "1'b1"
        else
          "#{width}'d#{value}"
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
        base = name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
        base = "_#{base}" if base.match?(/\A\d/)
        return "#{base}_rhdl" if VERILOG_KEYWORDS.include?(base)

        base
      end
    end
  end
end
