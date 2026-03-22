# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Data
        module Model
          def self.define_synapse_proposal_model
            @define_mutex.synchronize do
              return if const_defined?(:SynapseProposal, false)
              return unless defined?(Legion::Data) && Legion::Settings.dig(:data, :connected)

              db = Sequel::Model.db
              return unless db&.table_exists?(:synapse_proposals)

              klass = Class.new(Sequel::Model(:synapse_proposals)) do
                many_to_one :synapse, class: 'Legion::Extensions::Synapse::Data::Model::Synapse',
                                      key:   :synapse_id
              end
              klass.set_primary_key :id
              const_set(:SynapseProposal, klass)
            end
          end
        end
      end
    end
  end
end
