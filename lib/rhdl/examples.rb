examples_path = File.expand_path('../../../examples', __FILE__)
Dir["#{examples_path}/*.rb"].each { |f| require f }
