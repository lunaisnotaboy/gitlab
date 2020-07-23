# frozen_string_literal: true

# Searches a projects repository for a metrics dashboard and formats the output.
# Expects any custom dashboards will be located in `.gitlab/dashboards`
# Use Gitlab::Metrics::Dashboard::Finder to retrive dashboards.
module Metrics
  module Dashboard
    class CustomDashboardService < ::Metrics::Dashboard::BaseService
      DASHBOARD_ROOT = ".gitlab/dashboards"
      DASHBOARD_EXTENSION = '.yml'

      class << self
        def valid_params?(params)
          params[:dashboard_path].present?
        end

        def all_dashboard_paths(project)
          project.repository.user_defined_metrics_dashboard_paths
            .map do |filepath|
              {
                path: filepath,
                display_name: name_for_path(filepath),
                default: false,
                system_dashboard: false,
                out_of_the_box_dashboard: out_of_the_box_dashboard?
              }
            end
        end

        def file_finder(project)
          Gitlab::Template::Finders::RepoTemplateFinder.new(project, DASHBOARD_ROOT, DASHBOARD_EXTENSION)
        end

        # Grabs the filepath after the base directory.
        def name_for_path(filepath)
          filepath.delete_prefix("#{DASHBOARD_ROOT}/")
        end
      end

      private

      # Searches the project repo for a custom-defined dashboard.
      def get_raw_dashboard
        yml = self.class.file_finder(project).read(dashboard_path)

        load_yaml(yml)
      end

      def cache_key
        "project_#{project.id}_metrics_dashboard_#{dashboard_path}"
      end
    end
  end
end
