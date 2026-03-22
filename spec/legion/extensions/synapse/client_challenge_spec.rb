# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/legion/extensions/synapse/client'

RSpec.describe 'Synapse::Client challenge methods' do
  let(:client) { Legion::Extensions::Synapse::Client.new }

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    allow(Legion::Settings).to receive(:dig).with(:data, :connected).and_return(true)
    allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'challenge').and_return(nil)
    allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'proposals').and_return(nil)
  end

  after(:each) do
    Legion::Extensions::Synapse::Data::Model.define_synapse_challenge_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_proposal_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_signal_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_mutation_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_model
    Legion::Extensions::Synapse::Data::Model::SynapseChallenge.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  let(:synapse) do
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
      routing_strategy: 'direct', confidence: 0.85, status: 'active',
      origin: 'explicit', version: 1
    )
  end

  let(:proposal) do
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
      synapse_id: synapse.id, proposal_type: 'transform_mutation',
      trigger: 'proactive', status: 'pending', rationale: 'test'
    )
  end

  describe '#challenge_proposal' do
    it 'challenges a pending proposal' do
      result = client.challenge_proposal(proposal_id: proposal.id)
      expect(result[:success]).to be true
    end
  end

  describe '#challenges' do
    it 'returns challenge records for a proposal' do
      client.challenge_proposal(proposal_id: proposal.id)
      results = client.challenges(proposal_id: proposal.id)
      expect(results).not_to be_empty
      expect(results.first.challenger_type).to eq('conflict')
    end
  end

  describe '#challenger_stats' do
    it 'returns stats hash' do
      stats = client.challenger_stats
      expect(stats).to include(:total, :correct, :by_type)
    end
  end
end
