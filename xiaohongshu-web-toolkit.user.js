// ==UserScript==
// @name         小红书网页脚本
// @namespace    https://github.com/zwmopen/userscripts
// @version      0.4.2
// @description  配合聚光的小红书网页杂七杂八工具：记忆关键词、榜单、筛选、指标和日期，并从内容卡片直达蒲公英作者主页
// @author       Codex
// @match        https://ad.xiaohongshu.com/*
// @match        https://juguang.xiaohongshu.com/*
// @match        https://xhsad.com/*
// @match        https://www.xiaohongshu.com/explore/*
// @match        https://www.xiaohongshu.com/discovery/item/*
// @match        https://www.xiaohongshu.com/note/*
// @match        https://www.xiaohongshu.com/user/profile/*
// @updateURL    https://raw.githubusercontent.com/zwmopen/scripts/master/xiaohongshu-web-toolkit.user.js
// @downloadURL  https://raw.githubusercontent.com/zwmopen/scripts/master/xiaohongshu-web-toolkit.user.js
// @run-at       document-start
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_deleteValue
// @grant        GM_registerMenuCommand
// ==/UserScript==

(function () {
  'use strict';

  const VERSION = 'v1';
  const STORAGE_KEY = `xhs-juguang-filter-memory:${VERSION}`;
  const FILTER_NAMES = ['所属行业', '流量场域', '内容类型', '内容来源', '题材'];
  const SEARCH_PLACEHOLDERS = ['使用逗号区隔可进行批量搜索', '试试搜'];
  const SORT_VALUES = [
    '曝光量', '阅读率', '阅读量', '互动量', '互动率',
    '曝光咨询率', '阅读咨询率', '阅读开口率', '阅读留资率', '表单提交率',
    '点赞量', '评论量', '收藏量', '转发量',
  ];
  const DATE_VALUES = ['近1日', '近3日', '近7日', '近14日', '近30日', '近90日', '近180日', '近365日', '全部'];
  const TAB_PREFIX = 'square-tabs-item-';
  const PUGONGYING_HOST = 'pgy.xiaohongshu.com';
  const PUGONGYING_BUTTON_CLASS = 'xhs-pgy-direct-button';
  const PENDING_PGY_KEY = 'xhs-juguang-pending-pgy-navigation';

  let host;
  let shadow;
  let statusNode;
  let currentOpenFilter = null;
  let currentFilterPath = [];
  let lastKnownTab = '';
  let lastKnownSort = '';
  let lastKnownDate = '';
  const triggerCache = new Map();
  let saveTimer = 0;
  let restoreTimer = 0;
  let restoring = false;
  let restoreScheduled = false;
  let cardScanTimer = 0;
  let cardStyleInstalled = false;

  const normalize = (value) => String(value || '').replace(/\s+/g, ' ').trim();
  const shortText = (value, max = 80) => normalize(value).slice(0, max);
  const isVisible = (element) => {
    if (!element || !(element instanceof Element)) return false;
    const style = window.getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0' && element.getClientRects().length > 0;
  };
  const isEditable = (element) => element && /^(INPUT|TEXTAREA|SELECT)$/.test(element.tagName);
  const wait = (ms) => new Promise((resolve) => window.setTimeout(resolve, ms));

  function pageKey() {
    return `${location.origin}${location.pathname}`;
  }

  function readStore() {
    try {
      if (typeof GM_getValue === 'function') {
        return GM_getValue(STORAGE_KEY, {}) || {};
      }
      return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
    } catch (error) {
      console.warn('[聚光筛选记忆] 读取失败', error);
      return {};
    }
  }

  function writeStore(store) {
    try {
      if (typeof GM_setValue === 'function') {
        GM_setValue(STORAGE_KEY, store);
      } else {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
      }
    } catch (error) {
      console.warn('[聚光筛选记忆] 保存失败', error);
    }
  }

  function deleteStore() {
    try {
      if (typeof GM_deleteValue === 'function') {
        GM_deleteValue(STORAGE_KEY);
      } else {
        localStorage.removeItem(STORAGE_KEY);
      }
    } catch (error) {
      console.warn('[聚光筛选记忆] 清除失败', error);
    }
  }

  function getSavedState() {
    const store = readStore();
    return store[pageKey()] || null;
  }

  function setStatus(message, tone = 'normal') {
    if (!statusNode) return;
    statusNode.textContent = message;
    statusNode.dataset.tone = tone;
  }

  function getSearchInput() {
    const inputs = Array.from(document.querySelectorAll('input, textarea'))
      .filter((input) => isVisible(input));
    return inputs.find((input) => {
      const placeholder = normalize(input.getAttribute('placeholder'));
      const aria = normalize(input.getAttribute('aria-label'));
      return SEARCH_PLACEHOLDERS.some((word) => placeholder.includes(word) || aria.includes(word));
    }) || inputs.find((input) => normalize(input.getAttribute('placeholder')).includes('搜索')) || null;
  }

  function readSearch() {
    const input = getSearchInput();
    return input ? normalize(input.value) : '';
  }

  function setNativeValue(input, value) {
    const prototype = input instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const descriptor = Object.getOwnPropertyDescriptor(prototype, 'value');
    if (descriptor && descriptor.set) descriptor.set.call(input, value);
    else input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function findSearchButton(input) {
    if (!input) return null;
    const inputRect = input.getBoundingClientRect();
    const containers = [];
    let element = input.parentElement;
    for (let index = 0; index < 6 && element && element !== document.body; index += 1) {
      containers.push(element);
      element = element.parentElement;
    }
    const candidates = [];
    for (const container of containers) {
      for (const button of Array.from(container.querySelectorAll('button, [role="button"]'))) {
        if (!isVisible(button) || button === host) continue;
        const rect = button.getBoundingClientRect();
        const text = normalize(button.textContent);
        const label = normalize(button.getAttribute('aria-label') || button.getAttribute('title'));
        const sameRow = Math.abs((rect.top + rect.bottom) / 2 - (inputRect.top + inputRect.bottom) / 2) < Math.max(28, inputRect.height * 1.8);
        const rightOfInput = rect.left >= inputRect.right - 24;
        const searchLike = /搜索|查询|search/i.test(`${text} ${label}`);
        const distance = Math.abs(rect.left - inputRect.right) + Math.abs(rect.top - inputRect.top);
        if (sameRow && (searchLike || rightOfInput)) candidates.push({ button, searchLike, distance });
      }
      if (candidates.some((item) => item.searchLike)) break;
    }
    return candidates.sort((a, b) => Number(b.searchLike) - Number(a.searchLike) || a.distance - b.distance)[0]?.button || null;
  }

  function triggerSearch(input) {
    if (!input) return false;
    input.click();
    ['keydown', 'keyup'].forEach((type) => input.dispatchEvent(new KeyboardEvent(type, {
      key: 'Enter',
      code: 'Enter',
      keyCode: 13,
      which: 13,
      bubbles: true,
    })));
    const button = findSearchButton(input);
    if (button) {
      button.click();
      return true;
    }
    const scope = input.closest('form, [class*="search"], [class*="Search"]');
    const fallback = scope && Array.from(scope.querySelectorAll('button, [role="button"]')).find(isVisible);
    if (fallback) {
      fallback.click();
      return true;
    }
    return false;
  }

  function parseUrl(raw) {
    try {
      return new URL(raw, location.href);
    } catch (error) {
      return null;
    }
  }

  function isXhsHost(hostname) {
    const host = String(hostname || '').toLowerCase();
    return host === 'xiaohongshu.com'
      || host.endsWith('.xiaohongshu.com')
      || host === 'xhslink.cn'
      || host.endsWith('.xhslink.cn');
  }

  function isJuguangHost(hostname = location.hostname) {
    const host = String(hostname || '').toLowerCase();
    return host === 'ad.xiaohongshu.com' || host === 'juguang.xiaohongshu.com' || host === 'xhsad.com';
  }

  function isNotePath(pathname) {
    return /\/(?:explore|discovery\/item|note)\//i.test(pathname || '');
  }

  function isProfilePath(pathname) {
    return /\/(?:user\/profile|profile|creator)\//i.test(pathname || '');
  }

  function extractProfileId(raw) {
    const url = parseUrl(raw);
    if (!url || !isXhsHost(url.hostname) || !isProfilePath(url.pathname)) return '';
    const match = url.pathname.match(/\/user\/profile\/([^/?#]+)/i);
    return match ? decodeURIComponent(match[1]) : '';
  }

  function toPugongyingProfileUrl(raw) {
    const profileId = /^[\w-]{4,120}$/.test(String(raw || '')) ? String(raw) : extractProfileId(raw);
    return profileId ? `https://${PUGONGYING_HOST}/solar/pre-trade/blogger-detail/${encodeURIComponent(profileId)}` : '';
  }

  function isLikelyNoteHref(raw) {
    const url = parseUrl(raw);
    return Boolean(url && isXhsHost(url.hostname) && isNotePath(url.pathname));
  }

  function isLikelyProfileHref(raw) {
    const url = parseUrl(raw);
    return Boolean(url && isXhsHost(url.hostname) && isProfilePath(url.pathname));
  }

  function findCardForNoteAnchor(anchor) {
    let classElement = anchor;
    for (let index = 0; index < 8 && classElement && classElement !== document.body; index += 1) {
      const className = String(classElement.className || '');
      const rect = classElement.getBoundingClientRect();
      const hasImage = Boolean(classElement.querySelector('img, video'));
      const looksSized = rect.width >= 160 && rect.width <= 720 && rect.height >= 160 && rect.height <= 900;
      if (looksSized && hasImage && (/(^|[-_])card([-_]|$)/i.test(className) || classElement.hasAttribute('data-note-id') || classElement.hasAttribute('data-noteid'))) {
        return classElement;
      }
      classElement = classElement.parentElement;
    }

    let element = anchor;
    let best = anchor;
    for (let index = 0; index < 7 && element && element !== document.body; index += 1) {
      const rect = element.getBoundingClientRect();
      const text = normalize(element.textContent);
      const hasImage = Boolean(element.querySelector('img, video'));
      if (rect.width >= 160 && rect.width <= 720 && rect.height >= 160 && rect.height <= 900 && hasImage && text.length >= 4 && text.length <= 1600) {
        best = element;
      }
      element = element.parentElement;
    }
    return best;
  }

  function findProfileLink(card) {
    const scopes = [];
    let scope = card;
    for (let index = 0; index < 7 && scope && scope !== document.body; index += 1) {
      scopes.push(scope);
      scope = scope.parentElement;
    }
    for (const scope of scopes) {
      const links = Array.from(scope.querySelectorAll('a[href]'));
      const profile = links.find((link) => isLikelyProfileHref(link.href));
      if (profile) return profile;
    }
    return null;
  }

  function collectCardMetadata(card) {
    const urls = [];
    const ids = [];
    const debug = new Set();
    const seen = new WeakSet();
    const addString = (value, keyHint = '') => {
      const text = String(value || '').trim();
      if (!text || text.length > 500) return;
      if (/^(?:https?:)?\/\//i.test(text) || /\/(?:explore|discovery\/item|note|user\/profile|profile)\//i.test(text)) {
        urls.push(text);
      }
      if (!/^[\w-]{4,120}$/.test(text)) return;
      const hint = String(keyHint || '').toLowerCase();
      if (/(?:user|author|creator|profile)[-_]?(?:id)?/i.test(hint)) {
        ids.push({ kind: 'profile', key: hint, value: text });
      } else if (/(?:note|item|content)[-_]?(?:id)?/i.test(hint)) {
        ids.push({ kind: 'note', key: hint, value: text });
      } else if (/(?:^|[._-])id$/i.test(hint)) {
        ids.push({ kind: 'unknown', key: hint, value: text });
      }
    };
    const visit = (value, depth, keyHint = '', parentHint = '') => {
      if (depth > 5 || value == null) return;
      if (typeof value === 'string') {
        addString(value, `${parentHint}.${keyHint}`);
        return;
      }
      if (typeof value !== 'object' && typeof value !== 'function') return;
      if (Array.isArray(value)) {
        value.slice(0, 40).forEach((item) => visit(item, depth + 1, keyHint, parentHint));
        return;
      }
      if (typeof value === 'object') {
        if (seen.has(value)) return;
        seen.add(value);
      }
      let keys = [];
      try {
        keys = Object.keys(value).slice(0, 120);
      } catch (error) {
        return;
      }
      for (const key of keys) {
        if (/^(?:children|memoizedProps|pendingProps|props|return|sibling|child|alternate|key|ref|type|elementType)$/i.test(key) || /react/i.test(key)) {
          visit(value[key], depth + 1, key, parentHint);
        } else if (/(?:url|href|link|user|author|creator|profile|note|item|content|id)/i.test(key)) {
          visit(value[key], depth + 1, key, `${parentHint}.${keyHint}`);
        }
      }
    };

    for (const attribute of Array.from(card.attributes || [])) {
      if (/^(?:data-|href$|src$)/i.test(attribute.name)) addString(attribute.value, attribute.name);
    }
    const elements = [card, ...Array.from(card.querySelectorAll('*')).slice(0, 500)];
    for (const element of elements) {
      try {
        const elementClass = normalize(String(element.className || '')).replace(/\s+/g, '.').slice(0, 80);
        if (elementClass) debug.add(`${String(element.tagName || '').toLowerCase()}.${elementClass}`);
        if (element.href) addString(element.href, 'href');
        for (const attribute of Array.from(element.attributes || [])) {
          if (/^(?:data-|href$|src$)/i.test(attribute.name)) addString(attribute.value, attribute.name);
        }
        for (const key of Object.keys(element)) {
          if (key.startsWith('__reactProps') || key.startsWith('__reactFiber') || key.startsWith('__reactInternalInstance')) {
            debug.add(key.slice(0, 36));
            try {
              Object.keys(element[key] || {}).filter((name) => /url|href|link|user|author|creator|profile|note|item|content|route|path|id/i.test(name)).slice(0, 24).forEach((name) => debug.add(`react:${name}`));
            } catch (error) {
              // Ignore a React object that is being replaced during a render.
            }
            visit(element[key], 0, key, '');
          }
        }
      } catch (error) {
        // React internals are implementation details and may throw while a card rerenders.
      }
    }
    return { urls: [...new Set(urls)], ids, debug: [...debug].slice(0, 36) };
  }

  function resolvePugongyingUrl(card, metadata = collectCardMetadata(card)) {
    const profile = findProfileLink(card);
    if (profile) {
      const profileUrl = toPugongyingProfileUrl(profile.href);
      if (profileUrl) return profileUrl;
    }

    const links = [];
    if (card && card.matches && card.matches('a[href]')) links.push(card);
    if (card) links.push(...Array.from(card.querySelectorAll('a[href]')));
    const profilePath = metadata.urls.find((value) => isLikelyProfileHref(value));
    if (profilePath) {
      const profileUrl = toPugongyingProfileUrl(profilePath);
      if (profileUrl) return profileUrl;
    }

    const dataId = card && (
      card.getAttribute('data-user-id')
      || card.getAttribute('data-author-id')
      || card.getAttribute('data-userid')
    );
    if (dataId && /^[\w-]+$/.test(dataId)) {
      return toPugongyingProfileUrl(dataId);
    }
    const profileId = metadata.ids.find((item) => item.kind === 'profile');
    if (profileId) return toPugongyingProfileUrl(profileId.value);

    // Some card renderers put the avatar/profile link in a sibling wrapper
    // outside the note anchor's immediate card element. Walk a few bounded
    // ancestors and inspect their links before falling back to XHS navigation.
    let scope = card;
    for (let index = 0; index < 7 && scope && scope !== document.body; index += 1) {
      const nearbyProfile = Array.from(scope.querySelectorAll('a[href]'))
        .find((link) => isLikelyProfileHref(link.href));
      if (nearbyProfile) {
        const profileUrl = toPugongyingProfileUrl(nearbyProfile.href);
        if (profileUrl) return profileUrl;
      }
      scope = scope.parentElement;
    }
    return '';
  }

  function readPendingPgyNavigation() {
    try {
      const value = typeof GM_getValue === 'function'
        ? GM_getValue(PENDING_PGY_KEY, null)
        : JSON.parse(localStorage.getItem(PENDING_PGY_KEY) || 'null');
      if (!value || !value.createdAt || Date.now() - Number(value.createdAt) > 30000) return null;
      return value;
    } catch (error) {
      return null;
    }
  }

  function markPendingPgyNavigation() {
    const value = { createdAt: Date.now() };
    try {
      if (typeof GM_setValue === 'function') GM_setValue(PENDING_PGY_KEY, value);
      else localStorage.setItem(PENDING_PGY_KEY, JSON.stringify(value));
    } catch (error) {
      // The note page still opens normally if storage is unavailable.
    }
  }

  function clearPendingPgyNavigation() {
    try {
      if (typeof GM_deleteValue === 'function') GM_deleteValue(PENDING_PGY_KEY);
      else localStorage.removeItem(PENDING_PGY_KEY);
    } catch (error) {
      // Ignore storage cleanup failures.
    }
  }

  function withPendingPgyQuery(raw) {
    const url = parseUrl(raw);
    if (!url) return '';
    url.searchParams.set('xhs_pgy', '1');
    url.searchParams.set('xhs_pgy_ts', String(Date.now()));
    return url.href;
  }

  function findOriginalNoteHref(card) {
    const anchors = [];
    if (card && card.matches && card.matches('a[href]')) anchors.push(card);
    if (card) anchors.push(...Array.from(card.querySelectorAll('a[href]')));
    return anchors.map((anchor) => anchor.href).find(isLikelyNoteHref) || '';
  }

  function findNoteAuthorProfileUrl() {
    const links = Array.from(document.querySelectorAll('a[href]'))
      .filter((link) => isLikelyProfileHref(link.href));
    const preferred = links.find((link) => /xsec_source=pc_user/i.test(link.href))
      || links.find((link) => link.id === 'user-hover-guide')
      || links.find((link) => {
        const rect = link.getBoundingClientRect();
        return rect.top >= 0 && rect.top < Math.max(720, window.innerHeight * 0.9);
      })
      || links[0];
    return preferred ? toPugongyingProfileUrl(preferred.href) : '';
  }

  function redirectPendingNoteToPugongying() {
    const queryRequested = new URLSearchParams(location.search).get('xhs_pgy') === '1';
    if (!queryRequested && !readPendingPgyNavigation()) return;
    let observer;
    let timer;
    let finished = false;
    const tryRedirect = () => {
      if (finished) return true;
      const profile = findNoteAuthorProfileUrl();
      if (!profile) return false;
      finished = true;
      clearPendingPgyNavigation();
      if (observer) observer.disconnect();
      if (timer) window.clearInterval(timer);
      window.location.replace(profile);
      return true;
    };
    const stop = () => {
      if (finished) return;
      finished = true;
      clearPendingPgyNavigation();
      if (observer) observer.disconnect();
      if (timer) window.clearInterval(timer);
    };
    if (tryRedirect()) return;
    observer = new MutationObserver(tryRedirect);
    observer.observe(document.documentElement, { childList: true, subtree: true });
    timer = window.setInterval(tryRedirect, 250);
    window.setTimeout(stop, 30000);
  }

  function redirectPendingProfileToPugongying() {
    const queryRequested = new URLSearchParams(location.search).get('xhs_pgy') === '1';
    if (!queryRequested && !readPendingPgyNavigation()) return;
    const profile = toPugongyingProfileUrl(location.href);
    if (!profile) return;
    clearPendingPgyNavigation();
    window.location.replace(profile);
  }

  function findOriginalCardTarget(card) {
    const elements = Array.from(card.querySelectorAll('a[href], button, [role="button"]'))
      .filter((element) => isVisible(element) && !element.closest(`.${PUGONGYING_BUTTON_CLASS}`));
    return elements.find((element) => isLikelyNoteHref(element.href))
      || elements[0]
      || Array.from(card.querySelectorAll('img, video')).find(isVisible)
      || card;
  }

  function findOriginalProfileHref(card) {
    const target = findOriginalCardTarget(card);
    const candidates = [];
    if (target && target.href) candidates.push(target.href);
    if (card && card.matches && card.matches('a[href]')) candidates.push(card.href);
    if (card) candidates.push(...Array.from(card.querySelectorAll('a[href]')).map((link) => link.href));
    return candidates.find(isLikelyProfileHref) || '';
  }

  function triggerOriginalCardNavigation(card) {
    const target = findOriginalCardTarget(card);
    if (!target) return;
    if (typeof target.click === 'function') {
      target.click();
      return;
    }
    target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
  }

  function installCardStyle() {
    if (cardStyleInstalled || !document.head) return;
    const style = document.createElement('style');
    style.id = 'xhs-pgy-direct-style';
    style.textContent = `
      .${PUGONGYING_BUTTON_CLASS} {
        position: absolute !important;
        right: 8px !important;
        bottom: 8px !important;
        z-index: 20 !important;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        min-width: 28px !important;
        height: 24px !important;
        padding: 0 7px !important;
        border: 1px solid rgba(255, 255, 255, .75) !important;
        border-radius: 12px !important;
        background: rgba(22, 24, 28, .78) !important;
        box-shadow: 0 2px 8px rgba(0, 0, 0, .2) !important;
        color: #fff !important;
        cursor: pointer !important;
        font: 12px/1 -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", sans-serif !important;
        letter-spacing: 0 !important;
        text-decoration: none !important;
        user-select: none !important;
        white-space: nowrap !important;
      }
      .${PUGONGYING_BUTTON_CLASS}:hover { background: #ff2442 !important; }
      .${PUGONGYING_BUTTON_CLASS}:focus-visible { outline: 2px solid #ff2442 !important; outline-offset: 2px !important; }
    `;
    document.head.appendChild(style);
    cardStyleInstalled = true;
  }

  function addPugongyingButton(card) {
    if (!card || !(card instanceof Element)) return { added: false, present: false, metadata: { debug: [] } };
    if (card.querySelector(`.${PUGONGYING_BUTTON_CLASS}`)) return { added: false, present: true, metadata: { debug: [] } };
    const metadata = collectCardMetadata(card);
    const url = resolvePugongyingUrl(card, metadata);
    if (window.getComputedStyle(card).position === 'static') card.style.position = 'relative';

    const button = document.createElement('span');
    button.className = PUGONGYING_BUTTON_CLASS;
    button.setAttribute('role', 'button');
    button.setAttribute('tabindex', '0');
    button.setAttribute('aria-label', '打开蒲公英作者主页');
    button.title = url ? `打开蒲公英作者主页：${url}` : '打开笔记并识别作者后转到蒲公英';
    button.textContent = '蒲';

    const open = (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (typeof event.stopImmediatePropagation === 'function') event.stopImmediatePropagation();
      if (url) {
        window.open(url, '_blank', 'noopener,noreferrer');
      } else {
        markPendingPgyNavigation();
        const noteHref = findOriginalNoteHref(card);
        if (noteHref) {
          window.open(withPendingPgyQuery(noteHref), '_blank', 'noopener,noreferrer');
        } else {
          const profileHref = findOriginalProfileHref(card);
          if (profileHref) {
            window.open(withPendingPgyQuery(profileHref), '_blank', 'noopener,noreferrer');
            return;
          }
          triggerOriginalCardNavigation(card);
        }
      }
    };
    button.addEventListener('click', open);
    button.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') open(event);
    });
    card.appendChild(button);
    return { added: true, present: true, metadata };
  }

  function scanContentCards() {
    if (!document.body || !isXhsHost(location.hostname)) return;
    installCardStyle();
    const seen = new Set();
    let candidates = 0;
    let buttons = 0;
    const debugHints = new Set();
    const anchors = Array.from(document.querySelectorAll('a[href]')).filter((anchor) => {
      return isVisible(anchor) && isLikelyNoteHref(anchor.href);
    });
    for (const anchor of anchors) {
      const card = findCardForNoteAnchor(anchor);
      if (!card || seen.has(card)) continue;
      seen.add(card);
      candidates += 1;
      const result = addPugongyingButton(card);
      result.metadata.debug.slice(0, 8).forEach((hint) => debugHints.add(hint));
      if (result.present) buttons += 1;
    }

    const images = Array.from(document.querySelectorAll('img')).filter(isVisible);
    for (const image of images) {
      let element = image;
      let candidate = null;
      for (let index = 0; index < 8 && element && element !== document.body; index += 1) {
        const rect = element.getBoundingClientRect();
        const text = normalize(element.textContent);
        const imageCount = element.querySelectorAll('img').length;
        const className = String(element.className || '');
        if (rect.width >= 160 && rect.width <= 720 && rect.height >= 160 && rect.height <= 900
          && imageCount >= 1 && imageCount <= 20 && text.length >= 8 && text.length <= 1600
          && (/card|item|note/i.test(className) || imageCount >= 2)) {
          candidate = element;
        }
        element = element.parentElement;
      }
      if (candidate && !seen.has(candidate)) {
        seen.add(candidate);
        candidates += 1;
        const result = addPugongyingButton(candidate);
        result.metadata.debug.slice(0, 8).forEach((hint) => debugHints.add(hint));
        if (result.present) buttons += 1;
      }
    }
    if (host && candidates > 0) {
      const hint = [...debugHints].slice(0, 4).join('、');
      setStatus(`已扫描 ${candidates} 张卡片${buttons ? `，已添加 ${buttons} 个蒲公英按钮` : `，等待识别作者信息${hint ? `（${hint}）` : ''}`}`);
    }
  }

  function scheduleCardScan() {
    window.clearTimeout(cardScanTimer);
    cardScanTimer = window.setTimeout(scanContentCards, 280);
  }

  function tabElements() {
    return Array.from(document.querySelectorAll(`[id^="${TAB_PREFIX}"], [role="tab"]`)).filter(isVisible);
  }

  function tabName(element) {
    if (!element) return '';
    const id = element.id || '';
    return id.startsWith(TAB_PREFIX) ? id.slice(TAB_PREFIX.length) : shortText(element.textContent, 60);
  }

  function isActiveTab(element) {
    const aria = element.getAttribute('aria-selected');
    const className = String(element.className || '');
    return aria === 'true' || /active|selected|current/i.test(className);
  }

  function readTab() {
    const active = tabElements().find(isActiveTab);
    return tabName(active) || lastKnownTab || '';
  }

  function findTab(value) {
    const wanted = normalize(value);
    return tabElements().find((element) => tabName(element) === wanted)
      || tabElements().find((element) => normalize(element.textContent).includes(wanted));
  }

  function filterTrigger(label) {
    const wanted = normalize(label);
    const cached = triggerCache.get(wanted);
    if (cached && cached.isConnected && isVisible(cached)) return cached;
    const exact = Array.from(document.querySelectorAll('body *'))
      .filter((element) => isVisible(element) && normalize(element.textContent) === wanted);
    const fuzzy = Array.from(document.querySelectorAll('body *'))
      .filter((element) => {
        const text = normalize(element.textContent);
        return isVisible(element) && text.startsWith(wanted) && text.length <= wanted.length + 50;
      });
    const candidates = exact.length ? exact : fuzzy;
    if (!candidates.length) return null;
    const result = candidates.sort((a, b) => {
      const aClickable = /^(BUTTON|SUMMARY)$/.test(a.tagName) || a.getAttribute('role') === 'button';
      const bClickable = /^(BUTTON|SUMMARY)$/.test(b.tagName) || b.getAttribute('role') === 'button';
      return Number(bClickable) - Number(aClickable) || a.children.length - b.children.length;
    })[0];
    triggerCache.set(wanted, result);
    return result;
  }

  function clickFilterTrigger(label) {
    const trigger = filterTrigger(label);
    if (!trigger) return false;
    trigger.click();
    return true;
  }

  function popupCandidates() {
    const selectors = [
      '[role="dialog"]', '[role="listbox"]', '[role="menu"]', '[role="tree"]',
      '[class*="popover"]', '[class*="Popover"]', '[class*="dropdown"]', '[class*="Dropdown"]',
      '[class*="select-menu"]', '[class*="SelectMenu"]', '[class*="menu-panel"]', '[class*="MenuPanel"]',
    ];
    return Array.from(document.querySelectorAll(selectors.join(','))).filter((element) => {
      if (!isVisible(element)) return false;
      const rect = element.getBoundingClientRect();
      return rect.width > 80 && rect.height > 30 && rect.width < window.innerWidth * 0.9 && rect.height < window.innerHeight * 0.9;
    });
  }

  function openPopup() {
    const candidates = popupCandidates();
    if (!candidates.length) return document.body;
    return candidates.sort((a, b) => {
      const ar = a.getBoundingClientRect();
      const br = b.getBoundingClientRect();
      const aStyle = window.getComputedStyle(a);
      const bStyle = window.getComputedStyle(b);
      const aLayer = ['absolute', 'fixed', 'sticky'].includes(aStyle.position) ? -100000 : 0;
      const bLayer = ['absolute', 'fixed', 'sticky'].includes(bStyle.position) ? -100000 : 0;
      return (aLayer + ar.width * ar.height) - (bLayer + br.width * br.height);
    })[0];
  }

  function visibleKnownValue(values) {
    const wanted = new Set(values);
    return Array.from(document.querySelectorAll('body *'))
      .filter((element) => isVisible(element) && wanted.has(normalize(element.textContent)))
      .sort((a, b) => a.children.length - b.children.length)
      .map((element) => normalize(element.textContent))[0] || '';
  }

  function clickChoiceTrigger(values, preferred) {
    const candidates = [preferred, visibleKnownValue(values), ...values].filter(Boolean);
    for (const value of candidates) {
      const trigger = filterTrigger(value);
      if (trigger) {
        trigger.click();
        return true;
      }
    }
    return false;
  }

  function exactTextCandidates(root, wanted) {
    const value = normalize(wanted);
    if (!value) return [];
    return Array.from(root.querySelectorAll('*')).filter((element) => {
      if (!isVisible(element) || isEditable(element)) return false;
      return normalize(element.textContent) === value;
    });
  }

  function clickableText(root, wanted) {
    const candidates = exactTextCandidates(root, wanted);
    if (!candidates.length) return null;
    return candidates.sort((a, b) => {
      const score = (element) => {
        let result = 0;
        if (['LI', 'BUTTON', 'OPTION'].includes(element.tagName)) result -= 5;
        if (element.getAttribute('role') === 'option' || element.getAttribute('role') === 'menuitem') result -= 5;
        result += Math.min(element.children.length, 10);
        return result;
      };
      return score(a) - score(b);
    })[0];
  }

  function fuzzyClickableText(root, wanted) {
    const value = normalize(wanted);
    if (!value) return null;
    return Array.from(root.querySelectorAll('[role="option"], [role="menuitem"], li, button, [class*="item"], [class*="Item"]'))
      .filter((element) => isVisible(element) && !isEditable(element))
      .sort((a, b) => normalize(a.textContent).length - normalize(b.textContent).length)
      .find((element) => normalize(element.textContent).includes(value)) || null;
  }

  function clickOption(root, value) {
    const element = clickableText(root, value) || fuzzyClickableText(root, value);
    if (!element) return false;
    element.click();
    return true;
  }

  function knownValueFromTarget(target, values) {
    const text = normalize(target && target.textContent);
    return values.find((value) => text === value || text.includes(value)) || '';
  }

  function nearestOptionText(target) {
    let element = target instanceof Element ? target : null;
    while (element && element !== document.body) {
      if (!isVisible(element) || isEditable(element)) {
        element = element.parentElement;
        continue;
      }
      const text = shortText(element.textContent, 80);
      const role = element.getAttribute('role') || '';
      const likely = role === 'option' || role === 'menuitem' || ['LI', 'BUTTON'].includes(element.tagName)
        || /item|option|menu/i.test(String(element.className || ''));
      if (likely && text && text.length <= 60) return text;
      element = element.parentElement;
    }
    const ownText = shortText(target && target.textContent, 60);
    return ownText && ownText.length <= 60 ? ownText : '';
  }

  function scheduleSave() {
    if (restoring) return;
    window.clearTimeout(saveTimer);
    saveTimer = window.setTimeout(saveCurrentState, 250);
  }

  function saveCurrentState() {
    const store = readStore();
    const previous = store[pageKey()] || {};
    const searchInput = getSearchInput();
    const next = {
      ...previous,
      search: searchInput ? normalize(searchInput.value) : (previous.search || ''),
      tab: readTab() || previous.tab || '',
      sort: lastKnownSort || visibleKnownValue(SORT_VALUES) || previous.sort || '',
      date: lastKnownDate || visibleKnownValue(DATE_VALUES) || previous.date || '',
      filters: { ...(previous.filters || {}) },
      updatedAt: new Date().toISOString(),
    };
    if (currentOpenFilter && currentFilterPath.length) {
      next.filters[currentOpenFilter] = { path: [...currentFilterPath] };
    }
    store[pageKey()] = next;
    writeStore(store);
    setStatus('已自动保存');
  }

  function clearCurrentState() {
    const store = readStore();
    delete store[pageKey()];
    writeStore(store);
    setStatus('已清除本页记忆', 'muted');
  }

  async function applySavedState(manual = false) {
    const saved = getSavedState();
    if (!saved) {
      setStatus('还没有保存的条件', 'muted');
      return;
    }
    if (restoring) return;
    restoring = true;
    setStatus('正在恢复…');
    try {
      const tab = findTab(saved.tab);
      if (tab && tabName(tab) !== readTab()) {
        tab.click();
        await wait(220);
      }

      const input = getSearchInput();
      if (input && typeof saved.search === 'string' && normalize(input.value) !== normalize(saved.search)) {
        setNativeValue(input, saved.search);
      }

      for (const label of FILTER_NAMES) {
        const entry = saved.filters && saved.filters[label];
        const path = entry && Array.isArray(entry.path) ? entry.path : [];
        if (!path.length || !clickFilterTrigger(label)) continue;
        await wait(140);
        for (const part of path) {
          const popup = openPopup();
          if (!clickOption(popup, part)) break;
          await wait(160);
        }
        await wait(100);
      }

      if (saved.sort && clickChoiceTrigger(SORT_VALUES, lastKnownSort || saved.sort)) {
        await wait(100);
        clickOption(openPopup(), saved.sort);
      }
      if (saved.date && clickChoiceTrigger(DATE_VALUES, lastKnownDate || saved.date)) {
        await wait(100);
        clickOption(openPopup(), saved.date);
      }

      // 聚光的搜索词写入后不会自动刷新结果，最后显式点击搜索按钮。
      if (input && typeof saved.search === 'string' && normalize(saved.search)) {
        triggerSearch(input);
        await wait(500);
      }

      setStatus(manual ? '已恢复上次筛选' : '已恢复上次筛选');
    } catch (error) {
      console.warn('[聚光筛选记忆] 恢复失败', error);
      setStatus('恢复时遇到页面差异', 'warn');
    } finally {
      restoring = false;
      currentOpenFilter = null;
      currentFilterPath = [];
    }
  }

  function scheduleRestore(reason = 'load') {
    if (restoreScheduled) return;
    restoreScheduled = true;
    let attempts = 0;
    const run = () => {
      attempts += 1;
      const saved = getSavedState();
      if (saved && (getSearchInput() || tabElements().length || filterTrigger(FILTER_NAMES[0]))) {
        restoreScheduled = false;
        applySavedState(false);
        return;
      }
      if (attempts < 12) {
        restoreTimer = window.setTimeout(run, 500);
      } else {
        restoreScheduled = false;
        setStatus(`未找到可恢复的页面控件（${reason}）`, 'muted');
      }
    };
    window.clearTimeout(restoreTimer);
    restoreTimer = window.setTimeout(run, 600);
  }

  function installClickTracking() {
    document.addEventListener('click', (event) => {
      const target = event.target instanceof Element ? event.target : null;
      if (!target || restoring) return;

      const tab = target.closest(`[id^="${TAB_PREFIX}"], [role="tab"]`);
      if (tab) {
        lastKnownTab = tabName(tab);
        scheduleSave();
        return;
      }

      for (const label of FILTER_NAMES) {
        const trigger = filterTrigger(label);
        if (trigger && (target === trigger || trigger.contains(target) || target.closest(`[aria-label="${label}"]`))) {
          currentOpenFilter = label;
          currentFilterPath = [];
          return;
        }
      }

      const sort = knownValueFromTarget(target, SORT_VALUES);
      const date = knownValueFromTarget(target, DATE_VALUES);
      if (sort) {
        lastKnownSort = sort;
        scheduleSave();
        return;
      }
      if (date) {
        lastKnownDate = date;
        scheduleSave();
        return;
      }

      const popup = currentOpenFilter ? openPopup() : null;
      if (currentOpenFilter && popup && popup !== document.body && popup.contains(target) && isVisible(popup)) {
        const optionText = nearestOptionText(target);
        const ignored = FILTER_NAMES.includes(optionText) || SEARCH_PLACEHOLDERS.some((word) => optionText.includes(word));
        if (optionText && !ignored && optionText.length <= 60) {
          currentFilterPath.push(optionText);
          scheduleSave();
        }
      }
    }, true);

    document.addEventListener('input', (event) => {
      if (!restoring && event.target instanceof Element && getSearchInput() === event.target) scheduleSave();
    }, true);
    document.addEventListener('change', (event) => {
      if (!restoring) scheduleSave();
    }, true);
  }

  function installHistoryTracking() {
    ['pushState', 'replaceState'].forEach((method) => {
      const original = history[method];
      history[method] = function (...args) {
        const result = original.apply(this, args);
        window.setTimeout(() => scheduleRestore(method), 80);
        window.setTimeout(scheduleCardScan, 180);
        return result;
      };
    });
    window.addEventListener('popstate', () => {
      scheduleRestore('popstate');
      scheduleCardScan();
    });
  }

  function createPanel() {
    if (!document.body || document.getElementById('xhs-juguang-filter-memory')) return;
    host = document.createElement('div');
    host.id = 'xhs-juguang-filter-memory';
    host.style.cssText = 'all:initial;position:fixed;z-index:2147483647;right:18px;bottom:18px;';
    shadow = host.attachShadow({ mode: 'open' });
    shadow.innerHTML = `
      <style>
        :host { all: initial; }
        .box { font: 13px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif; color:#263238; background:#fff; border:1px solid #e6e9ef; border-radius:10px; box-shadow:0 5px 22px rgba(0,0,0,.14); padding:8px; width:176px; }
        .title { display:flex; align-items:center; justify-content:space-between; gap:8px; font-weight:600; margin:0 2px 6px; }
        .dot { width:7px; height:7px; border-radius:50%; background:#37c58a; display:inline-block; margin-right:5px; }
        .status { color:#607080; font-size:12px; min-height:17px; margin:0 2px 7px; }
        .status[data-tone="warn"] { color:#c97a00; }
        .status[data-tone="muted"] { color:#8a949e; }
        .actions { display:flex; gap:6px; }
        button { border:0; border-radius:6px; padding:6px 8px; cursor:pointer; font:inherit; }
        .restore { background:#3478f6; color:#fff; flex:1; }
        .clear { color:#65717c; background:#f2f4f7; }
        button:hover { filter:brightness(.97); }
      </style>
      <div class="box">
        <div class="title"><span><span class="dot"></span>筛选记忆</span><span>聚光</span></div>
        <div class="status" data-tone="muted">等待页面控件</div>
        <div class="actions"><button class="restore" type="button">恢复上次</button><button class="clear" type="button">清除</button></div>
      </div>`;
    document.body.appendChild(host);
    statusNode = shadow.querySelector('.status');
    shadow.querySelector('.restore').addEventListener('click', () => applySavedState(true));
    shadow.querySelector('.clear').addEventListener('click', clearCurrentState);
    setStatus(getSavedState() ? '已找到上次条件' : '等待页面控件', 'muted');
  }

  function registerMenu() {
    if (typeof GM_registerMenuCommand !== 'function') return;
    GM_registerMenuCommand('聚光：恢复上次筛选', () => applySavedState(true));
    GM_registerMenuCommand('聚光：清除本页记忆', clearCurrentState);
  }

  function boot() {
    if (!isJuguangHost()) {
      if (isNotePath(location.pathname)) redirectPendingNoteToPugongying();
      else if (isProfilePath(location.pathname)) redirectPendingProfileToPugongying();
      return;
    }
    if (!isJuguangHost()) return;
    installClickTracking();
    installHistoryTracking();
    registerMenu();
    createPanel();
    scheduleRestore('boot');
    scheduleCardScan();
    const observer = new MutationObserver(() => {
      if (!host || !document.body.contains(host)) createPanel();
      scheduleCardScan();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }
})();
