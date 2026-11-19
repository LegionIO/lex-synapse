# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:synapses) do
      add_column :last_decay_at, DateTime
    end
  end
end
