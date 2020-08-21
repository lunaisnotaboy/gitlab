# frozen_string_literal: true

module Resolvers
  module IncidentManagement
    class OncallScheduleResolver < BaseResolver
      alias_method :project, :object

      type Types::IncidentManagement::OncallScheduleType.connection_type, null: true

      def resolve(**args)
        ::IncidentManagement::OncallSchedulesFinder.new(context[:current_user], project).execute
      end
    end
  end
end
