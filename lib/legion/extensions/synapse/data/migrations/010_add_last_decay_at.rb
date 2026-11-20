# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:synapses) do
      add_column :last_decay_at, DateTime
    end
    from(:synapses).update(last_decay_at: Sequel::CURRENT_TIMESTAMP)
  end

  down do
    alter_table(:synapses) do
      drop_column :last_decay_at
    end
  end
end
