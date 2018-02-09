class Array

  def multisample(size, count=1)
    (0...count).map { infinisample(size) }.transpose.each do |vars|
      yield vars
    end
  end


  def infinisample(size)
    (0..size).map { self[rand(self.length)] }
  end

end
