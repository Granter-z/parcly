/// 与商品 DOM 结构无关的营销浮标增量清理。
library;

/// 只检查新增文本，不读取 innerText，也不重复扫描整个商品列表。
const String pddCleanUiScript = r'''
(function() {
  try {
    if (window.__pddCleanInstalled) return;
    window.__pddCleanInstalled = true;
    var style = document.createElement('style');
    style.id = '__pdd_clean_ui_style';
    style.textContent = [
      '[class*="open-app"]', '[class*="wake-app"]',
      '[class*="app-wake"]', '[class*="download-app"]',
      '[class*="app-download"]', '[class*="btn-open"]',
      '[class*="btn-app"]', '[class*="top-bar-download"]',
      '[class*="bottom-bar-download"]', '[id*="open-app"]',
      '[id*="wake-app"]', 'div[class*="downloadBar"]',
      'div[class*="openApp"]'
    ].join(',') + ' { display: none !important; opacity: 0 !important; visibility: hidden !important; pointer-events: none !important; width: 0 !important; height: 0 !important; }';
    (document.head || document.documentElement).appendChild(style);
    var badgeTexts = ['在App打开', '在APP打开', '在app打开', 'App内打开', 'APP内打开', '打开App', '打开APP'];
    function hideBadge(el) {
      el.style.setProperty('display', 'none', 'important');
      el.style.setProperty('visibility', 'hidden', 'important');
      el.style.setProperty('pointer-events', 'none', 'important');
    }
    function inspectText(textNode) {
      if (textNode.parentElement && textNode.parentElement.__pddBadgeChecked) return;
      inspectElement(textNode.parentElement);
    }
    function inspectElement(el) {
      // textContent 不触发布局；只读新增节点及少量祖先，兼容拆到多个子节点的文本。
      if (!el || el.__pddBadgeChecked) return;
      // 标记已检查元素，避免 MutationObserver 后续批次反复触发 getComputedStyle
      el.__pddBadgeChecked = true;
      var candidate = el;
      var text = (candidate.textContent || '').trim();
      for (var level = 0; level < 4 && candidate && candidate !== document.body &&
          candidate !== document.documentElement && text.length > 20; level++) {
        candidate = candidate.parentElement;
        text = candidate ? (candidate.textContent || '').trim() : '';
      }
      // 已知边界：≤20 字的商品名若恰好含「在App打开」等营销文案，也会连卡片隐藏。
      if (!candidate || !text || text.length > 20) return;
      if (!badgeTexts.some(function(t) { return text.indexOf(t) !== -1; })) return;
      if ((text.indexOf('打开App') !== -1 || text.indexOf('打开APP') !== -1) && text.length > 10) return;
      var target = candidate;
      var cur = target;
      for (var d = 0; d < 4 && cur && cur.parentElement &&
          cur.parentElement !== document.body && cur.parentElement !== document.documentElement; d++) {
        var pos = window.getComputedStyle(cur).position;
        if (pos === 'fixed' || pos === 'absolute') {
          target = cur;
          break;
        }
        cur = cur.parentElement;
      }
      if (target) hideBadge(target);
    }
    function inspect(root) {
      if (root.nodeType === Node.TEXT_NODE) {
      inspectText(root);
      } else if (root.nodeType === Node.ELEMENT_NODE) {
        inspectElement(root);
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        var node;
        while ((node = walker.nextNode())) inspectText(node);
      }
    }
    function onReady(callback) {
      if (document.body) callback();
      else document.addEventListener('DOMContentLoaded', callback, {once: true});
    }
    onReady(function() {
      inspect(document.body);
      var pending = false;
      var observer = new MutationObserver(function(records) {
        if (pending) return;
        pending = true;
        requestAnimationFrame(function() {
          pending = false;
          for (var r = 0; r < records.length; r++) {
            if (records[r].type === 'characterData') {
              if (records[r].target && records[r].target.parentElement) {
                records[r].target.parentElement.__pddBadgeChecked = false;
              }
              inspectText(records[r].target);
            }
            for (var i = 0; i < records[r].addedNodes.length; i++) {
              var added = records[r].addedNodes[i];
              if (added && added.nodeType === Node.TEXT_NODE && added.parentElement) {
                added.parentElement.__pddBadgeChecked = false;
              }
              inspect(added);
            }
          }
        });
      });
      observer.observe(document.body, {childList: true, subtree: true, characterData: true});
      window.__pddCleanObserver = observer;
    });
  } catch(e) {}
})();
''';
