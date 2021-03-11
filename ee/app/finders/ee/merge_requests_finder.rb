# frozen_string_literal: true

module EE
  module MergeRequestsFinder
    extend ActiveSupport::Concern
    extend ::Gitlab::Utils::Override

    override :filter_items
    def filter_items(items)
      items = super(items)
      items = by_approvers(items)
      items = by_merge_commit_sha(items)

      items
    end

    def filter_negated_items(items)
      items = super(items)
      by_negated_approvers(items)
    end

    # Filter by merge requests approval list that contains specified user directly or as part of group membership
    def by_approvers(items)
      ::MergeRequests::ByApproversFinder
        .new(params[:approver_usernames], params[:approver_ids])
        .execute(items)
    end

    def by_negated_approvers(items)
      ::MergeRequests::ByApproversFinder
        .new(not_params[:approver_usernames], not_params[:approver_ids], negated: true)
        .execute(items)
    end

    def by_merge_commit_sha(items)
      return items unless params[:merge_commit_sha].present?

      items.by_merge_commit_sha(params[:merge_commit_sha])
    end

    class_methods do
      extend ::Gitlab::Utils::Override

      override :scalar_params
      def scalar_params
        @scalar_params ||= super + [:approver_ids]
      end

      override :array_params
      def array_params
        @array_params ||= super.merge(approver_usernames: [])
      end
    end
  end
end
