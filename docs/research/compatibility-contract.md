# Контракт совместимости новой формы задач

Источники: анализ кода `redmine_process_button`, `redmine_master_forms`, `issue_field_visibility`, темы `master_forms_modern` + живая проверка DOM на работающем инстансе (:3300, production, задача #139187, июль 2026). Скриншоты текущего UI — в [screenshots/](screenshots/).

Общий принцип: почти все интеграции отказывают **тихо** (блок просто не отрендерится, слот останется `display:none`, параметр придёт `nil`) — без ошибок в логах. Поэтому каждую позицию чек-листа надо проверять глазами/тестом, а не по отсутствию исключений.

## 1. Хуки, которые обязаны вызываться

| Хук | Где вызывается сейчас | Кто слушает |
|---|---|---|
| `view_issues_show_details_bottom` | `issues/show` внутри `div.attributes` | master_forms (action buttons + crumbs), sla_light, task_overlap_finder, issue_cause, favorites, unread_issues, report_registry, final_date, neural_dispatcher, additional_tags |
| `view_issues_show_description_bottom` | `issues/show` после full-width CF | master_forms (шторка), process_button (comment_only JS), recurring_tasks, mass_subtask |
| `view_issues_form_details_top` | `issues/_form:2` | a_common_libs |
| `view_issues_form_details_bottom` | `issues/_form:53`, после `#attributes` | master_forms (tree selections), additional_tags, additionals, custom_asignee, final_date, issue_cause, unread_issues, westaco_versions |
| `view_issues_edit_notes_bottom` | `issues/_edit:45` | (резерв) |
| `view_issues_history_journal_bottom` | journals | link_issue |
| `view_layouts_base_html_head` | `layouts/base:16` | process_button и master_forms грузят через него CSS/JS/`window.MasterWizardBtnMap` — не трогаем layout |
| `controller_issues_edit_after_save` | `IssuesController#save_issue_with_child_records` после `@issue.save` | process_button (события), master_forms (**сохранение `mwf_tree_selections`**) |

## 2. DOM-якоря на странице просмотра (issues/show)

- **Ровно один `<h2>`** с заголовком задачи. Deface `redmine_process_button` делает `insert_after 'h2'` (тулбар `.pb-toolbar`); JS master_forms вставляет бейдж L1/L2/L3 и «тип работ» в **первый** `h2` (`document.querySelector('h2')`).
- **Контейнер, матчащийся `#content div.issue.details`** — JS master_forms создаёт `.mwf-crumbs-row` (цепочка + похожие) и вставляет её **перед** этим блоком; баннер заказчика ищет его же. Нет селектора → крошки навсегда `display:none`.
- **`.contextual` с `a.icon-edit`, `a.icon-copy`, `a.icon-del`** и `.contextual` у описания с `a.icon-comment` — permission-скрытие кнопок (`mwf_hide_edit_button` и др.). Потеря классов = дыра в политике доступа, не косметика.
- **`#context-menu`** с `ul > li > a`, классом `.folder`, ссылками `a[href*="bulk_update"]` — то же скрытие для контекстного меню.
- **`#update`**, **`#all_attributes`**, `[name*="time_entry"]`, **`#issue_notes`** — режим comment_only у process_button (`GET /issues/:id?comment_only=1` + одноразовый session-токен): JS скрывает атрибуты/трудозатраты, показывает `#update`, скроллит к `#issue_notes`.
- Модалка **`#ajax-modal`** + core-функции `showModal`/`hideModal` (application.js) — используются preview/edit-режимами кнопок и модальным мастером. `#top-menu` — для позиционирования модалки (деградация мягкая).

## 3. DOM-якоря на форме редактирования (issues/_edit → _form)

- **`form#issue-form`**, сабмит штатным `PUT /issues/:id` (`IssuesController#update`). Если сохранять иначе — самим вызывать `call_hook(:controller_issues_edit_after_save, ...)`.
- **`select#issue_tracker_id`** — master_forms вставляет `#mwf-work-type-slot` («Тип работ») сразу после него на DOMContentLoaded. Нет id → поле недоступно.
- **`textarea#issue_notes`** внутри `fieldset` (поиск обёртки: `.closest('.jstBlock')` → `.closest('p')` → fieldset) — скрытие комментария для заказчика (`hide_customer_comment`).
- **Поля `mwf_tree_selections[<dict_code>][]`** (multiple select + parallel hidden reset `value=""`) — единственный канал записи справочников мастера из штатной формы; имя менять нельзя. Рендерятся хуком `view_issues_form_details_bottom` — достаточно сохранить хук.
- **Стандартные Rails-id полей** `issue_project_id`, `issue_tracker_id`, `issue_subject`, `issue_status_id`, `issue_assigned_to_id`, `issue_custom_field_values_<id>` (30 шт. на боевой форме) — на них завязан `issue_field_visibility` («Простая форма», конфиг `window.issueSimpleFields`) и куча плагинного JS. Новая форма обязана строить поля через штатные form-билдеры, сохраняя id.
- Fieldset-структура сейчас: «Изменить свойства» / «Добавить трудозатраты» (со своими CF) / «Примечания» / «Файлы».

## 4. Процессные кнопки (redmine_process_button)

- Кнопки: `a.pb-btn` с `data-url` вида `/issues/:issue_id/process_buttons/:id/execute`, `data-mode` = `silent|preview|edit`, `data-preview-url`/`data-edit-url`, `data-confirmation`. Обработчики **делегированы на document** — переживут любую перестройку DOM, если сами кнопки рендерятся с этими классами/атрибутами.
- Endpoints: `POST .../execute` (JSON: `{success, error, redirect_url}`), `GET .../preview` и `.../edit_form` (JS-ответ в `#ajax-modal`; формы `#process-button-preview-form` / `#process-button-edit-form`).
- Тулбар: `.pb-toolbar` (+ зоны, `.pb-group`, `.pb-more-dropdown` overflow, `.pb-virtual-dropdown` группы). Классы `pb-*` зарезервированы.
- **Перехват мастером**: `master_wizard_modal.js` ловит клики по `.pb-btn`, матчит `data-url` по `/process_buttons/(\d+)/execute` против `window.MasterWizardBtnMap` и открывает модальный мастер вместо родного действия. Если кнопки потеряют класс/атрибут — перехват молча исчезнет.
- CSRF-токен в `<meta name="csrf-token">` обязателен (стандартный layout).

## 5. Мастер форм (redmine_master_forms)

- Собственные пути создания/обновления (`RunWizard`/`UpdateWizard`/`RunAddendum` через `MasterWizardController`, модальный режим — партиал в `#ajax-modal`, ответ JSON) — от разметки issues/show и _edit **не зависят**, не трогаем.
- Данные — в своих таблицах `master_wizard_*` (FK на `issues.id`), в `issues` колонок нет.
- Шторка `#mwf-drawer` + `#mwf-drawer-trigger` + `#mwf-drawer-overlay` — самодостаточна (как и `#sla-drawer` sla_light и `#nd-drawer` neural_dispatcher); все три живут на body фиксированными панелями и переживут замену шаблона при сохранённых хуках.
- Deface-оверрайд master_forms таргетирует `process_buttons/_form` (админка другого плагина) — нас не касается.
- Тема `master_forms_modern` — чистый CSS поверх core-классов `.details .attribute .label/.value`, `.journal` и mwf-классов хуков. При новой разметке перестанет матчиться по core-части (визуальная деградация, не поломка); mwf-классы продолжат краситься. Новую форму тестировать и с активной темой.

## 6. Живые факты (проверено на :3300)

- Порядок детей `#content` на show: `flash` → `.contextual` → `h2` → `.pb-toolbar` (Deface) → `.mwf-crumbs-row` (JS-перенос) → `div.issue.details` → `#history` → … → `#update` → `p.other-formats` → `#context-menu`.
- На реальной задаче: кнопки «Решена» / «Создать подзадачу на отдел» / «Закрепить в графике»; крошки «L1 → L2 (вы здесь)» + «Похожие»; блоки «Пересекающиеся задачи» (task_overlap_finder), «Отчёты» (report_registry), «Функционал…» (issue_cause), Tags; вкладки истории «История | Примечания | Изменения свойств»; приватные журналы автоматики (диспетчер).
- Правая кромка: шторки SLA (🟢 бейдж) / Диспетчер / Мастер.
- На edit: «Простая форма» (issue_field_visibility), `#mwf-work-type-slot` возле трекера, `details.mwf-edit-dicts` «Данные мастера», 30 CF-инпутов, select2 — 1 шт.

## 7. Следствия для архитектуры новой формы

1. Новая разметка show обязана нести «скелетные» якоря: единственный `h2`, блок с классами `issue details` внутри `#content`, `.contextual` с иконками-ссылками, скрытый `#update` с формой, `#context-menu`.
2. Форма — только через штатные form-билдеры (`labelled_form_for @issue`) с родными id и сабмитом в `IssuesController#update`.
3. Плагинный вывод не «встраивать» в свою сетку принудительно: отдать хук-слотам собственные контейнеры-карточки в тех же местах документа (details_bottom — внутри блока атрибутов, description_bottom — после описания), CSS новой формы не должен ломать `pb-*` и `mwf-*`.
4. Инлайн-редактирование реализовывать как частичную отправку той же формы (или PUT с `issue[...]`), чтобы `controller_issues_edit_after_save` и safe_attributes плагинов срабатывали как раньше.
5. Каждый пункт контракта закрывать функциональным тестом/скриншот-тестом: отказ везде тихий.
