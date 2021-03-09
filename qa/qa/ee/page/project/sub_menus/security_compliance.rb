# frozen_string_literal: true

module QA
  module EE
    module Page
      module Project
        module SubMenus
          module SecurityCompliance
            extend QA::Page::PageConcern

            def self.prepended(base)
              base.class_eval do
                view 'ee/app/views/layouts/nav/sidebar/_project_security_link.html.haml' do
                  element :security_dashboard_link
                  element :dependency_list_link
                  element :vulnerability_report_link
                  element :audit_events_settings_link
                end
              end
            end

            def click_on_security_dashboard
              within_sidebar do
                click_element :security_dashboard_link
              end
            end

            def click_on_dependency_list
              hover_security_compliance do
                within_submenu do
                  click_element(:dependency_list_link)
                end
              end
            end

            def click_on_vulnerability_report
              hover_security_compliance do
                within_submenu do
                  click_element(:vulnerability_report_link)
                end
              end
            end

            def click_on_security_configuration_link
              hover_security_compliance do
                within_submenu do
                  click_element(:security_configuration_link)
                end
              end
            end

            def hover_security_compliance
              within_sidebar do
                find_element(:security_dashboard_link).hover

                yield
              end
            end

            def go_to_audit_events_settings
              hover_security_compliance do
                within_submenu do
                  click_element :audit_events_settings_link
                end
              end
            end
          end
        end
      end
    end
  end
end
