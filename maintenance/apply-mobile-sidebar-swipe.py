from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "chatgpt-conversation-tree.user.js"
TEST = ROOT / "tests" / "test_mobile_sidebar_swipe.py"

TEST_CONTENT = r'''from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "chatgpt-conversation-tree.user.js").read_text(encoding="utf-8")

class MobileSidebarSwipeTests(unittest.TestCase):
    def test_mobile_swipe_installed_at_startup(self):
        self.assertIn("function installMobileSidebarSwipe()", SOURCE)
        self.assertIn("installMobileSidebarSwipe();", SOURCE)

    def test_left_edge_swipe_opens_sidebar(self):
        self.assertIn("startX <= MOBILE_SWIPE_EDGE_PX", SOURCE)
        self.assertIn("dx >= MOBILE_SWIPE_DISTANCE_PX", SOURCE)
        self.assertIn("setMobileNativeSidebarOpen(true)", SOURCE)

    def test_right_edge_swipe_closes_sidebar(self):
        self.assertIn("startX >= innerWidth - MOBILE_SWIPE_EDGE_PX", SOURCE)
        self.assertIn("dx <= -MOBILE_SWIPE_DISTANCE_PX", SOURCE)
        self.assertIn("setMobileNativeSidebarOpen(false)", SOURCE)

    def test_vertical_scroll_is_not_treated_as_swipe(self):
        self.assertIn("MOBILE_SWIPE_MAX_VERTICAL_PX", SOURCE)
        self.assertIn("Math.abs(dy) > MOBILE_SWIPE_MAX_VERTICAL_PX", SOURCE)
        self.assertIn("Math.abs(dy) > Math.abs(dx) * 0.75", SOURCE)

    def test_native_sidebar_controls_have_multiple_selectors(self):
        self.assertIn("open-sidebar-button", SOURCE)
        self.assertIn("close-sidebar-button", SOURCE)
        self.assertIn("打开侧边栏", SOURCE)
        self.assertIn("关闭侧边栏", SOURCE)

if __name__ == "__main__":
    unittest.main()
'''

TEST.parent.mkdir(parents=True, exist_ok=True)
TEST.write_text(TEST_CONTENT, encoding="utf-8")

# TDD RED: ZIP-patched source does not yet contain swipe navigation.
red = subprocess.run([sys.executable, str(TEST)], cwd=ROOT)
if red.returncode == 0:
    raise SystemExit("RED phase failed: swipe tests unexpectedly passed before patch")

source = SCRIPT.read_text(encoding="utf-8")
anchor = "  // 启动引导\n"
if anchor not in source:
    raise SystemExit("startup anchor missing")

block = r'''  const MOBILE_SWIPE_EDGE_PX = 34;
  const MOBILE_SWIPE_DISTANCE_PX = 72;
  const MOBILE_SWIPE_MAX_VERTICAL_PX = 64;
  const MOBILE_SWIPE_MAX_DURATION_MS = 850;

  function mobileSidebarButton(wantOpen) {
    const selectors = wantOpen
      ? [
          '[data-testid="open-sidebar-button"]',
          'button[aria-label*="Open sidebar" i]',
          'button[aria-label*="Open navigation" i]',
          'button[title*="Open sidebar" i]',
          'button[aria-label*="打开侧边栏"]',
          'button[aria-label*="打开菜单"]',
        ]
      : [
          '[data-testid="close-sidebar-button"]',
          'button[aria-label*="Close sidebar" i]',
          'button[aria-label*="Close navigation" i]',
          'button[title*="Close sidebar" i]',
          'button[aria-label*="关闭侧边栏"]',
          'button[aria-label*="关闭菜单"]',
        ];
    for (const selector of selectors) {
      const button = [...document.querySelectorAll(selector)].find((node) => isElementVisible(node));
      if (button) return button;
    }

    const buttons = [...document.querySelectorAll('button')].filter((node) => isElementVisible(node));
    const pattern = wantOpen
      ? /open sidebar|open navigation|打开侧边栏|打开菜单|菜单/i
      : /close sidebar|close navigation|关闭侧边栏|关闭菜单/i;
    return buttons.find((button) => pattern.test(elementText(button))) || null;
  }

  function mobileNativeSidebarVisible() {
    if (mobileSidebarButton(false)) return true;
    const candidates = [...document.querySelectorAll('nav, aside, [role="navigation"]')];
    return candidates.some((node) => {
      if (!isElementVisible(node)) return false;
      const rect = node.getBoundingClientRect?.();
      if (!rect) return false;
      return rect.width >= Math.min(220, innerWidth * 0.58)
        && rect.height >= innerHeight * 0.55
        && rect.left < innerWidth * 0.35
        && rect.right > 0;
    });
  }

  function setMobileNativeSidebarOpen(wantOpen) {
    const open = mobileNativeSidebarVisible();
    if (open === wantOpen) return true;
    const button = mobileSidebarButton(wantOpen);
    if (button) {
      button.click();
      return true;
    }

    if (!wantOpen) {
      const sidebar = [...document.querySelectorAll('nav, aside, [role="navigation"]')]
        .find((node) => {
          if (!isElementVisible(node)) return false;
          const rect = node.getBoundingClientRect?.();
          return rect && rect.width > 180 && rect.height > innerHeight * 0.5 && rect.left < innerWidth * 0.35;
        });
      if (sidebar) {
        const sidebarRect = sidebar.getBoundingClientRect();
        const backdrop = [...document.querySelectorAll('button, [role="button"], div')]
          .filter((node) => node !== sidebar && !sidebar.contains(node) && isElementVisible(node))
          .find((node) => {
            const rect = node.getBoundingClientRect?.();
            if (!rect) return false;
            const style = getComputedStyle(node);
            return ['fixed', 'absolute'].includes(style.position)
              && rect.left <= sidebarRect.right + 4
              && rect.right >= innerWidth - 4
              && rect.top <= 4
              && rect.bottom >= innerHeight - 4;
          });
        if (backdrop) {
          backdrop.click();
          return true;
        }
      }
    }
    return false;
  }

  function installMobileSidebarSwipe() {
    if (!isMobileZipMode() || installMobileSidebarSwipe.installed) return;
    installMobileSidebarSwipe.installed = true;
    let startX = 0;
    let startY = 0;
    let startAt = 0;
    let mode = '';
    let claimed = false;

    const reset = () => {
      startX = 0;
      startY = 0;
      startAt = 0;
      mode = '';
      claimed = false;
    };

    document.addEventListener('touchstart', (event) => {
      if (event.touches?.length !== 1) {
        reset();
        return;
      }
      const touch = event.touches[0];
      startX = touch.clientX;
      startY = touch.clientY;
      startAt = Date.now();
      claimed = false;
      if (startX <= MOBILE_SWIPE_EDGE_PX) mode = 'open';
      else if (startX >= innerWidth - MOBILE_SWIPE_EDGE_PX) mode = 'close';
      else mode = '';
    }, { capture: true, passive: true });

    document.addEventListener('touchmove', (event) => {
      if (!mode || event.touches?.length !== 1) return;
      const touch = event.touches[0];
      const dx = touch.clientX - startX;
      const dy = touch.clientY - startY;
      const horizontalIntent = Math.abs(dx) >= 18 && Math.abs(dx) > Math.abs(dy) * 1.35;
      const correctDirection = mode === 'open' ? dx > 0 : dx < 0;
      if (horizontalIntent && correctDirection) {
        claimed = true;
        event.preventDefault();
      }
    }, { capture: true, passive: false });

    document.addEventListener('touchend', (event) => {
      if (!mode || event.changedTouches?.length !== 1) {
        reset();
        return;
      }
      const touch = event.changedTouches[0];
      const dx = touch.clientX - startX;
      const dy = touch.clientY - startY;
      const duration = Date.now() - startAt;
      const verticalInvalid = Math.abs(dy) > MOBILE_SWIPE_MAX_VERTICAL_PX
        || Math.abs(dy) > Math.abs(dx) * 0.75;
      const fastEnough = duration <= MOBILE_SWIPE_MAX_DURATION_MS;
      let handled = false;

      if (!verticalInvalid && fastEnough) {
        if (mode === 'open' && startX <= MOBILE_SWIPE_EDGE_PX && dx >= MOBILE_SWIPE_DISTANCE_PX) {
          handled = setMobileNativeSidebarOpen(true);
        } else if (mode === 'close' && startX >= innerWidth - MOBILE_SWIPE_EDGE_PX && dx <= -MOBILE_SWIPE_DISTANCE_PX) {
          handled = setMobileNativeSidebarOpen(false);
        }
      }
      if (handled || claimed) event.preventDefault();
      reset();
    }, { capture: true, passive: false });

    document.addEventListener('touchcancel', reset, { capture: true, passive: true });
  }

'''
source = source.replace(anchor, block + anchor, 1)

init_anchor = "  bindImageDownloadEvents();\n"
if init_anchor not in source:
    raise SystemExit("initialization anchor missing")
source = source.replace(init_anchor, init_anchor + "  installMobileSidebarSwipe();\n", 1)

SCRIPT.write_text(source, encoding="utf-8")

green = subprocess.run([sys.executable, str(TEST)], cwd=ROOT)
if green.returncode != 0:
    raise SystemExit("GREEN phase failed for sidebar swipe")

syntax = subprocess.run(["node", "--check", str(SCRIPT)], cwd=ROOT)
if syntax.returncode != 0:
    raise SystemExit("node --check failed after sidebar swipe patch")

print("mobile sidebar swipe patch applied; tests and syntax check passed")
