---
stage: Create
group: Ecosystem
info: To determine the technical writer assigned to the Stage/Group associated with this page, see https://about.gitlab.com/handbook/engineering/ux/technical-writing/#assignments
---

# Integrations **(FREE)**

Integrations allow you to integrate GitLab with other applications. They
are a bit like plugins in that they allow a lot of freedom in adding
functionality to GitLab.

## Accessing integrations

You can find the available integrations under your project's
**Settings > Integrations** page.

There are more than 20 integrations to integrate with. Click on the one that you
want to configure.

![Integrations list](img/project_integrations_v13_3.png)

## Integrations listing

Click on the service links to see further configuration instructions and details.

| Service | Description | Service Hooks |
| ------- | ----------- | ------------- |
| Asana     | Asana - Teamwork without email | No |
| Assembla | Project Management Software (Source Commits Endpoint) | No |
| [Atlassian Bamboo CI](bamboo.md) | A continuous integration and build server | Yes |
| Buildkite | Continuous integration and deployments | Yes |
| [Bugzilla](bugzilla.md) | Bugzilla issue tracker | No |
| Campfire | Simple web-based real-time group chat | No |
| [Confluence](../../../api/services.md#confluence-service) | Replaces the link to the internal wiki with a link to a Confluence Cloud Workspace | No |
| Custom Issue Tracker | Custom issue tracker | No |
| [Discord Notifications](discord_notifications.md) | Receive event notifications in Discord | No |
| Drone CI | Continuous Integration platform built on Docker, written in Go | Yes |
| [Emails on push](emails_on_push.md) | Email the commits and diff of each push to a list of recipients | No |
| External wiki | Replaces the link to the internal wiki with a link to an external wiki | No |
| Flowdock | Flowdock is a collaboration web app for technical teams | No |
| [Generic alerts](../../../operations/incident_management/integrations.md) **(ULTIMATE)** | Receive alerts on GitLab from any source | No |
| [GitHub](github.md) **(PREMIUM)** | Sends pipeline notifications to GitHub | No |
| [Hangouts Chat](hangouts_chat.md) | Receive events notifications in Google Hangouts Chat | No |
| [HipChat](hipchat.md) | Private group chat and IM | No |
| [Irker (IRC gateway)](irker.md) | Send IRC messages, on update, to a list of recipients through an Irker gateway | No |
| [Jira](jira.md) | Jira issue tracker | No |
| [Jenkins](../../../integration/jenkins.md) **(STARTER)** | An extendable open source continuous integration server | Yes |
| JetBrains TeamCity CI | A continuous integration and build server | Yes |
| [Mattermost slash commands](mattermost_slash_commands.md) | Mattermost chat and ChatOps slash commands | No |
| [Mattermost Notifications](mattermost.md) | Receive event notifications in Mattermost | No |
| [Microsoft teams](microsoft_teams.md) |  Receive notifications for actions that happen on GitLab into a room on Microsoft Teams using Office 365 Connectors | No |
| Packagist | Update your projects on Packagist, the main Composer repository | Yes |
| Pipelines emails | Email the pipeline status to a list of recipients | No |
| [Slack Notifications](slack.md) | Send GitLab events (for example, an issue was created) to Slack as notifications | No |
| [Slack slash commands](slack_slash_commands.md) **(FREE SELF)** | Use slash commands in Slack to control GitLab | No |
| [GitLab Slack application](gitlab_slack_application.md) **(FREE SAAS)** | Use Slack's official application | No |
| PivotalTracker | Project Management Software (Source Commits Endpoint) | No |
| [Prometheus](prometheus.md) | Monitor the performance of your deployed apps | No |
| Pushover | Pushover makes it easy to get real-time notifications on your Android device, iPhone, iPad, and Desktop | No |
| [Redmine](redmine.md) | Redmine issue tracker | No |
| [EWM](ewm.md) | EWM work item tracker | No |
| [Unify Circuit](unify_circuit.md) | Receive events notifications in Unify Circuit | No |
| [Webex Teams](webex_teams.md) | Receive events notifications in Webex Teams | No |
| [YouTrack](youtrack.md) | YouTrack issue tracker | No |

## Push hooks limit

> [Introduced](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/17874) in GitLab 12.4.

If a single push includes changes to more than three branches or tags, services
supported by `push_hooks` and `tag_push_hooks` events aren't executed.

The number of branches or tags supported can be changed via
[`push_event_hooks_limit` application setting](../../../api/settings.md#list-of-settings-that-can-be-accessed-via-api-calls).

## Service templates

Service templates are a way to set predefined values for a project integration across
all new projects on the instance.

Read more about [Service templates](services_templates.md).

## Project integration management

Project integration management lets you control integration settings across all projects
of an instance. On the project level, administrators you can choose whether to inherit the
instance configuration or provide custom settings.

Read more about [Project integration management](../../admin_area/settings/project_integration_management.md).

## Troubleshooting integrations

Some integrations use service hooks for integration with external applications. To confirm which ones use service hooks, see the [integrations listing](#integrations-listing) above. GitLab stores details of service hook requests made within the last 2 days. To view details of the requests, go to that integration's configuration page.

The **Recent Deliveries** section lists the details of each request made within the last 2 days:

- HTTP status code (green for 200-299 codes, red for the others, `internal error` for failed deliveries)
- Triggered event
- URL to which the request was sent
- Elapsed time of the request
- Relative time in which the request was made

To view more information about the request's execution, click the respective **View details** link.
On the details page, you can see the request headers and body sent and received by GitLab.

To repeat a delivery using the same data, click **Resend Request**.

![Recent deliveries](img/webhook_logs.png)

### Uninitialized repositories

Some integrations fail with an error `Test Failed. Save Anyway` when you attempt to set them up on
uninitialized repositories. Some integrations use push data to build the test payload,
and this error occurs when no push events exist in the project yet.

To resolve this error, initialize the repository by pushing a test file to the project and set up
the integration again.

## Contributing to integrations

Because GitLab is open source we can ship with the code and tests for all
plugins. This allows the community to keep the plugins up to date so that they
always work in newer GitLab versions.

For an overview of what integrations are available, please see the
[project_services source directory](https://gitlab.com/gitlab-org/gitlab/tree/master/app/models/project_services).

Contributions are welcome!
