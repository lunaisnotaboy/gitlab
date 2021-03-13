# frozen_string_literal: true

class CleanupMoveContainerRegistryEnabledToProjectFeature < ActiveRecord::Migration[6.0]
  DOWNTIME = false

  BATCH_SIZE = 10_000

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

      if ids.empty?
        logger.info(message: "#{self.class}: All project rows between #{range} already had their container_registry_enabled values copied to project_features")
      else
        logger.info(message: "#{self.class}: Project IDs with container_registry_enabled not copied by background migration were copied now: #{ids}")
      end
    end
  end

  def down
    # no-op
  end

  private

  def update_sql(from_id, to_id)
    <<~SQL
    WITH cte AS (
      SELECT p.id, p.container_registry_enabled
      FROM projects p join project_features pf
      ON pf.project_id = p.id
      WHERE p.id BETWEEN #{from_id} AND #{to_id} AND
      pf.container_registry_access_level != (CASE p.container_registry_enabled
                                            WHEN true THEN 20
                                            WHEN false THEN 0
                                            ELSE 0
                                            END)
    )
    UPDATE project_features
    SET container_registry_access_level = (CASE cte.container_registry_enabled
                                          WHEN true THEN 20
                                          WHEN false THEN 0
                                          ELSE 0
                                          END)
    FROM cte
    WHERE project_features.project_id = cte.id
    RETURNING cte.id
    SQL
  end

  def logger
    @logger ||= Gitlab::BackgroundMigration::Logger.build
  end
end
