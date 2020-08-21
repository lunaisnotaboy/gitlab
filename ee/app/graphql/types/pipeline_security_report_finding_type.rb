# frozen_string_literal: true

module Types
  # rubocop: disable Graphql/AuthorizeTypes
  class PipelineSecurityReportFindingType < BaseObject
    graphql_name 'PipelineSecurityReportFinding'

    description 'Represents vulnerability finding of a security report on the pipeline.'

    field :report_type, VulnerabilityReportTypeEnum, null: true,
          description: 'Type of the security report that found the vulnerability finding.'

    field :name, GraphQL::STRING_TYPE, null: true,
          description: 'Name of the vulnerability finding.'

    field :severity, VulnerabilitySeverityEnum, null: true,
          description: 'Severity of the vulnerability finding.'

    field :confidence, GraphQL::STRING_TYPE, null: true,
          description: 'Type of the security report that found the vulnerability.'

    field :scanner, VulnerabilityScannerType, null: true,
          description: 'Scanner metadata for the vulnerability.'

    field :identifiers, [VulnerabilityIdentifierType], null: false,
          description: 'Identifiers of the vulnerabilit finding.'

    field :project_fingerprint, GraphQL::STRING_TYPE, null: true,
          description: 'Name of the vulnerability finding.'

    field :uuid, GraphQL::STRING_TYPE, null: true,
          description: 'Name of the vulnerability finding.'

    field :project, ::Types::ProjectType, null: true,
          description: 'The project on which the vulnerability finding was found.'

    field :description, GraphQL::STRING_TYPE, null: true,
          description: 'Description of the vulnerability finding.'

    field :location, VulnerabilityLocationType, null: true,
          description: 'Location metadata for the vulnerability. Its fields depend on the type of security scan that found the vulnerability.'

    field :solution, GraphQL::STRING_TYPE, null: true,
          description: "URL to the vulnerability's details page."

    def location
      object.location&.merge(report_type: object.report_type)
    end
  end
end
