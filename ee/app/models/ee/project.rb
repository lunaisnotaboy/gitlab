# frozen_string_literal: true

module EE
  # Project EE mixin
  #
  # This module is intended to encapsulate EE-specific model logic
  # and be prepended in the `Project` model
  module Project
    extend ActiveSupport::Concern
    extend ::Gitlab::Utils::Override
    extend ::Gitlab::Cache::RequestCache
    include ::Gitlab::Utils::StrongMemoize
    include ::EE::GitlabRoutingHelper # rubocop: disable Cop/InjectEnterpriseEditionModule
    include IgnorableColumns

    GIT_LFS_DOWNLOAD_OPERATION = 'download'.freeze

    prepended do
      include Elastic::ProjectsSearch
      include EE::DeploymentPlatform # rubocop: disable Cop/InjectEnterpriseEditionModule
      include EachBatch
      include InsightsFeature
      include DeprecatedApprovalsBeforeMerge
      include UsageStatistics

      ignore_columns :mirror_last_update_at, :mirror_last_successful_update_at, remove_after: '2019-12-15', remove_with: '12.6'

      before_save :set_override_pull_mirror_available, unless: -> { ::Gitlab::CurrentSettings.mirror_available }
      before_save :set_next_execution_timestamp_to_now, if: ->(project) { project.mirror? && project.mirror_changed? && project.import_state }

      after_update :remove_mirror_repository_reference,
        if: ->(project) { project.mirror? && project.import_url_updated? }

      belongs_to :mirror_user, foreign_key: 'mirror_user_id', class_name: 'User'
      belongs_to :deleting_user, foreign_key: 'marked_for_deletion_by_user_id', class_name: 'User'

      has_one :repository_state, class_name: 'ProjectRepositoryState', inverse_of: :project
      has_one :project_registry, class_name: 'Geo::ProjectRegistry', inverse_of: :project
      has_one :push_rule, ->(project) { project&.feature_available?(:push_rules) ? all : none }
      has_one :index_status

      has_one :jenkins_service
      has_one :jenkins_deprecated_service
      has_one :github_service
      has_one :gitlab_slack_application_service

      has_one :service_desk_setting, class_name: 'ServiceDeskSetting'
      has_one :tracing_setting, class_name: 'ProjectTracingSetting'
      has_one :feature_usage, class_name: 'ProjectFeatureUsage'
      has_one :status_page_setting, inverse_of: :project

      has_many :reviews, inverse_of: :project
      has_many :approvers, as: :target, dependent: :destroy # rubocop:disable Cop/ActiveRecordDependent
      has_many :approver_users, through: :approvers, source: :user
      has_many :approver_groups, as: :target, dependent: :destroy # rubocop:disable Cop/ActiveRecordDependent
      has_many :approval_rules, class_name: 'ApprovalProjectRule'
      has_many :approval_merge_request_rules, through: :merge_requests, source: :approval_rules
      has_many :audit_events, as: :entity
      has_many :designs, inverse_of: :project, class_name: 'DesignManagement::Design'
      has_many :path_locks
      has_many :requirements

      # the rationale behind vulnerabilities and vulnerability_findings can be found here:
      # https://gitlab.com/gitlab-org/gitlab/issues/10252#terminology
      has_many :vulnerabilities
      has_many :vulnerability_feedback, class_name: 'Vulnerabilities::Feedback'
      has_many :vulnerability_findings, class_name: 'Vulnerabilities::Occurrence' do
        def lock_for_confirmation!(id)
          where(vulnerability_id: nil).lock.find(id)
        end
      end
      has_many :vulnerability_identifiers, class_name: 'Vulnerabilities::Identifier'
      has_many :vulnerability_scanners, class_name: 'Vulnerabilities::Scanner'
      has_many :vulnerability_exports, class_name: 'Vulnerabilities::Export'

      has_many :protected_environments
      has_many :software_license_policies, inverse_of: :project, class_name: 'SoftwareLicensePolicy'
      accepts_nested_attributes_for :software_license_policies, allow_destroy: true
      has_many :packages, class_name: 'Packages::Package'
      has_many :package_files, through: :packages, class_name: 'Packages::PackageFile'
      has_many :merge_trains, foreign_key: 'target_project_id', inverse_of: :target_project

      has_many :webide_pipelines, -> { webide_source }, class_name: 'Ci::Pipeline', inverse_of: :project

      has_many :operations_feature_flags, class_name: 'Operations::FeatureFlag'
      has_one :operations_feature_flags_client, class_name: 'Operations::FeatureFlagsClient'

      has_many :project_aliases

      has_many :upstream_project_subscriptions, class_name: 'Ci::Subscriptions::Project', foreign_key: :downstream_project_id, inverse_of: :downstream_project
      has_many :upstream_projects, class_name: 'Project', through: :upstream_project_subscriptions, source: :upstream_project
      has_many :downstream_project_subscriptions, class_name: 'Ci::Subscriptions::Project', foreign_key: :upstream_project_id, inverse_of: :upstream_project
      has_many :downstream_projects, class_name: 'Project', through: :downstream_project_subscriptions, source: :downstream_project

      has_many :sourced_pipelines, class_name: 'Ci::Sources::Project', foreign_key: :source_project_id

      scope :with_shared_runners_limit_enabled, -> { with_shared_runners.non_public_only }

      scope :mirror, -> { where(mirror: true) }

      scope :mirrors_to_sync, ->(freeze_at, limit: nil) do
        mirror
          .joins_import_state
          .where.not(import_state: { status: [:scheduled, :started] })
          .where("import_state.next_execution_timestamp <= ?", freeze_at)
          .where("import_state.retry_count <= ?", ::Gitlab::Mirror::MAX_RETRY)
          .limit(limit)
      end

      scope :with_wiki_enabled, -> { with_feature_enabled(:wiki) }
      scope :within_shards, -> (shard_names) { where(repository_storage: Array(shard_names)) }
      scope :outside_shards, -> (shard_names) { where.not(repository_storage: Array(shard_names)) }
      scope :verification_failed_repos, -> { joins(:repository_state).merge(ProjectRepositoryState.verification_failed_repos) }
      scope :verification_failed_wikis, -> { joins(:repository_state).merge(ProjectRepositoryState.verification_failed_wikis) }
      scope :for_plan_name, -> (name) { joins(namespace: :plan).where(plans: { name: name }) }
      scope :requiring_code_owner_approval,
            -> { joins(:protected_branches).where(protected_branches: { code_owner_approval_required: true }) }
      scope :with_active_services, -> { joins(:services).merge(::Service.active) }
      scope :with_active_jira_services, -> { joins(:services).merge(::JiraService.active) }
      scope :with_jira_dvcs_cloud, -> { joins(:feature_usage).merge(ProjectFeatureUsage.with_jira_dvcs_integration_enabled(cloud: true)) }
      scope :with_jira_dvcs_server, -> { joins(:feature_usage).merge(ProjectFeatureUsage.with_jira_dvcs_integration_enabled(cloud: false)) }
      scope :service_desk_enabled, -> { where(service_desk_enabled: true) }
      scope :github_imported, -> { where(import_type: 'github') }
      scope :with_protected_branches, -> { joins(:protected_branches) }
      scope :with_repositories_enabled, -> { joins(:project_feature).where(project_features: { repository_access_level: ::ProjectFeature::ENABLED }) }

      scope :with_security_reports_stored, -> { where('EXISTS (?)', ::Vulnerabilities::Occurrence.scoped_project.select(1)) }
      scope :with_security_reports, -> { where('EXISTS (?)', ::Ci::JobArtifact.security_reports.scoped_project.select(1)) }
      scope :with_github_service_pipeline_events, -> { joins(:github_service).merge(GithubService.pipeline_hooks) }
      scope :with_active_prometheus_service, -> { joins(:prometheus_service).merge(PrometheusService.active) }
      scope :with_enabled_error_tracking, -> { joins(:error_tracking_setting).where(project_error_tracking_settings: { enabled: true }) }
      scope :with_tracing_enabled, -> { joins(:tracing_setting) }
      scope :with_packages, -> { joins(:packages) }
      scope :mirrored_with_enabled_pipelines, -> do
        joins(:project_feature).mirror.where(mirror_trigger_builds: true,
                                             project_features: { builds_access_level: ::ProjectFeature::ENABLED })
      end
      scope :with_slack_service, -> { joins(:slack_service) }
      scope :with_slack_slash_commands_service, -> { joins(:slack_slash_commands_service) }
      scope :with_prometheus_service, -> { joins(:prometheus_service) }
      scope :aimed_for_deletion, -> (date) { where('marked_for_deletion_at <= ?', date).without_deleted }
      scope :with_repos_templates, -> { where(namespace_id: ::Gitlab::CurrentSettings.current_application_settings.custom_project_templates_group_id) }
      scope :with_groups_level_repos_templates, -> { joins("INNER JOIN namespaces ON projects.namespace_id = namespaces.custom_project_templates_group_id") }
      scope :with_designs, -> { where(id: DesignManagement::Design.select(:project_id)) }
      scope :with_deleting_user, -> { includes(:deleting_user) }

      delegate :shared_runners_minutes, :shared_runners_seconds, :shared_runners_seconds_last_reset,
        to: :statistics, allow_nil: true

      delegate :actual_shared_runners_minutes_limit,
        :shared_runners_minutes_used?, to: :shared_runners_limit_namespace

      delegate :last_update_succeeded?, :last_update_failed?,
        :ever_updated_successfully?, :hard_failed?,
        to: :import_state, prefix: :mirror, allow_nil: true

      delegate :log_jira_dvcs_integration_usage, :jira_dvcs_server_last_sync_at, :jira_dvcs_cloud_last_sync_at, to: :feature_usage

      delegate :merge_pipelines_enabled, :merge_pipelines_enabled=, :merge_pipelines_enabled?, :merge_pipelines_were_disabled?, to: :ci_cd_settings
      delegate :merge_trains_enabled?, to: :ci_cd_settings
      delegate :actual_limits, :actual_plan_name, to: :namespace, allow_nil: true

      validates :repository_size_limit,
        numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true }
      validates :max_pages_size,
        numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true,
                        less_than: ::Gitlab::Pages::MAX_SIZE / 1.megabyte }

      validates :approvals_before_merge, numericality: true, allow_blank: true

      validates :pull_mirror_branch_prefix, length: { maximum: 50 }
      validate :check_pull_mirror_branch_prefix

      with_options if: :mirror? do
        validates :import_url, presence: true
        validates :mirror_user, presence: true
      end

      default_value_for :packages_enabled, true

      accepts_nested_attributes_for :tracing_setting, update_only: true, allow_destroy: true
      accepts_nested_attributes_for :status_page_setting, update_only: true, allow_destroy: true

      alias_attribute :fallback_approvals_required, :approvals_before_merge
    end

    class_methods do
      def search_by_visibility(level)
        where(visibility_level: ::Gitlab::VisibilityLevel.string_options[level])
      end

      def with_slack_application_disabled
        joins('LEFT JOIN services ON services.project_id = projects.id AND services.type = \'GitlabSlackApplicationService\' AND services.active IS true')
          .where('services.id IS NULL')
      end

      def find_by_service_desk_project_key(key)
        # project_key is not indexed for now
        # see https://gitlab.com/gitlab-org/gitlab/-/merge_requests/24063#note_282435524 for details
        joins(:service_desk_setting).find_by('service_desk_settings.project_key' => key)
      end
    end

    def can_store_security_reports?
      namespace.store_security_reports_available? || public?
    end

    def tracing_external_url
      self.tracing_setting.try(:external_url)
    end

    def latest_pipeline_with_security_reports
      all_pipelines.newest_first(ref: default_branch).with_reports(::Ci::JobArtifact.security_reports).first ||
        all_pipelines.newest_first(ref: default_branch).with_legacy_security_reports.first
    end

    def latest_pipeline_with_reports(reports)
      all_pipelines.newest_first(ref: default_branch).with_reports(reports).take
    end

    def ensure_external_webhook_token
      return if external_webhook_token.present?

      self.external_webhook_token = Devise.friendly_token
    end

    def shared_runners_limit_namespace
      root_namespace
    end

    def mirror
      super && feature_available?(:repository_mirrors) && pull_mirror_available?
    end
    alias_method :mirror?, :mirror

    def mirror_with_content?
      mirror? && !empty_repo?
    end

    def fetch_mirror(forced: false)
      return unless mirror?

      # Only send the password if it's needed
      url =
        if import_data&.password_auth?
          import_url
        else
          username_only_import_url
        end

      repository.fetch_upstream(url, forced: forced)
    end

    def can_override_approvers?
      !disable_overriding_approvers_per_merge_request
    end

    def shared_runners_available?
      super && !shared_runners_limit_namespace.shared_runners_minutes_used?
    end

    def link_pool_repository
      super
      repository.log_geo_updated_event
    end

    def object_pool_missing?
      has_pool_repository? && !pool_repository.object_pool.exists?
    end

    def shared_runners_minutes_limit_enabled?
      !public? && shared_runners_enabled? &&
        shared_runners_limit_namespace.shared_runners_minutes_limit_enabled?
    end

    # This makes the feature disabled by default, in contrary to how
    # `#feature_available?` makes a feature enabled by default.
    #
    # This allows to:
    # - Enable the feature flag for a given project, regardless of the license.
    #   This is useful for early testing a feature in production on a given project.
    # - Enable the feature flag globally and still check that the license allows
    #   it. This is the case when we're ready to enable a feature for anyone
    #   with the correct license.
    def beta_feature_available?(feature)
      ::Feature.enabled?(feature, self) ||
        (::Feature.enabled?(feature) && feature_available?(feature))
    end
    alias_method :alpha_feature_available?, :beta_feature_available?

    def push_audit_events_enabled?
      ::Feature.enabled?(:repository_push_audit_event, self)
    end

    def feature_available?(feature, user = nil)
      if ::ProjectFeature::FEATURES.include?(feature)
        super
      else
        licensed_feature_available?(feature, user)
      end
    end

    def multiple_approval_rules_available?
      feature_available?(:multiple_approval_rules)
    end

    def code_owner_approval_required_available?
      feature_available?(:code_owner_approval_required)
    end

    def github_external_pull_request_pipelines_available?
      mirror? &&
        feature_available?(:ci_cd_projects) &&
        feature_available?(:github_project_service_integration)
    end

    def scoped_approval_rules_enabled?
      ::Feature.enabled?(:scoped_approval_rules, self, default_enabled: true)
    end

    def service_desk_enabled
      ::EE::Gitlab::ServiceDesk.enabled?(project: self) && super
    end
    alias_method :service_desk_enabled?, :service_desk_enabled

    def service_desk_address
      return unless service_desk_enabled?

      config = ::Gitlab.config.incoming_email
      wildcard = ::Gitlab::IncomingEmail::WILDCARD_PLACEHOLDER

      config.address&.gsub(wildcard, "#{full_path_slug}-#{id}-issue-")
    end

    override :add_import_job
    def add_import_job
      return if gitlab_custom_project_template_import?

      # Historically this was intended ensure `super` is only called
      # when a project is imported(usually on project creation only) so `repository_exists?`
      # check was added so that it does not stop mirroring if later on mirroring option is added to the project.
      #
      # With jira importer we need to allow to run the import multiple times on same project,
      # which can conflict with scheduled mirroring(if that project had or will have mirroring enabled),
      # so we are checking if its a jira reimport then we trigger that and skip mirroring even if mirroring
      # should have been started. When we run into race condition with mirroring on a jira imported project
      # the mirroring would still be picked up 1 minute later, based on `Gitlab::Mirror::SCHEDULER_CRON` and
      # `ProjectUpdateState#mirror_update_due?``
      return super if jira_force_import? || import? && !repository_exists?

      if mirror?
        ::Gitlab::Metrics.add_event(:mirrors_scheduled)
        job_id = RepositoryUpdateMirrorWorker.perform_async(self.id)

        log_import_activity(job_id, type: :mirror)

        job_id
      end
    end

    override :has_active_hooks?
    def has_active_hooks?(hooks_scope = :push_hooks)
      super || has_group_hooks?(hooks_scope)
    end

    def has_group_hooks?(hooks_scope = :push_hooks)
      return unless group && feature_available?(:group_webhooks)

      group_hooks.hooks_for(hooks_scope).any?
    end

    def execute_hooks(data, hooks_scope = :push_hooks)
      super

      if group && feature_available?(:group_webhooks)
        run_after_commit_or_now do
          group_hooks.hooks_for(hooks_scope).each do |hook|
            hook.async_execute(data, hooks_scope.to_s)
          end
        end
      end
    end

    # No need to have a Kerberos Web url. Kerberos URL will be used only to
    # clone
    def kerberos_url_to_repo
      "#{::Gitlab.config.build_gitlab_kerberos_url + ::Gitlab::Routing.url_helpers.project_path(self)}.git"
    end

    def group_ldap_synced?
      group&.ldap_synced?
    end

    override :allowed_to_share_with_group?
    def allowed_to_share_with_group?
      super && !(group && ::Gitlab::CurrentSettings.lock_memberships_to_ldap?)
    end

    # TODO: Clean up this method in the https://gitlab.com/gitlab-org/gitlab/issues/33329
    def approvals_before_merge
      return 0 unless feature_available?(:merge_request_approvers)

      super
    end

    def visible_approval_rules(target_branch: nil)
      strong_memoize(:"visible_approval_rules_#{target_branch}") do
        visible_user_defined_rules(branch: target_branch) + approval_rules.report_approver
      end
    end

    def visible_user_defined_rules(branch: nil)
      return user_defined_rules.take(1) unless multiple_approval_rules_available?
      return user_defined_rules unless branch

      user_defined_rules.applicable_to_branch(branch)
    end

    # TODO: Clean up this method in the https://gitlab.com/gitlab-org/gitlab/issues/33329
    def min_fallback_approvals
      strong_memoize(:min_fallback_approvals) do
        visible_user_defined_rules.map(&:approvals_required).max.to_i
      end
    end

    def reset_approvals_on_push
      super && feature_available?(:merge_request_approvers)
    end
    alias_method :reset_approvals_on_push?, :reset_approvals_on_push

    def approver_ids=(value)
      ::Gitlab::Utils.ensure_array_from_string(value).each do |user_id|
        approvers.find_or_create_by(user_id: user_id, target_id: id)
      end
    end

    def approver_group_ids=(value)
      ::Gitlab::Utils.ensure_array_from_string(value).each do |group_id|
        approver_groups.find_or_initialize_by(group_id: group_id, target_id: id)
      end
    end

    def merge_requests_require_code_owner_approval?
      code_owner_approval_required_available? &&
        protected_branches.requiring_code_owner_approval.any?
    end

    def branch_requires_code_owner_approval?(branch_name)
      return false unless code_owner_approval_required_available?

      ::ProtectedBranch.branch_requires_code_owner_approval?(self, branch_name)
    end

    def require_password_to_approve
      super && password_authentication_enabled_for_web?
    end
    alias_method :require_password_to_approve?, :require_password_to_approve

    def find_path_lock(path, exact_match: false, downstream: false)
      path_lock_finder = strong_memoize(:path_lock_finder) do
        ::Gitlab::PathLocksFinder.new(self)
      end

      path_lock_finder.find(path, exact_match: exact_match, downstream: downstream)
    end

    def import_url_updated?
      # check if import_url has been updated and it's not just the first assignment
      saved_change_to_import_url? && saved_changes['import_url'].first
    end

    def remove_mirror_repository_reference
      run_after_commit do
        repository.async_remove_remote(::Repository::MIRROR_REMOTE)
      end
    end

    def username_only_import_url
      bare_url = read_attribute(:import_url)
      return bare_url unless ::Gitlab::UrlSanitizer.valid?(bare_url)

      ::Gitlab::UrlSanitizer.new(bare_url, credentials: { user: import_data&.user }).full_url
    end

    def username_only_import_url=(value)
      unless ::Gitlab::UrlSanitizer.valid?(value)
        self.import_url = value
        self.import_data&.user = nil
        value
      end

      url = ::Gitlab::UrlSanitizer.new(value)
      creds = url.credentials.slice(:user)

      write_attribute(:import_url, url.sanitized_url)
      create_or_update_import_data(credentials: creds)

      username_only_import_url
    end

    def repository_and_lfs_size
      statistics.total_repository_size
    end

    def above_size_limit?
      return false unless size_limit_enabled?

      repository_and_lfs_size > actual_size_limit
    end

    def size_to_remove
      repository_and_lfs_size - actual_size_limit
    end

    def actual_size_limit
      return namespace.actual_size_limit if repository_size_limit.nil?

      repository_size_limit
    end

    def size_limit_enabled?
      return false unless License.feature_available?(:repository_size_limit)

      actual_size_limit != 0
    end

    def changes_will_exceed_size_limit?(size_in_bytes)
      size_limit_enabled? &&
        (size_in_bytes > actual_size_limit ||
         size_in_bytes + repository_and_lfs_size > actual_size_limit)
    end

    def remove_import_data
      super unless mirror?
    end

    def merge_requests_ff_only_enabled
      super
    end
    alias_method :merge_requests_ff_only_enabled?, :merge_requests_ff_only_enabled

    override :disabled_services
    def disabled_services
      strong_memoize(:disabled_services) do
        [].tap do |services|
          services.push('jenkins', 'jenkins_deprecated') unless feature_available?(:jenkins_integration)
          services.push('github') unless feature_available?(:github_project_service_integration)
        end
      end
    end

    def pull_mirror_available?
      pull_mirror_available_overridden ||
        ::Gitlab::CurrentSettings.mirror_available
    end

    override :licensed_features
    def licensed_features
      return super unless License.current

      License.current.features.select do |feature|
        License.global_feature?(feature) || licensed_feature_available?(feature)
      end
    end

    def any_path_locks?
      path_locks.any?
    end
    request_cache(:any_path_locks?) { self.id }

    def protected_environment_enforced?(environment_name, user)
      protected_environment = protected_environment_by_name(environment_name)

      protected_environment && protected_environment.accessible_to?(user)
    end

    def protected_environment_accessible_to?(environment_name, user)
      protected_environment = protected_environment_by_name(environment_name)

      !protected_environment || protected_environment.accessible_to?(user)
    end

    def protected_environment_by_name(environment_name)
      return unless protected_environments_feature_available?

      key = "protected_environment_by_name:#{id}:#{environment_name}"

      ::Gitlab::SafeRequestStore.fetch(key) do
        protected_environments.find_by(name: environment_name)
      end
    end

    override :after_import
    def after_import
      super
      repository.log_geo_updated_event
      wiki.repository.log_geo_updated_event
      design_repository.log_geo_updated_event
    end

    override :import?
    def import?
      super || gitlab_custom_project_template_import?
    end

    def gitlab_custom_project_template_import?
      import_type == 'gitlab_custom_project_template' &&
        ::Gitlab::CurrentSettings.custom_project_templates_enabled?
    end

    def protected_environments_feature_available?
      feature_available?(:protected_environments)
    end

    # Because we use default_value_for we need to be sure
    # packages_enabled= method does exist even if we rollback migration.
    # Otherwise many tests from spec/migrations will fail.
    def packages_enabled=(value)
      if has_attribute?(:packages_enabled)
        write_attribute(:packages_enabled, value)
      end
    end

    # Update the default branch querying the remote to determine its HEAD
    def update_root_ref(remote_name)
      root_ref = repository.find_remote_root_ref(remote_name)
      change_head(root_ref) if root_ref.present?
    end

    def feature_flags_client_token
      instance = operations_feature_flags_client || create_operations_feature_flags_client!
      instance.token
    end

    def root_namespace
      if namespace.has_parent?
        namespace.root_ancestor
      else
        namespace
      end
    end

    def active_webide_pipelines(user:)
      webide_pipelines.running_or_pending.for_user(user)
    end

    override :lfs_http_url_to_repo
    def lfs_http_url_to_repo(operation)
      return super unless ::Gitlab::Geo.secondary_with_primary?
      return super if operation == GIT_LFS_DOWNLOAD_OPERATION # download always comes from secondary

      geo_primary_http_url_to_repo(self)
    end

    def feature_usage
      super.presence || build_feature_usage
    end

    # LFS and hashed repository storage are required for using Design Management.
    def design_management_enabled?
      lfs_enabled? &&
        # We will allow the hashed storage requirement to be disabled for
        # a few releases until we are able to understand the impact of the
        # hashed storage requirement for existing design management projects.
        # See https://gitlab.com/gitlab-org/gitlab/issues/13428#note_238729038
        (hashed_storage?(:repository) || ::Feature.disabled?(:design_management_require_hashed_storage, self, default_enabled: true)) &&
        feature_available?(:design_management)
    end

    def design_repository
      strong_memoize(:design_repository) do
        DesignManagement::Repository.new(self)
      end
    end

    override(:expire_caches_before_rename)
    def expire_caches_before_rename(old_path)
      super

      design = ::Repository.new("#{old_path}#{::EE::Gitlab::GlRepository::DESIGN.path_suffix}", self, shard: repository_storage, repo_type: ::EE::Gitlab::GlRepository::DESIGN)

      if design.exists?
        design.before_delete
      end
    end

    def package_already_taken?(package_name)
      namespace.root_ancestor.all_projects
        .joins(:packages)
        .where.not(id: id)
        .merge(Packages::Package.with_name(package_name))
        .exists?
    end

    def adjourned_deletion?
      feature_available?(:adjourned_deletion_for_projects_and_groups) &&
        ::Gitlab::CurrentSettings.deletion_adjourned_period > 0
    end

    def marked_for_deletion?
      marked_for_deletion_at.present? &&
        feature_available?(:adjourned_deletion_for_projects_and_groups)
    end

    def ancestor_marked_for_deletion
      return unless feature_available?(:adjourned_deletion_for_projects_and_groups)

      ancestors(hierarchy_order: :asc)
        .joins(:deletion_schedule).first
    end

    def has_packages?(package_type)
      return false unless feature_available?(:packages)

      packages.where(package_type: package_type).exists?
    end

    def disable_overriding_approvers_per_merge_request
      return super unless License.feature_available?(:admin_merge_request_approvers_rules)

      ::Gitlab::CurrentSettings.disable_overriding_approvers_per_merge_request? ||
        super
    end
    alias_method :disable_overriding_approvers_per_merge_request?, :disable_overriding_approvers_per_merge_request

    def merge_requests_author_approval
      return super unless License.feature_available?(:admin_merge_request_approvers_rules)

      return false if ::Gitlab::CurrentSettings.prevent_merge_requests_author_approval?

      super
    end
    alias_method :merge_requests_author_approval?, :merge_requests_author_approval

    def merge_requests_disable_committers_approval
      return super unless License.feature_available?(:admin_merge_request_approvers_rules)

      ::Gitlab::CurrentSettings.prevent_merge_requests_committers_approval? ||
        super
    end
    alias_method :merge_requests_disable_committers_approval?, :merge_requests_disable_committers_approval

    def license_compliance
      strong_memoize(:license_compliance) { SCA::LicenseCompliance.new(self) }
    end

    override :template_source?
    def template_source?
      return true if namespace_id == ::Gitlab::CurrentSettings.current_application_settings.custom_project_templates_group_id

      ::Project.with_groups_level_repos_templates.exists?(id)
    end

    def jira_subscription_exists?
      feature_available?(:jira_dev_panel_integration) && JiraConnectSubscription.for_project(self).exists?
    end

    private

    def group_hooks
      GroupHook.where(group_id: group.self_and_ancestors)
    end

    def set_override_pull_mirror_available
      self.pull_mirror_available_overridden = read_attribute(:mirror)
      true
    end

    def set_next_execution_timestamp_to_now
      import_state.set_next_execution_to_now
    end

    def licensed_feature_available?(feature, user = nil)
      # This feature might not be behind a feature flag at all, so default to true
      return false unless ::Feature.enabled?(feature, user, default_enabled: true)

      available_features = strong_memoize(:licensed_feature_available) do
        Hash.new do |h, f|
          h[f] = load_licensed_feature_available(f)
        end
      end

      available_features[feature]
    end

    def load_licensed_feature_available(feature)
      globally_available = License.feature_available?(feature)

      if ::Gitlab::CurrentSettings.should_check_namespace_plan? && namespace
        globally_available &&
          (public? && namespace.public? || namespace.feature_available_in_plan?(feature))
      else
        globally_available
      end
    end

    def check_pull_mirror_branch_prefix
      return if pull_mirror_branch_prefix.blank?
      return unless pull_mirror_branch_prefix_changed?

      unless ::Gitlab::GitRefValidator.validate("#{pull_mirror_branch_prefix}master")
        errors.add(:pull_mirror_branch_prefix, _('Invalid Git ref'))
      end
    end

    def user_defined_rules
      strong_memoize(:user_defined_rules) do
        approval_rules.regular_or_any_approver.order(rule_type: :desc, id: :asc)
      end
    end
  end
end
