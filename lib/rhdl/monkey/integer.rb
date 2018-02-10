class Integer

  # 2s complement binary conversion
  #
  def to_b(bits=8)
    if self >= 0
      to_s(2).rjust(bits,'0')
    else
      (-self-1).to_s(2).rjust(bits,'0').gsub('0', '_').gsub('1','0').gsub('_','1')
    end
  end

  def sext(bits=8)
    to_s(2).sext(bits)
  end


  def to_ba(bits=8)
    to_b(bits).to_a.map(&:to_i)
  end


  def to_bi(bits=8)
    to_b(bits).reverse
  end


  def to_bai(bits=8)
    to_ba(bits).reverse
  end

end
