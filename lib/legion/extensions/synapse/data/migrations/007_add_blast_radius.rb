# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:synapses) do
      add_column :blast_radius,            String,   size: 10
      add_column :propagation_depth,       Integer,  default: 0
      add_column :downstream_count,        Integer,  default: 0
      add_column :blast_radius_updated_at, DateTime
    end
  end

  down do
    alter_table(:synapses) do
      drop_column :blast_radius
      drop_column :propagation_depth
      drop_column :downstream_count
      drop_column :blast_radius_updated_at
    end
  end
end
