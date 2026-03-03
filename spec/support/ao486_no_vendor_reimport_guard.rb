# frozen_string_literal: true

RSpec.configure do |config|
  config.around(:each, :no_vendor_reimport) do |example|
    if defined?(RHDL::Import) && RHDL::Import.respond_to?(:project)
      singleton = RHDL::Import.singleton_class
      original_project = RHDL::Import.method(:project)

      singleton.send(:define_method, :project) do |out:, **_options|
        _ = out
        raise "RHDL::Import.project is disallowed in ao486 non-import specs; use pre-generated artifacts under examples/ao486/hdl"
      end

      begin
        example.run
      ensure
        singleton.send(:define_method, :project, original_project)
      end
    else
      example.run
    end
  end
end
