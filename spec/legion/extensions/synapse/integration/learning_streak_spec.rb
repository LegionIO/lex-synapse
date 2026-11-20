# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/client'

RSpec.describe 'Synapse repair eligibility and consecutive successes' do
  let(:transformer) { double('TransformerClient') }
  let(:client) { Legion::Extensions::Synapse::Client.new(transformer_client: transformer) }
  let(:synapse) { client.create(source_function_id: 1, target_function_id: 2) }

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseChallenge.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  it 'offers repair when validation lowers an eligible synapse below autonomy' do
    synapse.update(confidence: 0.8, transform: '{"template":"bad"}', consecutive_successes: 12)
    allow(transformer).to receive(:transform).with(hash_including(engine: nil)).and_return(success: false, errors: ['invalid'])
    allow(transformer).to receive(:transform).with(hash_including(engine: :llm)).and_return(success: true, result: { template: 'fixed' })
    expect(client.evaluate(synapse_id: synapse.id)[:success]).to be(false)
    expect(synapse.refresh.confidence).to be_within(0.0001).of(0.77)
    expect(synapse.consecutive_successes).to eq(0)
    expect(synapse.proposals_dataset.first.proposal_type).to eq('transform_mutation')
  end

  it 'does not grant repair eligibility to a previously ineligible synapse' do
    synapse.update(confidence: 0.7, transform: '{"template":"bad"}')
    allow(transformer).to receive(:transform).and_return(success: false, errors: ['invalid'])
    client.evaluate(synapse_id: synapse.id)
    expect(synapse.proposals_dataset.count).to eq(0)
  end

  it 'persists the success streak across client instances' do
    client.evaluate(synapse_id: synapse.id)
    Legion::Extensions::Synapse::Client.new.evaluate(synapse_id: synapse.id)
    expect(synapse.refresh.consecutive_successes).to eq(2)
  end

  it 'applies the existing bonus on the 51st success' do
    synapse.update(confidence: 0.7, consecutive_successes: 50)
    client.evaluate(synapse_id: synapse.id)
    expect(synapse.refresh.confidence).to be_within(0.0001).of(0.77)
    expect(synapse.consecutive_successes).to eq(51)
  end

  it 'does not award the bonus on the 50th success' do
    synapse.update(confidence: 0.7, consecutive_successes: 49)
    client.evaluate(synapse_id: synapse.id)
    expect(synapse.refresh.confidence).to be_within(0.0001).of(0.72)
  end

  it 'preserves the streak when execution is unavailable' do
    synapse.update(attention: '{"field":"value"}', consecutive_successes: 12)
    client.evaluate(synapse_id: synapse.id)
    expect(synapse.refresh.consecutive_successes).to eq(12)
  end

  it 'resets the streak on downstream pain' do
    synapse.update(consecutive_successes: 50)
    client.handle_pain(synapse_id: synapse.id)
    client.evaluate(synapse_id: synapse.id)
    expect(synapse.refresh.consecutive_successes).to eq(1)
    expect(synapse.confidence).to be_within(0.0001).of(0.67)
  end

  it 'applies success and its streak bonus to updates committed during evaluation' do
    synapse.update(transform: '{"template":"hello"}')
    allow(transformer).to receive(:transform) do
      synapse.update(confidence: 0.4, consecutive_successes: 50)
      { success: true, result: {} }
    end

    client.evaluate(synapse_id: synapse.id)

    expect(synapse.refresh.confidence).to be_within(0.0001).of(0.47)
    expect(synapse.consecutive_successes).to eq(51)
  end

  it 'applies validation penalties to confidence committed while transforming' do
    synapse.update(transform: '{"template":"bad"}')
    allow(transformer).to receive(:transform) do
      synapse.update(confidence: 0.4, consecutive_successes: 17)
      { success: false, errors: ['invalid'] }
    end

    client.evaluate(synapse_id: synapse.id)

    expect(synapse.refresh.confidence).to be_within(0.0001).of(0.37)
    expect(synapse.consecutive_successes).to eq(0)
  end

  it 'applies pain to confidence committed after the initial synapse read' do
    signal_model = Legion::Extensions::Synapse::Data::Model::SynapseSignal
    allow(signal_model).to receive(:create).and_wrap_original do |create, **attributes|
      synapse.update(confidence: 0.8, consecutive_successes: 12)
      create.call(**attributes)
    end

    client.handle_pain(synapse_id: synapse.id)

    expect(synapse.refresh.confidence).to be_within(0.0001).of(0.75)
    expect(synapse.consecutive_successes).to eq(0)
  end

  it 'clamps persisted rewards and penalties at the confidence bounds' do
    allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:reactive?).and_return(false)
    synapse.update(confidence: 0.99)
    client.evaluate(synapse_id: synapse.id)
    expect(synapse.refresh.confidence).to eq(1.0)

    synapse.update(confidence: 0.01)
    client.handle_pain(synapse_id: synapse.id)
    expect(synapse.refresh.confidence).to eq(0.0)
  end
end
