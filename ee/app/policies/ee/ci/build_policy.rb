# frozen_string_literal: true
module EE
  module Ci
    module BuildPolicy
      extend ActiveSupport::Concern

      prepended do
        condition(:deployable_by_user) { deployable_by_user? }

        rule { ~deployable_by_user }.policy do
          prevent :update_build
        end

        condition(:deployable_by_reporter) { deployable_by_reporter? }

        rule { deployable_by_reporter }.policy do
          enable :update_build
          enable :update_commit_status
        end

        condition(:is_web_ide_terminal, scope: :subject) do
          @subject.pipeline.webide?
        end


        rule { is_web_ide_terminal & can?(:create_web_ide_terminal) & (admin | owner_of_job) }.policy do
          enable :read_web_ide_terminal
          enable :update_web_ide_terminal
        end

        rule { is_web_ide_terminal & ~can?(:update_web_ide_terminal) }.policy do
          prevent :create_build_terminal
        end

        rule { can?(:update_web_ide_terminal) & terminal }.policy do
          enable :create_build_terminal
          enable :create_build_service_proxy
        end

        rule { ~can?(:build_service_proxy_enabled) }.policy do
          prevent :create_build_service_proxy
        end

        private

        alias_method :current_user, :user
        alias_method :build, :subject

        def deployable_by_user?
          # We need to check if Protected Environments feature is available,
          # as evaluating `build.expanded_environment_name` is expensive.
          return true unless build.project.protected_environments_feature_available?

          build.project.protected_environment_accessible_to?(build.persisted_environment&.name, user)
        end

        def deployable_by_reporter?
          # We need to check if Protected Environments feature is available,
          # as evaluating `build.expanded_environment_name` is expensive.
          return true unless build.project.protected_environments_feature_available?

          build.project.protected_environment_enforced?(build.persisted_environment&.name, user)
        end
      end
    end
  end
end
