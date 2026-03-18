# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Data
        module Model
          class SynapseMutation < Sequel::Model(:synapse_mutations)
            many_to_one :synapse, class: 'Legion::Extensions::Synapse::Data::Model::Synapse'
          end
        end
      end
    end
  end
end
