# frozen_string_literal: true

require_relative 'runners/evaluate'
require_relative 'runners/pain'
require_relative 'runners/crystallize'
require_relative 'runners/mutate'
require_relative 'runners/revert'
require_relative 'runners/report'

module Legion
  module Extensions
    module Synapse
      class Client
        include Runners::Evaluate
        include Runners::Pain
        include Runners::Crystallize
        include Runners::Mutate
        include Runners::Revert
        include Runners::Report

        attr_reader :conditioner_client, :transformer_client

        def initialize(conditioner_client: nil, transformer_client: nil)
          @conditioner_client = conditioner_client
          @transformer_client = transformer_client
        end

        def evaluate(synapse_id:, payload: {})
          super(
            synapse_id:         synapse_id,
            payload:            payload,
            conditioner_client: @conditioner_client,
            transformer_client: @transformer_client
          )
        end

        def create(source_function_id:, target_function_id:, attention: nil, transform: nil,
                   routing_strategy: 'direct', origin: 'explicit', relationship_id: nil)
          Data::Model::Synapse.create(
            source_function_id: source_function_id,
            target_function_id: target_function_id,
            attention:          attention,
            transform:          transform,
            routing_strategy:   routing_strategy,
            origin:             origin,
            relationship_id:    relationship_id,
            confidence:         Helpers::Confidence.starting_score(origin),
            status:             origin == 'emergent' ? 'observing' : 'active'
          )
        end
      end
    end
  end
end
