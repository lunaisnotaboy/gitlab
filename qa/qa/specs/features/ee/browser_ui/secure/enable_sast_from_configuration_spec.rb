# frozen_string_literal: true

require 'pathname'

module QA
  RSpec.describe 'Secure', :runner do
    describe 'Enable SAST from UI' do
      let(:merge_request_description) do
        'Set .gitlab-ci.yml to enable or configure SAST security scanning using the GitLab managed template. You can [add variable overrides](https://docs.gitlab.com/ee/user/application_security/sast/#customizing-the-sast-settings) to customize SAST settings.'
      end

      let(:test_data_string_fields_array) do
        [
            %w(SECURE_ANALYZERS_PREFIX registry.example.com),
            ['SAST_EXCLUDED_PATHS', 'foo, bar'],
            %w(SAST_ANALYZER_IMAGE_TAG latest),
            ['SAST_BANDIT_EXCLUDED_PATHS', 'exclude_path_a, exclude_path_b']
        ]
      end

      let(:test_data_int_fields_array) do
        [
            %w(SEARCH_MAX_DEPTH 42),
            %w(SAST_BRAKEMAN_LEVEL 43),
            %w(SAST_GOSEC_LEVEL 7)
        ]
      end

      let(:test_data_checkbox_exclude_array) do
        %w(eslint kubesec nodejs-scan phpcs-security-audit)
      end

      let(:test_stage_name) do
        'test_all_the_things'
      end

      after(:all) do
        @runner.remove_via_api!
      end

      before(:all) do
        @executor = "qa-runner-#{Time.now.to_i}"

        Flow::Login.sign_in

        @project = Resource::Project.fabricate_via_api! do |project|
          project.name = Runtime::Env.auto_devops_project_name || 'project-with-secure'
          project.description = 'Project with Secure'
        end

        @runner = Resource::Runner.fabricate! do |runner|
          runner.project = @project
          runner.name = @executor
          runner.tags = %w[qa test]
        end

        # Push fixture to generate Secure reports
        Resource::Repository::ProjectPush.fabricate! do |project_push|
          project_push.project = @project
          project_push.directory = Pathname
                                       .new(__dir__)
                                       .join('../../../../../ee/fixtures/secure_sast_enable_from_ui_files')
          project_push.commit_message = 'Create Secure compatible application to serve premade reports'
        end.project.visit!

        Flow::Pipeline.wait_for_latest_pipeline(pipeline_condition: 'succeeded')
      end

      before do
        Flow::Login.sign_in_unless_signed_in
      end

      it 'runs sast job when enabled from configuration', testcase: 'https://gitlab.com/gitlab-org/quality/testcases/-/issues/1667' do
        Flow::Pipeline.visit_latest_pipeline

        # Baseline that we do not initially have a sast job
        Page::Project::Pipeline::Show.perform do |pipeline|
          expect(pipeline).to have_no_job('brakeman-sast')
        end
        Page::Project::Menu.perform(&:click_project)
        Page::Project::Menu.perform(&:click_on_security_configuration_link)

        EE::Page::Project::Secure::ConfigurationForm.perform do |config_form|
          expect(config_form).to have_sast_status('Not enabled')
          config_form.click_sast_enable_button
          config_form.click_expand_button

          test_data_string_fields_array.each do |test_data_string_array|
            config_form.fill_dynamic_field(test_data_string_array.first, test_data_string_array[1])
          end
          test_data_int_fields_array.each do |test_data_int_array|
            config_form.fill_dynamic_field(test_data_int_array.first, test_data_int_array[1])
          end
          test_data_checkbox_exclude_array.each do |test_data_checkbox|
            config_form.unselect_dynamic_checkbox(test_data_checkbox)
          end
          config_form.fill_dynamic_field('stage', test_stage_name)

          config_form.click_submit_button

          Page::MergeRequest::Show.perform do |merge_request|
            aggregate_failures "test Merge Request contents" do
              expect(merge_request).to have_description(merge_request_description)
              merge_request.click_diffs_tab
              expect(merge_request).to have_file('.gitlab-ci.yml')
              test_data_string_fields_array.each do |test_data_string_array|
                expect(merge_request).to have_content("#{test_data_string_array.first}: #{test_data_string_array[1]}")
              end
              test_data_int_fields_array.each do |test_data_int_array|
                expect(merge_request).to have_content("#{test_data_int_array.first}: '#{test_data_int_array[1]}'")
              end
              expect(merge_request).to have_content("stages: - test - #{test_stage_name}")
              expect(merge_request).to have_content("SAST_EXCLUDED_ANALYZERS: #{test_data_checkbox_exclude_array.join(', ')}")
            end
          end

          Page::MergeRequest::New.perform do |new_merge_request|
            new_merge_request.submit_merge_request
          end

          Page::MergeRequest::Show.perform do |merge_request|
            merge_request.try_to_merge!
          end

          Flow::Pipeline.visit_latest_pipeline

          Page::Project::Pipeline::Show.perform do |pipeline|
            expect(pipeline).to have_job('brakeman-sast')
          end

          Page::Project::Menu.perform(&:click_project)
          Page::Project::Menu.perform(&:click_on_security_configuration_link)

          EE::Page::Project::Secure::ConfigurationForm.perform do |config_form|
            aggregate_failures "test SAST status is Enabled" do
              expect(config_form).to have_sast_status('Enabled')
              expect(config_form).not_to have_sast_status('Not enabled')
            end
          end
        end
      end
    end
  end
end
