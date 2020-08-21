# frozen_string_literal: true

module Resolvers
  module IncidentManagement
    class OncallShiftsResolver < BaseResolver
      alias_method :rotation, :object

      type Types::IncidentManagement::OncallShiftType.connection_type, null: true

      argument :start_time,
               ::Types::TimeType,
               required: true,
               description: 'Start of timeframe to include shifts for.'

      argument :end_time,
               ::Types::TimeType,
               required: true,
               description: 'End of timeframe to include shifts for. Cannot exceed one month after start.'

      def resolve(start_time:, end_time:)
        result = ::IncidentManagement::OncallShifts::ReadService.new(
          rotation,
          current_user,
          start_time: start_time,
          end_time: end_time
        ).execute

        raise Gitlab::Graphql::Errors::ResourceNotAvailable, result.errors.join(', ') if result.error?

        result.payload[:shifts]
      end

      # See https://gitlab.com/gitlab-org/gitlab/-/issues/324421
      def self.complexity_multiplier(args)
        0.005
      end
    end
  end
end
