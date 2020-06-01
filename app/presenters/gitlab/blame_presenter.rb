# frozen_string_literal: true

module Gitlab
  class BlamePresenter < Gitlab::View::Presenter::Simple
    include ActionView::Helpers::UrlHelper
    include ActionView::Helpers::TranslationHelper
    include ActionView::Context
    include AvatarsHelper
    include BlameHelper
    include CommitsHelper
    include ApplicationHelper
    include TreeHelper
    include IconsHelper

    presents :blame

    def initialize(subject, **attributes)
      super

      precalculate_data_by_commit!
    end

    def groups
      @groups ||= blame.groups
    end

    def author_avatar_for_commit(commit_id)
      @author_avatars[commit_id]
    end

    def age_map_class_for_commit(commit_id)
      @age_map_classes[commit_id]
    end

    def commit_link_for_commit(commit_id)
      @commit_links[commit_id]
    end

    def commit_author_link_for_commit(commit_id)
      @commit_author_links[commit_id]
    end

    def project_blame_link_for_commit(commit_id)
      @project_blame_links[commit_id]
    end

    def time_ago_tooltip_for_commit(commit_id)
      @time_ago_tooltips[commit_id]
    end

    private

    def precalculate_data_by_commit!
      @author_avatars = {}
      @age_map_classes = {}
      @commit_links = {}
      @commit_author_links = {}
      @project_blame_links = {}
      @time_ago_tooltips = {}

      sprite_icon = sprite_icon('doc-versions', size: 16, css_class: 'doc-versions align-text-bottom')

      groups.each do |blame_group|
        commit = blame_group[:commit]
        @author_avatars[commit.id] ||= author_avatar(commit, size: 36, has_tooltip: false)

        @age_map_classes[commit.id] ||= age_map_class(commit.committed_date, project_duration)
        @commit_links[commit.id] ||= link_to commit.title, project_commit_path(project, commit.id), class: "cdark", title: commit.title


        @commit_author_links[commit.id] ||= commit_author_link(commit, avatar: false)
        @time_ago_tooltips[commit.id] ||= time_ago_with_tooltip(commit.committed_date)

        previous_commit_id = commit.parent_id

        @project_blame_links[commit.id] ||=
          begin
            if previous_commit_id
              link_to project_blame_path(project, tree_join(previous_commit_id, path)),
                      title: _('View blame prior to this change'),
                      aria: { label: _('View blame prior to this change') },
                      data: { toggle: 'tooltip', placement: 'right', container: 'body' } do
                        sprite_icon
                      end
            end
          end
        end
      end

      def project_duration
        @project_duration ||= age_map_duration(groups, project)
    end
  end
end
