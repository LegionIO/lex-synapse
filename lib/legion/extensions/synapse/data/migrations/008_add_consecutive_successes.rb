# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:synapses) do
      add_column :consecutive_successes, Integer, null: false, default: 0
    end
  end
end
