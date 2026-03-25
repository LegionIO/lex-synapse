# frozen_string_literal: true

Sequel.migration do
  up do
    # synapses: WHERE status = 'active' AND baseline_throughput > 0
    alter_table(:synapses) do
      add_index %i[status baseline_throughput], name: :idx_synapses_status_throughput, if_not_exists: true
    end

    # synapse_proposals: WHERE status = 'pending' AND challenge_state IS NULL ORDER BY id
    alter_table(:synapse_proposals) do
      add_index %i[status challenge_state], name: :idx_proposals_status_challenge, if_not_exists: true
    end
  end

  down do
    alter_table(:synapses) do
      drop_index %i[status baseline_throughput], name: :idx_synapses_status_throughput, if_exists: true
    end

    alter_table(:synapse_proposals) do
      drop_index %i[status challenge_state], name: :idx_proposals_status_challenge, if_exists: true
    end
  end
end
