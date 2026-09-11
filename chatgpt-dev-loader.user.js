// ==UserScript==
// @name         ChatGPT 最近对话分组（飞书式目录）
// @name:zh-CN   ChatGPT 作品助手（本地热重载直连版）
// @namespace    https://chatgpt.com/
// @version      999.0.0
// @description  本地开发直连模式：直接实时加载本地 D:\AICode\dev-live 源码，本地改完按 F5 秒级生效！
// @author       Codex
// @match        https://chatgpt.com/*
// @match        https://chat.openai.com/*
// @run-at       document-idle
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_deleteValue
// @grant        GM_listValues
// @grant        GM_download
// @grant        GM_registerMenuCommand
// @grant        GM_unregisterMenuCommand
// @grant        GM_xmlhttpRequest
// @grant        unsafeWindow
// @connect      *
// @require      file:///D:/AICode/dev-live/chatgpt-conversation-tree.user.js
// ==/UserScript==

(() => {
  'use strict';
  console.log('%c[ChatGPT 作品助手]%c 本地热重载直连模式已激活 (挂载源: D:\\AICode\\dev-live\\chatgpt-conversation-tree.user.js)', 'color:#10a37f;font-weight:bold;', 'color:default;');
})();
