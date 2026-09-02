require 'redmine'

Redmine::Plugin.register :redmine_issue_new_forms do
  name 'Redmine Issue New Forms'
  author 'BAZIS'
  description 'Современная форма просмотра задачи: группировка полей, скрытие пустых, сохранение всех хуков плагинов'
  version '0.1.0'
  requires_redmine version_or_higher: '4.1.0'

  settings partial: 'settings/rinf_settings',
           default: {
             'enable_new_show' => '1',
             'groups_yaml'     => ''
           }
end

Rails.configuration.to_prepare do
  require_dependency 'redmine_issue_new_forms'
  require_dependency 'redmine_issue_new_forms/field_groups'
  require_dependency 'redmine_issue_new_forms/hooks'
  require_dependency 'redmine_issue_new_forms/issues_controller_patch'

  unless IssuesController.include?(RedmineIssueNewForms::IssuesControllerPatch)
    IssuesController.send(:include, RedmineIssueNewForms::IssuesControllerPatch)
  end
  IssuesController.helper(RinfIssuesHelper)
end
