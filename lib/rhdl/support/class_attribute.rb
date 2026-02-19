# frozen_string_literal: true

class Module
  unless method_defined?(:class_attribute)
    # Lightweight class-level attribute helper with superclass fallback.
    def class_attribute(*attrs)
      attrs.each do |attr_name|
        ivar = :"@#{attr_name}"
        reader_name = attr_name.to_sym
        writer_name = :"#{attr_name}="

        define_singleton_method(reader_name) do
          if instance_variable_defined?(ivar)
            instance_variable_get(ivar)
          elsif superclass.respond_to?(reader_name)
            superclass.public_send(reader_name)
          end
        end

        define_singleton_method(writer_name) do |value|
          instance_variable_set(ivar, value)
        end

        define_method(reader_name) do
          self.class.public_send(reader_name)
        end

        define_method(writer_name) do |value|
          self.class.public_send(writer_name, value)
        end
      end
    end
  end
end
