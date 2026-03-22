# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Data
        module Model
          def self.define_synapse_challenge_model
            @define_mutex.synchronize do
              return if const_defined?(:SynapseChallenge, false)
              return unless defined?(Legion::Data) && Legion::Settings.dig(:data, :connected)

              db = Sequel::Model.db
              return unless db&.table_exists?(:synapse_challenges)

              klass = Class.new(Sequel::Model(:synapse_challenges)) do
                many_to_one :proposal, class: 'Legion::Extensions::Synapse::Data::Model::SynapseProposal',
                                       key:   :proposal_id
              end
              klass.set_primary_key :id
              const_set(:SynapseChallenge, klass)
            end
          end
        end
      end
    end
  end
end
