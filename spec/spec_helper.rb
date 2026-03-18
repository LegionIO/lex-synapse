# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

require 'bundler/setup'
require 'json'

unless defined?(Legion::Logging)
  module Legion
    module Logging
      def self.info(*); end
      def self.debug(*); end
      def self.warn(*); end
      def self.error(*); end
    end
  end
end

unless defined?(Legion::JSON)
  module Legion
    module JSON
      def self.load(str)
        ::JSON.parse(str, symbolize_names: true)
      end

      def self.dump(obj)
        ::JSON.generate(obj)
      end
    end
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
