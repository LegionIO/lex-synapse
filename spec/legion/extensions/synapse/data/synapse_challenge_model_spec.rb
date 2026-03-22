# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SynapseChallenge model' do
  let(:synapse) do
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
      routing_strategy: 'direct', confidence: 0.85, status: 'active',
      origin: 'explicit', version: 1
    )
  end

  let(:proposal) do
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
      synapse_id: synapse.id, proposal_type: 'transform_mutation',
      trigger: 'proactive', status: 'pending'
    )
  end

  let(:model) { Legion::Extensions::Synapse::Data::Model::SynapseChallenge }

  after do
    model.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  it 'creates a challenge record' do
    challenge = model.create(
      proposal_id: proposal.id, challenger_type: 'conflict',
      verdict: 'support', reasoning: 'no conflicts',
      challenger_confidence: 0.5
    )
    expect(challenge.id).not_to be_nil
    expect(challenge.verdict).to eq('support')
  end

  it 'belongs to a proposal' do
    challenge = model.create(
      proposal_id: proposal.id, challenger_type: 'llm',
      verdict: 'challenge', reasoning: 'weak rationale',
      challenger_confidence: 0.6
    )
    expect(challenge.proposal).to eq(proposal)
  end

  it 'queries by challenger_type' do
    model.create(proposal_id: proposal.id, challenger_type: 'conflict', verdict: 'support')
    model.create(proposal_id: proposal.id, challenger_type: 'llm', verdict: 'challenge')
    expect(model.where(challenger_type: 'llm').count).to eq(1)
  end

  it 'queries by outcome' do
    model.create(proposal_id: proposal.id, challenger_type: 'llm', verdict: 'support', outcome: 'correct')
    model.create(proposal_id: proposal.id, challenger_type: 'llm', verdict: 'challenge', outcome: 'incorrect')
    expect(model.where(outcome: 'correct').count).to eq(1)
  end

  it 'defaults challenger_confidence to 0.5' do
    challenge = model.create(
      proposal_id: proposal.id, challenger_type: 'conflict', verdict: 'support'
    )
    expect(challenge.challenger_confidence).to eq(0.5)
  end
end
