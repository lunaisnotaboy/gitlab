# frozen_string_literal: true

module EE
  module Gitlab
    module ProjectTemplate
      extend ActiveSupport::Concern

      class_methods do
        extend ::Gitlab::Utils::Override

        def localized_ee_templates_table
          [
            ::Gitlab::ProjectTemplate.new('hipaa_audit_protocol', 'HIPAA Audit Protocol', _('A project containing issues for each audit inquiry in the HIPAA Audit Protocol published by the U.S. Department of Health & Human Services'), 'https://gitlab.com/gitlab-org/project-templates/hipaa-audit-protocol', 'illustrations/logos/asklepian.svg')
          ].freeze
        end

        override :all
        def all
          return super unless License.feature_available?(:enterprise_templates)

          super + localized_ee_templates_table
        end
      end
    end
  end
end
