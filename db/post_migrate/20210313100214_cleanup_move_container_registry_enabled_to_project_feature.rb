# frozen_string_literal: true

# See https://docs.gitlab.com/ee/development/migration_style_guide.html
# for more information on how to write migrations for GitLab.

class CleanupMoveContainerRegistryEnabledToProjectFeature < ActiveRecord::Migration[6.0]
  # Uncomment the following include if you require helper functions:
  # include Gitlab::Database::MigrationHelpers

  DOWNTIME = false

  BATCH_SIZE = 100_000

  disable_ddl_transaction!

  class Project < ApplicationRecord
    include EachBatch

    self.table_name = "projects"
  end

  def up
    Gitlab::BackgroundMigration.steal('MoveContainerRegistryEnabledToProjectFeature')

    Project.each_batch(of: BATCH_SIZE) do |batch|
      range = batch.pluck('MIN(id)', 'MAX(id)').first

      result = ActiveRecord::Base.connection.execute(update_sql(*range))
      ids = result.collect { |a| a["id"] }

      next if ids.empty?

      logger.info(message: "#{self.class}: Project IDs with container_registry_enabled not copied by background migration were copied now: #{ids}")
    end
  end

  def down
    # no-op
  end

  private

  def update_sql(from_id, to_id)
    <<~SQL
    with cte as (
      select p.id, p.container_registry_enabled
      from projects p left join project_features pf
      on pf.project_id = p.id
      where p.id between #{from_id} AND #{to_id} AND
      pf.container_registry_access_level != (CASE p.container_registry_enabled
                                            WHEN true THEN 20
                                            WHEN false THEN 0
                                            ELSE 0
                                            END)
    )
    update project_features
    set container_registry_access_level = (CASE cte.container_registry_enabled
                                          WHEN true THEN 20
                                          WHEN false THEN 0
                                          ELSE 0
                                          END)
    from cte
    where project_features.project_id = cte.id
    returning cte.id
    SQL
  end

  def logger
    @logger ||= Gitlab::BackgroundMigration::Logger.build
  end
end
