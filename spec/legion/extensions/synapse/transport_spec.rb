# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/transport'
require 'legion/extensions/synapse/transport/exchanges/synapse'
require 'legion/extensions/synapse/transport/queues/evaluate'
require 'legion/extensions/synapse/transport/queues/pain'
require 'legion/extensions/synapse/transport/messages/signal'
require 'legion/extensions/synapse/transport/messages/pain'

RSpec.describe 'Synapse Transport' do
  it 'defines Transport module' do
    expect(Legion::Extensions::Synapse::Transport).to be_a(Module)
  end

  it 'defines additional_e_to_q' do
    bindings = Legion::Extensions::Synapse::Transport.additional_e_to_q
    expect(bindings).to be_an(Array)
    expect(bindings.size).to eq(2)
  end

  it 'has evaluate routing key' do
    keys = Legion::Extensions::Synapse::Transport.additional_e_to_q.map { |b| b[:routing_key] }
    expect(keys).to include('synapse.evaluate')
  end

  it 'has pain routing key' do
    keys = Legion::Extensions::Synapse::Transport.additional_e_to_q.map { |b| b[:routing_key] }
    expect(keys).to include('task.failed')
  end
end
