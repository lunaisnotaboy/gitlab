# frozen_string_literal: true

RSpec.shared_context 'Composer user type' do |user_type, add_member|
  before do
    group.send("add_#{user_type}", user) if add_member && user_type != :anonymous
    project.send("add_#{user_type}", user) if add_member && user_type != :anonymous
  end
end

RSpec.shared_examples 'Composer package index' do |user_type, status, add_member = true|
  include_context 'Composer user type', user_type, add_member do
    it 'returns the package index' do
      subject

      expect(response).to have_gitlab_http_status(status)
      expect(response).to match_response_schema('public_api/v4/packages/composer/index')
    end
  end
end

RSpec.shared_examples 'Composer empty provider index' do |user_type, status, add_member = true|
  include_context 'Composer user type', user_type, add_member do
    it 'returns the package index' do
      subject

      expect(response).to have_gitlab_http_status(status)
      expect(response).to match_response_schema('public_api/v4/packages/composer/provider')
      expect(json_response['providers']).to eq({})
    end
  end
end

RSpec.shared_examples 'Composer provider index' do |user_type, status, add_member = true|
  include_context 'Composer user type', user_type, add_member do
    it 'returns the package index' do
      subject

      expect(response).to have_gitlab_http_status(status)
      expect(response).to match_response_schema('public_api/v4/packages/composer/provider')
      expect(json_response['providers']).to include(package.name)
    end
  end
end

RSpec.shared_examples 'Composer package api request' do |user_type, status, add_member = true|
  include_context 'Composer user type', user_type, add_member do
    it 'returns the package index' do
      subject

      expect(response).to have_gitlab_http_status(status)
      expect(response).to match_response_schema('public_api/v4/packages/composer/package')
      expect(json_response['packages']).to include(package.name)
      expect(json_response['packages'][package.name]).to include(package.version)
    end
  end
end

RSpec.shared_examples 'Composer package creation' do |user_type, status, add_member = true|
  context "for user type #{user_type}" do
    before do
      group.send("add_#{user_type}", user) if add_member && user_type != :anonymous
      project.send("add_#{user_type}", user) if add_member && user_type != :anonymous
    end

    it 'creates package files' do
      expect { subject }
          .to change { project.packages.composer.count }.by(1)

      expect(response).to have_gitlab_http_status(status)
    end
    it_behaves_like 'a gitlab tracking event', described_class.name, 'register_package'
  end
end

RSpec.shared_examples 'process Composer api request' do |user_type, status, add_member = true|
  context "for user type #{user_type}" do
    before do
      group.send("add_#{user_type}", user) if add_member && user_type != :anonymous
      project.send("add_#{user_type}", user) if add_member && user_type != :anonymous
    end

    it_behaves_like 'returning response status', status
  end
end

RSpec.shared_context 'Composer auth headers' do |user_role, user_token|
  let(:token) { user_token ? personal_access_token.token : 'wrong' }
  let(:headers) { user_role == :anonymous ? {} : build_basic_auth_header(user.username, token) }
end

RSpec.shared_context 'Composer api project access' do |project_visibility_level, user_role, user_token|
  include_context 'Composer auth headers', user_role, user_token do
    before do
      project.update!(visibility_level: Gitlab::VisibilityLevel.const_get(project_visibility_level, false))
    end
  end
end

RSpec.shared_context 'Composer api group access' do |project_visibility_level, user_role, user_token|
  include_context 'Composer auth headers', user_role, user_token do
    before do
      project.update!(visibility_level: Gitlab::VisibilityLevel.const_get(project_visibility_level, false))
      group.update!(visibility_level: Gitlab::VisibilityLevel.const_get(project_visibility_level, false))
    end
  end
end

RSpec.shared_examples 'rejects Composer access with unknown group id' do
  context 'with an unknown group' do
    let(:group) { double(id: non_existing_record_id) }

    context 'as anonymous' do
      it_behaves_like 'process Composer api request', :anonymous, :not_found
    end

    context 'as authenticated user' do
      subject { get api(url), headers: build_basic_auth_header(user.username, personal_access_token.token) }

      it_behaves_like 'process Composer api request', :anonymous, :not_found
    end
  end
end

RSpec.shared_examples 'rejects Composer access with unknown project id' do
  context 'with an unknown project' do
    let(:project) { double(id: non_existing_record_id) }

    context 'as anonymous' do
      it_behaves_like 'process Composer api request', :anonymous, :not_found
    end

    context 'as authenticated user' do
      subject { get api(url), headers: build_basic_auth_header(user.username, personal_access_token.token) }

      it_behaves_like 'process Composer api request', :anonymous, :not_found
    end
  end
end
