# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Decay checkpoint upgrade' do
  let(:database) { Sequel.sqlite }
  let(:migrations) { File.expand_path('../../../../../lib/legion/extensions/synapse/data/migrations', __dir__) }

  after { database.disconnect }

  it 'starts existing synapses at upgrade time without replaying their already-decayed history' do
    Sequel::Migrator.run(database, migrations, target: 9)
    old_created_at = Time.now - (30 * 86_400)
    id = database[:synapses].insert(confidence: 0.8, created_at: old_created_at)
    before_upgrade = Time.at(Time.now.to_i)

    Sequel::Migrator.run(database, migrations, target: 10)

    row = database[:synapses].where(id: id).first
    expect(row[:last_decay_at]).to be_between(before_upgrade, Time.now)
    expect(row[:confidence]).to eq(0.8)
    expect(row[:created_at]).to be_within(0.001).of(old_created_at)
    new_id = database[:synapses].insert(confidence: 0.8)
    expect(database[:synapses].where(id: new_id).get(:last_decay_at)).to be_nil
  end

  it 'removes the checkpoint when rolling back the unpublished migration' do
    Sequel::Migrator.run(database, migrations, target: 10)
    Sequel::Migrator.run(database, migrations, target: 9)
    expect(database.schema(:synapses).map(&:first)).not_to include(:last_decay_at)
  end
end
