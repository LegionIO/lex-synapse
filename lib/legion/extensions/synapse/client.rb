# frozen_string_literal: true

require_relative 'runners/evaluate'
require_relative 'runners/pain'
require_relative 'runners/crystallize'
require_relative 'runners/mutate'
require_relative 'runners/revert'
require_relative 'runners/report'
require_relative 'runners/gaia_report'
require_relative 'runners/dream'
require_relative 'runners/promote'
require_relative 'runners/retrieve'
require_relative 'runners/propose'
require_relative 'runners/challenge'
require_relative 'data/models/synapse_proposal'
require_relative 'helpers/proposals'

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
        include Runners::GaiaReport
        include Runners::Dream
        include Runners::Promote
        include Runners::Retrieve
        include Runners::Propose
        include Runners::Challenge

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
          Data::Model.define_synapse_model
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

        def proposals(synapse_id:, status: nil)
          Data::Model.define_synapse_proposal_model
          dataset = Data::Model::SynapseProposal.where(synapse_id: synapse_id)
          dataset = dataset.where(status: status) if status
          dataset.order(Sequel.desc(:id)).all
        end

        def review_proposal(proposal_id:, status:)
          Data::Model.define_synapse_proposal_model
          return { success: false, error: "invalid status: #{status}" } unless Helpers::Proposals::VALID_STATUSES.include?(status)

          proposal = Data::Model::SynapseProposal[proposal_id]
          return { success: false, error: 'proposal not found' } unless proposal

          proposal.update(status: status, reviewed_at: Time.now)
          { success: true, proposal_id: proposal_id, status: status }
        end

        def challenge_proposal(proposal_id:)
          super(proposal_id: proposal_id, transformer_client: @transformer_client)
        end

        def challenges(proposal_id:)
          Data::Model.define_synapse_challenge_model
          Data::Model::SynapseChallenge.where(proposal_id: proposal_id).order(Sequel.desc(:id)).all
        end

        def challenger_stats
          Data::Model.define_synapse_challenge_model
          resolved = Data::Model::SynapseChallenge.exclude(outcome: nil)
          {
            total:   resolved.count,
            correct: resolved.where(outcome: 'correct').count,
            by_type: resolved.group_and_count(:challenger_type).to_h { |r| [r[:challenger_type], r[:count]] }
          }
        end
      end
    end
  end
end
