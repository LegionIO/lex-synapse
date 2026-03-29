# frozen_string_literal: true

require 'legion/extensions/synapse/version'
require_relative 'synapse/client'

module Legion
  module Extensions
    module Synapse
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core

      def self.remote_invocable?
        false
      end

      def self.data_required?
        true
      end

      def data_required?
        true
      end
    end
  end
end
