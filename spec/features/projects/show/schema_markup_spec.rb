# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Projects > Show > Schema Markup' do
  let_it_be(:project) { create(:project, :repository, :public, :with_avatar, description: 'foobar', tag_list: 'tag1, tag2') }

  it 'shows SoftwareSourceCode structured markup', :js do
    visit project_path(project)
    wait_for_all_requests

    aggregate_failures do
      expect(page).to have_selector('[itemscope][itemtype="http://schema.org/SoftwareSourceCode"]')
      expect(page).to have_selector('img[itemprop="image"]')
      expect(page).to have_selector('[itemprop="name"]', text: project.name)
      expect(page).to have_selector('[itemprop="identifier"]', text: "Project ID: #{project.id}")
      expect(page).to have_selector('[itemprop="abstract"]', text: project.description)
      expect(page).to have_selector('[itemprop="license"]', text: project.repository.license.name)
      expect(find_all('[itemprop="keywords"]').map(&:text)).to match_array(project.tag_list.map(&:capitalize))
      expect(page).to have_selector('[itemprop="about"]')
    end
  end
end
