module RedmineIssueNewForms
  class Hooks < Redmine::Hook::ViewListener
    # Plugin assets are loaded only on the issues controller and only while
    # the new form is enabled, so the rest of the application is untouched.
    def view_layouts_base_html_head(context = {})
      controller = context[:controller]
      return '' unless controller.is_a?(IssuesController)
      return '' unless RedmineIssueNewForms.enabled?

      stylesheet_link_tag('rinf_issue', plugin: 'redmine_issue_new_forms') +
        javascript_include_tag('rinf_issue', plugin: 'redmine_issue_new_forms')
    end
  end
end
