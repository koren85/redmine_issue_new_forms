module RedmineIssueNewForms
  # Runtime prepend of the plugin view directory. A plain app/views override
  # would lose to redmine_workflow_hidden_fields (alphabetically later plugins
  # prepend their view paths after us), so we prepend per-request instead —
  # the same pattern a_common_libs uses for its acl_prepended_views.
  module IssuesControllerPatch
    def self.included(base)
      base.class_eval do
        before_action :rinf_prepend_view_path, only: [:show]
      end
    end

    private

    def rinf_prepend_view_path
      return unless RedmineIssueNewForms.enabled?

      prepend_view_path(RedmineIssueNewForms.prepended_views_path)
    end
  end
end
