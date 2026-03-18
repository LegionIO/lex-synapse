# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Data
        module Model
          class Synapse < Sequel::Model(:synapses)
            one_to_many :mutations, class: 'Legion::Extensions::Synapse::Data::Model::SynapseMutation'
            one_to_many :signals,   class: 'Legion::Extensions::Synapse::Data::Model::SynapseSignal'
          end
        end
      end
    end
  end
end
