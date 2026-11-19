# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/actors/decay'

RSpec.describe Legion::Extensions::Synapse::Actor::Decay do
  let(:actor) { described_class.allocate }
  let(:now) { Time.local(2026, 11, 19, 12) }
  let(:synapse) do
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
      confidence: 0.8, status: 'active', created_at: now - (5 * 3600)
    )
  end

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse.id).delete
    synapse.delete
  end

  it 'does not decay a synapse that received traffic within the last hour' do
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(synapse_id: synapse.id, created_at: now - 1800)
    expect(actor.action(now: now)).to eq(decayed: 0)
    expect(synapse.refresh.confidence).to eq(0.8)
    expect(synapse.last_decay_at).to be_nil
  end

  it 'catches up completed idle hours after delayed startup' do
    synapse
    expect(actor.action(now: now)).to eq(decayed: 1)
    expect(synapse.refresh.confidence).to be_within(1e-10).of(0.8 * (0.998**5))
    expect(synapse.last_decay_at).to eq(now)
  end

  it 'does not reapply an interval after an actor restart' do
    synapse
    actor.action(now: now)
    confidence = synapse.refresh.confidence
    expect(described_class.allocate.action(now: now)).to eq(decayed: 0)
    expect(synapse.refresh.confidence).to eq(confidence)
    expect(described_class.allocate.action(now: now + 3600)).to eq(decayed: 1)
    expect(synapse.refresh.confidence).to be_within(1e-10).of(confidence * 0.998)
  end

  it 'preserves fractional idle time for the next tick' do
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(synapse_id: synapse.id, created_at: now - 5400)
    expect(actor.action(now: now)).to eq(decayed: 1)
    expect(synapse.refresh.confidence).to be_within(1e-10).of(0.8 * 0.998)
    expect(synapse.last_decay_at).to eq(now - 1800)
    expect(actor.action(now: now + 1800)).to eq(decayed: 1)
    expect(synapse.refresh.confidence).to be_within(1e-10).of(0.8 * (0.998**2))
  end

  it 'starts a new idle interval after traffic resumes' do
    synapse
    actor.action(now: now)
    confidence = synapse.refresh.confidence
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(synapse_id: synapse.id, created_at: now + 1800)
    expect(actor.action(now: now + 3600)).to eq(decayed: 0)
    expect(actor.action(now: now + 5400)).to eq(decayed: 1)
    expect(synapse.refresh.confidence).to be_within(1e-10).of(confidence * 0.998)
  end

  it 'does not decay a newly created synapse or a non-active synapse' do
    synapse.update(created_at: now - 1800)
    expect(actor.action(now: now)).to eq(decayed: 0)
    synapse.update(status: 'dampened', created_at: now - 7200)
    expect(actor.action(now: now)).to eq(decayed: 0)
    expect(synapse.refresh.confidence).to eq(0.8)
  end

  it 'does not reverse decay when the clock moves backwards' do
    synapse.update(last_decay_at: now + 3600)
    expect(actor.action(now: now)).to eq(decayed: 0)
    expect(synapse.refresh.confidence).to eq(0.8)
  end

  it 'rolls back confidence when the checkpoint write fails' do
    synapse
    allow_any_instance_of(Legion::Extensions::Synapse::Data::Model::Synapse).to receive(:update).and_wrap_original do |method, attributes|
      method.call(attributes)
      raise Sequel::DatabaseError, 'checkpoint failure'
    end
    expect { actor.action(now: now) }.to raise_error(Sequel::DatabaseError)
    expect(synapse.refresh.confidence).to eq(0.8)
    expect(synapse.last_decay_at).to be_nil
  end
end
