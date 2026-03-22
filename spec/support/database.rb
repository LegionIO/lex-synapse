# frozen_string_literal: true

require 'sequel'

DB = Sequel.sqlite unless defined?(DB)
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path('../../lib/legion/extensions/synapse/data/migrations', __dir__))

Sequel::Model.db = DB

unless defined?(Legion::Settings)
  module Legion
    module Settings
      def self.dig(*_keys)
        true
      end
    end
  end
end

unless defined?(Legion::Data)
  module Legion
    module Data; end
  end
end

require_relative '../../lib/legion/extensions/synapse/data/models/synapse'
require_relative '../../lib/legion/extensions/synapse/data/models/synapse_mutation'
require_relative '../../lib/legion/extensions/synapse/data/models/synapse_signal'
require_relative '../../lib/legion/extensions/synapse/data/models/synapse_proposal'
require_relative '../../lib/legion/extensions/synapse/data/models/synapse_challenge'

Legion::Extensions::Synapse::Data::Model.define_synapse_model
Legion::Extensions::Synapse::Data::Model.define_synapse_mutation_model
Legion::Extensions::Synapse::Data::Model.define_synapse_signal_model
Legion::Extensions::Synapse::Data::Model.define_synapse_proposal_model
Legion::Extensions::Synapse::Data::Model.define_synapse_challenge_model
