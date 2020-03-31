# frozen_string_literal: true

module EE
  module MergeRequestPolicy
    extend ActiveSupport::Concern

    prepended do
      with_scope :subject
      condition(:can_override_approvers, score: 0) do
        @subject.target_project&.can_override_approvers?
      end

      rule { ~can_override_approvers }.prevent :update_approvers
      rule { can?(:update_merge_request) }.policy do
        enable :update_approvers
        enable :approve_merge_request
      end

      rule { can?(:read_merge_request) }.policy do
        enable :approve_merge_request
      end

    end
  end
end
