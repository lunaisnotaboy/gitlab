# frozen_string_literal: true

require 'spec_helper'
require Rails.root.join('db', 'post_migrate', '20210313100214_cleanup_move_container_registry_enabled_to_project_feature.rb')

RSpec.describe CleanupMoveContainerRegistryEnabledToProjectFeature, :migration do
  let(:namespace) { table(:namespaces).create!(name: 'gitlab', path: 'gitlab-org') }
  let(:non_null_project_features) { { pages_access_level: 20 } }

  let!(:project1) { table(:projects).create!(namespace_id: namespace.id, name: 'project 1', container_registry_enabled: true) }
  let!(:project2) { table(:projects).create!(namespace_id: namespace.id, name: 'project 2', container_registry_enabled: false) }
  let!(:project3) { table(:projects).create!(namespace_id: namespace.id, name: 'project 3', container_registry_enabled: nil) }

  let!(:project4) { table(:projects).create!(namespace_id: namespace.id, name: 'project 4', container_registry_enabled: true) }
  let!(:project5) { table(:projects).create!(namespace_id: namespace.id, name: 'project 5', container_registry_enabled: false) }
  let!(:project6) { table(:projects).create!(namespace_id: namespace.id, name: 'project 6', container_registry_enabled: nil) }

  let!(:project_feature1) { table(:project_features).create!(project_id: project1.id, container_registry_access_level: 20, **non_null_project_features) }
  let!(:project_feature2) { table(:project_features).create!(project_id: project2.id, container_registry_access_level: 0, **non_null_project_features) }
  let!(:project_feature3) { table(:project_features).create!(project_id: project3.id, container_registry_access_level: 0, **non_null_project_features) }

  let!(:project_feature4) { table(:project_features).create!(project_id: project4.id, container_registry_access_level: 0, **non_null_project_features) }
  let!(:project_feature5) { table(:project_features).create!(project_id: project5.id, container_registry_access_level: 20, **non_null_project_features) }
  let!(:project_feature6) { table(:project_features).create!(project_id: project6.id, container_registry_access_level: 20, **non_null_project_features) }

  before do
    stub_const("#{described_class}::BATCH_SIZE", 3)
  end

  it 'steals remaining jobs and updates any remaining rows' do
    expect(Gitlab::BackgroundMigration).to receive(:steal).with('MoveContainerRegistryEnabledToProjectFeature').and_call_original

    expect_next_instance_of(Gitlab::BackgroundMigration::Logger) do |logger|
      expect(logger).to receive(:info)
        .with(message: "#{described_class}: All project rows between [#{project1.id}, #{project3.id}] already had their container_registry_enabled values copied to project_features")

      expect(logger).to receive(:info)
        .with(message: "#{described_class}: Project IDs with container_registry_enabled not copied by background migration were copied now: [#{project4.id}, #{project5.id}, #{project6.id}]")
    end

    migrate!

    expect(project_feature1.reload.container_registry_access_level).to eq(20)
    expect(project_feature2.reload.container_registry_access_level).to eq(0)
    expect(project_feature3.reload.container_registry_access_level).to eq(0)
    expect(project_feature4.reload.container_registry_access_level).to eq(20)
    expect(project_feature5.reload.container_registry_access_level).to eq(0)
    expect(project_feature6.reload.container_registry_access_level).to eq(0)
  end
end
