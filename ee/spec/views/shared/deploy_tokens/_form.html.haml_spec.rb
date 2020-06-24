# frozen_string_literal: true

require 'spec_helper'

describe 'shared/deploy_tokens/_form.html.haml' do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:user) { create(:user) }
  let_it_be(:token) { build(:deploy_token) }
  let_it_be(:project, refind: true) { create(:project, :private) }
  let_it_be(:group, refind: true) { create(:group) }

  RSpec.shared_examples "display deploy token settings" do |role, type, can|
    let(:subject) { type == :project ? project : group }

    if can
      it "renders the packages scopes for user role #{role} in #{type}" do
        render 'shared/deploy_tokens/form', token: token, group_or_project: subject

        expect(rendered).to have_content('Allows read access to the package registry')
      end
    else
      it "does not render the packages scopes for user role #{role} in #{type}" do
        render 'shared/deploy_tokens/form', token: token, group_or_project: subject

        expect(rendered).not_to have_content('Allows read access to the package registry')
      end
    end
  end

  where(:packages_enabled, :feature_enabled, :role, :subject, :can) do
    true  | true  | :owner      | :group   | true
    true  | false | :owner      | :group   | false
    false | true  | :owner      | :group   | false
    false | false | :owner      | :group   | false
    true  | true  | :maintainer | :group   | true
    true  | false | :maintainer | :group   | false
    false | true  | :maintainer | :group   | false
    false | false | :maintainer | :group   | false
    true  | true  | :maintainer | :project | true
    false | true  | :maintainer | :project | false
    true  | false | :maintainer | :project | false
    false | false | :maintainer | :project | false
  end

  with_them do
    before do
      subject.send("add_#{role}", user)
      allow(view).to receive(:current_user).and_return(user)
      stub_config(packages: { enabled: packages_enabled })
      stub_licensed_features(packages: feature_enabled)
    end

    it_behaves_like 'display deploy token settings', params[:role], params[:subject], params[:can]
  end
end
