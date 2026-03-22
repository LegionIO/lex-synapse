# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/version'

RSpec.describe Legion::Extensions::Synapse do
  it 'has a version number' do
    expect(Legion::Extensions::Synapse::VERSION).not_to be_nil
  end

  it 'has version 0.4.0' do
    expect(Legion::Extensions::Synapse::VERSION).to eq('0.4.0')
  end
end
