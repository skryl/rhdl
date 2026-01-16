# VHDL-2008 code generator

require_relative "ir"

module RHDL
  module Export
    module VHDL
      VHDL_KEYWORDS = %w[
        abs access after alias all and architecture array assert attribute begin block body
        buffer bus case component configuration constant context cover disconnect downto
        else elsif end entity exit file for force function generate generic group guarded
        if impure in inertial inout is label library linkage literal loop map mod nand new
        next nor not null of on open or others out package port postponed procedure process
        protected pure range record register reject release report return rol ror select
        severity signal shared sla sll sra srl subtype then to transport type unaffected
        units until use variable wait when while with xnor xor
      ].freeze

      module_function

      def generate(module_def)
        name = sanitize(module_def.name)
        lines = []
        lines << "library ieee;"
        lines << "use ieee.std_logic_1164.all;"
        lines << "use ieee.numeric_std.all;"
        lines << ""
        lines << "entity #{name} is"
        unless module_def.ports.empty?
          lines << "  port("
          port_lines = module_def.ports.map { |port| "    #{port_decl(port)}" }
          lines << port_lines.join(";\n")
          lines << "  );"
        end
        lines << "end #{name};"
        lines << ""
        lines << "architecture rtl of #{name} is"
        module_def.regs.each do |reg|
          lines << "  signal #{sanitize(reg.name)} : #{type_for(reg.width)};"
        end
        module_def.nets.each do |net|
          lines << "  signal #{sanitize(net.name)} : #{type_for(net.width)};"
        end
        lines << "begin"

        module_def.assigns.each do |assign|
          lines << "  #{sanitize(assign.target)} <= #{expr(assign.expr)};"
        end

        module_def.processes.each do |process|
          lines << ""
          lines << process_block(process)
        end

        lines << "end rtl;"
        lines.join("\n")
      end

      def port_decl(port)
        dir = case port.direction
              when :in then "in"
              when :out then "out"
              when :inout then "inout"
              else "in"
              end
        "#{sanitize(port.name)} : #{dir} #{type_for(port.width)}"
      end

      def type_for(width)
        width > 1 ? "std_logic_vector(#{width - 1} downto 0)" : "std_logic"
      end

      def process_block(process)
        lines = []
        if process.clocked
          lines << "  #{sanitize(process.name)} : process(#{sanitize(process.clock)})"
          lines << "  begin"
          lines << "    if rising_edge(#{sanitize(process.clock)}) then"
          process.statements.each do |stmt|
            lines.concat(statement(stmt, indent: 6))
          end
          lines << "    end if;"
          lines << "  end process #{sanitize(process.name)};"
        else
          sens = process.sensitivity_list.map { |sig| sanitize(sig) }.join(", ")
          lines << "  #{sanitize(process.name)} : process(#{sens})"
          lines << "  begin"
          process.statements.each do |stmt|
            lines.concat(statement(stmt, indent: 4))
          end
          lines << "  end process #{sanitize(process.name)};"
        end
        lines.join("\n")
      end

      def statement(stmt, indent:)
        pad = " " * indent
        case stmt
        when IR::SeqAssign
          ["#{pad}#{sanitize(stmt.target)} <= #{expr(stmt.expr)};"]
        when IR::If
          cond = expr_bool(stmt.condition)
          lines = ["#{pad}if #{cond} then"]
          stmt.then_statements.each { |s| lines.concat(statement(s, indent: indent + 2)) }
          unless stmt.else_statements.empty?
            lines << "#{pad}else"
            stmt.else_statements.each { |s| lines.concat(statement(s, indent: indent + 2)) }
          end
          lines << "#{pad}end if;"
          lines
        else
          []
        end
      end

      def expr_bool(expr_node)
        if expr_node.is_a?(IR::BinaryOp) && comparison_op?(expr_node.op)
          return expr(expr_node)
        end

        rendered = expr(expr_node)
        if expr_node.width == 1
          "#{rendered} = '1'"
        else
          "#{rendered} /= (others => '0')"
        end
      end

      def expr(expr_node)
        case expr_node
        when IR::Signal
          sanitize(expr_node.name)
        when IR::Literal
          literal(expr_node.value, expr_node.width)
        when IR::UnaryOp
          "not #{expr(expr_node.operand)}"
        when IR::BinaryOp
          binary_expr(expr_node)
        when IR::Mux
          "(#{expr(expr_node.when_true)} when #{expr_bool(expr_node.condition)} else #{expr(expr_node.when_false)})"
        when IR::Concat
          expr_node.parts.map { |part| expr(part) }.join(" & ")
        when IR::Slice
          base = expr(expr_node.base)
          if expr_node.range.min == expr_node.range.max
            "#{base}(#{expr_node.range.min})"
          else
            "#{base}(#{expr_node.range.max} downto #{expr_node.range.min})"
          end
        when IR::Resize
          resize(expr_node)
        else
          raise ArgumentError, "Unsupported expression: #{expr_node.inspect}"
        end
      end

      def binary_expr(expr_node)
        op = expr_node.op
        left = expr(expr_node.left)
        right = expr(expr_node.right)

        if comparison_op?(op)
          return "(#{compare_operand(expr_node.left, left)} #{comparison_op(op)} #{compare_operand(expr_node.right, right)})"
        end

        case op
        when :+, :-
          "std_logic_vector(unsigned(#{left}) #{binary_op(op)} unsigned(#{right}))"
        when :&
          "(#{left} and #{right})"
        when :|
          "(#{left} or #{right})"
        when :^
          "(#{left} xor #{right})"
        when :<<
          "std_logic_vector(shift_left(unsigned(#{left}), #{shift_amount(expr_node.right)}))"
        when :>>
          "std_logic_vector(shift_right(unsigned(#{left}), #{shift_amount(expr_node.right)}))"
        else
          raise ArgumentError, "Unsupported binary operator: #{op}"
        end
      end

      def compare_operand(node, rendered)
        return rendered if node.width == 1

        "unsigned(#{rendered})"
      end

      def shift_amount(node)
        if node.is_a?(IR::Literal)
          node.value
        else
          "to_integer(unsigned(#{expr(node)}))"
        end
      end

      def resize(resize_node)
        target_width = resize_node.width
        inner = resize_node.expr
        rendered = expr(inner)
        return rendered if target_width == inner.width

        if inner.width == 1
          vector = "(0 downto 0 => #{rendered})"
          rendered = "std_logic_vector'(#{vector})"
        end

        "std_logic_vector(resize(unsigned(#{rendered}), #{target_width}))"
      end

      def literal(value, width)
        if width == 1
          value.to_i == 0 ? "'0'" : "'1'"
        else
          "std_logic_vector(to_unsigned(#{value}, #{width}))"
        end
      end

      def binary_op(op)
        {
          :+ => "+",
          :- => "-",
          :<< => "sll",
          :>> => "srl"
        }.fetch(op)
      end

      def comparison_op(op)
        {
          :== => "=",
          :!= => "/=",
          :< => "<",
          :> => ">",
          :<= => "<=",
          :>= => ">="
        }.fetch(op)
      end

      def comparison_op?(op)
        %i[== != < > <= >=].include?(op)
      end

      def sanitize(name)
        base = name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
        base = "#{base}_rhdl" if VHDL_KEYWORDS.include?(base.downcase)
        base
      end
    end
  end
end
