# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Data
        module Model
          def self.define_synapse_model
            return if const_defined?(:Synapse, false)
            return unless defined?(Legion::Data) && Legion::Settings.dig(:data, :connected)

            db = Sequel::Model.db
            return unless db&.table_exists?(:synapses)

            klass = Class.new(Sequel::Model(:synapses)) do
              one_to_many :mutations, class: 'Legion::Extensions::Synapse::Data::Model::SynapseMutation',
                                      key:   :synapse_id
              one_to_many :signals,   class: 'Legion::Extensions::Synapse::Data::Model::SynapseSignal',
                                      key:   :synapse_id
            end
            klass.set_primary_key :id
            const_set(:Synapse, klass)
          end
        end
      end
    end
  end
end
