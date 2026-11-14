// ==UserScript==
// @name         小红书网页脚本
// @namespace    https://github.com/zwmopen/userscripts
// @version      0.4.8
// @description  配合聚光的小红书网页工具：自动保存并恢复关键词、筛选、指标和日期；卡片按钮直达蒲公英作者主页
// @author       Codex
// @match        https://ad.xiaohongshu.com/*
// @match        https://juguang.xiaohongshu.com/*
// @match        https://xhsad.com/*
// @match        https://www.xiaohongshu.com/explore/*
// @match        https://www.xiaohongshu.com/discovery/item/*
// @match        https://www.xiaohongshu.com/note/*
// @match        https://www.xiaohongshu.com/user/profile/*
// @updateURL    https://github.com/zwmopen/scripts/raw/refs/heads/master/xiaohongshu-web-toolkit.user.js
// @downloadURL  https://github.com/zwmopen/scripts/raw/refs/heads/master/xiaohongshu-web-toolkit.user.js
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

  let currentOpenFilter = null;
  let currentFilterPath = [];
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
        if (!isVisible(button)) continue;
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
    return /\/(?:user\/profile|profile|creator)(?:\/|$)/i.test(pathname || '');
  }

  function extractProfileId(raw) {
    const url = parseUrl(raw);
    if (!url || !isXhsHost(url.hostname) || !isProfilePath(url.pathname)) return '';
    const match = url.pathname.match(/\/(?:user\/)?profile\/([^/?#]+)/i)
      || url.pathname.match(/\/creator\/([^/?#]+)/i);
    let profileId = match ? match[1] : '';
    if (!profileId) {
      profileId = url.searchParams.get('user_id')
        || url.searchParams.get('userid')
        || url.searchParams.get('author_id')
        || url.searchParams.get('creator_id')
        || url.searchParams.get('profile_id')
        || '';
    }
    try {
      profileId = decodeURIComponent(profileId);
    } catch (error) {
      // Keep the raw route segment if it contains a malformed escape sequence.
    }
    return /^[\w-]{4,120}$/.test(profileId) ? profileId : '';
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
    for (let index = 0; index < 12 && scope && scope !== document.body; index += 1) {
      scopes.push(scope);
      scope = scope.parentElement;
    }
    const cardRect = card && card.getBoundingClientRect ? card.getBoundingClientRect() : null;
    const cardCenter = cardRect ? {
      x: (cardRect.left + cardRect.right) / 2,
      y: (cardRect.top + cardRect.bottom) / 2,
    } : null;
    const candidates = [];
    for (const scope of scopes) {
      const links = Array.from(scope.querySelectorAll('a[href]'));
      links.filter((link) => isLikelyProfileHref(link.href)).forEach((link) => {
        if (!candidates.includes(link)) candidates.push(link);
      });
    }
    return candidates.sort((a, b) => {
      if (!cardCenter) return 0;
      const distance = (link) => {
        const rect = link.getBoundingClientRect();
        const x = (rect.left + rect.right) / 2;
        const y = (rect.top + rect.bottom) / 2;
        return Math.hypot(x - cardCenter.x, y - cardCenter.y);
      };
      return distance(a) - distance(b);
    })[0] || null;
  }

  function findAvatarProfileUrl(card) {
    if (!card || !card.getBoundingClientRect) return '';
    const cardRect = card.getBoundingClientRect();
    const scopes = [];
    let scope = card;
    for (let index = 0; index < 12 && scope && scope !== document.body; index += 1) {
      scopes.push(scope);
      scope = scope.parentElement;
    }

    const images = [];
    for (const candidateScope of scopes) {
      for (const image of Array.from(candidateScope.querySelectorAll('img'))) {
        if (images.includes(image)) continue;
        const rect = image.getBoundingClientRect();
        const smallSquare = rect.width >= 16 && rect.width <= 112
          && rect.height >= 16 && rect.height <= 112
          && rect.width / rect.height >= 0.65 && rect.width / rect.height <= 1.5;
        const nearCardAvatarPosition = rect.left >= cardRect.left - 36
          && rect.left <= cardRect.left + 150
          && rect.top >= cardRect.top - 30
          && rect.top <= cardRect.top + 170;
        if (smallSquare && nearCardAvatarPosition) images.push(image);
      }
      // Once the search reaches a broad list/grid, avoid scanning every card.
      if (candidateScope.querySelectorAll('a[href]').length > 300) break;
    }

    for (const image of images) {
      let element = image;
      for (let depth = 0; depth < 6 && element && element !== document.body; depth += 1) {
        if (element.matches('a[href]')) {
          const profileUrl = toPugongyingProfileUrl(element.href);
          if (profileUrl) return profileUrl;
        }

        for (const attribute of Array.from(element.attributes || [])) {
          const key = attribute.name.toLowerCase();
          if (!/(?:user|author|creator|profile)[-_]?(?:id)?$/.test(key)) continue;
          const value = attribute.value.trim();
          if (/^[\w-]{4,120}$/.test(value)) return toPugongyingProfileUrl(value);
        }

        const localMetadata = collectCardMetadata(element);
        const localProfilePath = localMetadata.urls.find((value) => isLikelyProfileHref(value));
        if (localProfilePath) {
          const profileUrl = toPugongyingProfileUrl(localProfilePath);
          if (profileUrl) return profileUrl;
        }
        const localProfileId = localMetadata.ids.find((item) => item.kind === 'profile');
        if (localProfileId) return toPugongyingProfileUrl(localProfileId.value);
        element = element.parentElement;
      }
    }
    return '';
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

    const avatarProfileUrl = findAvatarProfileUrl(card);
    if (avatarProfileUrl) return avatarProfileUrl;

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
    button.setAttribute('aria-label', url ? '直接打开蒲公英作者主页' : '识别作者后直接打开蒲公英');
    button.title = url
      ? `直接打开蒲公英作者主页：${url}`
      : '点击时重试识别作者；识别失败不会打开小红书中转页';
    button.textContent = '蒲';

    const open = (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (typeof event.stopImmediatePropagation === 'function') event.stopImmediatePropagation();
      const directUrl = url || resolvePugongyingUrl(card, collectCardMetadata(card));
      if (!directUrl) {
        button.title = '没有找到头像对应的作者链接或作者 ID';
        button.setAttribute('aria-label', '未找到作者 ID，未打开页面');
        return;
      }
      window.open(directUrl, '_blank', 'noopener,noreferrer');
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
    const anchors = Array.from(document.querySelectorAll('a[href]')).filter((anchor) => {
      return isVisible(anchor) && isLikelyNoteHref(anchor.href);
    });
    for (const anchor of anchors) {
      const card = findCardForNoteAnchor(anchor);
      if (!card || seen.has(card)) continue;
      seen.add(card);
      addPugongyingButton(card);
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
        addPugongyingButton(candidate);
      }
    }
  }

  function scheduleCardScan() {
    window.clearTimeout(cardScanTimer);
    cardScanTimer = window.setTimeout(scanContentCards, 280);
  }

  function tabElements() {
    return Array.from(document.querySelectorAll(`[id^="${TAB_PREFIX}"], [role="tab"]`)).filter(isVisible);
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
  }

  function clearCurrentState() {
    const store = readStore();
    delete store[pageKey()];
    writeStore(store);
  }

  async function applySavedState() {
    const saved = getSavedState();
    if (!saved) return;
    if (restoring) return;
    restoring = true;
    try {
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
    } catch (error) {
      console.warn('[聚光筛选记忆] 恢复失败', error);
    } finally {
      restoring = false;
      currentOpenFilter = null;
      currentFilterPath = [];
    }
  }

  function scheduleRestore() {
    if (restoreScheduled) return;
    restoreScheduled = true;
    let attempts = 0;
    const run = () => {
      attempts += 1;
      const saved = getSavedState();
      if (saved && (getSearchInput() || tabElements().length || filterTrigger(FILTER_NAMES[0]))) {
        restoreScheduled = false;
        applySavedState();
        return;
      }
      if (attempts < 12) {
        restoreTimer = window.setTimeout(run, 500);
      } else {
        restoreScheduled = false;
      }
    };
    window.clearTimeout(restoreTimer);
    restoreTimer = window.setTimeout(run, 600);
  }

  function installClickTracking() {
    document.addEventListener('click', (event) => {
      const target = event.target instanceof Element ? event.target : null;
      if (!target || restoring) return;

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
        window.setTimeout(scheduleRestore, 80);
        window.setTimeout(scheduleCardScan, 180);
        return result;
      };
    });
    window.addEventListener('popstate', () => {
      scheduleRestore();
      scheduleCardScan();
    });
  }

  function registerMenu() {
    if (typeof GM_registerMenuCommand !== 'function') return;
    GM_registerMenuCommand('聚光：重新应用上次筛选', applySavedState);
    GM_registerMenuCommand('聚光：清除此页筛选记录', clearCurrentState);
  }

  function boot() {
    if (!isJuguangHost()) return;
    installClickTracking();
    installHistoryTracking();
    registerMenu();
    scheduleRestore();
    scheduleCardScan();
    const observer = new MutationObserver(() => {
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
