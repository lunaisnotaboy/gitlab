# frozen_string_literal: true

require 'spec_helper'

RSpec.describe JiraService do
  include AssetsHelpers

  let_it_be(:project) { create(:project, :repository) }

  let(:current_user) { build_stubbed(:user) }
  let(:url) { 'http://jira.example.com' }
  let(:api_url) { 'http://api-jira.example.com' }
  let(:username) { 'jira-username' }
  let(:password) { 'jira-password' }
  let(:transition_id) { 'test27' }
  let(:server_info_results) { { 'deploymentType' => 'Cloud' } }
  let(:jira_service) do
    described_class.new(
      project: project,
      url: url,
      username: username,
      password: password
    )
  end

  before do
    WebMock.stub_request(:get, /serverInfo/).to_return(body: server_info_results.to_json )
  end

  describe '#options' do
    let(:options) do
      {
        project: project,
        active: true,
        username: 'username',
        password: 'test',
        jira_issue_transition_id: 24,
        url: 'http://jira.test.com/path/'
      }
    end

    let(:service) { described_class.create!(options) }

    it 'sets the URL properly' do
      # jira-ruby gem parses the URI and handles trailing slashes fine:
      # https://github.com/sumoheavy/jira-ruby/blob/v1.7.0/lib/jira/http_client.rb#L62
      expect(service.options[:site]).to eq('http://jira.test.com/')
    end

    it 'leaves out trailing slashes in context' do
      expect(service.options[:context_path]).to eq('/path')
    end

    context 'username with trailing whitespaces' do
      before do
        options.merge!(username: 'username ')
      end

      it 'leaves out trailing whitespaces in username' do
        expect(service.options[:username]).to eq('username')
      end
    end

    it 'provides additional cookies to allow basic auth with oracle webgate' do
      expect(service.options[:use_cookies]).to eq(true)
      expect(service.options[:additional_cookies]).to eq(['OBBasicAuth=fromDialog'])
    end

    context 'using api URL' do
      before do
        options.merge!(api_url: 'http://jira.test.com/api_path/')
      end

      it 'leaves out trailing slashes in context' do
        expect(service.options[:context_path]).to eq('/api_path')
      end
    end

    context 'with proxy options' do
      before do
        options.merge!(
          proxy_address: 'http://proxy.com',
          proxy_port: '80',
          proxy_username: 'proxy_user',
          proxy_password: 'proxy_pass'
        )
      end

      it 'sets the proxy settings' do
        expect(service.options[:proxy_address]).to eq('http://proxy.com')
        expect(service.options[:proxy_port]).to eq('80')
        expect(service.options[:proxy_username]).to eq('proxy_user')
        expect(service.options[:proxy_password]).to eq('proxy_pass')
      end

      context 'with trailing whitespaces' do
        before do
          options.merge!(
            proxy_address: 'http://proxy.com ',
            proxy_port: '80 ',
            proxy_username: 'proxy_user '
          )
        end

        it 'sets the proxy settings without trailing whitespaces' do
          expect(service.options[:proxy_address]).to eq('http://proxy.com')
          expect(service.options[:proxy_port]).to eq('80')
          expect(service.options[:proxy_username]).to eq('proxy_user')
        end
      end
    end
  end

  describe '#fields' do
    let(:service) { create(:jira_service) }

    subject(:fields) { service.fields }

    it 'includes transition help link' do
      transition_id_field = fields.find { |field| field[:name] == 'jira_issue_transition_id' }

      expect(transition_id_field[:title]).to eq('Jira workflow transition IDs')
      expect(transition_id_field[:help]).to include('/help/user/project/integrations/jira')
    end
  end

  describe 'Associations' do
    it { is_expected.to belong_to :project }
    it { is_expected.to have_one :service_hook }
  end

  describe '.reference_pattern' do
    using RSpec::Parameterized::TableSyntax

    where(:key, :result) do
      '#123'               | ''
      '1#23#12'            | ''
      'JIRA-1234A'         | 'JIRA-1234'
      'JIRA-1234-some_tag' | 'JIRA-1234'
      'JIRA-1234_some_tag' | 'JIRA-1234'
      'EXT_EXT-1234'       | 'EXT_EXT-1234'
      'EXT3_EXT-1234'      | 'EXT3_EXT-1234'
      '3EXT_EXT-1234'      | ''
    end

    with_them do
      specify do
        expect(described_class.reference_pattern.match(key).to_s).to eq(result)
      end
    end
  end

  describe '#create' do
    let(:params) do
      {
        project: project,
        url: url, api_url: api_url,
        username: username, password: password,
        jira_issue_transition_id: transition_id
      }
    end

    subject { described_class.create!(params) }

    it 'does not store data into properties' do
      expect(subject.properties).to be_nil
    end

    it 'stores data in data_fields correctly' do
      service = subject

      expect(service.jira_tracker_data.url).to eq(url)
      expect(service.jira_tracker_data.api_url).to eq(api_url)
      expect(service.jira_tracker_data.username).to eq(username)
      expect(service.jira_tracker_data.password).to eq(password)
      expect(service.jira_tracker_data.jira_issue_transition_id).to eq(transition_id)
      expect(service.jira_tracker_data.deployment_cloud?).to be_truthy
    end

    context 'when loading serverInfo' do
      let!(:jira_service) { subject }

      context 'Cloud instance' do
        let(:server_info_results) { { 'deploymentType' => 'Cloud' } }

        it 'is detected' do
          expect(jira_service.jira_tracker_data.deployment_cloud?).to be_truthy
        end
      end

      context 'Server instance' do
        let(:server_info_results) { { 'deploymentType' => 'Server' } }

        it 'is detected' do
          expect(jira_service.jira_tracker_data.deployment_server?).to be_truthy
        end
      end

      context 'Unknown instance' do
        let(:server_info_results) { { 'deploymentType' => 'FutureCloud' } }

        it 'is detected' do
          expect(jira_service.jira_tracker_data.deployment_unknown?).to be_truthy
        end
      end
    end
  end

  # we need to make sure we are able to read both from properties and jira_tracker_data table
  # TODO: change this as part of https://gitlab.com/gitlab-org/gitlab/issues/29404
  context 'overriding properties' do
    let(:access_params) do
      { url: url, api_url: api_url, username: username, password: password,
        jira_issue_transition_id: transition_id }
    end

    let(:data_params) do
      {
        url: url, api_url: api_url,
        username: username, password: password,
        jira_issue_transition_id: transition_id
      }
    end

    shared_examples 'handles jira fields' do
      let(:data_params) do
        {
          url: url, api_url: api_url,
          username: username, password: password,
          jira_issue_transition_id: transition_id
        }
      end

      context 'reading data' do
        it 'reads data correctly' do
          expect(service.url).to eq(url)
          expect(service.api_url).to eq(api_url)
          expect(service.username).to eq(username)
          expect(service.password).to eq(password)
          expect(service.jira_issue_transition_id).to eq(transition_id)
        end
      end

      describe '#update' do
        context 'basic update' do
          let_it_be(:new_username) { 'new_username' }
          let_it_be(:new_url) { 'http://jira-new.example.com' }

          before do
            service.update!(username: new_username, url: new_url)
          end

          it 'leaves properties field emtpy' do
            # expect(service.reload.properties).to be_empty
          end

          it 'stores updated data in jira_tracker_data table' do
            data = service.jira_tracker_data.reload

            expect(data.url).to eq(new_url)
            expect(data.api_url).to eq(api_url)
            expect(data.username).to eq(new_username)
            expect(data.password).to eq(password)
            expect(data.jira_issue_transition_id).to eq(transition_id)
          end
        end

        context 'when updating the url, api_url, username, or password' do
          it 'updates deployment type' do
            service.update!(url: 'http://first.url')
            service.jira_tracker_data.update!(deployment_type: 'server')

            expect(service.jira_tracker_data.deployment_server?).to be_truthy

            service.update!(api_url: 'http://another.url')
            service.jira_tracker_data.reload

            expect(service.jira_tracker_data.deployment_cloud?).to be_truthy
            expect(WebMock).to have_requested(:get, /serverInfo/).twice
          end

          it 'calls serverInfo for url' do
            service.update!(url: 'http://first.url')

            expect(WebMock).to have_requested(:get, /serverInfo/)
          end

          it 'calls serverInfo for api_url' do
            service.update!(api_url: 'http://another.url')

            expect(WebMock).to have_requested(:get, /serverInfo/)
          end

          it 'calls serverInfo for username' do
            service.update!(username: 'test-user')

            expect(WebMock).to have_requested(:get, /serverInfo/)
          end

          it 'calls serverInfo for password' do
            service.update!(password: 'test-password')

            expect(WebMock).to have_requested(:get, /serverInfo/)
          end
        end

        context 'when not updating the url, api_url, username, or password' do
          it 'does not update deployment type' do
            expect {service.update!(jira_issue_transition_id: 'jira_issue_transition_id')}.to raise_error(ActiveRecord::RecordInvalid)

            expect(WebMock).not_to have_requested(:get, /serverInfo/)
          end
        end

        context 'when not allowed to test an instance or group' do
          it 'does not update deployment type' do
            allow(service).to receive(:can_test?).and_return(false)

            service.update!(url: 'http://first.url')

            expect(WebMock).not_to have_requested(:get, /serverInfo/)
          end
        end

        context 'stored password invalidation' do
          context 'when a password was previously set' do
            context 'when only web url present' do
              let(:data_params) do
                {
                  url: url, api_url: nil,
                  username: username, password: password,
                  jira_issue_transition_id: transition_id
                }
              end

              it 'resets password if url changed' do
                service
                service.url = 'http://jira_edited.example.com'
                service.save!

                expect(service.reload.url).to eq('http://jira_edited.example.com')
                expect(service.password).to be_nil
              end

              it 'does not reset password if url "changed" to the same url as before' do
                service.url = 'http://jira.example.com'
                service.save!

                expect(service.reload.url).to eq('http://jira.example.com')
                expect(service.password).not_to be_nil
              end

              it 'resets password if url not changed but api url added' do
                service.api_url = 'http://jira_edited.example.com/rest/api/2'
                service.save!

                expect(service.reload.api_url).to eq('http://jira_edited.example.com/rest/api/2')
                expect(service.password).to be_nil
              end

              it 'does not reset password if new url is set together with password, even if it\'s the same password' do
                service.url = 'http://jira_edited.example.com'
                service.password = password
                service.save!

                expect(service.password).to eq(password)
                expect(service.url).to eq('http://jira_edited.example.com')
              end

              it 'resets password if url changed, even if setter called multiple times' do
                service.url = 'http://jira1.example.com/rest/api/2'
                service.url = 'http://jira1.example.com/rest/api/2'
                service.save!

                expect(service.password).to be_nil
              end

              it 'does not reset password if username changed' do
                service.username = 'some_name'
                service.save!

                expect(service.reload.password).to eq(password)
              end

              it 'does not reset password if password changed' do
                service.url = 'http://jira_edited.example.com'
                service.password = 'new_password'
                service.save!

                expect(service.reload.password).to eq('new_password')
              end

              it 'does not reset password if the password is touched and same as before' do
                service.url = 'http://jira_edited.example.com'
                service.password = password
                service.save!

                expect(service.reload.password).to eq(password)
              end
            end

            context 'when both web and api url present' do
              let(:data_params) do
                {
                  url: url, api_url: 'http://jira.example.com/rest/api/2',
                  username: username, password: password,
                  jira_issue_transition_id: transition_id
                }
              end

              it 'resets password if api url changed' do
                service.api_url = 'http://jira_edited.example.com/rest/api/2'
                service.save!

                expect(service.password).to be_nil
              end

              it 'does not reset password if url changed' do
                service.url = 'http://jira_edited.example.com'
                service.save!

                expect(service.password).to eq(password)
              end

              it 'resets password if api url set to empty' do
                service.update!(api_url: '')

                expect(service.reload.password).to be_nil
              end
            end
          end

          context 'when no password was previously set' do
            let(:data_params) do
              {
                url: url, username: username
              }
            end

            it 'saves password if new url is set together with password' do
              service.url = 'http://jira_edited.example.com/rest/api/2'
              service.password = 'password'
              service.save!
              expect(service.reload.password).to eq('password')
              expect(service.reload.url).to eq('http://jira_edited.example.com/rest/api/2')
            end
          end
        end
      end
    end

    # this  will be removed as part of https://gitlab.com/gitlab-org/gitlab/issues/29404
    context 'when data are stored in properties' do
      let(:properties) { data_params }
      let!(:service) do
        create(:jira_service, :without_properties_callback, properties: properties.merge(additional: 'something'))
      end

      it_behaves_like 'handles jira fields'
    end

    context 'when data are stored in separated fields' do
      let(:service) do
        create(:jira_service, data_params.merge(properties: {}))
      end

      it_behaves_like 'handles jira fields'
    end

    context 'when data are stored in both properties and separated fields' do
      let(:properties) { data_params }
      let(:service) do
        create(:jira_service, :without_properties_callback, active: false, properties: properties).tap do |service|
          create(:jira_tracker_data, data_params.merge(service: service))
        end
      end

      it_behaves_like 'handles jira fields'
    end
  end

  describe '#find_issue' do
    let(:issue_key) { 'JIRA-123' }
    let(:issue_url) { "#{url}/rest/api/2/issue/#{issue_key}" }

    before do
      stub_request(:get, issue_url).with(basic_auth: [username, password])
    end

    it 'call the Jira API to get the issue' do
      jira_service.find_issue(issue_key)

      expect(WebMock).to have_requested(:get, issue_url)
    end

    context 'with options' do
      let(:issue_url) { "#{url}/rest/api/2/issue/#{issue_key}?expand=renderedFields" }

      it 'calls the Jira API with the options to get the issue' do
        jira_service.find_issue(issue_key, rendered_fields: true)

        expect(WebMock).to have_requested(:get, issue_url)
      end
    end
  end

  describe '#close_issue' do
    let(:custom_base_url) { 'http://custom_url' }

    shared_examples 'close_issue' do
      let(:issue_key)       { 'JIRA-123' }
      let(:issue_url)       { "#{url}/rest/api/2/issue/#{issue_key}" }
      let(:transitions_url) { "#{issue_url}/transitions" }
      let(:comment_url)     { "#{issue_url}/comment" }
      let(:remote_link_url) { "#{issue_url}/remotelink" }
      let(:transitions)     { nil }

      let(:issue_fields) do
        {
          id: issue_key,
          self: issue_url,
          transitions: transitions
        }
      end

      subject(:close_issue) do
        jira_service.close_issue(resource, ExternalIssue.new(issue_key, project))
      end

      before do
        allow(jira_service).to receive_messages(jira_issue_transition_id: '999')

        # These stubs are needed to test JiraService#close_issue.
        # We close the issue then do another request to API to check if it got closed.
        # Here is stubbed the API return with a closed and an opened issues.
        open_issue   = JIRA::Resource::Issue.new(jira_service.client, attrs: issue_fields.deep_stringify_keys)
        closed_issue = open_issue.dup
        allow(open_issue).to receive(:resolution).and_return(false)
        allow(closed_issue).to receive(:resolution).and_return(true)
        allow(JIRA::Resource::Issue).to receive(:find).and_return(open_issue, closed_issue)

        allow_any_instance_of(JIRA::Resource::Issue).to receive(:key).and_return('JIRA-123')
        allow(JIRA::Resource::Remotelink).to receive(:all).and_return([])

        WebMock.stub_request(:get, issue_url).with(basic_auth: %w(jira-username jira-password))
        WebMock.stub_request(:post, transitions_url).with(basic_auth: %w(jira-username jira-password))
        WebMock.stub_request(:post, comment_url).with(basic_auth: %w(jira-username jira-password))
        WebMock.stub_request(:post, remote_link_url).with(basic_auth: %w(jira-username jira-password))
      end

      let(:external_issue) { ExternalIssue.new('JIRA-123', project) }

      def close_issue
        jira_service.close_issue(resource, external_issue, current_user)
      end

      it 'calls Jira API' do
        close_issue

        expect(WebMock).to have_requested(:post, comment_url).with(
          body: /Issue solved with/
        ).once
      end

      it 'tracks usage' do
        expect(Gitlab::UsageDataCounters::HLLRedisCounter)
          .to receive(:track_event)
          .with('i_ecosystem_jira_service_close_issue', values: current_user.id)

        close_issue
      end

      it 'does not fail if remote_link.all on issue returns nil' do
        allow(JIRA::Resource::Remotelink).to receive(:all).and_return(nil)

        expect { close_issue }.not_to raise_error
      end

      # Check https://developer.atlassian.com/jiradev/jira-platform/guides/other/guide-jira-remote-issue-links/fields-in-remote-issue-links
      # for more information
      it 'creates Remote Link reference in Jira for comment' do
        close_issue

        favicon_path = "http://localhost/assets/#{find_asset('favicon.png').digest_path}"

        # Creates comment
        expect(WebMock).to have_requested(:post, comment_url)
        # Creates Remote Link in Jira issue fields
        expect(WebMock).to have_requested(:post, remote_link_url).with(
          body: hash_including(
            GlobalID: 'GitLab',
            relationship: 'mentioned on',
            object: {
              url: "#{Gitlab.config.gitlab.url}/#{project.full_path}/-/commit/#{commit_id}",
              title: "Solved by commit #{commit_id}.",
              icon: { title: 'GitLab', url16x16: favicon_path },
              status: { resolved: true }
            }
          )
        ).once
      end

      context 'when "comment_on_event_enabled" is set to false' do
        it 'creates Remote Link reference but does not create comment' do
          allow(jira_service).to receive_messages(comment_on_event_enabled: false)
          close_issue

          expect(WebMock).not_to have_requested(:post, comment_url)
          expect(WebMock).to have_requested(:post, remote_link_url)
        end
      end

      context 'when Remote Link already exists' do
        let(:remote_link) do
          double(
            'remote link',
            object: {
              url: "#{Gitlab.config.gitlab.url}/#{project.full_path}/-/commit/#{commit_id}"
            }.with_indifferent_access
          )
        end

        it 'does not create comment' do
          allow(JIRA::Resource::Remotelink).to receive(:all).and_return([remote_link])

          expect(remote_link).to receive(:save!)

          close_issue

          expect(WebMock).not_to have_requested(:post, comment_url)
        end
      end

      it 'does not send comment or remote links to issues already closed' do
        allow_any_instance_of(JIRA::Resource::Issue).to receive(:resolution).and_return(true)

        close_issue

        expect(WebMock).not_to have_requested(:post, comment_url)
        expect(WebMock).not_to have_requested(:post, remote_link_url)
      end

      it 'does not send comment or remote links to issues with unknown resolution' do
        allow_any_instance_of(JIRA::Resource::Issue).to receive(:respond_to?).with(:resolution).and_return(false)

        close_issue

        expect(WebMock).not_to have_requested(:post, comment_url)
        expect(WebMock).not_to have_requested(:post, remote_link_url)
      end

      it 'references the GitLab commit' do
        stub_config_setting(base_url: custom_base_url)

        close_issue

        expect(WebMock).to have_requested(:post, comment_url).with(
          body: %r{#{custom_base_url}/#{project.full_path}/-/commit/#{commit_id}}
        ).once
      end

      it 'references the GitLab commit' do
        stub_config_setting(relative_url_root: '/gitlab')
        stub_config_setting(url: Settings.send(:build_gitlab_url))

        allow(described_class).to receive(:default_url_options) do
          { script_name: '/gitlab' }
        end

        close_issue

        expect(WebMock).to have_requested(:post, comment_url).with(
          body: %r{#{Gitlab.config.gitlab.url}/#{project.full_path}/-/commit/#{commit_id}}
        ).once
      end

      it 'logs exception when transition id is not valid' do
        allow(jira_service).to receive(:log_error)
        WebMock.stub_request(:post, transitions_url).with(basic_auth: %w(jira-username jira-password)).and_raise("Bad Request")

        close_issue

        expect(jira_service).to have_received(:log_error).with(
          "Issue transition failed",
          error: hash_including(
            exception_class: 'StandardError',
            exception_message: "Bad Request"
          ),
          client_url: "http://jira.example.com"
        )
      end

      it 'calls the api with jira_issue_transition_id' do
        close_issue

        expect(WebMock).to have_requested(:post, transitions_url).with(
          body: /"id":"999"/
        ).once
      end

      context 'when using multiple transition ids' do
        before do
          allow(jira_service).to receive_messages(jira_issue_transition_id: '1,2,3')
        end

        it 'calls the api with transition ids separated by comma' do
          close_issue

          1.upto(3) do |transition_id|
            expect(WebMock).to have_requested(:post, transitions_url).with(
              body: /"id":"#{transition_id}"/
            ).once
          end

          expect(WebMock).to have_requested(:post, comment_url)
        end

        it 'calls the api with transition ids separated by semicolon' do
          allow(jira_service).to receive_messages(jira_issue_transition_id: '1;2;3')

          close_issue

          1.upto(3) do |transition_id|
            expect(WebMock).to have_requested(:post, transitions_url).with(
              body: /"id":"#{transition_id}"/
            ).once
          end

          expect(WebMock).to have_requested(:post, comment_url)
        end

        context 'when a transition fails' do
          before do
            WebMock.stub_request(:post, transitions_url).with(basic_auth: %w(jira-username jira-password)).to_return do |request|
              { status: request.body.include?('"id":"2"') ? 500 : 200 }
            end
          end

          it 'stops the sequence' do
            close_issue

            1.upto(2) do |transition_id|
              expect(WebMock).to have_requested(:post, transitions_url).with(
                body: /"id":"#{transition_id}"/
              )
            end

            expect(WebMock).not_to have_requested(:post, transitions_url).with(
              body: /"id":"3"/
            )

            expect(WebMock).not_to have_requested(:post, comment_url)
          end
        end
      end
    end

    context 'when resource is a merge request' do
      let(:resource) { create(:merge_request) }
      let(:commit_id) { resource.diff_head_sha }

      it_behaves_like 'close_issue'
    end

    context 'when resource is a commit' do
      let(:resource) { project.commit('master') }
      let(:commit_id) { resource.id }

      it_behaves_like 'close_issue'
    end
  end

  describe '#create_cross_reference_note' do
    let_it_be(:user) { build_stubbed(:user) }
    let(:jira_issue) { ExternalIssue.new('JIRA-123', project) }

    subject { jira_service.create_cross_reference_note(jira_issue, resource, user) }

    shared_examples 'creates a comment on Jira' do
      let(:issue_url) { "#{url}/rest/api/2/issue/JIRA-123" }
      let(:comment_url) { "#{issue_url}/comment" }
      let(:remote_link_url) { "#{issue_url}/remotelink" }

      before do
        allow(JIRA::Resource::Remotelink).to receive(:all).and_return([])
        stub_request(:get, issue_url).with(basic_auth: [username, password])
        stub_request(:post, comment_url).with(basic_auth: [username, password])
        stub_request(:post, remote_link_url).with(basic_auth: [username, password])
      end

      it 'creates a comment on Jira' do
        subject

        expect(WebMock).to have_requested(:post, comment_url).with(
          body: /mentioned this issue in/
        ).once
      end

      it 'tracks usage' do
        expect(Gitlab::UsageDataCounters::HLLRedisCounter)
          .to receive(:track_event)
          .with('i_ecosystem_jira_service_cross_reference', values: user.id)

        subject
      end
    end

    context 'when resource is a commit' do
      let(:resource) { project.commit('master') }

      context 'when disabled' do
        before do
          allow_next_instance_of(JiraService) do |instance|
            allow(instance).to receive(:commit_events) { false }
          end
        end

        it { is_expected.to eq('Events for commits are disabled.') }
      end

      context 'when enabled' do
        it_behaves_like 'creates a comment on Jira'
      end
    end

    context 'when resource is a merge request' do
      let(:resource) { build_stubbed(:merge_request, source_project: project) }

      context 'when disabled' do
        before do
          allow_next_instance_of(JiraService) do |instance|
            allow(instance).to receive(:merge_requests_events) { false }
          end
        end

        it { is_expected.to eq('Events for merge requests are disabled.') }
      end

      context 'when enabled' do
        it_behaves_like 'creates a comment on Jira'
      end
    end
  end

  describe '#test' do
    let(:server_info_results) { { 'url' => 'http://url', 'deploymentType' => 'Cloud' } }

    def server_info
      jira_service.test(nil)
    end

    context 'when the test succeeds' do
      it 'gets Jira project with URL when API URL not set' do
        expect(server_info).to eq(success: true, result: server_info_results)
        expect(WebMock).to have_requested(:get, /jira.example.com/)
      end

      it 'gets Jira project with API URL if set' do
        jira_service.update!(api_url: 'http://jira.api.com')

        expect(server_info).to eq(success: true, result: server_info_results)
        expect(WebMock).to have_requested(:get, /jira.api.com/)
      end
    end

    context 'when the test fails' do
      it 'returns result with the error' do
        test_url = 'http://jira.example.com/rest/api/2/serverInfo'
        error_message = 'Some specific failure.'

        WebMock.stub_request(:get, test_url).with(basic_auth: [username, password])
          .to_raise(JIRA::HTTPError.new(double(message: error_message)))

        expect(jira_service).to receive(:log_error).with(
          'Error sending message',
          client_url: 'http://jira.example.com',
          error: error_message
        )

        expect(jira_service.test(nil)).to eq(success: false, result: error_message)
      end
    end
  end

  describe 'project and issue urls' do
    context 'when gitlab.yml was initialized' do
      it 'is prepopulated with the settings' do
        settings = {
          'jira' => {
            'url' => 'http://jira.sample/projects/project_a',
            'api_url' => 'http://jira.sample/api'
          }
        }
        allow(Gitlab.config).to receive(:issues_tracker).and_return(settings)

        service = project.create_jira_service(active: true)

        expect(service.url).to eq('http://jira.sample/projects/project_a')
        expect(service.api_url).to eq('http://jira.sample/api')
      end
    end

    it 'removes trailing slashes from url' do
      service = described_class.new(url: 'http://jira.test.com/path/')

      expect(service.url).to eq('http://jira.test.com/path')
    end
  end

  describe 'favicon urls' do
    it 'includes the standard favicon' do
      props = described_class.new.send(:build_remote_link_props, url: 'http://example.com', title: 'title')
      expect(props[:object][:icon][:url16x16]).to match %r{^http://localhost/assets/favicon(?:-\h+).png$}
    end

    it 'includes returns the custom favicon' do
      create :appearance, favicon: fixture_file_upload('spec/fixtures/dk.png')

      props = described_class.new.send(:build_remote_link_props, url: 'http://example.com', title: 'title')
      expect(props[:object][:icon][:url16x16]).to match %r{^http://localhost/uploads/-/system/appearance/favicon/\d+/dk.png$}
    end
  end

  context 'generating external URLs' do
    let(:service) { described_class.new(url: 'http://jira.test.com/path/') }

    describe '#issues_url' do
      it 'handles trailing slashes' do
        expect(service.issues_url).to eq('http://jira.test.com/path/browse/:id')
      end
    end

    describe '#new_issue_url' do
      it 'handles trailing slashes' do
        expect(service.new_issue_url).to eq('http://jira.test.com/path/secure/CreateIssue!default.jspa')
      end
    end
  end
end
