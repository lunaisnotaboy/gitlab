# frozen_string_literal: true

module Resolvers
  class DastSiteProfileResolver < BaseResolver
    alias_method :project, :object

    type Types::DastSiteProfileType.connection_type, null: true

    when_single do
      argument :id, ::Types::GlobalIDType[::DastSiteProfile], required: true,
               description: "ID of the site profile."
    end

    def resolve(**args)
      if args[:id]
        # TODO: remove this coercion when the compatibility layer is removed
        # See: https://gitlab.com/gitlab-org/gitlab/-/issues/257883
        gid = ::Types::GlobalIDType[::DastSiteProfile].coerce_isolated_input(args[:id])
        DastSiteProfilesFinder.new(project_id: project.id, id: gid.model_id).execute
      else
        DastSiteProfilesFinder.new(project_id: project.id).execute
      end
    end
  end
end
