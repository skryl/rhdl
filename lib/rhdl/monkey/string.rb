class String

  def to_a
    each_char.to_a
  end

  def sext(bits=8)
    rjust(bits, self[0])
  end

end
