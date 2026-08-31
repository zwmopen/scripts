// ==UserScript==
// @name         ChatGPT 最近对话分组（飞书式目录）
// @name:zh-CN   ChatGPT 作品助手（图片下载、打包与提示词）
// @namespace    https://chatgpt.com/
// @version      1.17.0
// @description  为 ChatGPT 提供图片组快捷下载、下载并打包、本地作品去重与提示词管理；不再修改原生侧边栏。
// @author       Codex
// @match        https://chatgpt.com/*
// @match        https://chat.openai.com/*
// @run-at       document-idle
// @updateURL    https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-conversation-tree.user.js
// @downloadURL  https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-conversation-tree.user.js
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_deleteValue
// @grant        GM_listValues
// @grant        GM_download
// @grant        GM_registerMenuCommand
// @grant        GM_unregisterMenuCommand
// @grant        GM_xmlhttpRequest
// @grant        unsafeWindow
// @connect      raw.githubusercontent.com
// ==/UserScript==

(() => {
  'use strict';

  const APP_ID = 'cgpt-conversation-tree';
  const SCRIPT_VERSION = '1.17.0';
  // 1.16.0 起停止向 ChatGPT 原生侧边栏注入分组、拖动和历史预加载功能。
  // 1.17.0 彻底剥离旧侧边栏废弃代码，脚本轻量化运行。
  const SIDEBAR_GROUPING_ENABLED = false;

  // DOM 节点与样式 ID / 类名
  const HEADER_ID = `${APP_ID}-header-actions`;
  const MENU_ID = `${APP_ID}-menu`;
  const STYLE_ID = `${APP_ID}-style`;
  const PARKING_ID = `${APP_ID}-parking`;
  const RENAME_ID = `${APP_ID}-batch-rename`;
  const RENAME_STAGE_ID = `${APP_ID}-rename-stage`;
  const IMPORT_INPUT_ID = `${APP_ID}-import-input`;
  const PROMPT_BUTTON_ID = `${APP_ID}-prompt-button`;
  const PROMPT_PANEL_ID = `${APP_ID}-prompt-panel`;
  const IMAGE_DOWNLOAD_CLASS = `${APP_ID}-image-download-all`;
  const IMAGE_DOWNLOAD_SLOT_CLASS = `${APP_ID}-image-download-slot`;
  const TEXT_DOWNLOAD_CLASS = `${APP_ID}-text-download`;
  const TEXT_DOWNLOAD_SLOT_CLASS = `${APP_ID}-text-download-slot`;
  const WORK_PACKAGE_CLASS = `${APP_ID}-work-package`;
  const IMAGE_DOWNLOAD_TOAST_ID = `${APP_ID}-image-download-toast`;

  // 本地协议与元数据标记
  const WORK_PACKAGE_PROTOCOL_URL = 'cgpt-workpkg://run';
  const WORK_PACKAGE_TITLE_MARKER = 'WORKPKG_GPT_TITLE_B64:';
  const WORK_PACKAGE_METADATA_MARKER = 'WORKPKG_GPT_META_B64:';

  // 存储键名（保持旧版存储键兼容，确保历史数据导出无损）
  const STORAGE_KEY = `${APP_ID}:state:v3`;
  const LEGACY_STORAGE_KEY = `${APP_ID}:state:v1`;
  const GM_STATE_KEY = 'state-v3';
  const BACKUP_PREFIX = `${APP_ID}:backup:`;
  const GM_BACKUP_PREFIX = 'backup:';
  const MAX_BACKUPS = 8;
  const PROMPT_STORAGE_KEY = `${APP_ID}:prompts:v1`;
  const GM_PROMPT_KEY = 'prompts-v1';
  const USERSCRIPT_RAW_URL = 'https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-conversation-tree.user.js';
  const CLOUD_PROMPT_URL = 'https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-cloud-prompts.json';
  const CLOUD_PROMPT_CACHE_KEY = 'cloud-prompts-cache-v1';
  const CLOUD_PROMPT_CACHE_STORAGE_KEY = `${APP_ID}:cloud-prompts-cache:v1`;
  const CLOUD_PROMPT_BACKUPS_KEY = 'cloud-prompts-backups-v1';
  const CLOUD_PROMPT_BACKUPS_STORAGE_KEY = `${APP_ID}:cloud-prompts-backups:v1`;
  const CLOUD_PROMPT_AUTO_SYNC_INTERVAL = 24 * 60 * 60 * 1000;
  const MAX_CLOUD_PROMPT_BACKUPS = 5;
  const MAX_CLOUD_PROMPT_RESPONSE_BYTES = 2 * 1024 * 1024;
  const DIAGNOSTIC_LOG_KEY = `${APP_ID}:diagnostic-log:v1`;
  const MAX_DIAGNOSTIC_LOGS = 220;
  const WORK_PACKAGE_VISIBLE_KEY = 'work-package-visible';
  const WORK_PACKAGE_HELPER_READY_KEY = 'work-package-helper-ready-v1';
  const WORK_PACKAGE_INSTALLER_URL = 'https://raw.githubusercontent.com/zwmopen/scripts/master/%E5%AE%89%E8%A3%85GPT%E4%BD%9C%E5%93%81%E5%8A%A9%E6%89%8B.vbs';
  const IMAGE_DOWNLOAD_VISIBLE_KEY = 'image-download-visible';

  // 图标
  const icons = {
    download: '<svg viewBox="0 0 18 18"><path d="M9 3v8"/><path d="m5.5 8 3.5 3.5L12.5 8"/><path d="M4 14.5h10"/></svg>',
    package: '<svg viewBox="0 0 18 18"><path d="M3 6.2 9 3l6 3.2v6.4L9 16l-6-3.4z"/><path d="M3 6.2 9 9.4l6-3.2M9 9.4V16"/><path d="M7.2 5.1 13 8.2"/><path d="M5.2 11.1h3.1M6.8 9.5l1.6 1.6-1.6 1.6"/></svg>',
  };

  // 运行期状态
  let promptState = loadPromptState();
  let cloudPromptState = loadCloudPromptState();
  let cloudPromptSyncing = false;
  let cloudPromptSyncPromise = null;
  let editingPromptId = '';
  let promptHelpVisible = false;
  let promptButtonTimer = 0;
  let imageToolsTimer = 0;
  let imageEventsBound = false;
  let userscriptMenuCommandIds = [];
  let diagnosticLogs = loadDiagnosticLogs();
  let diagnosticSaveTimer = 0;
  let workPackageAccountName = '';
  let workPackageAccountLookupPromise = null;
  let pendingImportMode = 'merge';

  let imageDownloadButtonVisible = (() => {
    try {
      return GM_getValue(IMAGE_DOWNLOAD_VISIBLE_KEY, true) !== false;
    } catch {
      return true;
    }
  })();

  let workPackageButtonVisible = (() => {
    try {
      return GM_getValue(WORK_PACKAGE_VISIBLE_KEY, true) !== false;
    } catch {
      return true;
    }
  })();

  let workPackageHelperReady = (() => {
    try {
      return GM_getValue(WORK_PACKAGE_HELPER_READY_KEY, false) === true;
    } catch {
      return false;
    }
  })();

  // ==========================================
  // 1. 数据结构与历史兼容层（用于安全导出旧分组）
  // ==========================================

  function defaultState() {
    return {
      version: 3,
      tree: [],
      known: {},
      updatedAt: 0,
    };
  }

  function countStateItems(candidate) {
    let folders = 0;
    let chats = 0;
    const walk = (nodes) => (Array.isArray(nodes) ? nodes : []).forEach((node) => {
      if (node?.type === 'folder') {
        folders += 1;
        walk(node.children);
      } else if (node?.type === 'chat' && node.chatId) {
        chats += 1;
      }
    });
    walk(candidate?.tree);
    return { folders, chats };
  }

  function loadState() {
    const modernSources = [];
    try {
      modernSources.push(GM_getValue(GM_STATE_KEY, null));
    } catch {}
    try {
      modernSources.push(JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null'));
    } catch {}

    const validModern = modernSources.filter((candidate) => candidate && Array.isArray(candidate.tree));
    const nonEmptyModern = validModern.filter((candidate) => {
      const counts = countStateItems(candidate);
      return counts.folders > 0 || counts.chats > 0;
    });

    let legacy = null;
    try {
      legacy = JSON.parse(localStorage.getItem(LEGACY_STORAGE_KEY) || 'null');
    } catch {
      legacy = null;
    }

    let candidates = nonEmptyModern.length ? nonEmptyModern : validModern;
    if (!nonEmptyModern.length && legacy && Array.isArray(legacy.tree)) {
      candidates = [...candidates, legacy];
    }

    const parsed = candidates
      .filter((candidate) => candidate && Array.isArray(candidate.tree))
      .sort((a, b) => Number(b.updatedAt || 0) - Number(a.updatedAt || 0))[0];

    if (!parsed) return defaultState();
    return {
      ...defaultState(),
      ...parsed,
      version: 3,
      known: parsed.known && typeof parsed.known === 'object' ? parsed.known : {},
    };
  }

  // ==========================================
  // 2. 本地与云端提示词库
  // ==========================================

  function defaultPromptState() {
    return {
      version: 1,
      items: [],
      updatedAt: 0,
    };
  }

  function normalizePromptItem(item) {
    const title = compactTitle(item?.title || '');
    const content = String(item?.content || '').trim();
    if (!title && !content) return null;
    const now = Date.now();
    return {
      id: String(item?.id || uid('prompt')),
      title: title || compactTitle(content).slice(0, 28) || '未命名提示词',
      content,
      createdAt: Number(item?.createdAt || now),
      updatedAt: Number(item?.updatedAt || now),
    };
  }

  function loadPromptState() {
    const sources = [];
    try { sources.push(GM_getValue(GM_PROMPT_KEY, null)); } catch {}
    try { sources.push(JSON.parse(localStorage.getItem(PROMPT_STORAGE_KEY) || 'null')); } catch {}
    const source = sources
      .filter((candidate) => candidate && Array.isArray(candidate.items))
      .sort((a, b) => Number(b.updatedAt || 0) - Number(a.updatedAt || 0))[0];
    if (!source) return defaultPromptState();
    const items = source.items
      .map((item) => normalizePromptItem(item))
      .filter(Boolean)
      .slice(0, 300);
    return {
      version: 1,
      items,
      updatedAt: Number(source.updatedAt || 0),
    };
  }

  function savePromptState() {
    promptState.updatedAt = Date.now();
    const payload = {
      version: 1,
      items: promptState.items.map((item) => ({ ...item })),
      updatedAt: promptState.updatedAt,
    };
    try { GM_setValue(GM_PROMPT_KEY, payload); } catch {}
    try {
      localStorage.setItem(PROMPT_STORAGE_KEY, JSON.stringify(payload));
    } catch (error) {
      console.warn('[ChatGPT 辅助器] 提示词保存失败：', error);
    }
  }

  function defaultCloudPromptState() {
    return {
      schemaVersion: 1,
      version: '',
      items: [],
      updatedAt: 0,
      syncedAt: 0,
    };
  }

  function promptTimestamp(value, fallback = Date.now()) {
    const numeric = Number(value);
    if (Number.isFinite(numeric) && numeric > 0) return numeric;
    const parsed = Date.parse(String(value || ''));
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function normalizeCloudPromptItem(item, index = 0) {
    const title = compactTitle(item?.title || '').slice(0, 160);
    const content = String(item?.content || '').trim().slice(0, 50000);
    if (!title && !content) return null;
    const sourceId = String(
      item?.sourceId || String(item?.id || `item-${index + 1}`).replace(/^cloud:/, '')
    ).slice(0, 240);
    const updatedAt = promptTimestamp(item?.updatedAt, Date.now());
    return {
      id: `cloud:${sourceId}`,
      sourceId,
      source: 'cloud',
      title: title || compactTitle(content).slice(0, 28) || '未命名云端提示词',
      content,
      createdAt: promptTimestamp(item?.createdAt, updatedAt),
      updatedAt,
    };
  }

  function normalizeCloudPromptState(source) {
    if (!source || typeof source !== 'object') return defaultCloudPromptState();
    const rawItems = Array.isArray(source.prompts) ? source.prompts : source.items;
    if (!Array.isArray(rawItems)) return defaultCloudPromptState();
    return {
      schemaVersion: 1,
      version: String(source.version || ''),
      items: rawItems
        .slice(0, 500)
        .map((item, index) => normalizeCloudPromptItem(item, index))
        .filter(Boolean),
      updatedAt: promptTimestamp(source.updatedAt, 0),
      syncedAt: promptTimestamp(source.syncedAt, 0),
    };
  }

  function loadCloudPromptState() {
    const sources = [];
    try { sources.push(GM_getValue(CLOUD_PROMPT_CACHE_KEY, null)); } catch {}
    try { sources.push(JSON.parse(localStorage.getItem(CLOUD_PROMPT_CACHE_STORAGE_KEY) || 'null')); } catch {}
    const source = sources
      .filter((candidate) => candidate && (Array.isArray(candidate.items) || Array.isArray(candidate.prompts)))
      .sort((a, b) => promptTimestamp(b.syncedAt, 0) - promptTimestamp(a.syncedAt, 0))[0];
    return normalizeCloudPromptState(source);
  }

  function saveCloudPromptState() {
    const payload = {
      schemaVersion: 1,
      version: cloudPromptState.version,
      items: cloudPromptState.items.map((item) => ({ ...item })),
      updatedAt: cloudPromptState.updatedAt,
      syncedAt: cloudPromptState.syncedAt,
    };
    try { GM_setValue(CLOUD_PROMPT_CACHE_KEY, payload); } catch {}
    try {
      localStorage.setItem(CLOUD_PROMPT_CACHE_STORAGE_KEY, JSON.stringify(payload));
    } catch (error) {
      console.warn('[ChatGPT 辅助器] 云端提示词缓存失败：', error);
    }
  }

  function cloudPromptSnapshot(source = cloudPromptState) {
    return {
      schemaVersion: 1,
      version: String(source?.version || ''),
      items: (source?.items || []).map((item) => ({ ...item })),
      updatedAt: Number(source?.updatedAt || 0),
      syncedAt: Number(source?.syncedAt || 0),
      backedUpAt: Date.now(),
    };
  }

  function loadCloudPromptBackups() {
    let raw = null;
    try { raw = GM_getValue(CLOUD_PROMPT_BACKUPS_KEY, null); } catch {}
    if (!Array.isArray(raw)) {
      try { raw = JSON.parse(localStorage.getItem(CLOUD_PROMPT_BACKUPS_STORAGE_KEY) || 'null'); } catch {}
    }
    return (Array.isArray(raw) ? raw : [])
      .map((item) => normalizeCloudPromptState(item))
      .filter((item) => item.items.length)
      .slice(0, MAX_CLOUD_PROMPT_BACKUPS);
  }

  function saveCloudPromptBackups(backups) {
    const payload = backups.slice(0, MAX_CLOUD_PROMPT_BACKUPS).map((item) => cloudPromptSnapshot(item));
    try { GM_setValue(CLOUD_PROMPT_BACKUPS_KEY, payload); } catch {}
    try { localStorage.setItem(CLOUD_PROMPT_BACKUPS_STORAGE_KEY, JSON.stringify(payload)); } catch {}
  }

  function backupCloudPromptState(source = cloudPromptState) {
    if (!source?.items?.length) return;
    const snapshot = cloudPromptSnapshot(source);
    const signature = `${snapshot.version}|${snapshot.updatedAt}|${snapshot.items.length}`;
    const backups = loadCloudPromptBackups().filter((item) => (
      `${item.version}|${item.updatedAt}|${item.items.length}` !== signature
    ));
    backups.unshift(snapshot);
    saveCloudPromptBackups(backups);
  }

  function cloudPromptBackupCount() {
    return loadCloudPromptBackups().length;
  }

  function cloudPromptStatusText() {
    const lastSync = Number(cloudPromptState.syncedAt || 0);
    const time = lastSync
      ? new Date(lastSync).toLocaleString('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })
      : '未同步';
    return `本地 ${promptState.items.length} · 云端 ${cloudPromptState.items.length} · ${time}`;
  }

  function restorePreviousCloudPrompts() {
    const backups = loadCloudPromptBackups();
    const previous = backups.shift();
    if (!previous) {
      showImageDownloadToast('没有可恢复的云端提示词版本', false);
      return false;
    }
    const current = cloudPromptSnapshot(cloudPromptState);
    if (current.items.length) backups.push(current);
    cloudPromptState = { ...previous, syncedAt: Date.now() };
    saveCloudPromptState();
    saveCloudPromptBackups(backups);
    if (!document.getElementById(PROMPT_PANEL_ID)?.hidden) renderPromptPanel();
    showImageDownloadToast(`已恢复云端提示词：${cloudPromptState.items.length} 条`, true);
    addDiagnosticLog('prompt:cloud-restore', {
      count: cloudPromptState.items.length,
      version: cloudPromptState.version,
    });
    return true;
  }

  function visiblePromptItems() {
    const localIds = new Set(promptState.items.map((item) => String(item.id)));
    const localContent = new Set(promptState.items.map((item) => `${item.title}\n${item.content}`));
    const cloudItems = cloudPromptState.items.filter((item) => (
      !localIds.has(item.sourceId) && !localContent.has(`${item.title}\n${item.content}`)
    ));
    return [...promptState.items, ...cloudItems];
  }

  function findPromptItem(promptId) {
    return promptState.items.find((item) => item.id === promptId)
      || cloudPromptState.items.find((item) => item.id === promptId)
      || null;
  }

  function requestCloudPromptJson() {
    const url = `${CLOUD_PROMPT_URL}?ts=${Date.now()}`;
    if (typeof GM_xmlhttpRequest === 'function') {
      return new Promise((resolve, reject) => {
        GM_xmlhttpRequest({
          method: 'GET',
          url,
          timeout: 15000,
          headers: { Accept: 'application/json' },
          onload(response) {
            if (response.status < 200 || response.status >= 300) {
              reject(new Error(`GitHub 返回 HTTP ${response.status}`));
              return;
            }
            const body = String(response.responseText || '');
            if (body.length > MAX_CLOUD_PROMPT_RESPONSE_BYTES) {
              reject(new Error('云端提示词文件超过 2MB，已拒绝加载'));
              return;
            }
            try { resolve(JSON.parse(body)); }
            catch { reject(new Error('云端提示词不是有效 JSON')); }
          },
          onerror: () => reject(new Error('无法连接 GitHub 云端提示词库')),
          ontimeout: () => reject(new Error('连接 GitHub 云端提示词库超时')),
        });
      });
    }
    return fetch(url, { cache: 'no-store' }).then(async (response) => {
      if (!response.ok) throw new Error(`GitHub 返回 HTTP ${response.status}`);
      const body = await response.text();
      if (body.length > MAX_CLOUD_PROMPT_RESPONSE_BYTES) {
        throw new Error('云端提示词文件超过 2MB，已拒绝加载');
      }
      try { return JSON.parse(body); }
      catch { throw new Error('云端提示词不是有效 JSON'); }
    });
  }

  async function syncCloudPrompts(manual = false) {
    if (cloudPromptSyncPromise) {
      if (manual) showImageDownloadToast('云端提示词正在同步…', true);
      return cloudPromptSyncPromise;
    }
    cloudPromptSyncing = true;
    if (!document.getElementById(PROMPT_PANEL_ID)?.hidden) renderPromptPanel();
    if (manual) showImageDownloadToast('正在连接 GitHub 同步云端提示词…', true);
    addDiagnosticLog('prompt:cloud-sync-start', { manual });

    cloudPromptSyncPromise = (async () => {
      try {
        const payload = await requestCloudPromptJson();
        const next = normalizeCloudPromptState(payload);
        if (!next.items.length) {
          throw new Error('云端提示词文件为空或未包含有效提示词');
        }
        if (cloudPromptState.items.length) {
          backupCloudPromptState(cloudPromptState);
        }
        cloudPromptState = {
          ...next,
          syncedAt: Date.now(),
        };
        saveCloudPromptState();
        if (!document.getElementById(PROMPT_PANEL_ID)?.hidden) renderPromptPanel();
        if (manual) showImageDownloadToast(`云端提示词已同步：${next.items.length} 条`, true);
        addDiagnosticLog('prompt:cloud-sync-success', {
          count: next.items.length,
          version: next.version,
          manual,
        });
        return true;
      } catch (error) {
        console.warn('[ChatGPT 辅助器] 云端提示词同步失败：', error);
        if (manual) {
          showImageDownloadToast(`云端提示词同步失败：${error.message || '网络异常'}`, false);
        }
        addDiagnosticLog('prompt:cloud-sync-failed', {
          message: error?.message || String(error),
          manual,
        });
        return false;
      } finally {
        cloudPromptSyncing = false;
        cloudPromptSyncPromise = null;
        if (!document.getElementById(PROMPT_PANEL_ID)?.hidden) renderPromptPanel();
      }
    })();

    return cloudPromptSyncPromise;
  }

  function scheduleCloudPromptSync() {
    const lastSync = Number(cloudPromptState.syncedAt || 0);
    if (!lastSync || Date.now() - lastSync > CLOUD_PROMPT_AUTO_SYNC_INTERVAL) {
      window.setTimeout(() => void syncCloudPrompts(false), 2400);
    }
  }

  function exportCloudPromptFile() {
    const payload = {
      schemaVersion: 1,
      version: new Date().toISOString().slice(0, 10),
      updatedAt: Date.now(),
      prompts: promptState.items.map((item, index) => ({
        id: item.id || `prompt-${index + 1}`,
        title: item.title,
        content: item.content,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
      })),
    };
    const json = JSON.stringify(payload, null, 2);
    const blob = new Blob([json], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = 'chatgpt-cloud-prompts.json';
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    showImageDownloadToast(`已导出云端提示词文件：${payload.prompts.length} 条`, true);
  }

  // ==========================================
  // 3. 诊断日志与调试 API
  // ==========================================

  function loadDiagnosticLogs() {
    try {
      const logs = JSON.parse(localStorage.getItem(DIAGNOSTIC_LOG_KEY) || '[]');
      return Array.isArray(logs) ? logs.slice(-MAX_DIAGNOSTIC_LOGS) : [];
    } catch {
      return [];
    }
  }

  function saveDiagnosticLogs(immediate = false) {
    if (!immediate) {
      clearTimeout(diagnosticSaveTimer);
      diagnosticSaveTimer = window.setTimeout(() => saveDiagnosticLogs(true), 900);
      return;
    }
    try {
      localStorage.setItem(
        DIAGNOSTIC_LOG_KEY,
        JSON.stringify(diagnosticLogs.slice(-MAX_DIAGNOSTIC_LOGS))
      );
    } catch {}
  }

  function safeDiagnosticDetail(value, depth = 0) {
    if (value == null || ['string', 'number', 'boolean'].includes(typeof value)) {
      const text = String(value ?? '');
      if (typeof value === 'string') return text.slice(0, 500);
      return value;
    }
    if (depth > 2) return '[depth-limit]';
    if (Array.isArray(value)) {
      return value.slice(0, 20).map((item) => safeDiagnosticDetail(item, depth + 1));
    }
    if (typeof value === 'object') {
      const output = {};
      Object.entries(value).slice(0, 30).forEach(([key, item]) => {
        if (/token|cookie|authorization|password|secret/i.test(key)) return;
        output[key] = safeDiagnosticDetail(item, depth + 1);
      });
      return output;
    }
    return String(value).slice(0, 200);
  }

  function diagnosticSnapshot() {
    return {
      scriptVersion: SCRIPT_VERSION,
      pageUrl: location.href,
      pageTitle: document.title,
      promptsCount: promptState.items.length,
      cloudPromptsCount: cloudPromptState.items.length,
      imageButtonsVisible: imageDownloadButtonVisible,
      workPackageButtonVisible: workPackageButtonVisible,
    };
  }

  function addDiagnosticLog(eventName, detail = {}) {
    const entry = {
      at: new Date().toISOString(),
      event: eventName,
      detail: safeDiagnosticDetail(detail),
      snapshot: safeDiagnosticDetail(diagnosticSnapshot()),
    };
    diagnosticLogs.push(entry);
    diagnosticLogs = diagnosticLogs.slice(-MAX_DIAGNOSTIC_LOGS);
    saveDiagnosticLogs();
    try {
      const pageWindow = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;
      pageWindow.__cgptConversationTreeDiagnostics = {
        snapshot: diagnosticSnapshot(),
        logs: diagnosticLogs,
      };
    } catch {}
    console.debug('[ChatGPT 助手诊断]', eventName, entry);
  }

  async function copyDiagnosticLogs() {
    const payload = {
      format: `${APP_ID}:diagnostics`,
      exportedAt: new Date().toISOString(),
      snapshot: diagnosticSnapshot(),
      logs: diagnosticLogs.slice(-MAX_DIAGNOSTIC_LOGS),
    };
    const text = JSON.stringify(payload, null, 2);
    try {
      await navigator.clipboard.writeText(text);
      window.alert(`已复制诊断日志：${payload.logs.length} 条。`);
    } catch {
      const blob = new Blob([text], { type: 'application/json;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `chatgpt-helper-diagnostics-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
      document.body.append(anchor);
      anchor.click();
      anchor.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    }
  }

  function clearDiagnosticLogs() {
    diagnosticLogs = [];
    saveDiagnosticLogs(true);
    addDiagnosticLog('diagnostic:cleared');
  }

  function installConversationTreeDebugApi() {
    try {
      const pageWindow = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;
      pageWindow.CGPTConversationTreeDebug = {
        snapshot: () => diagnosticSnapshot(),
        logs: () => diagnosticLogs.slice(),
        copyLogs: () => copyDiagnosticLogs(),
        clearLogs: () => clearDiagnosticLogs(),
        version: SCRIPT_VERSION,
      };
    } catch {}
  }

  // ==========================================
  // 4. 通用工具函数
  // ==========================================

  function uid(prefix) {
    if (crypto?.randomUUID) return `${prefix}:${crypto.randomUUID()}`;
    return `${prefix}:${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  }

  function compactTitle(value) {
    return String(value || '')
      .replace(/\s+/g, ' ')
      .replace(/^(打开|Open)\s*/i, '')
      .trim()
      .slice(0, 180);
  }

  function escapeHtml(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#039;');
  }

  function base64Utf8(value) {
    const bytes = new TextEncoder().encode(String(value || ''));
    let binary = '';
    bytes.forEach((byte) => {
      binary += String.fromCharCode(byte);
    });
    return btoa(binary);
  }

  function sleep(ms) {
    return new Promise((resolve) => window.setTimeout(resolve, ms));
  }

  function runWhenIdle(callback, timeout = 900) {
    if (typeof requestIdleCallback === 'function') {
      requestIdleCallback(callback, { timeout });
      return;
    }
    window.setTimeout(callback, Math.min(timeout, 260));
  }

  function isElementVisible(element) {
    if (!element || !element.isConnected) return false;
    const rect = element.getBoundingClientRect?.();
    if (!rect || rect.width < 1 || rect.height < 1) return false;
    const style = getComputedStyle(element);
    return style.visibility !== 'hidden' && style.display !== 'none' && Number(style.opacity || 1) > 0;
  }

  function elementText(element) {
    return compactTitle([
      element?.innerText,
      element?.getAttribute?.('aria-label'),
      element?.getAttribute?.('title'),
      element?.getAttribute?.('data-testid'),
    ].filter(Boolean).join(' '));
  }

  // ==========================================
  // 5. 会话与账号元数据提取（剪贴板桥接）
  // ==========================================

  function chatInfoFromHref(href) {
    try {
      const url = new URL(href, location.href);
      if (url.origin !== location.origin) return null;
      const match = url.pathname.match(/\/c\/([^/?#]+)/);
      if (!match) return null;
      return {
        chatId: decodeURIComponent(match[1]),
        url: url.pathname,
      };
    } catch {
      return null;
    }
  }

  function currentChatId() {
    return chatInfoFromHref(location.href)?.chatId || '';
  }

  function normalizeWorkPackageConversationTitle(value) {
    let title = compactTitle(value);
    title = title
      .replace(/\s+[-\u2013\u2014]\s+(Microsoft Edge|Google Chrome|Chrome|Chromium|Brave|Mozilla Firefox)$/i, '')
      .replace(/\s+[-\u2013\u2014]\s*(ChatGPT|OpenAI)\s*$/i, '')
      .replace(/^\s*(ChatGPT|OpenAI)\s*[-\u2013\u2014]\s*/i, '');
    title = compactTitle(title);
    if (!title || /^(ChatGPT|OpenAI|New chat|\u65b0\u804a\u5929)$/i.test(title)) return '';
    return title.slice(0, 80);
  }

  function currentWorkPackageConversationTitle() {
    const candidates = [
      document.querySelector('main h1')?.innerText || '',
      document.title || '',
    ];
    for (const candidate of candidates) {
      const title = normalizeWorkPackageConversationTitle(candidate);
      if (title) return title;
    }
    return '';
  }

  function workPackageTitleMarker(title = currentWorkPackageConversationTitle()) {
    const normalized = normalizeWorkPackageConversationTitle(title);
    if (!normalized) return '';
    return `<!--${WORK_PACKAGE_TITLE_MARKER}${base64Utf8(normalized)}-->`;
  }

  function normalizeWorkPackageAccountName(value) {
    const ignored = /^(ChatGPT|OpenAI|Plus|Pro|Team|Business|Enterprise|Free|Upgrade|升级|设置|Settings|Log out|退出|Open profile menu|Profile|Account|账号|个人资料|个人资料图片|头像|Profile picture|User avatar)$/i;
    const lines = String(value || '').split(/\r?\n/);
    for (const rawLine of lines) {
      const line = compactTitle(rawLine);
      if (!line || ignored.test(line) || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(line)) continue;
      return line.slice(0, 120);
    }
    return '';
  }

  async function refreshWorkPackageAccountName() {
    if (workPackageAccountLookupPromise) return workPackageAccountLookupPromise;
    workPackageAccountLookupPromise = (async () => {
      try {
        const response = await fetch('/api/auth/session', {
          credentials: 'include',
          cache: 'no-store',
          headers: { Accept: 'application/json' },
        });
        if (!response.ok) return workPackageAccountName;
        const session = await response.json();
        const name = normalizeWorkPackageAccountName(session?.user?.name);
        if (name) workPackageAccountName = name;
      } catch (error) {
        addDiagnosticLog('workpkg:account-name-fetch-failed', {
          message: error?.message || String(error),
        });
      }
      return workPackageAccountName;
    })().finally(() => {
      workPackageAccountLookupPromise = null;
    });
    return workPackageAccountLookupPromise;
  }

  function currentWorkPackageAccountName() {
    if (workPackageAccountName) return workPackageAccountName;
    refreshWorkPackageAccountName();
    const selectors = [
      '[data-testid="accounts-profile-button"]',
      '[data-testid="profile-button"]',
      '[data-testid*="account"][data-testid*="profile"]',
      'button[aria-label*="profile" i]',
      'button[aria-label*="account" i]',
      'button[aria-label*="个人资料"]',
      'button[aria-label*="账号"]',
    ];
    const roots = selectors.flatMap((selector) => Array.from(document.querySelectorAll(selector)));
    for (const root of roots) {
      const candidates = [
        root.getAttribute('data-user-name'),
        root.querySelector('[data-user-name]')?.getAttribute('data-user-name'),
        root.innerText,
        root.querySelector('img[alt]')?.getAttribute('alt'),
        root.getAttribute('title'),
        root.getAttribute('aria-label'),
      ];
      for (const candidate of candidates) {
        const name = normalizeWorkPackageAccountName(candidate);
        if (name) {
          workPackageAccountName = name;
          return name;
        }
      }
    }
    return '未识别账号';
  }

  function currentWorkPackageConversationUrl() {
    const chatId = currentChatId();
    if (!chatId) return '';
    return `${location.origin}/c/${encodeURIComponent(chatId)}`;
  }

  function workPackageMetadataMarker() {
    const conversationUrl = currentWorkPackageConversationUrl();
    if (!conversationUrl) return '';
    const metadata = {
      accountName: currentWorkPackageAccountName(),
      conversationUrl,
    };
    return `<!--${WORK_PACKAGE_METADATA_MARKER}${base64Utf8(JSON.stringify(metadata))}-->`;
  }

  function workPackageClipboardMarkers(title = currentWorkPackageConversationTitle()) {
    return `${workPackageTitleMarker(title)}${workPackageMetadataMarker()}`;
  }

  function stripWorkPackageMarkers(html = '') {
    return String(html || '')
      .replace(/<!--WORKPKG_GPT_TITLE_B64:[A-Za-z0-9+/=]+-->/g, '')
      .replace(/<!--WORKPKG_GPT_META_B64:[A-Za-z0-9+/=]+-->/g, '');
  }

  function htmlFromPlainText(text = '') {
    return escapeHtml(text).replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n/g, '<br>');
  }

  function selectedHtmlFragment() {
    const selection = window.getSelection?.();
    if (!selection || selection.rangeCount <= 0) return '';
    const container = document.createElement('div');
    for (let index = 0; index < selection.rangeCount; index += 1) {
      container.append(selection.getRangeAt(index).cloneContents());
    }
    return container.innerHTML || '';
  }

  function installWorkPackageClipboardBridge() {
    if (installWorkPackageClipboardBridge.installed) return;
    installWorkPackageClipboardBridge.installed = true;
    document.addEventListener('copy', (event) => {
      const title = currentWorkPackageConversationTitle();
      const markers = workPackageClipboardMarkers(title);
      const selection = window.getSelection?.();
      const text = selection?.toString?.() || '';
      if (!event.clipboardData || !markers || !text.trim()) return;

      const selectedHtml = selectedHtmlFragment();
      const html = `${stripWorkPackageMarkers(selectedHtml || htmlFromPlainText(text))}${markers}`;
      event.clipboardData.setData('text/plain', text);
      event.clipboardData.setData('text/html', html);
      event.preventDefault();
      addDiagnosticLog('workpkg:copy-metadata-marker', { title, conversationUrl: currentWorkPackageConversationUrl() });
    }, true);
  }

  // ==========================================
  // 6. 样式注入（仅包含提示词、按钮与提示条）
  // ==========================================

  function removeLegacySidebarGroupingUi() {
    [
      APP_ID,
      HEADER_ID,
      MENU_ID,
      PARKING_ID,
      RENAME_ID,
      RENAME_STAGE_ID,
      IMPORT_INPUT_ID,
      `${APP_ID}-conversation-tree-menu`,
    ].forEach((id) => document.getElementById(id)?.remove());
    document.querySelectorAll('[data-cgpt-recent-menu-item], [data-cgpt-native-menu-item]')
      .forEach((element) => element.remove());
  }

  function injectStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      #${PROMPT_PANEL_ID} {
        position: fixed;
        z-index: 2147483647;
        width: min(420px, calc(100vw - 24px));
        max-height: min(620px, calc(100vh - 24px));
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 10px;
        box-sizing: border-box;
        overflow: hidden;
        border: 1px solid color-mix(in srgb, currentColor 12%, transparent);
        border-radius: 16px;
        color: var(--text-primary, inherit);
        background: var(--main-surface-primary, Canvas);
        box-shadow: 0 18px 44px rgba(0,0,0,.18);
      }
      #${PROMPT_PANEL_ID}[hidden] {
        display: none;
      }
      .cgpt-prompt-head,
      .cgpt-prompt-foot,
      .cgpt-prompt-row-actions {
        display: flex;
        align-items: center;
        gap: 6px;
      }
      .cgpt-prompt-head {
        flex: 0 0 auto;
        justify-content: space-between;
        font-weight: 600;
        padding: 0 2px;
      }
      .cgpt-prompt-head span:last-child,
      .cgpt-prompt-foot {
        flex-wrap: wrap;
        justify-content: flex-end;
      }
      .cgpt-prompt-head small {
        color: var(--text-tertiary, #888);
        font-weight: 400;
      }
      #${PROMPT_PANEL_ID} button {
        border: 0;
        border-radius: 10px;
        padding: 7px 9px;
        color: inherit;
        background: transparent;
        cursor: pointer;
        text-align: left;
      }
      #${PROMPT_PANEL_ID} button:hover {
        background: var(--sidebar-surface-secondary, rgba(0,0,0,.06));
      }
      #${PROMPT_PANEL_ID} button:disabled {
        opacity: .55;
        cursor: progress;
      }
      #${PROMPT_PANEL_ID} .cgpt-prompt-primary {
        background: var(--sidebar-surface-secondary, rgba(0,0,0,.08));
        font-weight: 600;
      }
      #${PROMPT_PANEL_ID} .cgpt-prompt-help-button {
        width: 30px;
        padding: 7px 0;
        border-radius: 999px;
        text-align: center;
        font-weight: 700;
      }
      .cgpt-prompt-help {
        flex: 0 0 auto;
        padding: 10px 12px;
        border: 1px solid color-mix(in srgb, currentColor 10%, transparent);
        border-radius: 12px;
        background: var(--sidebar-surface-secondary, rgba(0,0,0,.04));
        font-size: 12px;
        line-height: 1.55;
      }
      .cgpt-prompt-help strong {
        display: block;
        margin-bottom: 4px;
        font-size: 13px;
      }
      .cgpt-prompt-help p {
        margin: 4px 0;
      }
      .cgpt-prompt-help ul {
        margin: 5px 0;
        padding-left: 18px;
      }
      .cgpt-prompt-help small {
        color: var(--text-tertiary, #777);
      }
      #${PROMPT_PANEL_ID} .cgpt-danger {
        color: #e03131;
      }
      .cgpt-prompt-list {
        flex: 1 1 auto;
        min-height: 42px;
        display: flex;
        flex-direction: column;
        gap: 4px;
        max-height: none;
        overflow: auto;
      }
      .cgpt-prompt-row {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        gap: 8px;
        align-items: center;
        padding: 6px;
        border-radius: 12px;
        cursor: pointer;
      }
      .cgpt-prompt-row:hover,
      .cgpt-prompt-row:focus-visible {
        background: var(--sidebar-surface-secondary, rgba(0,0,0,.06));
        outline: none;
      }
      .cgpt-prompt-insert {
        min-width: 0;
        display: grid;
        gap: 3px;
      }
      .cgpt-prompt-title {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-weight: 600;
      }
      .cgpt-prompt-cloud-badge {
        display: inline-flex;
        margin-left: 6px;
        padding: 1px 5px;
        border-radius: 999px;
        color: #2563eb;
        background: rgba(37, 99, 235, .1);
        font-size: 11px;
        font-weight: 500;
        vertical-align: 1px;
      }
      .cgpt-prompt-preview,
      .cgpt-prompt-empty {
        color: var(--text-tertiary, #888);
        font-size: 12px;
        line-height: 1.35;
      }
      .cgpt-prompt-preview {
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
      }
      .cgpt-prompt-row-actions {
        opacity: .78;
      }
      .cgpt-prompt-row:hover .cgpt-prompt-row-actions,
      .cgpt-prompt-row:focus-visible .cgpt-prompt-row-actions {
        opacity: 1;
      }
      .cgpt-prompt-row-actions button {
        padding: 6px 8px;
        white-space: nowrap;
      }
      .cgpt-prompt-editor {
        flex: 0 0 auto;
        display: grid;
        gap: 8px;
        padding-top: 4px;
        max-height: min(360px, 52vh);
        overflow: auto;
      }
      .cgpt-prompt-editor input,
      .cgpt-prompt-editor textarea {
        width: 100%;
        box-sizing: border-box;
        padding: 9px 10px;
        border: 1px solid color-mix(in srgb, currentColor 12%, transparent);
        border-radius: 10px;
        color: inherit;
        background: var(--main-surface-primary, Canvas);
        font: inherit;
      }
      .cgpt-prompt-editor textarea {
        min-height: 120px;
        max-height: min(220px, 34vh);
        resize: vertical;
        line-height: 1.45;
      }
      .cgpt-prompt-foot {
        position: sticky;
        bottom: 0;
        z-index: 1;
        padding-top: 6px;
        background: var(--main-surface-primary, Canvas);
      }

      .${IMAGE_DOWNLOAD_SLOT_CLASS} {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        margin-inline-start: 2px;
        vertical-align: middle;
      }
      .${IMAGE_DOWNLOAD_SLOT_CLASS}.cgpt-image-download-fallback {
        display: flex;
        margin: 7px 0 2px;
      }
      .${TEXT_DOWNLOAD_SLOT_CLASS} {
        display: inline-flex;
        align-items: center;
        margin-inline-start: 4px;
        vertical-align: middle;
      }
      .${IMAGE_DOWNLOAD_CLASS},
      .${WORK_PACKAGE_CLASS},
      .${TEXT_DOWNLOAD_CLASS} {
        position: relative;
        min-width: 34px;
        height: 34px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        padding: 0 7px;
        border: 0;
        border-radius: 10px;
        color: var(--text-primary, currentColor);
        background: transparent;
        font: inherit;
        font-size: 12px;
        line-height: 1;
        cursor: pointer;
      }
      .${IMAGE_DOWNLOAD_CLASS}:hover,
      .${WORK_PACKAGE_CLASS}:hover,
      .${TEXT_DOWNLOAD_CLASS}:hover {
        background: var(--sidebar-surface-tertiary, rgba(0,0,0,.08));
      }
      .${IMAGE_DOWNLOAD_CLASS}.cgpt-image-download-done {
        color: #16a34a;
        background: color-mix(in srgb, #16a34a 9%, transparent);
      }
      .${WORK_PACKAGE_CLASS}.cgpt-work-package-called {
        color: #2563eb;
        background: color-mix(in srgb, #2563eb 9%, transparent);
      }
      .${WORK_PACKAGE_CLASS}.cgpt-work-package-done {
        color: #16a34a;
        background: color-mix(in srgb, #16a34a 9%, transparent);
      }
      .${WORK_PACKAGE_CLASS}.cgpt-work-package-warning {
        color: #b45309;
        background: color-mix(in srgb, #f59e0b 12%, transparent);
      }
      .${WORK_PACKAGE_CLASS}[disabled] {
        opacity: .78;
        cursor: progress;
      }
      .${IMAGE_DOWNLOAD_CLASS}[disabled] {
        opacity: .58;
        cursor: progress;
      }
      .${IMAGE_DOWNLOAD_CLASS} svg,
      .${WORK_PACKAGE_CLASS} svg,
      .${TEXT_DOWNLOAD_CLASS} svg {
        width: 16px;
        height: 16px;
        flex: 0 0 16px;
        fill: none;
        stroke: currentColor;
        stroke-width: 1.65;
        stroke-linecap: round;
        stroke-linejoin: round;
      }
      .${IMAGE_DOWNLOAD_CLASS} .cgpt-image-download-count {
        min-width: 26px;
        font-size: 12px;
        font-weight: 600;
        line-height: 1;
        text-align: right;
        font-variant-numeric: tabular-nums;
      }
      .${IMAGE_DOWNLOAD_CLASS} .cgpt-image-download-status {
        white-space: nowrap;
        font-size: 12px;
        font-weight: 600;
        line-height: 1;
      }
      .${WORK_PACKAGE_CLASS} .cgpt-work-package-label {
        white-space: nowrap;
        font-size: 12px;
        font-weight: 600;
        line-height: 1;
      }
      #${IMAGE_DOWNLOAD_TOAST_ID} {
        position: fixed;
        right: 18px;
        bottom: 18px;
        z-index: 2147483647;
        max-width: min(320px, calc(100vw - 36px));
        padding: 10px 13px;
        border: 1px solid color-mix(in srgb, currentColor 11%, transparent);
        border-radius: 12px;
        color: var(--text-primary, #111);
        background: var(--main-surface-primary, Canvas);
        box-shadow: 0 12px 34px rgba(0,0,0,.18);
        font-size: 13px;
        line-height: 1.35;
      }
      #${IMAGE_DOWNLOAD_TOAST_ID}.cgpt-image-download-toast-ok {
        border-color: color-mix(in srgb, #16a34a 34%, transparent);
      }
    `;
    document.head.append(style);
  }

  // ==========================================
  // 7. 提示词面板与输入框交互
  // ==========================================

  function ensurePromptPanel() {
    let panel = document.getElementById(PROMPT_PANEL_ID);
    if (panel) return panel;
    panel = document.createElement('section');
    panel.id = PROMPT_PANEL_ID;
    panel.hidden = true;
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', '提示词库');
    document.body.append(panel);
    return panel;
  }

  function promptComposerInput() {
    return document.querySelector('#prompt-textarea')
      || [...document.querySelectorAll('main textarea, form textarea, main [contenteditable="true"], form [contenteditable="true"]')]
        .find((element) => {
          if (element.closest?.(`#${PROMPT_PANEL_ID}`)) return false;
          const rect = element.getBoundingClientRect?.();
          return rect && rect.width > 160 && rect.height > 20 && isElementVisible(element);
        })
      || null;
  }

  function composerRootFor(element) {
    return element?.closest?.('form')
      || element?.closest?.('[data-testid*="composer"], [class*="composer"], main')
      || null;
  }

  function directChildContaining(parent, child) {
    if (!parent || !child || !parent.contains(child)) return null;
    let current = child;
    while (current?.parentElement && current.parentElement !== parent) {
      current = current.parentElement;
    }
    return current?.parentElement === parent ? current : null;
  }

  function findModelButton(composer) {
    if (!composer) return null;
    const buttons = [...composer.querySelectorAll('button')]
      .filter((button) => (
        button.id !== PROMPT_BUTTON_ID
        && !button.closest(`#${PROMPT_PANEL_ID}, .${IMAGE_DOWNLOAD_SLOT_CLASS}`)
        && isElementVisible(button)
      ));
    const byText = buttons.find((button) => /高级|模型|model|GPT|auto|thinking|reason|fast|legacy|standard|默认/i.test(
      compactTitle(`${button.innerText || ''} ${button.getAttribute('aria-label') || ''} ${button.title || ''}`)
    ));
    if (byText) return byText;
    return buttons.find((button) => {
      const rect = button.getBoundingClientRect();
      const inputRect = promptComposerInput()?.getBoundingClientRect?.();
      return inputRect && rect.left > inputRect.left + inputRect.width * 0.45 && rect.top > inputRect.top - 20;
    }) || null;
  }

  function promptButtonMount(modelButton, composer, input) {
    if (!modelButton) return null;
    let row = null;
    let parent = modelButton.parentElement;
    while (parent && parent !== composer && parent !== document.body) {
      const style = getComputedStyle(parent);
      const rect = parent.getBoundingClientRect?.();
      const isRow = (
        rect
        && rect.width > 120
        && rect.height < 88
        && (
          (style.display.includes('flex') && !style.flexDirection.startsWith('column'))
          || style.display.includes('grid')
        )
        && parent.querySelectorAll('button').length >= 2
      );
      if (isRow) {
        row = parent;
        break;
      }
      parent = parent.parentElement;
    }
    if (!row) return { parent: modelButton.parentElement, before: modelButton };
    const before = directChildContaining(row, modelButton) || modelButton;
    const inputChild = directChildContaining(row, input);
    if (inputChild && inputChild === before) return { parent: modelButton.parentElement, before: modelButton };
    return { parent: row, before };
  }

  function syncPromptButtonStyle(button, modelButton) {
    if (!button || !modelButton?.isConnected) return;
    try {
      const style = getComputedStyle(modelButton);
      const rect = modelButton.getBoundingClientRect?.();
      button.style.fontSize = style.fontSize || '';
      button.style.fontWeight = style.fontWeight || '';
      button.style.fontFamily = style.fontFamily || '';
      button.style.lineHeight = style.lineHeight || '';
      button.style.color = style.color || '';
      button.style.height = rect?.height ? `${Math.round(rect.height)}px` : style.height || '';
      button.style.paddingTop = style.paddingTop || '0px';
      button.style.paddingBottom = style.paddingBottom || '0px';
      button.style.paddingLeft = '4px';
      button.style.paddingRight = '4px';
      button.style.marginTop = style.marginTop || '';
      button.style.marginBottom = style.marginBottom || '';
    } catch {}
  }

  function ensurePromptButton() {
    const input = promptComposerInput();
    if (!input) return false;
    const composer = composerRootFor(input);
    if (!composer) return false;

    let button = document.getElementById(PROMPT_BUTTON_ID);
    if (!button) {
      button = document.createElement('button');
      button.id = PROMPT_BUTTON_ID;
      button.type = 'button';
      button.textContent = '提示词';
      button.title = '打开提示词库';
      button.setAttribute('aria-haspopup', 'dialog');
      button.setAttribute('aria-expanded', 'false');
      button.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        togglePromptPanel(button);
      }, true);
    }

    const modelButton = findModelButton(composer);
    const mount = promptButtonMount(modelButton, composer, input);
    const targetParent = mount?.parent
      || [...composer.querySelectorAll('div')].reverse().find((element) => (
        element.querySelectorAll('button').length >= 2 && element.contains(input) === false
      ))
      || input.parentElement;

    if (!targetParent) return false;
    syncPromptButtonStyle(button, modelButton);
    if (mount?.before && mount.parent === targetParent) {
      if (button.parentElement !== targetParent || button.nextSibling !== mount.before) {
        targetParent.insertBefore(button, mount.before);
      }
    } else if (button.parentElement !== targetParent) {
      targetParent.insertBefore(button, targetParent.firstChild || null);
    }
    return true;
  }

  function schedulePromptButton(delay = 180) {
    window.clearTimeout(promptButtonTimer);
    promptButtonTimer = window.setTimeout(() => {
      runWhenIdle(() => ensurePromptButton(), 700);
    }, delay);
  }

  function closePromptPanel() {
    const panel = document.getElementById(PROMPT_PANEL_ID);
    const button = document.getElementById(PROMPT_BUTTON_ID);
    if (panel) panel.hidden = true;
    if (button) button.setAttribute('aria-expanded', 'false');
    editingPromptId = '';
  }

  function positionPromptPanel(button = null) {
    const panel = document.getElementById(PROMPT_PANEL_ID);
    const anchor = button || panel?.__cgptPromptAnchor || document.getElementById(PROMPT_BUTTON_ID);
    if (!panel || panel.hidden || !anchor?.isConnected) return;
    const rect = anchor.getBoundingClientRect();
    const availableAbove = Math.max(220, rect.top - 12);
    panel.style.top = 'auto';
    panel.style.maxHeight = `${Math.min(620, availableAbove)}px`;
    panel.style.bottom = `${Math.max(8, innerHeight - rect.top + 8)}px`;
    const width = panel.offsetWidth || 420;
    panel.style.left = `${Math.max(8, Math.min(innerWidth - width - 8, rect.left + rect.width - width))}px`;
  }

  function togglePromptPanel(button) {
    const panel = ensurePromptPanel();
    if (!panel.hidden) {
      closePromptPanel();
      return;
    }
    panel.__cgptPromptAnchor = button;
    editingPromptId = '';
    renderPromptPanel();
    panel.hidden = false;
    positionPromptPanel(button);
    button.setAttribute('aria-expanded', 'true');
  }

  function renderPromptPanel() {
    const panel = ensurePromptPanel();
    const visibleItems = visiblePromptItems();
    const editing = editingPromptId
      ? promptState.items.find((item) => item.id === editingPromptId)
      : null;
    const editorTitle = editingPromptId === 'new' ? '新建提示词' : '编辑提示词';
    const list = visibleItems.length ? visibleItems.map((item) => `
      <div class="cgpt-prompt-row"
           data-cgpt-prompt-action="insert"
           data-prompt-id="${escapeHtml(item.id)}"
           role="button"
           tabindex="0"
           title="插入输入框：${escapeHtml(item.title)}">
        <div class="cgpt-prompt-insert">
          <span class="cgpt-prompt-title">${escapeHtml(item.title)}${item.source === 'cloud' ? '<span class="cgpt-prompt-cloud-badge">云端</span>' : ''}</span>
          <span class="cgpt-prompt-preview">${escapeHtml(item.content || '空内容')}</span>
        </div>
        ${item.source === 'cloud' ? '' : `<span class="cgpt-prompt-row-actions">
          <button data-cgpt-prompt-action="edit" data-prompt-id="${escapeHtml(item.id)}">编辑</button>
          <button class="cgpt-danger" data-cgpt-prompt-action="delete" data-prompt-id="${escapeHtml(item.id)}">删除</button>
        </span>`}
      </div>`).join('') : '<div class="cgpt-prompt-empty">还没有提示词。点“新增”创建，或点“同步云端”从 GitHub 拉取。</div>';

    const editingTitle = editing?.title || '';
    const editingContent = editing?.content || '';
    panel.innerHTML = `
      <div class="cgpt-prompt-head">
        <span>提示词库 <small>${cloudPromptStatusText()}</small></span>
        <span>
          <button data-cgpt-prompt-action="new">＋ 新增</button>
          <button data-cgpt-prompt-action="sync-cloud" ${cloudPromptSyncing ? 'disabled' : ''}>${cloudPromptSyncing ? '同步中…' : '☁ 同步'}</button>
          <button class="cgpt-prompt-help-button" data-cgpt-prompt-action="toggle-help" aria-label="提示词库说明" title="提示词库说明">?</button>
          ${cloudPromptBackupCount() ? '<button data-cgpt-prompt-action="restore-cloud">↶ 回退</button>' : ''}
          <button data-cgpt-prompt-action="export-cloud">导出云端文件</button>
          <button data-cgpt-prompt-action="close">关闭</button>
        </span>
      </div>
      ${promptHelpVisible ? `
        <div class="cgpt-prompt-help">
          <strong>这个提示词库如何工作？</strong>
          <p><b>开发初衷：</b>在尽量保留 ChatGPT 原生体验的前提下，把常用提示词和作品生产集中成一个贴着网页生长的生产力工具。</p>
          <ul>
            <li><b>GitHub 云端库：</b>相当于维护的官方公共库；“同步”只会从云端拉取。</li>
            <li><b>浏览器本地库：</b>相当于个人自建库；新增、编辑和删除都只影响当前浏览器。</li>
            <li><b>合并规则：</b>两套数据一起显示；标题和内容完全相同时优先显示本地版本。</li>
            <li><b>安全设计：</b>云端同步不会覆盖本地库，并保留缓存和可回退版本。</li>
          </ul>
          <small>网页中新增提示词不会自动上传 GitHub；“导出云端文件”只生成 JSON 文件，也不会自动上传。</small>
        </div>
      ` : ''}
      <div class="cgpt-prompt-list">${list}</div>
      ${editingPromptId ? `
        <div class="cgpt-prompt-editor">
          <div>${editorTitle}</div>
          <input data-cgpt-prompt-title placeholder="标题" value="${escapeHtml(editingTitle)}">
          <textarea data-cgpt-prompt-content placeholder="提示词内容">${escapeHtml(editingContent)}</textarea>
          <div class="cgpt-prompt-foot">
            <button class="cgpt-prompt-primary" data-cgpt-prompt-action="save">保存</button>
            <button data-cgpt-prompt-action="cancel">取消</button>
          </div>
        </div>
      ` : ''}`;
    positionPromptPanel();
  }

  function upsertPromptFromPanel() {
    const panel = ensurePromptPanel();
    const titleInput = panel.querySelector('[data-cgpt-prompt-title]');
    const contentInput = panel.querySelector('[data-cgpt-prompt-content]');
    const content = String(contentInput?.value || '').trim();
    const title = compactTitle(titleInput?.value || content.slice(0, 32));
    if (!content) {
      window.alert('提示词内容不能为空。');
      return;
    }
    const now = Date.now();
    if (editingPromptId && editingPromptId !== 'new') {
      const item = promptState.items.find((candidate) => candidate.id === editingPromptId);
      if (item) {
        item.title = title || item.title;
        item.content = content;
        item.updatedAt = now;
      }
    } else {
      promptState.items.unshift({
        id: uid('prompt'),
        title: title || '未命名提示词',
        content,
        createdAt: now,
        updatedAt: now,
      });
    }
    savePromptState();
    editingPromptId = '';
    renderPromptPanel();
  }

  function deletePrompt(promptId) {
    const item = promptState.items.find((candidate) => candidate.id === promptId);
    if (!item) return;
    if (!window.confirm(`删除提示词“${item.title}”？`)) return;
    promptState.items = promptState.items.filter((candidate) => candidate.id !== promptId);
    savePromptState();
    renderPromptPanel();
  }

  function dispatchPasteLikeInput(input, text) {
    try {
      input.dispatchEvent(new InputEvent('beforeinput', {
        bubbles: true,
        cancelable: true,
        composed: true,
        inputType: 'insertFromPaste',
        data: text,
      }));
    } catch {}
    try {
      input.dispatchEvent(new InputEvent('input', {
        bubbles: true,
        composed: true,
        inputType: 'insertFromPaste',
        data: text,
      }));
    } catch {
      input.dispatchEvent(new Event('input', { bubbles: true }));
    }
  }

  function fastPasteIntoContentEditable(input, text) {
    if (!input?.isContentEditable) return false;
    input.focus();
    const selection = window.getSelection();
    if (!selection) return false;
    if (!selection.rangeCount || !input.contains(selection.anchorNode)) {
      const range = document.createRange();
      range.selectNodeContents(input);
      range.collapse(false);
      selection.removeAllRanges();
      selection.addRange(range);
    }
    const range = selection.rangeCount ? selection.getRangeAt(0) : document.createRange();
    range.deleteContents();
    range.insertNode(document.createTextNode(text));
    range.collapse(false);
    selection.removeAllRanges();
    selection.addRange(range);
    dispatchPasteLikeInput(input, text);
    return true;
  }

  function insertTextIntoComposer(text) {
    const input = promptComposerInput();
    if (!input) {
      window.alert('没有找到 ChatGPT 输入框。');
      return false;
    }
    input.focus();
    if (input instanceof HTMLTextAreaElement || input instanceof HTMLInputElement) {
      const start = input.selectionStart ?? input.value.length;
      const end = input.selectionEnd ?? input.value.length;
      input.setRangeText(text, start, end, 'end');
      dispatchPasteLikeInput(input, text);
      return true;
    }
    const selection = window.getSelection();
    if (selection && input.isContentEditable) {
      if (String(text || '').length > 800 && fastPasteIntoContentEditable(input, text)) {
        return true;
      }
      if (!selection.rangeCount || !input.contains(selection.anchorNode)) {
        const range = document.createRange();
        range.selectNodeContents(input);
        range.collapse(false);
        selection.removeAllRanges();
        selection.addRange(range);
      }
      const range = selection.rangeCount ? selection.getRangeAt(0) : document.createRange();
      range.deleteContents();
      const lines = String(text || '').split('\n');
      const fragment = document.createDocumentFragment();
      lines.forEach((line, index) => {
        if (index > 0) fragment.append(document.createElement('br'));
        if (line) fragment.append(document.createTextNode(line));
      });
      range.insertNode(fragment);
      range.collapse(false);
      selection.removeAllRanges();
      selection.addRange(range);
      dispatchPasteLikeInput(input, text);
      return true;
    }
    return false;
  }

  function insertPrompt(promptId) {
    const item = findPromptItem(promptId);
    if (!item?.content) return;
    const ok = insertTextIntoComposer(item.content);
    if (ok) {
      closePromptPanel();
      addDiagnosticLog('prompt:insert', {
        id: item.id,
        title: item.title,
        source: item.source || 'local',
      });
    }
  }

  // ==========================================
  // 8. 文本下载快捷按钮
  // ==========================================

  function showImageDownloadToast(message, ok = true) {
    let toast = document.getElementById(IMAGE_DOWNLOAD_TOAST_ID);
    if (!toast) {
      toast = document.createElement('div');
      toast.id = IMAGE_DOWNLOAD_TOAST_ID;
      toast.setAttribute('role', 'status');
      toast.setAttribute('aria-live', 'polite');
      document.body.append(toast);
    }
    toast.className = ok ? 'cgpt-image-download-toast-ok' : '';
    toast.textContent = message;
    window.clearTimeout(showImageDownloadToast.timer);
    showImageDownloadToast.timer = window.setTimeout(() => {
      toast.remove();
    }, 2000);
  }

  function textDownloadFilename(text = '') {
    const firstLine = String(text || '').split(/\r?\n/).map((line) => line.trim()).find(Boolean) || 'chatgpt-text';
    const safe = firstLine
      .replace(/[\\/:*?"<>|]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 42) || 'chatgpt-text';
    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    return `${safe}-${stamp}.txt`;
  }

  function textContentForDownload(card) {
    if (!card) return '';
    const clone = card.cloneNode(true);
    clone.querySelectorAll?.(`button, svg, .${TEXT_DOWNLOAD_SLOT_CLASS}, .${IMAGE_DOWNLOAD_SLOT_CLASS}, [aria-hidden="true"]`)
      .forEach((element) => element.remove());
    return String(clone.innerText || clone.textContent || '')
      .replace(/^\s*(text|txt|文本)\s*/i, '')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  function textCardForCopyButton(copyButton) {
    if (!copyButton || copyButton.closest?.(`.${TEXT_DOWNLOAD_SLOT_CLASS}, .${IMAGE_DOWNLOAD_SLOT_CLASS}`)) return null;
    const candidates = [];
    let node = copyButton.parentElement;
    for (let depth = 0; node && depth < 7; depth += 1, node = node.parentElement) {
      if (node.matches?.('main, article, [data-testid^="conversation-turn"], [data-message-author-role]')) break;
      if (node.querySelector?.('img')) continue;
      const rect = node.getBoundingClientRect?.();
      if (!rect || rect.width < 160 || rect.height < 42 || rect.height > 360) continue;
      const text = textContentForDownload(node);
      if (text.length < 12) continue;
      const buttonCount = node.querySelectorAll?.('button')?.length || 0;
      const hasTextBadge = /\b(text|txt)\b|文本/i.test(elementText(node));
      const score = (hasTextBadge ? 40 : 0)
        + (rect.height < 220 ? 12 : 0)
        + (buttonCount <= 4 ? 10 : 0)
        - Math.max(0, rect.height - 180) / 20;
      candidates.push({ node, score });
    }
    return candidates.sort((a, b) => b.score - a.score)[0]?.node || null;
  }

  function ensureTextDownloadButton(card, copyButton) {
    if (!card || !copyButton) return;
    let slot = copyButton.parentElement?.querySelector?.(`:scope > .${TEXT_DOWNLOAD_SLOT_CLASS}`) || null;
    if (!slot && copyButton.nextElementSibling?.classList?.contains(TEXT_DOWNLOAD_SLOT_CLASS)) {
      slot = copyButton.nextElementSibling;
    }
    if (!slot) {
      slot = document.createElement('span');
      slot.className = TEXT_DOWNLOAD_SLOT_CLASS;
      copyButton.insertAdjacentElement('afterend', slot);
    }
    let button = slot.querySelector(`.${TEXT_DOWNLOAD_CLASS}`);
    if (!button) {
      button = document.createElement('button');
      button.type = 'button';
      button.className = TEXT_DOWNLOAD_CLASS;
      button.title = '下载这个文本为 TXT';
      button.setAttribute('aria-label', '下载 TXT');
      button.innerHTML = icons.download;
      slot.append(button);
    }
    button.__cgptTextDownloadCard = card;
  }

  function refreshTextDownloadButtons() {
    const main = document.querySelector('main') || document.body;
    [...main.querySelectorAll(`.${TEXT_DOWNLOAD_SLOT_CLASS}`)].forEach((slot) => {
      const copyButton = slot.previousElementSibling;
      const card = copyButton ? textCardForCopyButton(copyButton) : null;
      if (!card) slot.remove();
    });
    [...main.querySelectorAll('button')].forEach((button) => {
      if (!isElementVisible(button) || button.closest?.(`#${MENU_ID}, .${IMAGE_DOWNLOAD_SLOT_CLASS}, .${TEXT_DOWNLOAD_SLOT_CLASS}`)) return;
      const label = elementText(button);
      if (!/\u590d\u5236|copy/i.test(label)) return;
      const card = textCardForCopyButton(button);
      if (!card) return;
      ensureTextDownloadButton(card, button);
    });
  }

  function triggerTextDownloadButton(button, event = null) {
    if (!button) return;
    event?.preventDefault?.();
    event?.stopPropagation?.();
    event?.stopImmediatePropagation?.();
    const card = button.__cgptTextDownloadCard || textCardForCopyButton(button.closest?.(`.${TEXT_DOWNLOAD_SLOT_CLASS}`)?.previousElementSibling);
    const text = textContentForDownload(card);
    if (!text) {
      window.alert('这个文本框里暂时没有找到可下载的文本。');
      return;
    }
    const blob = new Blob([`${text}\n`], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = textDownloadFilename(text);
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 800);
    showImageDownloadToast('TXT 下载完成', true);
  }

  // ==========================================
  // 9. 图片组识别、批量下载与本地作品包联动
  // ==========================================

  function setWorkPackageHelperReady(ready) {
    workPackageHelperReady = Boolean(ready);
    try { GM_setValue(WORK_PACKAGE_HELPER_READY_KEY, workPackageHelperReady); } catch {}
  }

  function downloadWorkPackageInstaller() {
    const fallback = () => window.open(WORK_PACKAGE_INSTALLER_URL, '_blank', 'noopener');
    if (typeof GM_download !== 'function') {
      fallback();
      return;
    }
    showImageDownloadToast('正在下载“安装GPT作品助手.vbs”...', true);
    GM_download({
      url: WORK_PACKAGE_INSTALLER_URL,
      name: '安装GPT作品助手.vbs',
      saveAs: false,
      onload: () => {
        showImageDownloadToast('安装脚本已下载，请双击运行一次', true);
        window.alert(
          '安装脚本已下载到浏览器下载目录。\n\n请双击“安装GPT作品助手.vbs”一次，安装完成后回到 ChatGPT 再点“下载并打包”。\n\n默认位置：\n图片：Windows 下载文件夹\n作品：文档\\GPT作品库\n去重数据：作品库\\_作品历史数据'
        );
      },
      onerror: () => {
        showImageDownloadToast('自动下载失败，已打开手动下载页', false);
        fallback();
      },
    });
  }

  function showWorkPackageFirstUseDialog() {
    return new Promise((resolve) => {
      const old = document.getElementById(`${APP_ID}-work-package-first-use`);
      old?.remove();
      const overlay = document.createElement('div');
      overlay.id = `${APP_ID}-work-package-first-use`;
      overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483646;background:rgba(0,0,0,.34);display:flex;align-items:center;justify-content:center;padding:20px';
      overlay.innerHTML = `
        <section role="dialog" aria-modal="true" aria-label="首次使用 GPT 作品助手" style="width:min(440px,calc(100vw - 32px));background:var(--main-surface-primary,#fff);color:var(--text-primary,#0d0d0d);border:1px solid rgba(127,127,127,.25);border-radius:18px;box-shadow:0 18px 60px rgba(0,0,0,.22);padding:22px;font:14px/1.6 system-ui,-apple-system,sans-serif">
          <h2 style="font-size:18px;margin:0 0 8px">首次使用需要安装本地作品助手</h2>
          <p style="margin:0 0 10px">网页负责下载图片，本地助手负责去重、整理和打包。只需下载安装脚本并双击一次。</p>
          <div style="background:rgba(127,127,127,.09);border-radius:12px;padding:10px 12px;margin-bottom:16px">
            <div>图片：Windows 下载文件夹</div>
            <div>作品：文档\\GPT作品库</div>
            <div>去重数据：作品库\\_作品历史数据</div>
          </div>
          <div style="display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap">
            <button data-action="cancel" style="border:0;background:transparent;padding:8px 12px;cursor:pointer">取消</button>
            <button data-action="ready" style="border:1px solid rgba(127,127,127,.35);background:transparent;border-radius:10px;padding:8px 12px;cursor:pointer">我已安装，继续</button>
            <button data-action="install" style="border:0;background:#10a37f;color:#fff;border-radius:10px;padding:8px 14px;cursor:pointer">下载安装助手</button>
          </div>
        </section>`;
      const finish = (action) => {
        overlay.remove();
        resolve(action);
      };
      overlay.addEventListener('click', (event) => {
        const action = event.target.closest('[data-action]')?.dataset.action;
        if (action) finish(action);
        else if (event.target === overlay) finish('cancel');
      });
      document.body.append(overlay);
    });
  }

  async function ensureWorkPackageHelperReady() {
    if (workPackageHelperReady) return true;
    const action = await showWorkPackageFirstUseDialog();
    if (action === 'install') {
      downloadWorkPackageInstaller();
      return false;
    }
    if (action === 'ready') {
      setWorkPackageHelperReady(true);
      return true;
    }
    return false;
  }

  async function freezeWorkPackageTask(batchId, expectedImages) {
    if (!batchId || !navigator.clipboard?.readText) return null;
    let copyText = '';
    try {
      copyText = await navigator.clipboard.readText();
    } catch (error) {
      addDiagnosticLog('workpkg:task-clipboard-read-failed', {
        batchId,
        message: error?.message || String(error),
      });
      return null;
    }
    if (!copyText || !copyText.trim()) return null;

    const task = {
      schemaVersion: 1,
      taskId: batchId,
      batchId,
      status: 'queued',
      createdAt: new Date().toISOString(),
      expectedImages: Math.max(0, Number(expectedImages || 0)),
      copyText,
      copyTitle: compactTitle(copyText.split(/\r?\n/).find((line) => line.trim()) || '').slice(0, 160),
      conversationTitle: currentWorkPackageConversationTitle(),
      accountName: currentWorkPackageAccountName(),
      conversationUrl: currentWorkPackageConversationUrl(),
      pageUrl: location.href,
      scriptVersion: SCRIPT_VERSION,
    };

    const blob = new Blob([JSON.stringify(task, null, 2)], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `chatgpt-workpkg-task-${batchId}.json`;
    anchor.rel = 'noopener';
    anchor.style.display = 'none';
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 3000);
    await sleep(180);
    addDiagnosticLog('workpkg:task-frozen', {
      batchId,
      expectedImages: task.expectedImages,
      copyTitle: task.copyTitle,
      conversationUrl: task.conversationUrl,
    });
    return task;
  }

  function openWorkPackageProtocol(url) {
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.rel = 'noopener';
    anchor.style.display = 'none';
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
  }

  function broadImageElements(scope = document, minSize = 24) {
    const root = scope === document ? (document.querySelector('main') || document.body) : scope;
    return [...root.querySelectorAll('img')].filter((img) => {
      if (img.closest?.(`#${MENU_ID}, .${IMAGE_DOWNLOAD_SLOT_CLASS}, .${TEXT_DOWNLOAD_SLOT_CLASS}`)) return false;
      if (img.closest?.('#history, nav, aside, [role="navigation"]')) return false;
      if (img.closest?.('[data-radix-menu-content], [data-radix-popper-content-wrapper]')) return false;
      const src = img.currentSrc || img.src || '';
      if (!src || /^data:image\/svg/i.test(src)) return false;
      const rect = img.getBoundingClientRect?.();
      if (!rect || rect.width < minSize || rect.height < minSize) return false;
      return isElementVisible(img);
    });
  }

  function contentImageElements(scope = document) {
    const root = scope === document ? (document.querySelector('main') || document.body) : scope;
    return [...root.querySelectorAll('img')].filter((img) => {
      if (img.closest?.(`#${MENU_ID}, .${IMAGE_DOWNLOAD_SLOT_CLASS}, .${TEXT_DOWNLOAD_SLOT_CLASS}`)) return false;
      if (img.closest?.('#history, nav, aside, [role="navigation"]')) return false;
      if (img.closest?.('[data-radix-menu-content], [data-radix-popper-content-wrapper]')) return false;
      const src = img.currentSrc || img.src || '';
      if (!src || /^data:image\/svg/i.test(src)) return false;
      const rect = img.getBoundingClientRect?.();
      if (!rect || rect.width < 105 || rect.height < 105) return false;
      return isElementVisible(img);
    });
  }

  function imageTurnContainer(img) {
    return img.closest?.('[data-testid^="conversation-turn"], [data-message-author-role], article, [class*="group/conversation-turn"]')
      || img.closest?.('main > div > div > div')
      || img.parentElement;
  }

  function countFromText(text) {
    const source = compactTitle(text || '');
    const patterns = [
      /\b\d+\s*\/\s*(\d+)\b/,
      /(?:本组|共|全部|total|all|of)\D{0,8}(\d{1,3})\D{0,6}(?:张|图|image|images)/i,
      /(?:下载|download)\D{0,8}(\d{1,3})\D{0,6}(?:张|图|image|images)/i,
      /(?:第|image|图片)\D{0,4}\d{1,3}\D{0,5}(?:共|of|\/)\D{0,4}(\d{1,3})/i,
    ];
    for (const pattern of patterns) {
      const match = source.match(pattern);
      const value = Number(match?.[1]);
      if (Number.isFinite(value) && value > 1 && value < 100) return value;
    }
    return 0;
  }

  function inferDeclaredImageCount(container, row) {
    const bits = [];
    const scopes = [container, row].filter(Boolean);
    scopes.forEach((scope) => {
      bits.push(elementText(scope));
      scope.querySelectorAll?.('[aria-label], [title], [alt], button, [role="button"]')
        .forEach((element) => {
          bits.push(elementText(element));
          bits.push(element.getAttribute?.('alt') || '');
        });
    });
    const declared = countFromText(bits.join(' '));
    if (declared) return declared;

    const candidates = broadImageElements(container || document, 24);
    let maxIndex = 0;
    candidates.forEach((img) => {
      const text = [
        img.getAttribute('aria-label'),
        img.getAttribute('title'),
        img.getAttribute('alt'),
        img.closest?.('button, [role="button"]')?.getAttribute?.('aria-label'),
      ].filter(Boolean).join(' ');
      const value = countFromText(text);
      if (value > maxIndex) maxIndex = value;
    });
    return maxIndex;
  }

  function findImageActionRow(container) {
    const buttons = [...container.querySelectorAll('button')]
      .filter((button) => !button.closest(`.${IMAGE_DOWNLOAD_SLOT_CLASS}, .${TEXT_DOWNLOAD_SLOT_CLASS}`));
    const scored = buttons.map((button) => {
      const text = elementText(button);
      const score = /\u590d\u5236|copy|\u66f4\u591a|more|\u9009\u9879|options|\u5206\u4eab|share/i.test(text) ? 10 : 0;
      return { button, score };
    }).sort((a, b) => b.score - a.score);

    for (const { button } of scored) {
      let row = button.parentElement;
      for (let depth = 0; row && depth < 4; depth += 1, row = row.parentElement) {
        if (row === container || row.querySelector?.('img')) continue;
        const rowButtons = row.querySelectorAll?.('button') || [];
        if (rowButtons.length >= 1 && rowButtons.length <= 8) return row;
      }
    }
    return null;
  }

  function isLikelyImageActionRow(row) {
    if (!row || !row.isConnected) return false;
    if (row.closest?.(`#${MENU_ID}, #history, nav, aside, [role="navigation"]`)) return false;
    if (row.querySelector?.('img')) return false;
    const rect = row.getBoundingClientRect?.();
    if (!rect || rect.width < 34 || rect.height < 18 || rect.height > 72) return false;
    const buttons = [...row.querySelectorAll('button')]
      .filter((button) => !button.closest(`.${IMAGE_DOWNLOAD_SLOT_CLASS}, .${TEXT_DOWNLOAD_SLOT_CLASS}`) && isElementVisible(button));
    if (buttons.length < 1 || buttons.length > 8) return false;
    const rowText = elementText(row);
    const hasKnownAction = buttons.some((button) => {
      const text = elementText(button);
      return /\u590d\u5236|copy|\u66f4\u591a|more|\u9009\u9879|options|\u6765\u6e90|source|\u5206\u652f|branch/i.test(text)
        || button.querySelectorAll('svg circle').length >= 2;
    });
    return hasKnownAction || /\u67e5\u770b\u6765\u6e90|\u5206\u652f|source|branch/i.test(rowText);
  }

  function actionRowsOnPage() {
    const main = document.querySelector('main') || document.body;
    const rows = new Set();
    [...main.querySelectorAll('button')].forEach((button) => {
      if (!isElementVisible(button) || button.closest(`.${IMAGE_DOWNLOAD_SLOT_CLASS}, .${TEXT_DOWNLOAD_SLOT_CLASS}`)) return;
      let row = button.parentElement;
      for (let depth = 0; row && depth < 5; depth += 1, row = row.parentElement) {
        if (isLikelyImageActionRow(row)) {
          rows.add(row);
          break;
        }
      }
    });
    return [...rows];
  }

  function overlapRatio(a, b) {
    const overlap = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left));
    return overlap / Math.max(1, Math.min(a.width, b.width));
  }

  function nearbyImagesForActionRow(row) {
    const rowRect = row.getBoundingClientRect();
    const maxActionGap = Math.max(96, Math.min(170, innerHeight * 0.18));
    const sameTurn = row.closest?.('[data-testid^="conversation-turn"], [data-message-author-role], article, [class*="group/conversation-turn"]');
    if (!sameTurn) return null;
    const authorNode = sameTurn.matches?.('[data-message-author-role]')
      ? sameTurn
      : sameTurn.querySelector?.('[data-message-author-role]');
    const authorRole = authorNode?.getAttribute?.('data-message-author-role') || '';
    if (authorRole && authorRole !== 'assistant') return null;
    const sameTurnImages = sameTurn
      ? broadImageElements(sameTurn, 24).filter((img) => {
          const rect = img.getBoundingClientRect();
          const gap = rowRect.top - rect.bottom;
          return gap > -70 && gap < maxActionGap && overlapRatio(rect, rowRect) > 0.08;
        })
      : [];
    if (sameTurnImages.length) {
      return { container: sameTurn, images: sameTurnImages };
    }
    return null;
  }

  function imageButtonLabel(count, downloaded = 0, busyText = '') {
    if (busyText) return busyText;
    const total = Math.max(0, Number(count || 0));
    if (!total) return '';
    const done = Math.max(0, Math.min(total, Number(downloaded || 0)));
    return `${done}/${total}`;
  }

  function imageButtonStatusText(state = 'idle') {
    if (state === 'running') return '下载中';
    if (state === 'done') return '下载完成';
    return '';
  }

  function ensureImageButtonLabels(button) {
    if (!button) return {};
    let status = button.querySelector('[data-cgpt-image-download-status]');
    let count = button.querySelector('[data-cgpt-image-download-label]');
    if (!status || !count) {
      button.innerHTML = `${icons.download}<span class="cgpt-image-download-status" data-cgpt-image-download-status hidden></span><span class="cgpt-image-download-count" data-cgpt-image-download-label hidden></span>`;
      status = button.querySelector('[data-cgpt-image-download-status]');
      count = button.querySelector('[data-cgpt-image-download-label]');
    }
    return { status, count };
  }

  function imageUrlForDirectDownload(img) {
    const src = img?.currentSrc || img?.src || '';
    if (!src || /^data:image\/svg/i.test(src)) return '';
    return src;
  }

  function uniqueImageUrls(images = []) {
    const urls = [];
    const seen = new Set();
    images.forEach((img) => {
      const url = imageUrlForDirectDownload(img);
      if (!url || seen.has(url)) return;
      seen.add(url);
      urls.push(url);
    });
    return urls;
  }

  function groupImageElements(scope = document) {
    const root = scope === document ? (document.querySelector('main') || document.body) : scope;
    return [...root.querySelectorAll('img')].filter((img) => {
      if (img.closest?.(`#${MENU_ID}, .${IMAGE_DOWNLOAD_SLOT_CLASS}, .${TEXT_DOWNLOAD_SLOT_CLASS}`)) return false;
      if (img.closest?.('#history, nav, aside, [role="navigation"]')) return false;
      if (img.closest?.('[data-radix-menu-content], [data-radix-popper-content-wrapper]')) return false;
      return Boolean(imageUrlForDirectDownload(img));
    });
  }

  function imageGroupElements(container, images = []) {
    return [...new Set([
      ...images,
      ...groupImageElements(container || document),
    ].filter((img) => img?.isConnected))];
  }

  function imageGroupUniqueCount(container, images = []) {
    const candidates = imageGroupElements(container, images);
    const urlCount = uniqueImageUrls(candidates).length;
    const declaredCount = inferDeclaredImageCount(container, null);
    return Math.max(urlCount || candidates.length, declaredCount);
  }

  function logImageDownloadStep(step, detail = {}) {
    try {
      console.info('[ChatGPT 图片下载快捷按钮]', step, detail);
      unsafeWindow.__cgptImageDownloadLastStep = {
        step,
        detail,
        time: new Date().toISOString(),
      };
    } catch {}
  }

  function setImageButtonProgress(button, downloaded, total, busy = false, forcedState = '') {
    const { status, count } = ensureImageButtonLabels(button);
    if (!button || !status || !count) return;
    const safeTotal = Math.max(0, Number(total || 0));
    const safeDownloaded = Math.max(0, Math.min(safeTotal || Number(downloaded || 0), Number(downloaded || 0)));
    button.dataset.cgptImageDownloaded = String(safeDownloaded);
    if (safeTotal) button.dataset.cgptImageTotal = String(safeTotal);
    const complete = safeTotal > 0 && safeDownloaded >= safeTotal;
    const state = forcedState || (busy ? 'running' : (complete ? 'done' : 'idle'));
    const statusText = imageButtonStatusText(state);
    const countText = imageButtonLabel(safeTotal, safeDownloaded);
    button.dataset.cgptBusyText = busy ? statusText : '';
    status.hidden = !statusText;
    status.textContent = statusText;
    count.hidden = !countText;
    count.textContent = countText;
    button.classList.toggle('cgpt-image-download-done', complete && !busy);
    if (safeTotal) {
      button.title = complete
        ? `已下载 ${safeDownloaded}/${safeTotal} 张图片；再次点击可重新下载`
        : `已下载 ${safeDownloaded}/${safeTotal} 张图片；点击可下载本组图片`;
    }
  }

  function newDownloadBatchId() {
    const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');
    const suffix = Math.random().toString(36).slice(2, 6).padEnd(4, '0');
    return `${stamp}-${suffix}`;
  }

  function directDownloadName(index, total, url, batchId) {
    let ext = 'jpg';
    try {
      const pathname = new URL(url, location.href).pathname;
      const match = pathname.match(/\.([a-z0-9]{3,5})(?:$|[?#])/i) || pathname.match(/\.([a-z0-9]{3,5})$/i);
      if (match?.[1] && !/html?|aspx?|php/i.test(match[1])) ext = match[1].toLowerCase();
    } catch {}
    return `chatgpt-workpkg-${batchId}-${String(index + 1).padStart(2, '0')}-of-${String(total).padStart(2, '0')}.${ext}`;
  }

  function gmDownload(url, name) {
    return new Promise((resolve) => {
      if (typeof GM_download === 'function' && !/^blob:/i.test(url)) {
        try {
          GM_download({
            url,
            name,
            saveAs: false,
            onload: () => resolve(true),
            onerror: (error) => {
              console.warn('[ChatGPT 图片下载] GM_download 失败，改用链接下载：', error);
              resolve(false);
            },
            ontimeout: () => resolve(false),
          });
          return;
        } catch (error) {
          console.warn('[ChatGPT 图片下载] GM_download 调用失败，改用链接下载：', error);
        }
      }
      try {
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = name;
        anchor.rel = 'noopener';
        anchor.style.display = 'none';
        document.body.append(anchor);
        anchor.click();
        anchor.remove();
        resolve(true);
      } catch (error) {
        console.warn('[ChatGPT 图片下载] 链接下载失败：', error);
        resolve(false);
      }
    });
  }

  async function downloadUrlsConcurrently(urls, onProgress = null, concurrency = 4, requestedBatchId = '') {
    const total = urls.length;
    const batchId = requestedBatchId || newDownloadBatchId();
    const limit = Math.max(1, Math.min(8, Number(concurrency || 4), total || 1));
    let nextIndex = 0;
    let ok = 0;
    const worker = async () => {
      while (nextIndex < total) {
        const index = nextIndex;
        nextIndex += 1;
        const success = await gmDownload(urls[index], directDownloadName(index, total, urls[index], batchId));
        if (success) ok += 1;
        if (onProgress) {
          try { onProgress(ok, total); } catch {}
        }
      }
    };
    await Promise.all(Array.from({ length: limit }, worker));
    return { ok, total, batchId };
  }

  async function directDownloadImages(images, onProgress = null, requestedBatchId = '') {
    const urls = [];
    const seen = new Set();
    images.forEach((img) => {
      const url = imageUrlForDirectDownload(img);
      if (!url || seen.has(url)) return;
      seen.add(url);
      urls.push(url);
    });
    const usableUrls = urls.filter((url) => !/^data:image\/svg/i.test(url));
    if (!usableUrls.length) return 0;
    if (onProgress) {
      try { onProgress(0, usableUrls.length); } catch {}
    }
    return downloadUrlsConcurrently(usableUrls, onProgress, 4, requestedBatchId);
  }

  async function runImageDownloadShortcut(button, requestedBatchId = '', onProgress = null) {
    if (button.disabled) return null;
    const container = button.__cgptImageDownloadContainer
      || button.closest('[data-cgpt-image-download-container]')
      || document;
    let images = [];
    if (Array.isArray(button.__cgptImageDownloadImages)) {
      images = button.__cgptImageDownloadImages.filter((img) => img?.isConnected);
    }
    if (!images.length) {
      images = groupImageElements(container);
    }
    if (!images.length) {
      window.alert('这个回复里暂时没有找到可下载的图片。');
      return null;
    }

    let totalImages = Number(button.dataset.cgptImageTotal || 0)
      || uniqueImageUrls(images).length
      || images.length;
    button.disabled = true;
    setImageButtonProgress(button, 0, totalImages, true);
    if (onProgress) {
      try { onProgress(0, totalImages); } catch {}
    }

    let downloaded = 0;
    try {
      logImageDownloadStep('开始直接下载', {
        imageCount: images.length,
        containerText: compactTitle(container.innerText || '').slice(0, 120),
      });
      const downloadResult = await directDownloadImages(images, (current, total) => {
        totalImages = total || totalImages;
        setImageButtonProgress(button, current, totalImages, true);
        if (onProgress) {
          try { onProgress(current, totalImages); } catch {}
        }
      }, requestedBatchId);
      downloaded = Number(downloadResult?.ok || 0);
      if (downloadResult?.batchId) {
        button.dataset.cgptWorkPackageBatchId = downloadResult.batchId;
      }
      if (!downloaded) {
        window.alert('下载失败了，可能是网络问题或者图片地址变了。');
      } else if (totalImages && downloaded >= totalImages) {
        showImageDownloadToast(`图片下载完成：${downloaded}/${totalImages}`, true);
      } else {
        showImageDownloadToast(`图片下载完成：${downloaded}/${totalImages || downloaded}，有图片未成功`, false);
      }
    } catch (error) {
      console.warn('[ChatGPT 图片下载快捷按钮] 下载失败：', error);
      window.alert('下载出错了，打开控制台看详细信息。');
    } finally {
      window.setTimeout(() => {
        button.disabled = false;
        setImageButtonProgress(button, downloaded, totalImages, false, downloaded ? 'done' : 'idle');
      }, 600);
    }
    return {
      downloaded,
      total: totalImages,
      batchId: button.dataset.cgptWorkPackageBatchId || requestedBatchId || '',
    };
  }

  function triggerImageDownloadButton(button, event = null) {
    if (!button || button.disabled) return;
    event?.preventDefault?.();
    event?.stopPropagation?.();
    event?.stopImmediatePropagation?.();
    logImageDownloadStep('外部按钮点击', {
      title: button.title,
      count: button.dataset.cgptImageCount,
    });
    runImageDownloadShortcut(button);
  }

  function setWorkPackageButtonState(button, state = 'idle', detail = {}) {
    if (!button) return;
    button.dataset.cgptWorkPackageState = state;
    button.classList.remove('cgpt-work-package-called', 'cgpt-work-package-done', 'cgpt-work-package-warning');
    button.disabled = ['preparing', 'downloading', 'packaging'].includes(state);
    if (state === 'preparing') {
      button.classList.add('cgpt-work-package-called');
      button.innerHTML = `${icons.package}<span class="cgpt-work-package-label">检查文案</span>`;
      button.title = '正在检查剪贴板文案';
      button.setAttribute('aria-label', '正在检查文案');
      return;
    }
    if (state === 'downloading') {
      const current = Math.max(0, Number(detail.current || 0));
      const total = Math.max(current, Number(detail.total || 0));
      button.classList.add('cgpt-work-package-called');
      button.innerHTML = `${icons.download}<span class="cgpt-work-package-label">下载 ${current}/${total || '?'}</span>`;
      button.title = `正在下载本组图片：${current}/${total || '?'}`;
      button.setAttribute('aria-label', button.title);
      return;
    }
    if (state === 'packaging') {
      button.classList.add('cgpt-work-package-called');
      button.innerHTML = `${icons.package}<span class="cgpt-work-package-label">打包中</span>`;
      button.title = '图片已下载，正在调用本地作品助手打包';
      button.setAttribute('aria-label', '正在打包作品文件夹');
      return;
    }
    if (state === 'needs-text') {
      button.classList.add('cgpt-work-package-warning');
      button.innerHTML = `${icons.package}<span class="cgpt-work-package-label">请先复制文案</span>`;
      button.title = '请先复制当前窗口的小红书文案，再点击下载并打包';
      button.setAttribute('aria-label', '请先复制文案');
      return;
    }
    if (state === 'done') {
      button.classList.add('cgpt-work-package-done');
      const total = Math.max(0, Number(detail.total || 0));
      const suffix = total ? ` ${total}/${total}` : '';
      button.innerHTML = `${icons.package}<span class="cgpt-work-package-label">完成${suffix}</span>`;
      button.title = total ? `下载并打包完成：${total}/${total} 张` : '下载并打包完成';
      button.setAttribute('aria-label', button.title);
      return;
    }
    button.innerHTML = `${icons.package}<span class="cgpt-work-package-label">下载并打包</span>`;
    button.title = '下载本组全部图片，并打包成作品文件夹';
    button.setAttribute('aria-label', '下载本组图片并打包成文件夹');
  }

  async function triggerWorkPackageButton(button, event = null) {
    if (!button || button.disabled) return;
    event?.preventDefault?.();
    event?.stopPropagation?.();
    event?.stopImmediatePropagation?.();
    if (!await ensureWorkPackageHelperReady()) {
      setWorkPackageButtonState(button, 'idle');
      return;
    }
    setWorkPackageButtonState(button, 'preparing');
    const slot = button.closest(`.${IMAGE_DOWNLOAD_SLOT_CLASS}`);
    const imageButton = slot?.querySelector(`.${IMAGE_DOWNLOAD_CLASS}`);
    const expectedImages = Number(imageButton?.dataset.cgptImageTotal || 0);
    const downloadedImages = Number(imageButton?.dataset.cgptImageDownloaded || 0);
    const batchId = imageButton?.dataset.cgptWorkPackageBatchId || newDownloadBatchId();
    const frozenTask = await freezeWorkPackageTask(batchId, expectedImages);
    if (!frozenTask) {
      showImageDownloadToast('请先复制当前窗口的小红书文案，再点“下载并打包”', false);
      setWorkPackageButtonState(button, 'needs-text');
      window.setTimeout(() => {
        if (button.dataset.cgptWorkPackageState === 'needs-text') {
          setWorkPackageButtonState(button, 'idle');
        }
      }, 2400);
      return;
    }
    showImageDownloadToast(`任务已冻结：${frozenTask.copyTitle || '已复制文案'} · ${expectedImages} 张`, true);

    if (imageButton && expectedImages > 0 && (
      downloadedImages < expectedImages
      || imageButton.dataset.cgptWorkPackageBatchId !== batchId
    )) {
      showImageDownloadToast(`先下载本组图片：${downloadedImages}/${expectedImages}`, true);
      setWorkPackageButtonState(button, 'downloading', { current: downloadedImages, total: expectedImages });
      const downloadResult = await runImageDownloadShortcut(imageButton, batchId, (current, total) => {
        setWorkPackageButtonState(button, 'downloading', { current, total });
      });
      if (!downloadResult || downloadResult.downloaded < downloadResult.total) {
        showImageDownloadToast('图片未下载完整，暂不打包', false);
        setWorkPackageButtonState(button, 'idle');
        return;
      }
      await sleep(450);
    }
    setWorkPackageButtonState(button, 'packaging');
    showImageDownloadToast('图片下载完成，正在打包成文件夹...', true);
    try {
      const protocolUrl = `${WORK_PACKAGE_PROTOCOL_URL}?batch=${encodeURIComponent(batchId)}&expected=${encodeURIComponent(expectedImages)}`;
      openWorkPackageProtocol(protocolUrl);
    } catch (error) {
      console.warn('[ChatGPT 作品包按钮] 调用本地协议失败：', error);
      window.alert('调用本地作品包脚本失败。请检查 cgpt-workpkg://run 协议是否已注册。');
      setWorkPackageButtonState(button, 'idle');
      return;
    }
    window.setTimeout(() => {
      setWorkPackageButtonState(button, 'done', { total: expectedImages });
      showImageDownloadToast('打包完成', true);
    }, 3600);
  }

  function ensureImageDownloadButton(container, images, preferredActionRow = null) {
    container.setAttribute('data-cgpt-image-download-container', 'true');
    let slot = container.querySelector(`.${IMAGE_DOWNLOAD_SLOT_CLASS}`);
    if (preferredActionRow && slot && slot.parentElement !== preferredActionRow) {
      slot.remove();
      slot = null;
    }
    if (!slot) {
      slot = document.createElement('span');
      slot.className = IMAGE_DOWNLOAD_SLOT_CLASS;
      const actionRow = preferredActionRow || findImageActionRow(container);
      if (actionRow) actionRow.append(slot);
      else {
        slot.classList.add('cgpt-image-download-fallback');
        container.append(slot);
      }
    }
    const groupElements = imageGroupElements(container, images);
    const count = imageGroupUniqueCount(container, images) || groupElements.length || images.length;
    let button = slot.querySelector(`.${IMAGE_DOWNLOAD_CLASS}`);
    if (!button) {
      button = document.createElement('button');
      button.type = 'button';
      button.className = IMAGE_DOWNLOAD_CLASS;
      button.setAttribute('aria-label', '下载本组图片');
      button.addEventListener('click', (event) => {
        triggerImageDownloadButton(button, event);
      }, true);
      slot.append(button);
    }
    button.hidden = !imageDownloadButtonVisible;
    let packageButton = slot.querySelector(`.${WORK_PACKAGE_CLASS}`);
    if (workPackageButtonVisible) {
      if (!packageButton) {
        packageButton = document.createElement('button');
        packageButton.type = 'button';
        packageButton.className = WORK_PACKAGE_CLASS;
        setWorkPackageButtonState(packageButton, 'idle');
        packageButton.addEventListener('click', (event) => {
          triggerWorkPackageButton(packageButton, event);
        }, true);
        slot.append(packageButton);
      }
      packageButton.onclick = (event) => triggerWorkPackageButton(packageButton, event);
    } else if (packageButton) {
      packageButton.remove();
    }
    slot.hidden = !imageDownloadButtonVisible && !workPackageButtonVisible;
    button.onclick = (event) => triggerImageDownloadButton(button, event);
    button.__cgptImageDownloadContainer = container;
    button.__cgptImageDownloadImages = groupElements;
    const declaredCount = Number(button.dataset.cgptExactCount || 0)
      || count
      || inferDeclaredImageCount(container, preferredActionRow || slot.parentElement);
    const totalCount = declaredCount || count || 0;
    const previousTotal = Number(button.dataset.cgptImageTotal || 0);
    if (!button.disabled && previousTotal && totalCount && previousTotal !== totalCount) {
      button.dataset.cgptImageDownloaded = '0';
    }
    button.dataset.cgptImageTotal = String(totalCount || '');
    button.dataset.cgptImageCount = String(totalCount || '');
    button.dataset.cgptImageElementCount = String(groupElements.length);
    button.title = declaredCount > 1
      ? `下载本组中的 ${declaredCount} 张图片`
      : '下载本组图片';
    if (!button.disabled) {
      const downloaded = Number(button.dataset.cgptImageDownloaded || 0);
      const countText = imageButtonLabel(totalCount, downloaded);
      const done = totalCount > 0 && downloaded >= totalCount;
      const statusText = imageButtonStatusText(done ? 'done' : 'idle');
      const status = `<span class="cgpt-image-download-status" data-cgpt-image-download-status${statusText ? '' : ' hidden'}>${escapeHtml(statusText)}</span>`;
      const badge = `<span class="cgpt-image-download-count" data-cgpt-image-download-label${countText ? '' : ' hidden'}>${escapeHtml(countText)}</span>`;
      button.innerHTML = `${icons.download}${status}${badge}`;
      button.classList.toggle('cgpt-image-download-done', done);
      if (downloaded) setImageButtonProgress(button, downloaded, totalCount, false);
    }
  }

  function refreshImageDownloadButtons() {
    const validSlots = new Set();
    const claimedContainers = new Set();
    actionRowsOnPage().forEach((row) => {
      const existingSlot = row.querySelector(`.${IMAGE_DOWNLOAD_SLOT_CLASS}`);
      const group = nearbyImagesForActionRow(row);
      if (!group?.images?.length) {
        existingSlot?.remove();
        return;
      }
      if (claimedContainers.has(group.container)) {
        existingSlot?.remove();
        return;
      }
      claimedContainers.add(group.container);
      const existingButton = existingSlot?.querySelector(`.${IMAGE_DOWNLOAD_CLASS}`);
      const currentElements = imageGroupElements(group.container, group.images);
      const currentCount = imageGroupUniqueCount(group.container, group.images) || currentElements.length;
      const previousElementCount = Number(existingButton?.dataset.cgptImageElementCount || 0);
      const previousCount = Number(existingButton?.dataset.cgptImageCount || 0);
      if (!existingButton || previousElementCount !== currentElements.length || previousCount !== currentCount) {
        ensureImageDownloadButton(group.container, group.images, row);
      }
      const activeSlot = row.querySelector(`.${IMAGE_DOWNLOAD_SLOT_CLASS}`);
      if (activeSlot) validSlots.add(activeSlot);
    });
    document.querySelectorAll(`.${IMAGE_DOWNLOAD_SLOT_CLASS}`).forEach((slot) => {
      if (!validSlots.has(slot)) slot.remove();
    });
    refreshTextDownloadButtons();
  }

  function scheduleImageDownloadButtons() {
    window.clearTimeout(imageToolsTimer);
    imageToolsTimer = window.setTimeout(() => {
      runWhenIdle(refreshImageDownloadButtons, 1200);
    }, 420);
  }

  function bindImageDownloadEvents() {
    if (imageEventsBound) return;
    imageEventsBound = true;
    document.addEventListener('click', (event) => {
      const workPackageButton = event.target.closest?.(`.${WORK_PACKAGE_CLASS}`);
      if (workPackageButton) {
        triggerWorkPackageButton(workPackageButton, event);
        return;
      }
      const textDownloadButton = event.target.closest?.(`.${TEXT_DOWNLOAD_CLASS}`);
      if (textDownloadButton) {
        triggerTextDownloadButton(textDownloadButton, event);
        return;
      }
      const imageDownloadButton = event.target.closest?.(`.${IMAGE_DOWNLOAD_CLASS}`);
      if (!imageDownloadButton) return;
      triggerImageDownloadButton(imageDownloadButton, event);
    }, true);
  }

  function installImageDownloadDebugApi() {
    try {
      unsafeWindow.CGPTImageDownloadDebug = {
        scan() {
          return [...document.querySelectorAll(`.${IMAGE_DOWNLOAD_CLASS}`)].map((button, index) => {
            const container = button.__cgptImageDownloadContainer
              || button.closest('[data-cgpt-image-download-container]');
            const images = container ? [
              ...contentImageElements(container),
              ...broadImageElements(container, 24),
            ] : [];
            const rect = button.getBoundingClientRect();
            return {
              index,
              title: button.title,
              text: compactTitle(button.textContent || ''),
              disabled: button.disabled,
              count: button.dataset.cgptImageCount || '',
              exactCount: button.dataset.cgptExactCount || '',
              uniqueUrls: uniqueImageUrls(images),
              rect: {
                x: Math.round(rect.x),
                y: Math.round(rect.y),
                w: Math.round(rect.width),
                h: Math.round(rect.height),
              },
              lastStep: unsafeWindow.__cgptImageDownloadLastStep || null,
            };
          });
        },
        click(index = 0) {
          const button = document.querySelectorAll(`.${IMAGE_DOWNLOAD_CLASS}`)[index];
          if (!button) return false;
          triggerImageDownloadButton(button);
          return true;
        },
        lastStep() {
          return unsafeWindow.__cgptImageDownloadLastStep || null;
        },
      };
    } catch {}
  }

  // ==========================================
  // 10. 油猴菜单命令与全量数据导出/导入
  // ==========================================

  function setImageDownloadButtonVisible(visible) {
    imageDownloadButtonVisible = Boolean(visible);
    try { GM_setValue(IMAGE_DOWNLOAD_VISIBLE_KEY, imageDownloadButtonVisible); } catch {}
    refreshImageDownloadButtons();
    showImageDownloadToast(
      imageDownloadButtonVisible ? '已显示单独下载按钮' : '已隐藏单独下载按钮',
      true
    );
    registerUserscriptMenuCommands();
  }

  function setWorkPackageButtonVisible(visible) {
    workPackageButtonVisible = Boolean(visible);
    try { GM_setValue(WORK_PACKAGE_VISIBLE_KEY, workPackageButtonVisible); } catch {}
    refreshImageDownloadButtons();
    showImageDownloadToast(
      workPackageButtonVisible ? '已显示下载并打包按钮' : '已隐藏下载并打包按钮',
      true
    );
    registerUserscriptMenuCommands();
  }

  function exportGroupData() {
    const legacyState = loadState();
    const legacyCounts = countStateItems(legacyState);
    const payload = {
      format: APP_ID,
      schemaVersion: 2,
      exportedAt: new Date().toISOString(),
      sourceHost: location.host,
      summary: {
        prompts: promptState.items.length,
        legacyFolders: legacyCounts.folders,
        legacyChats: legacyCounts.chats,
      },
      prompts: {
        version: 1,
        items: promptState.items.map((item) => ({ ...item })),
        updatedAt: promptState.updatedAt || 0,
      },
      legacySidebarState: legacyState,
    };
    const json = JSON.stringify(payload, null, 2);
    const blob = new Blob([json], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    anchor.href = url;
    anchor.download = `chatgpt-helper-data-${stamp}.json`;
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    showImageDownloadToast(`已导出数据（含 ${promptState.items.length} 条提示词与旧分组备份）`, true);
  }

  function ensureImportInput() {
    let input = document.getElementById(IMPORT_INPUT_ID);
    if (input) return input;
    input = document.createElement('input');
    input.id = IMPORT_INPUT_ID;
    input.type = 'file';
    input.accept = '.json,application/json';
    input.style.display = 'none';
    document.body.append(input);
    return input;
  }

  function chooseImportFile(mode = 'merge') {
    pendingImportMode = mode;
    const input = ensureImportInput();
    input.value = '';
    input.click();
  }

  async function handleImportFile(file) {
    if (!file) return;
    try {
      if (file.size > 5 * 1024 * 1024) {
        throw new Error('备份文件超过 5MB，已拒绝导入');
      }
      const raw = JSON.parse(await file.text());
      let importedPrompts = 0;
      if (raw && Array.isArray(raw.prompts?.items || raw.prompts || raw.items)) {
        const list = Array.isArray(raw.prompts?.items) ? raw.prompts.items : (Array.isArray(raw.prompts) ? raw.prompts : raw.items);
        const normalized = list.map((item) => normalizePromptItem(item)).filter(Boolean);
        if (pendingImportMode === 'replace') {
          promptState.items = normalized;
        } else {
          const existingIds = new Set(promptState.items.map((i) => i.id));
          normalized.forEach((item) => {
            if (!existingIds.has(item.id)) promptState.items.push(item);
          });
        }
        savePromptState();
        importedPrompts = normalized.length;
      }
      showImageDownloadToast(`导入完成：已导入 ${importedPrompts} 条提示词`, true);
      window.alert(`数据导入完成：共读取 ${importedPrompts} 条提示词。`);
    } catch (error) {
      window.alert(`导入失败：${error.message || '文件格式错误'}`);
    } finally {
      const input = document.getElementById(IMPORT_INPUT_ID);
      if (input) input.value = '';
    }
  }

  function compareVersions(v1, v2) {
    const p1 = String(v1 || '').split('.').map((n) => parseInt(n, 10) || 0);
    const p2 = String(v2 || '').split('.').map((n) => parseInt(n, 10) || 0);
    const len = Math.max(p1.length, p2.length);
    for (let i = 0; i < len; i += 1) {
      const a = p1[i] || 0;
      const b = p2[i] || 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }

  async function checkUserscriptUpdate(manual = true) {
    if (manual) showImageDownloadToast('正在连接 GitHub 检查脚本更新…', true);
    addDiagnosticLog('update:check-start', { currentVersion: SCRIPT_VERSION, manual });
    try {
      const url = `${USERSCRIPT_RAW_URL}?ts=${Date.now()}`;
      let text = '';
      if (typeof GM_xmlhttpRequest === 'function') {
        text = await new Promise((resolve, reject) => {
          GM_xmlhttpRequest({
            method: 'GET',
            url,
            timeout: 12000,
            onload: (res) => {
              if (res.status >= 200 && res.status < 300) resolve(res.responseText || '');
              else reject(new Error(`HTTP ${res.status}`));
            },
            onerror: () => reject(new Error('无法连接 GitHub 脚本仓库')),
            ontimeout: () => reject(new Error('连接 GitHub 脚本仓库超时')),
          });
        });
      } else {
        const res = await fetch(url, { cache: 'no-store' });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        text = await res.text();
      }

      const match = text.match(/@version\s+([0-9.]+)/i);
      const remoteVersion = match ? match[1].trim() : '';
      if (!remoteVersion) {
        throw new Error('未解析到远程脚本版本号');
      }

      const cmp = compareVersions(remoteVersion, SCRIPT_VERSION);
      if (cmp > 0) {
        showImageDownloadToast(`发现新版本 v${remoteVersion}（当前 v${SCRIPT_VERSION}），正在跳转更新…`, true);
        addDiagnosticLog('update:found-new-version', { currentVersion: SCRIPT_VERSION, remoteVersion });
        window.setTimeout(() => {
          window.open(USERSCRIPT_RAW_URL, '_blank', 'noopener');
        }, 800);
      } else {
        if (manual) {
          showImageDownloadToast(`当前已是最新版本 (v${SCRIPT_VERSION})`, true);
        }
        addDiagnosticLog('update:already-latest', { currentVersion: SCRIPT_VERSION, remoteVersion });
      }
    } catch (error) {
      console.warn('[ChatGPT 助手] 检查更新失败：', error);
      if (manual) {
        showImageDownloadToast(`检查更新失败：${error.message || '网络异常'}`, false);
        if (window.confirm(`检查在线更新失败（${error.message || '网络异常'}）。\n\n是否直接在新标签页打开脚本安装链接？`)) {
          window.open(USERSCRIPT_RAW_URL, '_blank', 'noopener');
        }
      }
      addDiagnosticLog('update:check-failed', { message: error?.message || String(error) });
    }
  }

  function registerUserscriptMenuCommands() {
    if (typeof GM_registerMenuCommand !== 'function') return;
    if (typeof GM_unregisterMenuCommand === 'function') {
      userscriptMenuCommandIds.forEach((id) => {
        try { GM_unregisterMenuCommand(id); } catch {}
      });
    }
    userscriptMenuCommandIds = [];
    const addMenu = (label, handler) => {
      const id = GM_registerMenuCommand(label, handler);
      if (id != null) userscriptMenuCommandIds.push(id);
    };

    // 1. 脚本与提示词更新
    addMenu(`🚀 检查脚本更新 (当前 v${SCRIPT_VERSION})`, () => void checkUserscriptUpdate(true));
    addMenu('☁ 同步 GitHub 云端提示词', () => void syncCloudPrompts(true));
    addMenu('📝 打开提示词库', () => {
      ensurePromptButton();
      const button = document.getElementById(PROMPT_BUTTON_ID);
      if (button) togglePromptPanel(button);
      else window.alert('没有找到 ChatGPT 输入框，暂时无法打开提示词库。');
    });

    // 2. 数据与提示词备份
    addMenu('📤 导出助手数据备份（含提示词+旧分组）', () => exportGroupData());
    addMenu('📥 导入提示词备份', () => chooseImportFile('merge'));
    addMenu('↶ 恢复上一版云端提示词', () => restorePreviousCloudPrompts());
    addMenu('📄 导出本地提示词为云端文件', () => exportCloudPromptFile());

    // 3. 界面显示开关
    addMenu(
      imageDownloadButtonVisible ? '👁 隐藏单独下载按钮' : '👁 显示单独下载按钮',
      () => setImageDownloadButtonVisible(!imageDownloadButtonVisible)
    );
    addMenu(
      workPackageButtonVisible ? '📦 隐藏下载并打包按钮' : '📦 显示下载并打包按钮',
      () => setWorkPackageButtonVisible(!workPackageButtonVisible)
    );

    // 4. 本地助手与诊断
    addMenu('🛠 设置本地作品助手（目录+作品集规则）', () => openWorkPackageProtocol('cgpt-workpkg://configure'));
    addMenu('📋 打开本地作品任务中心', () => openWorkPackageProtocol('cgpt-workpkg://center'));
    addMenu('🔍 检查本地作品助手环境', () => openWorkPackageProtocol('cgpt-workpkg://diagnose'));
    addMenu('📥 下载安装/更新本地作品助手', () => downloadWorkPackageInstaller());
    addMenu('📋 复制诊断日志', () => copyDiagnosticLogs());
  }

  // ==========================================
  // 11. 全局事件监听与初始化
  // ==========================================

  function bindEvents() {
    document.addEventListener('click', (event) => {
      const promptAction = event.target.closest?.('[data-cgpt-prompt-action]');
      if (promptAction) {
        event.preventDefault();
        event.stopPropagation();
        const action = promptAction.dataset.cgptPromptAction;
        const promptId = promptAction.dataset.promptId || '';
        if (action === 'new') {
          editingPromptId = 'new';
          renderPromptPanel();
        } else if (action === 'edit') {
          editingPromptId = promptId;
          renderPromptPanel();
        } else if (action === 'delete') {
          deletePrompt(promptId);
        } else if (action === 'insert') {
          insertPrompt(promptId);
        } else if (action === 'sync-cloud') {
          void syncCloudPrompts(true);
        } else if (action === 'check-update') {
          void checkUserscriptUpdate(true);
        } else if (action === 'toggle-help') {
          promptHelpVisible = !promptHelpVisible;
          renderPromptPanel();
        } else if (action === 'restore-cloud') {
          restorePreviousCloudPrompts();
        } else if (action === 'export-cloud') {
          exportCloudPromptFile();
        } else if (action === 'save') {
          upsertPromptFromPanel();
        } else if (action === 'cancel') {
          editingPromptId = '';
          renderPromptPanel();
        } else if (action === 'close') {
          closePromptPanel();
        }
        return;
      }
      if (!event.target.closest?.(`#${PROMPT_PANEL_ID}, #${PROMPT_BUTTON_ID}`)) {
        closePromptPanel();
      }
    }, true);

    document.addEventListener('change', (event) => {
      if (event.target.id === IMPORT_INPUT_ID) {
        handleImportFile(event.target.files?.[0]);
      }
    }, true);

    window.addEventListener('resize', () => {
      positionPromptPanel();
    }, { passive: true });

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && !document.getElementById(PROMPT_PANEL_ID)?.hidden) {
        closePromptPanel();
      }
      const promptRow = event.target.closest?.(`#${PROMPT_PANEL_ID} .cgpt-prompt-row[data-cgpt-prompt-action="insert"]`);
      if (
        promptRow
        && event.target === promptRow
        && (event.key === 'Enter' || event.key === ' ')
      ) {
        event.preventDefault();
        event.stopPropagation();
        insertPrompt(promptRow.dataset.promptId || '');
      }
    }, true);
  }

  // DOM 变动监听器：仅监听输入框和生图消息区域，杜绝历史侧边栏扫描消耗
  const observer = new MutationObserver((mutations) => {
    if (document.hidden) return;
    let scanImages = false;
    let scanComposer = false;
    for (const mutation of mutations) {
      const target = mutation.target.nodeType === 1
        ? mutation.target
        : mutation.target.parentElement;
      if (!target || target.closest?.(`#${PROMPT_PANEL_ID}, #${PROMPT_BUTTON_ID}, .${IMAGE_DOWNLOAD_SLOT_CLASS}, .${TEXT_DOWNLOAD_SLOT_CLASS}`)) {
        continue;
      }
      const rootReplacement = target === document.documentElement
        || target === document.body
        || [...mutation.addedNodes].some((node) => (
          node.nodeType === 1
          && (node.matches?.('main, nav, aside, #history') || node.querySelector?.('main, nav, aside, #history'))
        ));
      const touchesMain = rootReplacement || target.closest?.('main');
      const touchesComposer = touchesMain || target.closest?.('form, [data-testid*="composer"]');
      scanImages ||= Boolean(touchesMain);
      scanComposer ||= Boolean(touchesComposer);
      if (scanImages && scanComposer) break;
    }
    if (scanImages) scheduleImageDownloadButtons();
    if (scanComposer) schedulePromptButton();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) return;
    scheduleImageDownloadButtons();
    schedulePromptButton(80);
  });

  let previousUrl = location.href;
  window.setInterval(() => {
    if (document.hidden) return;
    if (location.href !== previousUrl) {
      previousUrl = location.href;
      scheduleImageDownloadButtons();
      schedulePromptButton(80);
    }
  }, 850);

  window.setInterval(() => {
    if (document.hidden) return;
    schedulePromptButton(400);
  }, 6000);

  // 启动引导
  removeLegacySidebarGroupingUi();
  injectStyles();
  registerUserscriptMenuCommands();
  refreshWorkPackageAccountName();
  installWorkPackageClipboardBridge();
  bindEvents();
  bindImageDownloadEvents();
  installImageDownloadDebugApi();
  installConversationTreeDebugApi();
  addDiagnosticLog('script:init');
  ensurePromptButton();
  scheduleCloudPromptSync();
  scheduleImageDownloadButtons();
})();
