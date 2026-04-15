# frozen_string_literal: true

require 'legion/extensions/synapse/version'
require_relative 'synapse/client'

module Legion
  module Extensions
    module Synapse
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core, false

      def self.remote_invocable?
        false
      end

      def self.mcp_tools?
        false
      end

      def self.mcp_tools_deferred?
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
