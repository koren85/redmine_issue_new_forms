module RedmineIssueNewForms
  # Resolves the ordered list of field groups used to render the sidebar of
  # the new issue show page (see RinfIssuesHelper#rinf_render_field_groups).
  #
  # Each group is a 3-element array:
  #   [key, label, matchers]
  #
  #   key      - Symbol identifying the group (used as CSS/data attribute).
  #   label    - Symbol (a locale key, resolved via `l`) for the built-in
  #              DEFAULT groups, or a plain String (the group name as typed
  #              by the administrator) for groups loaded from settings.
  #   matchers - Array of matchers used to assign a field descriptor to this
  #              group. A Symbol matcher compares against a field
  #              descriptor's :key (used for the handful of core attributes
  #              that have a stable internal name). A String matcher
  #              compares case-insensitively (after stripping whitespace)
  #              against a field descriptor's display label - this is how
  #              custom fields (and, from the settings UI, core attributes
  #              too) are matched.
  class FieldGroups
    # NOTE: there is deliberately no "General" group for status / priority /
    # done_ratio / parent issue: those four are already rendered in the page
    # header (the pill row and the subject tree), and RinfIssuesHelper does not
    # emit descriptors for them at all - see rinf_field_descriptors.
    DEFAULT = [
      [:people, :rinf_group_people, [
        :assigned_to,
        'Ответственный от исполнителя',
        'Ответственный от заказчика',
        'Ответственный AI',
        'Исполнитель'
      ]],
      [:dates, :rinf_group_dates, [
        :start_date,
        :due_date,
        'Фактическая дата начала',
        'Фактическая дата завершения',
        'Отклонение в сроках',
        'Итоговая дата',
        'Дата резолюции',
        'Дата передачи Заказчику',
        'Причина переноса срока',
        'Срок решения из телеграмм'
      ]],
      [:contract, :rinf_group_contract, [
        :fixed_version,
        :estimated_hours,
        'Относится к контракту',
        'Оценка времени на день',
        'Оценка (тимлид), ч',
        'Приоритет на день',
        'Оценка на день',
        'Порядок выполнения'
      ]],
      [:classification, :rinf_group_classification, [
        :category,
        'Вид доработки',
        'Задача региона',
        'Номер заявки',
        'Подзадача',
        'Результат решения',
        'Причина отклонения',
        'Пакет обновления'
      ]],
      [:quality, :rinf_group_quality, [
        'Замечания актуальны',
        'Не содержит тех. терминов',
        'Даны пояснения изменений',
        'Даны рекомендации',
        'Пунктуация и орфография',
        'На контроле',
        'На личном контроле',
        'Есть ответ на вопрос'
      ]],
      [:counters, :rinf_group_counters, [
        'Количество возвратов',
        'Счетчик на исправление',
        'Счетчик Новые требования',
        'Счетчик на Консультацию',
        'Счетчик Ошибок пакета'
      ]],
      [:development, :rinf_group_development, [
        'Ветка на Git',
        'Ссылка на контекст'
      ]],
      [:other, :rinf_group_other, []]
    ].freeze

    class << self
      # Returns the ordered list of groups to use: either the administrator
      # configured groups (Setting.plugin_redmine_issue_new_forms['groups_yaml'])
      # or DEFAULT if that setting is blank/invalid. Never raises.
      def resolve
        custom_groups || DEFAULT
      end

      private

      # Parses the 'groups_yaml' plugin setting. Expected shape:
      #   "Group name":
      #     - "Field label"
      #     - "Other field label"
      #
      # Returns nil (falls back to DEFAULT) when the setting is blank, not
      # valid YAML, or doesn't parse to a non-empty Hash of arrays.
      def custom_groups
        text = RedmineIssueNewForms.settings['groups_yaml'].to_s
        return nil if text.strip.empty?

        data = parse_yaml(text)
        return nil unless data.is_a?(Hash) && data.any?

        groups = build_groups(data)
        return nil if groups.empty?

        groups << [:other, :rinf_group_other, []]
        groups
      rescue StandardError
        nil
      end

      def build_groups(data)
        groups = []

        data.each do |name, fields|
          label = name.to_s.strip
          next if label.empty?

          matchers = Array(fields).map { |field| field.to_s.strip }.reject(&:empty?)
          next if matchers.empty?

          key = label.parameterize
          key = "group_#{groups.size}" if key.blank?
          # Avoid colliding with the :other key reserved for the trailing
          # fallback group appended after this method returns.
          key = "custom_#{key}" if key == 'other'

          groups << [key.to_sym, label, matchers]
        end

        groups
      end

      # YAML.safe_load's signature changed across Psych versions (keyword
      # args vs positional args). Try the modern form first and fall back to
      # the old positional form so this works under Ruby 2.6's bundled Psych
      # as well as newer ones.
      def parse_yaml(text)
        if YAML.respond_to?(:safe_load)
          begin
            YAML.safe_load(text, permitted_classes: [], aliases: false)
          rescue ArgumentError
            YAML.safe_load(text, [], [], false)
          end
        else
          YAML.load(text)
        end
      rescue StandardError
        nil
      end
    end
  end
end
