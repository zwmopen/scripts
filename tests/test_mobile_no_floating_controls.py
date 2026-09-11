from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "chatgpt-conversation-tree.user.js").read_text(encoding="utf-8")


def function_section(name, next_name):
    start = SOURCE.index(f"function {name}")
    end = SOURCE.index(f"function {next_name}", start)
    return SOURCE[start:end]


class MobileNoFloatingControlsTests(unittest.TestCase):
    def test_mobile_zip_floating_button_is_cleanup_only(self):
        section = function_section("ensureMobileZipFloatingButton", "refreshImageDownloadButtons")
        self.assertIn("document.getElementById(MOBILE_ZIP_FLOAT_ID)?.remove();", section)
        self.assertNotIn("document.createElement('button')", section)
        self.assertNotIn("document.body.append(button)", section)

    def test_mobile_sidebar_handle_is_cleanup_only(self):
        section = function_section("ensureMobileSidebarHandle", "installMobileSidebarSwipe")
        self.assertIn("document.getElementById(MOBILE_SIDEBAR_HANDLE_ID)?.remove();", section)
        self.assertNotIn("document.createElement('button')", section)
        self.assertNotIn("document.body.append(handle)", section)

    def test_invisible_swipe_gesture_remains(self):
        section = function_section("installMobileSidebarSwipe", "initMobileEnhancementsSafely")
        self.assertIn("document.addEventListener('touchstart'", section)
        self.assertIn("setMobileNativeSidebarOpen(true)", section)
        self.assertIn("setMobileNativeSidebarOpen(false)", section)

    def test_inline_mobile_zip_button_remains(self):
        section = function_section("ensureImageDownloadButton", "latestMobileImageGroup")
        self.assertIn("isMobileZipMode() || workPackageButtonVisible", section)
        self.assertIn("packageButton.className = WORK_PACKAGE_CLASS", section)


if __name__ == "__main__":
    unittest.main()
