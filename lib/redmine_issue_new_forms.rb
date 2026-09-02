module RedmineIssueNewForms
  PLUGIN_ID = :redmine_issue_new_forms

  class << self
    def plugin_root
      @plugin_root ||= File.expand_path('..', __dir__)
    end

    def prepended_views_path
      File.join(plugin_root, 'app', 'views', 'rinf_prepended_views')
    end

    def settings
      Setting.plugin_redmine_issue_new_forms || {}
    rescue StandardError
      {}
    end

    def enabled?
      settings['enable_new_show'].to_s == '1'
    end
  end
end
