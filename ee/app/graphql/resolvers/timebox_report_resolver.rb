# frozen_string_literal: true

module Resolvers
  class TimeboxReportResolver < BaseResolver
    type Types::TimeboxReportType, null: true

    alias_method :timebox, :object

    def resolve(*args)
      response = TimeboxReportService.new(timebox).execute

      raise GraphQL::ExecutionError, response.message if response.error?

      response.payload
    end
  end
end
