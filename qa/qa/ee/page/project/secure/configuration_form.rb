# frozen_string_literal: true

module QA
  module EE
    module Page
      module Project
        module Secure
          class ConfigurationForm < QA::Page::Base
            include QA::Page::Component::Select2
            include QA::Page::Settings::Common

            view 'ee/app/assets/javascripts/security_configuration/sast/components/configuration_form.vue' do
              element :submit_button
            end

            def click_expand_button
              expand_content(:analyzer_settings_content)
            end

            def click_submit_button
              click_element(:submit_button)
            end

            def click_sast_enable_button
              click_element('sast_enable_button')
            end

            def fill_dynamic_field(field_name, content)
              fill_element("#{field_name}_field", content)
            end

            def unselect_dynamic_checkbox(checkbox_name)
              # Workaround until https://gitlab.com/gitlab-org/gitlab/-/issues/323297 is resolved
              # uncheck_element("#{checkbox_name}_checkbox")
              page.driver.browser.action.move_to(find_element("#{checkbox_name}_checkbox", visible: false).native).click.perform
            end

            def has_sast_status?(status_text)
              within_element('sast_status') do
                has_text?(status_text)
              end
            end
          end
        end
      end
    end
  end
end
