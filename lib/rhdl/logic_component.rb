class Rhdl::LogicComponent
  extend Forwardable

  attr_reader :inputs, :outputs, :wires, :connections

  def_delegators :@logic, :components
  def_delegators :@klass, :input_types, :output_types, :wire_types, :logic_block


  def initialize(**values)
    @klass = self.class

    validate_port_names!(values.keys)

    @inputs  = input_types&.each_with_object({})  do |(name, opts), h|
      h[name] = Wire(values[name], **opts)
    end || {}

    @outputs = output_types&.each_with_object({}) do |(name, opts), h|
      h[name] = Wire(values[name], **opts)
    end || {}

    @wires   = wire_types&.each_with_object({})   do |(name, opts), h|
      h[name] = Wire(**opts)
    end || {}

    @connections = @inputs.merge(@outputs).merge(@wires).freeze

    @logic = LogicContext.new(@connections, logic_block)
    update!
  end


  def set!(**values)
    validate_port_names!(values.keys)

    values.flat_map do |key, val|
      inputs[key].set!(val)
    end

    Rhdl::Wire.propagate!
    self
  end


  def update!
    set!(inputs)
  end


  def inspect
    "#{self.class.name}#{inputs} => #{outputs}"
  end


  def validate_port_names!(names)
    names.map(&:to_sym).each do |name|
      if !input_types.keys.include?(name) && !output_types.keys.include?(name)
        raise "#{name} is not a port in #{self.class.name}"
      end
    end
  end



  # Logic Execution Context
  #
  class LogicContext #< BasicObject
    attr_reader :inputs, :outputs, :wires, :components

    def initialize(connections, logic_block, **defaults)
      @connections = connections
      @components  = []

      @connections.each do |name, val|
        instance_eval "def #{name}; @connections[:#{name}] end"
      end

      instance_exec(&logic_block)
    end

    def method_missing(method, *args, &blk)
      if (const = (::Rhdl.const_get("#{method}") rescue nil) ||
                  (::Object.const_get("#{method}") rescue nil))
        @components << const.new(*args)
      else
        super
      end
    end
  end


  # DSL definition
  #
  class << self

    attr_reader :input_types, :output_types, :wire_types, :logic_block

    def inputs(*inputs, **opts)
      @input_types ||= {}

      inputs.each { |input| @input_types[input.to_sym] = opts }
    end


    def outputs(*outputs, **opts)
      @output_types ||= {}

      outputs.each { |output| @output_types[output.to_sym] = opts }
    end


    def wires(*wires, **opts)
      @wire_types ||= {}

      wires.each { |wire| @wire_types[wire.to_sym] = opts }
    end


    def logic(&blk)
      @logic_block = blk
    end


    alias_method :input,  :inputs
    alias_method :output, :outputs
    alias_method :wire,   :wires

  end
end

