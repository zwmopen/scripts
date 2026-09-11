from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "chatgpt-conversation-tree.user.js"
source = SCRIPT.read_text(encoding="utf-8")

replacements = {
    "// @version      1.18.1-mobile.2": "// @version      1.18.2-mobile.3",
    "const SCRIPT_VERSION = '1.18.1-mobile.2';": "const SCRIPT_VERSION = '1.18.2-mobile.3';",
}
for old, new in replacements.items():
    if old not in source:
        raise SystemExit(f"Patch anchor missing: {old}")
    source = source.replace(old, new, 1)

zip_anchor = """  function ensureMobileZipFloatingButton() {
    let button = document.getElementById(MOBILE_ZIP_FLOAT_ID);
    if (!isMobileZipMode()) {
      button?.remove();
      return;
    }
"""
zip_replacement = zip_anchor + """    if (!document.body) {
      window.setTimeout(ensureMobileZipFloatingButton, 80);
      return;
    }
"""
if zip_anchor not in source:
    raise SystemExit("ZIP floating button anchor missing")
source = source.replace(zip_anchor, zip_replacement, 1)

sidebar_anchor = """  function ensureMobileSidebarHandle() {
    let handle = document.getElementById(MOBILE_SIDEBAR_HANDLE_ID);
    if (!isMobileZipMode()) {
      handle?.remove();
      return;
    }
"""
sidebar_replacement = sidebar_anchor + """    if (!document.body) {
      window.setTimeout(ensureMobileSidebarHandle, 80);
      return;
    }
"""
if sidebar_anchor not in source:
    raise SystemExit("mobile sidebar handle anchor missing")
source = source.replace(sidebar_anchor, sidebar_replacement, 1)

safe_init_anchor = """    document.addEventListener('touchcancel', reset, { capture: true, passive: true });
  }

  // 启动引导
"""
safe_init_block = """    document.addEventListener('touchcancel', reset, { capture: true, passive: true });
  }

  function initMobileEnhancementsSafely() {
    try {
      installMobileSidebarSwipe();
      ensureMobileZipFloatingButton();
    } catch (error) {
      console.warn('[ChatGPT 作品助手] 手机版增强初始化失败：', error);
      window.setTimeout(() => {
        try {
          ensureMobileSidebarHandle();
          ensureMobileZipFloatingButton();
        } catch (retryError) {
          console.warn('[ChatGPT 作品助手] 手机版增强延迟初始化失败：', retryError);
        }
      }, 240);
    }
  }

  // 启动引导
"""
if safe_init_anchor not in source:
    raise SystemExit("safe mobile init anchor missing")
source = source.replace(safe_init_anchor, safe_init_block, 1)

startup_old = """  bindEvents();
  bindImageDownloadEvents();
  installMobileSidebarSwipe();
  ensureMobileZipFloatingButton();
  installImageDownloadDebugApi();
  installConversationTreeDebugApi();
  addDiagnosticLog('script:init');
  ensurePromptButton();
  scheduleCloudPromptSync();
  scheduleImageDownloadButtons();
"""
startup_new = """  bindEvents();
  bindImageDownloadEvents();
  ensurePromptButton();
  schedulePromptButton(80);
  initMobileEnhancementsSafely();
  installImageDownloadDebugApi();
  installConversationTreeDebugApi();
  addDiagnosticLog('script:init');
  scheduleCloudPromptSync();
  scheduleImageDownloadButtons();
"""
if startup_old not in source:
    raise SystemExit("startup ordering anchor missing")
source = source.replace(startup_old, startup_new, 1)

SCRIPT.write_text(source, encoding="utf-8")
print("Via early-start fix applied")
