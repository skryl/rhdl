class Rhdl::LogicGate
  attr_reader :a, :b, :out
  attr_reader :value, :inputs, :outputs

  def initialize(a: nil, b: nil, out: nil)
    @a     = Wire(a)
    @b     = Wire(b)
    @out   = Wire(out)

    @a.add_output(self)
    @b.add_output(self)
    @out.set_input(self)

    @inputs  = [@a, @b]
    @outputs = [@out]

    update!
    out&.set!(@value)
  end

  def set!(a: nil, b: nil)
    @value = op(a, b)
    self
  end

  def update!
    set!(a: @a.value, b: @b.value)
  end


  def inspect
    "#{self.class.name}(#{@a.value}, #{@b.value}) => #{@out.value}"
  end
end

class Rhdl::AndGate < Rhdl::LogicGate

  def op(val0, val1)
    val0 & val1
  end

end


class Rhdl::NandGate < Rhdl::LogicGate

  def op(val0, val1)
    (val0 & val1) == 1 ? 0 : 1
  end

end


class Rhdl::OrGate < Rhdl::LogicGate

  def op(val0, val1)
    (val0 | val1)
  end

end


class Rhdl::XorGate < Rhdl::LogicGate

  def op(val0, val1)
    (val0 ^ val1)
  end

end


class Rhdl::NorGate < Rhdl::LogicGate

  def op(val0, val1)
    (val0 | val1) == 1 ? 0 : 1
  end

end


class Rhdl::NotGate < Rhdl::LogicGate

  def op(val0, val1)
    val0 == 0 ? 1 : 0
  end

end
