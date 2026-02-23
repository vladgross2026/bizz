/**
 * Онбординг-тур: пошаговые подсказки с подсветкой элементов.
 * Запуск: BizForumTour.start(steps, { forceShow: true }).
 * Повторно по ссылке: #/?tour=1 (игнорирует localStorage).
 */
(function () {
  var STORAGE_KEY = 'site_tour_completed';
  var TOUR_SHOW_SESSION = 'bizforum_show_tour';

  function getHashQuery() {
    var hash = (window.location.hash || '').slice(1);
    var q = hash.indexOf('?');
    if (q < 0) return {};
    var str = hash.slice(q + 1);
    var out = {};
    str.split('&').forEach(function (pair) {
      var i = pair.indexOf('=');
      if (i >= 0) out[decodeURIComponent(pair.slice(0, i).replace(/\+/g, ' '))] = decodeURIComponent((pair.slice(i + 1) || '').replace(/\+/g, ' '));
    });
    return out;
  }

  function t(key) {
    return (window.BizForum && window.BizForum.i18n && window.BizForum.i18n.t) ? window.BizForum.i18n.t(key) : key;
  }

  var overlayEl = null;
  var tooltipEl = null;
  var currentStepIndex = 0;
  var currentSteps = [];
  var options = { forceShow: false };
  var highlightedEl = null;

  function createOverlay() {
    if (overlayEl) return overlayEl;
    overlayEl = document.createElement('div');
    overlayEl.className = 'tour-overlay';
    overlayEl.setAttribute('aria-hidden', 'true');
    overlayEl.addEventListener('click', function (e) {
      if (e.target === overlayEl) close();
    });
    return overlayEl;
  }

  function createTooltip() {
    if (tooltipEl) return tooltipEl;
    tooltipEl = document.createElement('div');
    tooltipEl.className = 'tour-tooltip';
    tooltipEl.setAttribute('role', 'dialog');
    tooltipEl.setAttribute('aria-labelledby', 'tour-tooltip-title');
    tooltipEl.innerHTML =
      '<button type="button" class="tour-tooltip-close" aria-label="' + (t('tourClose') || 'Закрыть') + '">&times;</button>' +
      '<h3 class="tour-tooltip-title" id="tour-tooltip-title"></h3>' +
      '<p class="tour-tooltip-text"></p>' +
      '<div class="tour-tooltip-counter"></div>' +
      '<div class="tour-tooltip-actions">' +
      '<button type="button" class="tour-tooltip-prev">' + (t('tourBack') || 'Назад') + '</button>' +
      '<button type="button" class="tour-tooltip-next">' + (t('tourNext') || 'Далее') + '</button>' +
      '</div>';
    tooltipEl.querySelector('.tour-tooltip-close').addEventListener('click', close);
    tooltipEl.querySelector('.tour-tooltip-prev').addEventListener('click', function () { goToStep(currentStepIndex - 1); });
    tooltipEl.querySelector('.tour-tooltip-next').addEventListener('click', function () {
      if (currentStepIndex === currentSteps.length - 1) close();
      else goToStep(currentStepIndex + 1);
    });
    tooltipEl.addEventListener('click', function (e) { e.stopPropagation(); });
    return tooltipEl;
  }

  function removeHighlight() {
    if (highlightedEl) {
      highlightedEl.classList.remove('tour-highlight');
      highlightedEl = null;
    }
  }

  function positionTooltip(step, el) {
    if (!tooltipEl) return;
    var rect;
    var pos = (step.position || 'bottom').toLowerCase();
    if (el && el.getBoundingClientRect) {
      rect = el.getBoundingClientRect();
    } else {
      rect = { left: window.innerWidth / 2 - 180, top: window.innerHeight / 2 - 120, width: 360, height: 240 };
    }
    var gap = 12;
    var tw = 320;
    var th = tooltipEl.offsetHeight || 200;
    var left = 0;
    var top = 0;
    if (!el) {
      left = (window.innerWidth - tw) / 2;
      top = (window.innerHeight - th) / 2;
    } else {
      switch (pos) {
        case 'top':
          left = rect.left + (rect.width / 2) - (tw / 2);
          top = rect.top - th - gap;
          break;
        case 'left':
          left = rect.left - tw - gap;
          top = rect.top + (rect.height / 2) - (th / 2);
          break;
        case 'right':
          left = rect.right + gap;
          top = rect.top + (rect.height / 2) - (th / 2);
          break;
        default:
          left = rect.left + (rect.width / 2) - (tw / 2);
          top = rect.bottom + gap;
      }
    }
    left = Math.max(16, Math.min(window.innerWidth - tw - 16, left));
    top = Math.max(16, Math.min(window.innerHeight - th - 16, top));
    tooltipEl.style.left = left + 'px';
    tooltipEl.style.top = top + 'px';
  }

  function goToStep(index) {
    if (index < 0 || index >= currentSteps.length) return;
    removeHighlight();
    currentStepIndex = index;
    var step = currentSteps[index];
    var el = null;
    if (step.target) {
      el = document.querySelector(step.target);
      if (el) {
        el.classList.add('tour-highlight');
        highlightedEl = el;
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    }
    var titleEl = tooltipEl.querySelector('.tour-tooltip-title');
    var textEl = tooltipEl.querySelector('.tour-tooltip-text');
    var counterEl = tooltipEl.querySelector('.tour-tooltip-counter');
    var prevBtn = tooltipEl.querySelector('.tour-tooltip-prev');
    var nextBtn = tooltipEl.querySelector('.tour-tooltip-next');
    if (titleEl) titleEl.textContent = step.title || '';
    if (textEl) textEl.textContent = step.text || '';
    if (counterEl) counterEl.textContent = (index + 1) + ' ' + (t('tourOf') || 'из') + ' ' + currentSteps.length;
    if (prevBtn) prevBtn.style.display = index === 0 ? 'none' : '';
    if (nextBtn) {
      nextBtn.textContent = index === currentSteps.length - 1 ? (t('tourFinish') || 'Закрыть') : (t('tourNext') || 'Далее');
    }
    positionTooltip(step, el);
  }

  function close() {
    removeHighlight();
    if (overlayEl && overlayEl.parentNode) overlayEl.parentNode.removeChild(overlayEl);
    if (tooltipEl && tooltipEl.parentNode) tooltipEl.parentNode.removeChild(tooltipEl);
    try {
      if (!options.forceShow) localStorage.setItem(STORAGE_KEY, '1');
      sessionStorage.removeItem(TOUR_SHOW_SESSION);
    } catch (e) {}
    currentSteps = [];
    if (window.BizForumTour && window.BizForumTour.onClose) window.BizForumTour.onClose();
  }

  function start(steps, opts) {
    if (!steps || !steps.length) return;
    opts = opts || {};
    options.forceShow = !!opts.forceShow;
    currentSteps = steps;
    currentStepIndex = 0;
    createOverlay();
    createTooltip();
    if (!overlayEl.parentNode) document.body.appendChild(overlayEl);
    if (!tooltipEl.parentNode) document.body.appendChild(tooltipEl);
    overlayEl.classList.add('tour-overlay-visible');
    tooltipEl.classList.add('tour-tooltip-visible');
    goToStep(0);
  }

  function shouldShowAfterLogin() {
    var q = getHashQuery();
    if (q.tour === '1' || q.tour === 'true') return true;
    try {
      if (localStorage.getItem(STORAGE_KEY)) return false;
      if (sessionStorage.getItem(TOUR_SHOW_SESSION)) return true;
    } catch (e) {}
    return false;
  }

  function requestShowFromLink() {
    var q = getHashQuery();
    return q.tour === '1' || q.tour === 'true';
  }

  function markShowRequest() {
    try {
      sessionStorage.setItem(TOUR_SHOW_SESSION, '1');
    } catch (e) {}
  }

  window.BizForumTour = {
    start: start,
    close: close,
    shouldShowAfterLogin: shouldShowAfterLogin,
    requestShowFromLink: requestShowFromLink,
    markShowRequest: markShowRequest,
    STORAGE_KEY: STORAGE_KEY,
    getHashQuery: getHashQuery
  };
})();
