module RinfIssuesHelper
  # Renders the sidebar attribute groups for the new issue show page.
  #
  # Builds a flat list of field descriptors (core attributes + visible
  # half-width custom fields, each with a hidden_attribute?/disabled_core_fields
  # guard already applied), buckets them into the groups returned by
  # RedmineIssueNewForms::FieldGroups.resolve, and renders each non-empty
  # group as a <details class="rinf-group"> block.
  #
  # Never raises: any unexpected error while building the descriptors falls
  # back to rendering nothing rather than breaking the issue page.
  def rinf_render_field_groups(issue)
    return ''.html_safe unless issue

    groups = RedmineIssueNewForms::FieldGroups.resolve
    descriptors = rinf_field_descriptors(issue)
    buckets = rinf_bucket_descriptors(descriptors, groups)

    parts = groups.map do |key, label, _matchers|
      fields = buckets[key]
      next if fields.blank?

      rinf_render_group(key, label, fields)
    end.compact

    safe_join(parts)
  rescue StandardError => e
    Rails.logger.error("[redmine_issue_new_forms] rinf_render_field_groups failed: #{e.class}: #{e.message}") if defined?(Rails)
    ''.html_safe
  end

  # True if the workflow (redmine_workflow_hidden_fields) hides this
  # attribute for the current user/status. Missing the patch entirely (e.g.
  # plugin disabled) is treated as "not hidden".
  def rinf_hidden_attr?(issue, name)
    issue.respond_to?(:hidden_attribute?) && issue.hidden_attribute?(name)
  end

  # True if the tracker has this core field disabled.
  def rinf_disabled_attr?(issue, name)
    issue.respond_to?(:disabled_core_fields) && issue.disabled_core_fields.include?(name)
  end

  private

  # ---------------------------------------------------------------------
  # Descriptor collection
  # ---------------------------------------------------------------------

  # A field descriptor is a Hash:
  #   :key        - Symbol, matched against FieldGroups Symbol matchers
  #   :label      - String, the display label (matched against String matchers)
  #   :css        - String, extra CSS class (kept for theme/plugin compat, e.g. "cf_12")
  #   :value_html - the rendered value (String/SafeBuffer) or nil/blank
  #   :empty      - true if the field has no value
  #   :bool       - true if this is a boolean custom field (checklist rendering)
  #   :bool_on    - true if a boolean field's value is '1'
  def rinf_field_descriptors(issue)
    list = []
    return list unless issue

    unless rinf_hidden_attr?(issue, 'status')
      list << {
        key: :status, label: l(:field_status), css: 'status',
        value_html: (issue.status ? issue.status.name : nil),
        empty: issue.status.nil?
      }
    end

    unless rinf_hidden_attr?(issue, 'priority_id')
      list << {
        key: :priority, label: l(:field_priority), css: 'priority',
        value_html: (issue.priority ? issue.priority.name : nil),
        empty: issue.priority.nil?
      }
    end

    unless rinf_disabled_attr?(issue, 'assigned_to_id') || rinf_hidden_attr?(issue, 'assigned_to_id')
      list << {
        key: :assigned_to, label: l(:field_assigned_to), css: 'assigned-to',
        value_html: (issue.assigned_to ? link_to_user(issue.assigned_to) : nil),
        empty: issue.assigned_to.nil?
      }
    end

    no_categories = issue.category.nil? && issue.project && issue.project.issue_categories.none?
    unless rinf_disabled_attr?(issue, 'category_id') || no_categories || rinf_hidden_attr?(issue, 'category_id')
      list << {
        key: :category, label: l(:field_category), css: 'category',
        value_html: (issue.category ? issue.category.name : nil),
        empty: issue.category.nil?
      }
    end

    no_versions = issue.fixed_version.nil? &&
                  issue.respond_to?(:assignable_versions) && issue.assignable_versions.none?
    unless rinf_disabled_attr?(issue, 'fixed_version_id') || no_versions || rinf_hidden_attr?(issue, 'fixed_version_id')
      list << {
        key: :fixed_version, label: l(:field_fixed_version), css: 'fixed-version',
        value_html: (issue.fixed_version ? link_to_version(issue.fixed_version) : nil),
        empty: issue.fixed_version.nil?
      }
    end

    unless rinf_disabled_attr?(issue, 'start_date') || rinf_hidden_attr?(issue, 'start_date')
      list << {
        key: :start_date, label: l(:field_start_date), css: 'start-date',
        value_html: (issue.start_date ? format_date(issue.start_date) : nil),
        empty: issue.start_date.nil?
      }
    end

    unless rinf_disabled_attr?(issue, 'due_date') || rinf_hidden_attr?(issue, 'due_date')
      list << {
        key: :due_date, label: l(:field_due_date), css: 'due-date',
        value_html: issue_due_date_details(issue),
        empty: issue.due_date.nil?
      }
    end

    unless rinf_disabled_attr?(issue, 'done_ratio') || rinf_hidden_attr?(issue, 'done_ratio')
      list << {
        key: :done_ratio, label: l(:field_done_ratio), css: 'progress',
        value_html: progress_bar(issue.done_ratio, :legend => "#{issue.done_ratio}%"),
        empty: false
      }
    end

    unless rinf_disabled_attr?(issue, 'estimated_hours') || rinf_hidden_attr?(issue, 'estimated_hours')
      list << rinf_estimated_hours_descriptor(issue)
    end

    unless rinf_disabled_attr?(issue, 'parent_issue_id') || rinf_hidden_attr?(issue, 'parent_issue_id')
      list << rinf_parent_descriptor(issue)
    end

    list.concat(rinf_custom_field_descriptors(issue))
    list
  rescue StandardError
    list
  end

  def rinf_estimated_hours_descriptor(issue)
    parts = []
    details = issue_estimated_hours_details(issue)
    parts << details if details.present?

    if User.current.allowed_to?(:view_time_entries, issue.project) && issue.total_spent_hours.to_f > 0
      spent = issue_spent_hours_details(issue)
      parts << safe_join([l(:label_spent_time), ': ', spent]) if spent.present?
    end

    value = parts.present? ? safe_join(parts, ' · ') : nil

    {
      key: :estimated_hours, label: l(:field_estimated_hours), css: 'estimated-hours',
      value_html: value, empty: value.blank?
    }
  end

  def rinf_parent_descriptor(issue)
    parent = issue.parent
    parent_visible = parent.present? && parent.respond_to?(:visible?) && parent.visible?

    {
      key: :parent, label: l(:field_parent_issue), css: 'parent',
      value_html: (parent_visible ? link_to_issue(parent, :subject => false) : nil),
      empty: !parent_visible
    }
  end

  def rinf_custom_field_descriptors(issue)
    return [] unless issue.respond_to?(:visible_custom_field_values)

    issue.visible_custom_field_values.reject { |v| v.custom_field.full_width_layout? }.map do |v|
      cf = v.custom_field
      {
        key: "cf_#{cf.id}".to_sym,
        label: cf.name.to_s,
        css: "cf_#{cf.id}",
        value_html: show_value(v),
        empty: rinf_cf_value_blank?(v.value),
        bool: cf.field_format == 'bool',
        bool_on: v.value.to_s == '1'
      }
    end
  rescue StandardError
    []
  end

  def rinf_cf_value_blank?(value)
    if value.is_a?(Array)
      value.compact.reject { |v| v.to_s.strip.empty? }.empty?
    else
      value.blank?
    end
  end

  # ---------------------------------------------------------------------
  # Grouping
  # ---------------------------------------------------------------------

  def rinf_bucket_descriptors(descriptors, groups)
    buckets = Hash.new { |h, k| h[k] = [] }
    fallback_key = groups.last.first

    descriptors.each do |descriptor|
      match = groups.find { |_key, _label, matchers| matchers.any? { |m| rinf_matcher_match?(m, descriptor) } }
      key = match ? match.first : fallback_key
      buckets[key] << descriptor
    end

    buckets
  end

  def rinf_matcher_match?(matcher, descriptor)
    if matcher.is_a?(Symbol)
      descriptor[:key] == matcher
    else
      matcher.to_s.strip.casecmp(descriptor[:label].to_s.strip).zero?
    end
  end

  # ---------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------

  def rinf_render_group(key, label, fields)
    return ''.html_safe if fields.blank?

    group_label = label.is_a?(Symbol) ? l(label) : label.to_s
    # Bool (checklist) fields are never hidden by the "show empty" toggle, so
    # they always count as filled and never contribute to the hideable-empty
    # count - otherwise an all-bool group like "Quality control" would show
    # a misleading "show empty (N)" button that toggles nothing.
    filled = fields.reject { |f| f[:empty] && !f[:bool] }
    hideable_empty = fields.count { |f| f[:empty] && !f[:bool] }

    summary = content_tag(
      'summary',
      safe_join([group_label, ' ', content_tag('span', "#{filled.size} / #{fields.size}", :class => 'rinf-group__count')]),
      :class => 'rinf-group__summary'
    )

    fields_html = content_tag('div', safe_join(fields.map { |f| rinf_render_field(f) }), :class => 'rinf-fields')

    toggle =
      if hideable_empty > 0
        content_tag(
          'button', l(:rinf_show_empty, :count => hideable_empty),
          :type => 'button', :class => 'rinf-toggle-empty', :data => { 'rinf-target' => key }
        )
      end

    content_tag(
      'details', safe_join([summary, fields_html, toggle].compact),
      :class => 'rinf-group', :open => true, :data => { 'rinf-group' => key }
    )
  end

  def rinf_render_field(field)
    if field[:bool]
      rinf_render_check_field(field)
    else
      rinf_render_value_field(field)
    end
  end

  def rinf_render_value_field(field)
    css = ['attribute', 'rinf-field']
    css << 'rinf-field--empty' if field[:empty]
    css << field[:css] if field[:css].present?

    value = field[:value_html].presence || '—'

    content_tag(
      'div',
      content_tag('div', field[:label], :class => 'label rinf-field__label') +
        content_tag('div', value, :class => 'value rinf-field__value'),
      :class => css.join(' ')
    )
  end

  # Rendered for boolean custom fields as a checklist item instead of a
  # label/value pair. Empty (unset) booleans are still rendered - they are
  # simply shown as "off" - so they are never subject to the group's
  # "show empty" toggle.
  def rinf_render_check_field(field)
    css = ['attribute', 'rinf-field', 'rinf-check']
    css << 'rinf-check--on' if field[:bool_on]
    css << field[:css] if field[:css].present?

    content_tag(
      'div',
      content_tag('span', '', :class => 'rinf-check__box', 'aria-hidden' => 'true') +
        content_tag('div', field[:label], :class => 'label rinf-field__label'),
      :class => css.join(' ')
    )
  end
end
