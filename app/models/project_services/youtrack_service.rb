# frozen_string_literal: true

class YoutrackService < IssueTrackerService
  validates :project_url, :issues_url, presence: true, public_url: true, if: :activated?

  # {PROJECT-KEY}-{NUMBER} Examples: YT-1, PRJ-1, gl-030
  def self.reference_pattern(only_long: false)
    if only_long
      /(?<issue>\b[A-Za-z][A-Za-z0-9_]*-\d+\b)/
    else
      /(?<issue>\b[A-Za-z][A-Za-z0-9_]*-\d+\b)|(#{Issue.reference_prefix}#{Gitlab::Regex.issue})/
    end
  end

  def title
    'YouTrack'
  end

  def description
    s_('IssueTracker|YouTrack issue tracker')
  end

  def self.to_param
    'youtrack'
  end

  def fields
    [
      { type: 'text', name: 'project_url', title: _('Project URL'), required: true },
      { type: 'text', name: 'issues_url', title: s_('ProjectService|Issue URL'), required: true }
    ]
  end
end
