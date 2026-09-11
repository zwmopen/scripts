from pathlib import Path
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
        self.assertIn("screen?.width", section)

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
