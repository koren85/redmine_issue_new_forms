# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Цель проекта

Плагин для Redmine 4.1.3, который заменяет форму просмотра и редактирования задачи (issue show/edit) на современный интерфейс: группировка полей, скрытие пустых значений, инлайн-редактирование, сайдбар свойств — при **обязательном сохранении всех возможностей Redmine** (workflow, права, кастомные поля, журнал) и **вывода других плагинов через хуки**. Инсталляция тяжёлая: ~47 активных плагинов и ~35 полей на форме задачи.

Визуальный референс: [docs/mockups/issue-form-mock.html](docs/mockups/issue-form-mock.html) — открыть в браузере; там же показаны слоты хуков плагинов (переключатель «Слоты плагинов»).

Выбранный подход (по результатам исследования): **плагин с заменой шаблонов, НЕ тема**. Темы Redmine (`lib/redmine/themes.rb`) могут переопределять только CSS/JS/favicon — структуру ERB они не меняют. Плагин `redmine_pluggable_themes` это не расширяет.

## Окружение и команды

Плагин живёт внутри полной инсталляции Redmine: корень — `../../` (Redmine 4.1.3, Rails 5.2.5, Ruby 2.6.10, ограничение `>= 2.3, < 2.7`). БД — PostgreSQL 12 в docker (`redmine_dev2`).

Все команды выполняются из корня Redmine (`../../`):

```bash
docker compose up -d postgres          # поднять БД
# рабочий запуск (так запускает пользователь, production на :3300):
env RBENV_VERSION=2.6.10 /opt/homebrew/Cellar/rbenv/1.3.2/libexec/rbenv exec \
  ruby bin/rails server -b 127.0.0.1 -p 3300 -e production
bundle exec rake redmine:plugins:migrate NAME=redmine_issue_new_forms
bundle exec rake redmine:plugins:test NAME=redmine_issue_new_forms RAILS_ENV=test
# один тест:
bundle exec ruby -Itest plugins/redmine_issue_new_forms/test/unit/some_test.rb
```

Живой инстанс на `http://127.0.0.1:3300` можно смотреть браузером (Playwright); учётные данные администратора — у пользователя (в репозиторий не записывать). После изменения кода в production-режиме сервер надо перезапускать (кэш классов и вьюх).

Статика плагина кладётся в `assets/` (не `app/assets`!) и копируется при старте в `public/plugin_assets/redmine_issue_new_forms/` (`lib/redmine/plugin.rb:413`). Изменения в `init.rb` и `lib/` требуют перезапуска сервера; вьюхи и ассеты перечитываются в dev-режиме.

## Архитектура: как расширяется форма задачи в этой инсталляции

### Точки рендеринга ядра

- `app/views/issues/show.html.erb` — просмотр: таблица атрибутов через `issue_fields_rows` + `render_half_width_custom_fields_rows` / `render_full_width_custom_fields_rows` (`app/helpers/issues_helper.rb:305-375`).
- `app/views/issues/_edit.html.erb` → `_form.html.erb` → `_attributes.html.erb` → `_form_custom_fields.html.erb` — редактирование. Разделение полей на полную/половинную ширину — `CustomField#full_width_layout?` (`app/models/custom_field.rb:193`).
- Тег поля в форме: `custom_field_tag_with_label` (`app/helpers/custom_fields_helper.rb:119`), значение при просмотре: `show_value`.

### Хуки, которые ОБЯЗАНЫ остаться в любом нашем шаблоне

Локальные плагины реально используют (сломаются, если убрать `call_hook`):

- `view_issues_show_details_bottom` — additional_tags, redmine_sla_light, redmine_issue_cause, redmine_master_forms, redmine_favorites, unread_issues, report_registry, redmine_final_date, redmine_neural_dispatcher
- `view_issues_show_description_bottom` — redmine_process_button, redmine_recurring_tasks, redmine_mass_subtask, redmine_master_forms
- `view_issues_form_details_top` — a_common_libs
- `view_issues_form_details_bottom` — additional_tags, additionals, redmine_custom_asignee, redmine_final_date, redmine_issue_cause, unread_issues, westaco_versions, redmine_master_forms
- `view_issues_edit_notes_bottom`, `view_issues_history_journal_bottom` (redmine_link_issue), `view_issues_sidebar_issues_bottom` (westaco_versions, additionals)

### Критичный подводный камень: порядок переопределения вьюх

Плагины загружаются по алфавиту, и каждый **prepend**-ит свой `app/views` (`lib/redmine/plugin.rb:109-113,172`) ⇒ выигрывает алфавитно ПОСЛЕДНИЙ плагин. `redmine_workflow_hidden_fields` уже заменяет `issues/show.html.erb` (со своими guard-ами `@issue.hidden_attribute?(...)`), а имя `redmine_issue_new_forms` алфавитно РАНЬШЕ ⇒ наш файл `app/views/issues/show.html.erb` просто не подхватится.

Рабочий обход (паттерн из `a_common_libs`): prepend-ить собственный view-каталог в рантайме из патча контроллера — см. `plugins/a_common_libs/lib/acl/patches/controllers/issues_controller_patch.rb:14` (`prepend_view_path` на `app/views/acl_prepended_views`). Наш плагин должен делать так же (например, каталог `app/views/rinf_prepended_views/issues/…`), тогда порядок имён не важен.

### Что ещё влияет на форму и должно быть учтено

- **Видимость полей**: `redmine_workflow_hidden_fields` добавляет `Issue#hidden_attribute?` (`lib/redmine_workflow_hidden_fields/issue_patch.rb:45`) — наш шаблон обязан проверять его для каждого стандартного атрибута, как это делает их show-override. Плагин `issue_field_visibility` дополнительно фильтрует кастомные поля.
- **Deface доступен**: `redmine_base_deface` регистрирует `plugins/*/app/overrides` автоматически. Deface-оверрайды на issues/show есть у additionals, redmine_process_button, redmine_master_forms — они применяются к итоговому HTML, поэтому селекторы (`h2`, `.details` и т.п.), на которые они опираются, желательно сохранить в новой разметке.
- **Патч хелпера**: `redmine_issues_helper_patch` переопределяет `IssuesHelper#render_descendants_tree` и `#render_issue_relations` (жёстко зашиты custom fields id 81 и 63) — таблицы подзадач/связей рендерить через эти хелперы, не свои.
- Тема `master_forms_modern` (`public/themes/`) добавляет свои CSS/JS поверх — проверять новую форму с включённой темой.

### Контракт с redmine_process_button и redmine_master_forms — ОБЯЗАТЕЛЕН

Полный проверенный чек-лист: [docs/research/compatibility-contract.md](docs/research/compatibility-contract.md) (анализ кода + живая проверка DOM на :3300). Самое критичное — интеграции отказывают **тихо**, без ошибок:

- На show: ровно один `h2` (Deface-тулбар кнопок + бейдж L1/L2/L3 мастера), контейнер под селектор `#content div.issue.details` (крошки цепочки/похожих), `.contextual` c `a.icon-edit/copy/del/comment` (permission-скрытие), `#update`/`#all_attributes`/`#issue_notes` (режим comment_only), `#context-menu`, модалка `#ajax-modal`.
- На edit: `form#issue-form` с сабмитом в штатный `IssuesController#update`, `select#issue_tracker_id` (туда вставляется «Тип работ»), `textarea#issue_notes` внутри fieldset, поля `mwf_tree_selections[<code>][]`, стандартные Rails-id всех полей (`issue_*`, `issue_custom_field_values_<id>`) — на них же завязана «Простая форма» плагина issue_field_visibility.
- Кнопки процессов всегда `a.pb-btn` с `data-url .../process_buttons/:id/execute` — их перехватывает модальный мастер через `window.MasterWizardBtnMap`.
- Шторки `#mwf-drawer` / `#sla-drawer` / `#nd-drawer` живут на body и от разметки задачи не зависят.
- Тема `master_forms_modern` красит core-классы `.details .attribute .label/.value` — новую форму проверять и с ней.

## Текущее состояние (v0.1, июль 2026)

Реализована и проверена e2e новая страница **просмотра** задачи (show); форма редактирования — штатная (наш `#update` рендерится core-партиалом `action_menu_edit`). Устройство:

- `lib/redmine_issue_new_forms/issues_controller_patch.rb` — before_action на `show`, делает `prepend_view_path` на `app/views/rinf_prepended_views` (обход алфавитного порядка плагинов).
- `app/views/rinf_prepended_views/issues/show.html.erb` — новый шаблон; контракт (единственный `h2`, `div.issue.details`, все `call_hook`, `#update`, `#context-menu`, guard-ы `hidden_attribute?`) соблюдён и покрыт живым e2e-чеклистом. **Журнал и «Файлы» лежат вне `.rinf-layout`** — двухколоночная сетка отдана описанию и плагинным блокам, а переписка занимает всю ширину. Вложения — свёрнутый `<details>` ниже журнала (у задачи легко 20+ скриншотов, сверху они выдавливали комментарии за первый экран). Сайдбар: core-партиал `issues/_sidebar` **инлайнится** в шаблон, а не рендерится, чтобы свернуть список сохранённых запросов (~40 ссылок — самый высокий и самый нерелевантный блок страницы); все три его `call_hook` сохранены в исходном порядке, `#watchers` сохраняет id и стоит последним.
- `app/helpers/rinf_issues_helper.rb` + `lib/redmine_issue_new_forms/field_groups.rb` — дескрипторы полей (core-атрибуты + `visible_custom_field_values`), группировка (дефолт под эту инсталляцию, override — YAML в настройках плагина), рендер групп `<details>` с «Показать пустые (N)»; bool-CF — чек-лист, скрытию не подлежат.
- `assets/stylesheets/rinf_issue.css` — палитра `--rinf-*` объявлена на `:root`, всё остальное скоупировано под `.rinf-issue` **или** под классы body `controller-issues.action-show` (вне `.rinf-issue` лежит только ядровый `#sidebar`). Ширина страницы не ограничена (`max-width` снят). Правая панель оформлена рельсом в палитре формы и **сворачивается** (`html.rinf-sidebar-folded` → `width: 0`, `#content` как `flex:1` забирает место); специфичность `html.<класс> body.<классы> #sidebar` перебивает шесть ядровых медиазапросов `#sidebar{width:…}` без `!important`. Колонка свойств липкая **только когда влезает в окно** (класс `html.rinf-props-sticky` вешает JS): безусловный `sticky + max-height:100vh` делал её отдельным скроллером и резал нижние группы. Ядровое `div.issue div.attributes{margin-top:2em}` погашено для `.rinf-groups` — из-за него верх колонки не совпадал с верхом «Описания» на 24px. Под плавающие триггеры плагинов (`.sla-drawer-trigger` и соседи, `position:fixed; right:0`) в `.rinf-sidebar` зарезервировано 44px справа; широкие таблицы (`.rinf-plugin-zone`, таблицы в `.wiki`/`.journal`) получили свой горизонтальный скролл, иначе они рисовались поверх панели свойств; в файле есть «барьер» с `!important`, нейтрализующий core-правила `div.issue .attributes .attribute/.label/.value` (padding-left:180px, margin-left:-180px, float, overflow) — наша разметка сознательно сохраняет классы `attributes`/`attribute`/`label`/`value`/`cf_N` для совместимости с темами/плагинами, поэтому барьер обязателен.
- `assets/javascripts/rinf_issue.js` — тогглы пустых, персистентность любых `details[data-rinf-group]` (группы свойств, «Файлы», сохранённые запросы) в localStorage `rinf:groups:<key>`; **перенос `#content > h2` внутрь `.rinf-subject`** (номер задачи к теме — см. ниже); ручка сворачивания правой панели `#rinf-sidebar-toggle` с состоянием в `rinf:sidebar`; замер липкости колонки свойств.

  Позиция ручки считается, а не задаётся константой: триггеры шторок прибиты к правому краю, но по вертикали отсчитываются от середины окна, поэтому на невысоком экране уезжают вверх — ручка ищет место над их стеком, а если сверху не помещается, встаёт под ним. Список триггеров ищется **один раз** (перебор документа с `getComputedStyle` на каждый `resize` слишком дорог), дальше перечитываются только их рамки; `resize` схлопнут в один пересчёт на кадр.
- Выключатель: настройка плагина `enable_new_show` (работает без перезапуска — проверяется на каждый запрос).

**Гочи production-режима**: ассеты копируются в `public/plugin_assets/` только при старте сервера — после правки CSS/JS либо перезапуск, либо вручную `cp` в `public/plugin_assets/redmine_issue_new_forms/…`. Шаблоны/хелперы в production тоже кэшируются — нужен перезапуск.

Скриншоты: «до» — `docs/research/screenshots/current-issue-{show,edit}.png`, «после» — `new-form-{full,viewport}.png`.

### Принципы новой формы (из мока)

- Пустые поля скрыты по умолчанию, раскрываются per-группа («Показать пустые (N)»). Счётчика «заполнено / всего» в шапке группы нет намеренно — он не читался, а единственное осмысленное число уже названо в этой кнопке.
- Ничего не дублируется между шапкой и группами: статус, приоритет, готовность и родительская задача живут только в шапке (пилюли + дерево темы), поэтому `rinf_field_descriptors` их вообще не отдаёт, а группы «Основное» больше нет.
- Поля сгруппированы: Люди / Сроки / Контракт и оценка / Классификация / Контроль качества (чекбоксы как чек-лист) / Счётчики / Разработка. Группировка должна быть конфигурируемой (настройки плагина), а не зашитой.
- Номер задачи — часть идентификации, а не служебная надпись: `h2` переносится JS-ом к теме и стоит слева от неё (20px против 25px у темы). Именно перенос, а не дубль — единственность `h2` это контракт; deface `insert_after: 'h2'` у redmine_process_button уже отработал на рендере, а бейдж L1 и «Тип работ» master_forms кладёт внутрь `h2` при разборе документа, то есть до нашего `DOMContentLoaded`, и едет вместе с ним.
- Инлайн-редактирование поля отправляет обычный `PUT /issues/:id` (тот же `IssuesController#update`) — один журнал, workflow и права работают без изменений.
- Журнал — вкладки: Комментарии / История свойств / Всё / Трудозатраты.
- Хуки рендерятся в выделенные «слоты» на своих местах (см. мок), чтобы чужой вывод не ломал сетку.
