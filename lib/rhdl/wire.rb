class Rhdl::Wire

  attr_reader :input, :outputs
  attr_reader :value

  def initialize(val = 0)
    @value = val
    @outputs = Set.new
  end

  def add_output(output)
    @outputs += Array(output)
  end

  def set_input(input)
    @input = input
  end

  # force value to val
  #
  def set!(val = input.value)
    val = val.to_i
    raise 'value must be 0 or 1' if val != 0 && val != 1

    @value = val
    # @outputs.map(&:update!)
    self.class.changed(self)

    self
  end


  def update!
    set!
  end

  def to_i
    @value
  end

  def inspect
    "#{value}"
  end

  def ==(other)
    case other
    when Rhdl::Wire
      value == other.value
    when 0, 1
      value == other
    else
      raise TypeError.new('must be a Wire or Integer')
    end
  end



  class << self
    attr_reader :changes, :propagating

    def changed(wire)
      @changes << wire unless propagating
    end

    def propagate!(force: false)
      @propagating = true
      updated = @changes.dup

      while updated.size > 0
        updated = \
          updated.map { |c| c.outputs.to_a }
                 .flatten
                 .to_set


        updated.reject! do |c|
          orig = c.value
          c.update!
          c.value == orig
        end
      end

      @changes = []
      @propagating = false
      true
    end
  end

  @changes = Set.new
  @propagating = false

end

class Rhdl::WireBundle < Array

  def value
    map { |wire| wire.value }
  end

  def add(*args)
    each { |wire| wire.add(*args) }
  end

  def set!(val)
    w = Wire(val)

    case w
    when Rhdl::WireBundle
      zip(w).flat_map { |wire, w| wire.set!(w.value) }
    else
      flat_map { |wire| wire.set!(w.value) }
    end
  end

  def update!
    each(&:update!)
  end

  def ==(other)
    equal = true
    each.with_index { |wire, idx| equal = equal && other[idx].to_i == wire }
    equal
  end

  def inspect
    self.map(&:to_i).join('')
  end

end

# Wire constructor
#
def Wire(val=nil, bits: 1)
  case val
  when String
    Wire(val.split(//).map(&:to_i))
  when Array
    Rhdl::WireBundle.new(val.map { |v| Wire(v) })
  when Rhdl::Wire
    val
  when 0, 1
    Rhdl::Wire.new(val)
  when nil
    if bits == 1
      Rhdl::Wire.new(0)
    else
      Rhdl::WireBundle.new((0...bits).map { Rhdl::Wire.new(0) })
    end
  end
end
