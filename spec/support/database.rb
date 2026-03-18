# frozen_string_literal: true

require 'sequel'

DB = Sequel.sqlite unless defined?(DB)
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path('../../lib/legion/extensions/synapse/data/migrations', __dir__))

require_relative '../../lib/legion/extensions/synapse/data/models/synapse'
require_relative '../../lib/legion/extensions/synapse/data/models/synapse_mutation'
require_relative '../../lib/legion/extensions/synapse/data/models/synapse_signal'
