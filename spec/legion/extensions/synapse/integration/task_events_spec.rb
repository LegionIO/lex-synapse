# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/integration'

RSpec.describe Legion::Extensions::Synapse::Integration do
  let(:client) { Legion::Extensions::Synapse::Client.new }
  let(:synapse) { client.create(source_function_id: 1, target_function_id: 2, relationship_id: 123) }

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseChallenge.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  it 'leaves unwrapped relationships to tasker' do
    expect(described_class.evaluate_relationship(relationship_id: 999, payload: {})).to eq(wrapped: false)
  end

  it 'evaluates a wrapped relationship and correlates its signal with a child task' do
    synapse
    evaluation = described_class.evaluate_relationship(relationship_id: 123, payload: { value: 42 })
    expect(evaluation).to include(wrapped: true, allowed: true, result: { value: 42 })
    described_class.attach_task(signal_id: evaluation[:signal_id], task_id: 456, runner_class: 'Example::Target', function: 'consume')
    expect(synapse.signals_dataset.first.task_id).to eq(456)
  end

  it 'blocks dampened wrapped relationships' do
    synapse.update(status: 'dampened')
    expect(described_class.evaluate_relationship(relationship_id: 123, payload: {})).to include(wrapped: true, allowed: false)
  end

  it 'records host failure events once and resets the success streak' do
    evaluation = client.evaluate(synapse_id: synapse.id)
    described_class.attach_task(signal_id: evaluation[:signal_id], task_id: 456, runner_class: 'Example::Target', function: 'consume')
    listeners = {}
    events = double('HostEvents')
    allow(events).to receive(:on) { |name, &handler| listeners[name] = handler }
    described_class.install_events!(events: events)
    described_class.install_events!(events: events)
    expect(events).to have_received(:on).with('task.failed').once
    expect(events).to have_received(:on).with('task.completed').once
    before = synapse.refresh.confidence
    2.times { listeners.fetch('task.failed').call(task_id: 456, runner_class: 'Example::Target', function: 'consume') }
    expect(synapse.refresh.confidence).to be_within(0.0001).of(before - 0.05)
    expect(synapse.consecutive_successes).to eq(0)
    expect(synapse.signals_dataset.count).to eq(1)
    expect(synapse.signals_dataset.first.downstream_outcome).to eq('failed')
  end

  it 'records successful completion without counting a duplicate outcome' do
    evaluation = client.evaluate(synapse_id: synapse.id)
    described_class.attach_task(signal_id: evaluation[:signal_id], task_id: 456, runner_class: 'Example::Target', function: 'consume')
    expect(described_class.record_outcome(task_id: 456, outcome: :success, runner_class: 'Example::Target', function: 'consume')).to eq(recorded: 1)
    expect(described_class.record_outcome(task_id: 456, outcome: :failed, runner_class: 'Example::Target', function: 'consume')).to eq(recorded: 0)
    expect(client.report(synapse_id: synapse.id)[:success_rate]).to eq(1.0)
  end

  it 'reports correlated outcomes once while leaving undispatched evaluations unresolved' do
    client.evaluate(synapse_id: synapse.id)
    %i[success failed].each_with_index do |outcome, task_id|
      evaluation = client.evaluate(synapse_id: synapse.id)
      described_class.attach_task(signal_id: evaluation[:signal_id], task_id: task_id, runner_class: 'Example::Target', function: 'consume')
      2.times do
        described_class.record_outcome(task_id: task_id, outcome: outcome, runner_class: 'Example::Target', function: 'consume')
      end
    end
    expect(client.report(synapse_id: synapse.id)).to include(
      signals_24h: 3, completed_outcomes_24h: 2, successful_outcomes_24h: 1,
      failed_outcomes_24h: 1, unresolved_signals_24h: 1, evaluation_successes_24h: 3, success_rate: 0.5
    )
  end

  it 'ignores intermediate stage completion sharing the target task ID' do
    evaluation = client.evaluate(synapse_id: synapse.id)
    described_class.attach_task(signal_id: evaluation[:signal_id], task_id: 456, runner_class: 'Example::Target', function: 'consume')
    result = described_class.record_outcome(task_id: 456, outcome: :success, runner_class: 'Example::Transformer', function: 'transform')
    expect(result).to eq(recorded: 0)
    expect(synapse.signals_dataset.first.downstream_outcome).to be_nil
  end

  it 'ignores unrelated host tasks' do
    expect(described_class.record_outcome(task_id: nil, outcome: :failed, runner_class: 'Example::Target', function: 'consume')).to eq(recorded: 0)
    expect(described_class.record_outcome(task_id: 999, outcome: :failed, runner_class: 'Example::Target', function: 'consume')).to eq(recorded: 0)
  end
end
