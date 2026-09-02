/**
 * Управление группами полей в новой форме просмотра задачи
 * - Персистенция состояния групп (details open/closed) в localStorage
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
    var groups = document.querySelectorAll('.rinf-group[data-rinf-group]');
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
      if (!target.classList || !target.classList.contains('rinf-group')) {
        return;
      }

      var groupName = target.getAttribute('data-rinf-group');
      if (!groupName) return;

      var storageKey = 'rinf:groups:' + groupName;
      var state = target.hasAttribute('open') ? 'open' : 'closed';
      storage.save(storageKey, state);
    }, true); // capture phase

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
      var group = document.querySelector('.rinf-group[data-rinf-group="' + targetGroup + '"]');
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
        btn.textContent = 'Скрыть пустые';
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
