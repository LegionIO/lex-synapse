# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

require 'bundler/setup'
require 'legion/logging'
require 'legion/json'
require 'legion/settings'

require_relative 'support/database'

unless defined?(Legion::Extensions::Helpers::Lex)
  module Legion
    module Extensions
      module Helpers
        module Lex; end
      end
    end
  end
end

unless defined?(Legion::Extensions::Actors::Subscription)
  module Legion
    module Extensions
      module Actors
        class Subscription; end
      end
    end
  end
end

unless defined?(Legion::Extensions::Actors::Every)
  module Legion
    module Extensions
      module Actors
        class Every; end
      end
    end
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
