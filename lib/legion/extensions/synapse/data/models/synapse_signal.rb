# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Data
        module Model
          def self.define_synapse_signal_model
            @define_mutex.synchronize do
              return if const_defined?(:SynapseSignal, false)
              return unless defined?(Legion::Data) && Legion::Settings.dig(:data, :connected)

              db = Sequel::Model.db
              return unless db&.table_exists?(:synapse_signals)

              klass = Class.new(Sequel::Model(:synapse_signals)) do
                many_to_one :synapse, class: 'Legion::Extensions::Synapse::Data::Model::Synapse',
                                      key:   :synapse_id
              end
              klass.set_primary_key :id
              const_set(:SynapseSignal, klass)
            end
          end
        end
      end
    end
  end
end
