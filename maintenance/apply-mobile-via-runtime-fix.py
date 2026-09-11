from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "chatgpt-conversation-tree.user.js"
TEST = ROOT / "tests" / "test_mobile_via_runtime.py"

TEST_CONTENT = r'''from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "chatgpt-conversation-tree.user.js").read_text(encoding="utf-8")

class MobileViaRuntimeTests(unittest.TestCase):
    def test_version_bumped(self):
        self.assertIn("// @version      1.18.1-mobile.2", SOURCE)
        self.assertIn("const SCRIPT_VERSION = '1.18.1-mobile.2';", SOURCE)

    def test_mobile_detection_does_not_depend_only_on_ua(self):
        start = SOURCE.index("function isMobileZipMode")
        section = SOURCE[start:start + 1500]
        self.assertIn("navigator.maxTouchPoints", section)
        self.assertIn("matchMedia('(pointer: coarse)')", section)
        self.assertIn("screen.width", section)

    def test_manual_update_channel_stays_on_mobile_branch(self):
        self.assertIn("const USERSCRIPT_RAW_URL = 'https://raw.githubusercontent.com/zwmopen/scripts/mobile-via-zip/chatgpt-conversation-tree.user.js';", SOURCE)

    def test_mobile_zip_has_fixed_fallback_button(self):
        self.assertIn("MOBILE_ZIP_FLOAT_ID", SOURCE)
        self.assertIn("function ensureMobileZipFloatingButton", SOURCE)
        self.assertIn("data-cgpt-mobile-floating", SOURCE)
        refresh = SOURCE[SOURCE.index("function refreshImageDownloadButtons"):SOURCE.index("function scheduleImageDownloadButtons")]
        self.assertIn("ensureMobileZipFloatingButton()", refresh)

    def test_mobile_zip_button_ignores_old_hidden_desktop_setting(self):
        start = SOURCE.index("function ensureImageDownloadButton")
        section = SOURCE[start:start + 4200]
        self.assertIn("isMobileZipMode() || workPackageButtonVisible", section)

    def test_swipe_zone_is_inside_android_system_edge(self):
        self.assertIn("const MOBILE_SWIPE_EDGE_PX = 96;", SOURCE)
        swipe = SOURCE[SOURCE.index("function installMobileSidebarSwipe"):]
        self.assertIn("startX <= MOBILE_SWIPE_EDGE_PX", swipe)
        self.assertIn("startX >= innerWidth - MOBILE_SWIPE_EDGE_PX", swipe)

    def test_sidebar_has_visible_tap_fallback(self):
        self.assertIn("MOBILE_SIDEBAR_HANDLE_ID", SOURCE)
        self.assertIn("function ensureMobileSidebarHandle", SOURCE)
        self.assertIn("setMobileNativeSidebarOpen(!mobileNativeSidebarVisible())", SOURCE)

if __name__ == "__main__":
    unittest.main()
'''

TEST.parent.mkdir(parents=True, exist_ok=True)
TEST.write_text(TEST_CONTENT, encoding="utf-8")

# RED: current mobile build must fail these new Via-runtime regression tests.
red = subprocess.run([sys.executable, str(TEST)], cwd=ROOT)
if red.returncode == 0:
    raise SystemExit("RED phase failed: runtime regression tests passed before patch")

source = SCRIPT.read_text(encoding="utf-8")

replacements = {
    "// @version      1.18.0-mobile.1": "// @version      1.18.1-mobile.2",
    "const SCRIPT_VERSION = '1.18.0-mobile.1';": "const SCRIPT_VERSION = '1.18.1-mobile.2';",
    "const USERSCRIPT_RAW_URL = 'https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-conversation-tree.user.js';": "const USERSCRIPT_RAW_URL = 'https://raw.githubusercontent.com/zwmopen/scripts/mobile-via-zip/chatgpt-conversation-tree.user.js';",
    "  const MOBILE_SWIPE_EDGE_PX = 34;": "  const MOBILE_SWIPE_EDGE_PX = 96;",
}
for old, new in replacements.items():
    if old not in source:
        raise SystemExit(f"Patch anchor missing: {old}")
    source = source.replace(old, new, 1)

const_anchor = "  const IMAGE_DOWNLOAD_TOAST_ID = `${APP_ID}-image-download-toast`;"
const_new = const_anchor + "\n  const MOBILE_ZIP_FLOAT_ID = `${APP_ID}-mobile-zip-float`;\n  const MOBILE_SIDEBAR_HANDLE_ID = `${APP_ID}-mobile-sidebar-handle`;"
if const_anchor not in source:
    raise SystemExit("mobile constants anchor missing")
source = source.replace(const_anchor, const_new, 1)

old_mobile_detection = r'''  function isMobileZipMode() {
    const ua = String(navigator.userAgent || '');
    return /Android|iPhone|iPad|iPod|Mobile/i.test(ua);
  }
'''
new_mobile_detection = r'''  function isMobileZipMode() {
    const ua = String(navigator.userAgent || '');
    const uaMobile = /Android|iPhone|iPad|iPod|Mobile/i.test(ua);
    const touch = Number(navigator.maxTouchPoints || 0) > 0 || 'ontouchstart' in window;
    let coarsePointer = false;
    try { coarsePointer = window.matchMedia('(pointer: coarse)').matches; } catch {}
    const widths = [
      Number(globalThis.screen?.width || 0),
      Number(globalThis.screen?.availWidth || 0),
      Number(window.innerWidth || 0),
    ].filter((value) => value > 0);
    const narrowScreen = widths.length ? Math.min(...widths) <= 900 : false;
    return uaMobile || (touch && (coarsePointer || narrowScreen));
  }
'''
if old_mobile_detection not in source:
    raise SystemExit("isMobileZipMode anchor missing")
source = source.replace(old_mobile_detection, new_mobile_detection, 1)

old_mobile_urls = r'''  function mobilePackageImageUrls(button) {
    const slot = button?.closest?.(`.${IMAGE_DOWNLOAD_SLOT_CLASS}`);
    const imageButton = slot?.querySelector?.(`.${IMAGE_DOWNLOAD_CLASS}`);
    const container = imageButton?.__cgptImageDownloadContainer
      || button?.closest?.('[data-cgpt-image-download-container]')
      || button?.closest?.('[data-testid^="conversation-turn"], [data-message-author-role], article, [class*="group/conversation-turn"]')
      || document;
    let images = Array.isArray(imageButton?.__cgptImageDownloadImages)
      ? imageButton.__cgptImageDownloadImages.filter((img) => img?.isConnected)
      : [];
    if (!images.length) images = groupImageElements(container);
    return uniqueImageUrls(images);
  }
'''
new_mobile_urls = r'''  function mobilePackageImageUrls(button) {
    if (button?.dataset?.cgptMobileFloating === '1') {
      const forcedImages = Array.isArray(button.__cgptMobilePackageImages)
        ? button.__cgptMobilePackageImages.filter((img) => img?.isConnected)
        : [];
      return uniqueImageUrls(forcedImages);
    }
    const slot = button?.closest?.(`.${IMAGE_DOWNLOAD_SLOT_CLASS}`);
    const imageButton = slot?.querySelector?.(`.${IMAGE_DOWNLOAD_CLASS}`);
    const container = imageButton?.__cgptImageDownloadContainer
      || button?.closest?.('[data-cgpt-image-download-container]')
      || button?.closest?.('[data-testid^="conversation-turn"], [data-message-author-role], article, [class*="group/conversation-turn"]')
      || document;
    let images = Array.isArray(imageButton?.__cgptImageDownloadImages)
      ? imageButton.__cgptImageDownloadImages.filter((img) => img?.isConnected)
      : [];
    if (!images.length) images = groupImageElements(container);
    return uniqueImageUrls(images);
  }
'''
if old_mobile_urls not in source:
    raise SystemExit("mobilePackageImageUrls anchor missing")
source = source.replace(old_mobile_urls, new_mobile_urls, 1)

source = source.replace("    if (workPackageButtonVisible) {", "    if (isMobileZipMode() || workPackageButtonVisible) {", 1)
source = source.replace(
    "    slot.hidden = !imageDownloadButtonVisible && !workPackageButtonVisible;",
    "    slot.hidden = !imageDownloadButtonVisible && !(isMobileZipMode() || workPackageButtonVisible);",
    1,
)

refresh_anchor = "  function refreshImageDownloadButtons() {"
mobile_fallback_block = r'''  function latestMobileImageGroup() {
    const main = document.querySelector('main') || document.body;
    const turns = [...main.querySelectorAll('[data-testid^="conversation-turn"], [data-message-author-role], article, [class*="group/conversation-turn"]')];
    for (let index = turns.length - 1; index >= 0; index -= 1) {
      const turn = turns[index];
      const authorNode = turn.matches?.('[data-message-author-role]')
        ? turn
        : turn.querySelector?.('[data-message-author-role]');
      const authorRole = authorNode?.getAttribute?.('data-message-author-role') || '';
      if (authorRole && authorRole !== 'assistant') continue;
      const images = contentImageElements(turn);
      if (images.length) return { container: turn, images };
    }
    const images = contentImageElements(main);
    if (!images.length) return null;
    const last = images[images.length - 1];
    const container = imageTurnContainer(last) || main;
    const grouped = contentImageElements(container);
    return { container, images: grouped.length ? grouped : [last] };
  }

  function ensureMobileZipFloatingButton() {
    let button = document.getElementById(MOBILE_ZIP_FLOAT_ID);
    if (!isMobileZipMode()) {
      button?.remove();
      return;
    }
    if (!button) {
      button = document.createElement('button');
      button.id = MOBILE_ZIP_FLOAT_ID;
      button.type = 'button';
      button.className = WORK_PACKAGE_CLASS;
      button.dataset.cgptMobileFloating = '1';
      button.setAttribute('data-cgpt-mobile-floating', '1');
      button.style.cssText = [
        'position:fixed',
        'right:12px',
        'bottom:max(92px,calc(env(safe-area-inset-bottom,0px) + 78px))',
        'z-index:2147483000',
        'min-width:74px',
        'height:42px',
        'padding:0 12px',
        'border-radius:21px',
        'border:1px solid rgba(127,127,127,.3)',
        'background:var(--main-surface-primary,#fff)',
        'color:var(--text-primary,#111)',
        'box-shadow:0 6px 20px rgba(0,0,0,.18)',
        'display:inline-flex',
        'align-items:center',
        'justify-content:center',
        'gap:6px',
        'font:600 12px/1 system-ui,-apple-system,sans-serif',
      ].join(';');
      document.body.append(button);
      setWorkPackageButtonState(button, 'idle');
    }
    const group = latestMobileImageGroup();
    button.__cgptMobilePackageContainer = group?.container || null;
    button.__cgptMobilePackageImages = group?.images || [];
    if (!button.disabled && button.dataset.cgptWorkPackageState !== 'done') {
      setWorkPackageButtonState(button, 'idle');
    }
    button.style.opacity = group?.images?.length ? '1' : '.72';
    button.title = group?.images?.length
      ? `下载ZIP：当前识别到 ${group.images.length} 张图片`
      : '下载ZIP：当前页面暂未识别到可打包图片';
  }

'''
if refresh_anchor not in source:
    raise SystemExit("refreshImageDownloadButtons anchor missing")
source = source.replace(refresh_anchor, mobile_fallback_block + refresh_anchor, 1)

refresh_tail = "    refreshTextDownloadButtons();\n  }\n\n  function scheduleImageDownloadButtons()"
refresh_tail_new = "    refreshTextDownloadButtons();\n    ensureMobileZipFloatingButton();\n  }\n\n  function scheduleImageDownloadButtons()"
if refresh_tail not in source:
    raise SystemExit("refresh tail anchor missing")
source = source.replace(refresh_tail, refresh_tail_new, 1)

# Broaden current/native mobile sidebar selectors without relying on one ChatGPT DOM revision.
selector_anchor = "          '[data-testid=\"open-sidebar-button\"]',"
selector_new = selector_anchor + "\n          'button[data-testid*=\"sidebar\" i]',\n          'button[data-testid*=\"menu\" i]',\n          'button[aria-label*=\"menu\" i]',"
if selector_anchor not in source:
    raise SystemExit("open sidebar selector anchor missing")
source = source.replace(selector_anchor, selector_new, 1)

handle_anchor = "  function installMobileSidebarSwipe() {"
handle_block = r'''  function ensureMobileSidebarHandle() {
    let handle = document.getElementById(MOBILE_SIDEBAR_HANDLE_ID);
    if (!isMobileZipMode()) {
      handle?.remove();
      return;
    }
    if (handle) return;
    handle = document.createElement('button');
    handle.id = MOBILE_SIDEBAR_HANDLE_ID;
    handle.type = 'button';
    handle.textContent = '›';
    handle.setAttribute('aria-label', '打开或关闭侧边栏');
    handle.title = '点按切换侧边栏；也可从屏幕两侧内侧滑动';
    handle.style.cssText = [
      'position:fixed',
      'left:4px',
      'top:44vh',
      'z-index:2147482999',
      'width:24px',
      'height:56px',
      'border:0',
      'border-radius:0 12px 12px 0',
      'background:rgba(40,40,40,.42)',
      'color:#fff',
      'font:700 26px/1 system-ui,sans-serif',
      'display:flex',
      'align-items:center',
      'justify-content:center',
      'padding:0',
      'touch-action:manipulation',
    ].join(';');
    handle.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      setMobileNativeSidebarOpen(!mobileNativeSidebarVisible());
    }, true);
    document.body.append(handle);
  }

'''
if handle_anchor not in source:
    raise SystemExit("installMobileSidebarSwipe anchor missing")
source = source.replace(handle_anchor, handle_block + handle_anchor, 1)

install_head = "  function installMobileSidebarSwipe() {\n    if (!isMobileZipMode() || installMobileSidebarSwipe.installed) return;\n    installMobileSidebarSwipe.installed = true;"
install_head_new = install_head + "\n    ensureMobileSidebarHandle();"
if install_head not in source:
    raise SystemExit("sidebar install head anchor missing")
source = source.replace(install_head, install_head_new, 1)

# Make the edge zone 96px wide so gestures can begin inside the page, outside Android's system-back edge.
# Existing direction/distance guards remain unchanged, preventing vertical-scroll activation.

startup_anchor = "  installMobileSidebarSwipe();\n  installImageDownloadDebugApi();"
startup_new = "  installMobileSidebarSwipe();\n  ensureMobileZipFloatingButton();\n  installImageDownloadDebugApi();"
if startup_anchor not in source:
    raise SystemExit("startup anchor missing")
source = source.replace(startup_anchor, startup_new, 1)

SCRIPT.write_text(source, encoding="utf-8")

green = subprocess.run([sys.executable, str(TEST)], cwd=ROOT)
if green.returncode != 0:
    raise SystemExit("GREEN phase failed after Via runtime patch")

print("mobile Via runtime patch applied and regression tests passed")
