/**
 * Поведение новой формы просмотра задачи
 * - Персистенция состояния любых <details data-rinf-group> (группы свойств,
 *   «Файлы», список сохранённых запросов) в localStorage
 * - Toggle отображения пустых полей per-группа
 * - Восстановление состояния при загрузке страницы
 */
(function() {
  'use strict';

  var initialized = false;

  function init() {
    if (initialized) return;
    initialized = true;

    /**
     * Обёртка для работы с localStorage
     * Обрабатывает ошибки при private mode / переполнении
     */
    var storage = {
      save: function(key, value) {
        try {
          localStorage.setItem(key, value);
        } catch (e) {
          // private mode или переполнено — молча игнорируем
        }
      },
      get: function(key) {
        try {
          return localStorage.getItem(key);
        } catch (e) {
          return null;
        }
      }
    };

    /**
     * При инициализации: восстановить состояние групп из localStorage
     */
    var groups = document.querySelectorAll('details[data-rinf-group]');
    for (var i = 0; i < groups.length; i++) {
      var group = groups[i];
      var groupName = group.getAttribute('data-rinf-group');
      if (!groupName) continue;

      var storageKey = 'rinf:groups:' + groupName;
      var savedState = storage.get(storageKey);

      if (savedState === 'closed') {
        group.removeAttribute('open');
      } else if (savedState === 'open') {
        group.setAttribute('open', '');
      }
      // Если нет сохранённого состояния, оставляем текущее
    }

    /**
     * Слушать события toggle на <details class="rinf-group">
     * Сохранять текущее состояние (open/closed) в localStorage
     */
    document.addEventListener('toggle', function(e) {
      var target = e.target;
      if (!target.tagName || target.tagName !== 'DETAILS' || !target.hasAttribute('data-rinf-group')) {
        return;
      }

      var groupName = target.getAttribute('data-rinf-group');
      if (!groupName) return;

      var storageKey = 'rinf:groups:' + groupName;
      var state = target.hasAttribute('open') ? 'open' : 'closed';
      storage.save(storageKey, state);
    }, true); // capture phase

    /**
     * Номер задачи к теме.
     *
     * Ядро печатает «Поддержка #134698» в <h2> задолго до темы: между ними
     * встают тулбар кнопок процессов (deface insert_after: 'h2') и строка
     * цепочки/«Похожие» (её JS master_forms вставляет перед div.issue.details).
     * Переносим сам h2 в шапку задачи — не дублируем: единственность h2
     * сохраняется (это контракт с redmine_process_button и redmine_master_forms),
     * тулбар остаётся на месте, а бейдж L1 и «Тип работ» едут вместе с h2,
     * потому что master_forms кладёт их внутрь него ещё при разборе документа,
     * то есть до нашего DOMContentLoaded.
     */
    (function moveHeadingToSubject() {
      var heading = document.querySelector('#content > h2');
      var subject = document.querySelector('.rinf-issue .rinf-subject');
      if (heading && subject) {
        subject.insertBefore(heading, subject.firstChild);
      }
    })();

    /**
     * Сворачивание правой панели.
     *
     * #sidebar схлопывается в нулевую ширину, #content (flex: 1) забирает
     * освободившееся место. Ручку рисуем сами: ядро её не предусматривает.
     * Состояние — на пользователя, в localStorage.
     */
    (function foldableSidebar() {
      var sidebar = document.getElementById('sidebar');
      if (!sidebar || !sidebar.querySelector('.rinf-sidebar')) return;
      if (!document.querySelector('.rinf-issue')) return;

      var FOLD_H = 46, FOLD_GAP = 10, KEY = 'rinf:sidebar';
      var root = document.documentElement;

      var toggle = document.createElement('button');
      toggle.id = 'rinf-sidebar-toggle';
      toggle.type = 'button';
      document.body.appendChild(toggle);

      // Плавающие триггеры плагинов (SLA, Диспетчер, Мастер) прибиты к правому
      // краю окна, а по вертикали отсчитываются от его середины — на невысоком
      // экране они уезжают вверх. Поэтому ручку не ставим на фиксированную
      // высоту, а ищем свободное место рядом с их стеком.
      //
      // Сами элементы ищем один раз: перебор всего документа с
      // getComputedStyle на каждый resize стоил бы слишком дорого (на этой
      // форме несколько тысяч узлов). Триггеры приходят с сервера и в DOM уже
      // есть к моменту DOMContentLoaded; дальше перечитываем только их рамки.
      var widgets = null;
      function findWidgets() {
        var out = [];
        var all = document.body.querySelectorAll('*');
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          if (el === toggle) continue;
          var cs = window.getComputedStyle(el);
          if (cs.position !== 'fixed') continue;
          var r = el.getBoundingClientRect();
          if (r.width > 0 && r.height > 0 && r.width < 120 &&
              Math.abs(window.innerWidth - r.right) < 8) {
            out.push(el);
          }
        }
        return out;
      }

      function widgetBoxes() {
        if (widgets === null) widgets = findWidgets();
        var out = [];
        for (var i = 0; i < widgets.length; i++) {
          var cs = window.getComputedStyle(widgets[i]);
          if (cs.display === 'none' || cs.visibility === 'hidden') continue;
          var r = widgets[i].getBoundingClientRect();
          if (r.width > 0 && r.height > 0) out.push(r);
        }
        return out;
      }

      // Ширину раскрытой панели запоминаем: во время анимации
      // getBoundingClientRect вернул бы промежуточное значение (в момент
      // разворачивания — почти ноль) и ручка застряла бы у края окна.
      var openWidth = 0;

      function place() {
        var folded = root.classList.contains('rinf-sidebar-folded');
        if (!folded) {
          var w = Math.round(sidebar.getBoundingClientRect().width);
          if (w > 40) openWidth = w;
        }
        toggle.style.right = (folded ? 0 : openWidth) + 'px';

        var boxes = widgetBoxes();
        var top = 152;
        if (boxes.length) {
          var minTop = boxes[0].top, maxBottom = boxes[0].bottom;
          for (var i = 1; i < boxes.length; i++) {
            if (boxes[i].top < minTop) minTop = boxes[i].top;
            if (boxes[i].bottom > maxBottom) maxBottom = boxes[i].bottom;
          }
          var above = minTop - FOLD_H - FOLD_GAP;
          var below = maxBottom + FOLD_GAP;
          top = above >= 8 ? above
              : (below + FOLD_H <= window.innerHeight - 8 ? below : 8);
        }
        toggle.style.top = Math.round(top) + 'px';

        toggle.textContent = folded ? '\u2039' : '\u203A';
        var label = folded ? 'Развернуть правую панель' : 'Свернуть правую панель';
        toggle.setAttribute('aria-expanded', folded ? 'false' : 'true');
        toggle.setAttribute('aria-label', label);
        toggle.title = label;
      }

      if (storage.get(KEY) === 'folded') root.classList.add('rinf-sidebar-folded');

      toggle.addEventListener('click', function () {
        var folded = root.classList.toggle('rinf-sidebar-folded');
        storage.save(KEY, folded ? 'folded' : 'open');
        place();
      });

      sidebar.addEventListener('transitionend', function (e) {
        // Разворот закончился — ширина стала настоящей, уточняем позицию.
        if (e.propertyName === 'width') place();
      });

      var pending = false;
      window.addEventListener('resize', function () {
        if (pending) return;
        pending = true;
        window.requestAnimationFrame(function () { pending = false; place(); });
      });
      place();
    })();

    /**
     * Липкость колонки свойств — только когда она целиком помещается в окно.
     *
     * Безусловный sticky с max-height: 100vh превращал колонку в отдельный
     * скроллер и отрезал нижние группы, хотя страница заведомо выше и
     * вмещает всё. Высота меняется при раскрытии пустых полей и сворачивании
     * групп, поэтому пересчитываем по этим событиям.
     */
    (function stickyProperties() {
      var side = document.querySelector('.rinf-issue .rinf-side');
      if (!side) return;

      var root = document.documentElement;

      function check() {
        root.classList.remove('rinf-props-sticky');
        if (side.getBoundingClientRect().height <= window.innerHeight - 20) {
          root.classList.add('rinf-props-sticky');
        }
      }

      var pending = false;
      window.addEventListener('resize', function () {
        if (pending) return;
        pending = true;
        window.requestAnimationFrame(function () { pending = false; check(); });
      });
      document.addEventListener('click', function () { setTimeout(check, 0); });
      document.addEventListener('toggle', function () { setTimeout(check, 0); }, true);
      check();
    })();

    /**
     * Обработка клика по кнопкам toggle-empty
     * - Toggle класса rinf-show-empty на соответствующей группе
     * - Изменение текста кнопки между "Показать пустые (N)" и "Скрыть пустые"
     * - Сохранение оригинального текста в data-original-text при первом клике
     */
    document.addEventListener('click', function(e) {
      var btn = e.target;

      // Проверяем, что это кнопка toggle-empty
      if (!btn.classList || !btn.classList.contains('rinf-toggle-empty')) {
        return;
      }

      var targetGroup = btn.getAttribute('data-rinf-target');
      if (!targetGroup) return;

      // Найти соответствующую группу по data-rinf-group
      var group = document.querySelector('details[data-rinf-group="' + targetGroup + '"]');
      if (!group) {
        return;
      }

      // Toggle класса rinf-show-empty
      group.classList.toggle('rinf-show-empty');

      // Сохраняем исходный текст если это первый клик
      if (!btn.getAttribute('data-original-text')) {
        btn.setAttribute('data-original-text', btn.textContent);
      }

      var originalText = btn.getAttribute('data-original-text');
      var isShowing = group.classList.contains('rinf-show-empty');

      // Меняем текст кнопки
      if (isShowing) {
        btn.textContent = btn.getAttribute('data-rinf-hide-label') || 'Скрыть пустые';
      } else {
        btn.textContent = originalText;
      }
    });
  }

  /**
   * Инициализация на DOMContentLoaded
   * Если документ уже загружен, инициализируем сразу
   */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    // Уже загружен (если скрипт подключен с defer или async в конце body)
    init();
  }
})();
