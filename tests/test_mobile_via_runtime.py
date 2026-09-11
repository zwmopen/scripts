from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "chatgpt-conversation-tree.user.js").read_text(encoding="utf-8")

class MobileViaRuntimeTests(unittest.TestCase):
    def test_version_bumped(self):
        self.assertIn("// @version      1.18.6-mobile.7", SOURCE)
        self.assertIn("const SCRIPT_VERSION = '1.18.6-mobile.7';", SOURCE)

    def test_mobile_detection_does_not_depend_only_on_ua(self):
        start = SOURCE.index("function isMobileZipMode")
        section = SOURCE[start:start + 1500]
        self.assertIn("navigator.maxTouchPoints", section)
        self.assertIn("matchMedia('(pointer: coarse)')", section)
        self.assertIn("screen?.width", section)

    def test_manual_update_channel_stays_on_mobile_branch(self):
        self.assertIn("const USERSCRIPT_RAW_URL = 'https://raw.githubusercontent.com/zwmopen/scripts/mobile-via-zip/chatgpt-conversation-tree.user.js';", SOURCE)

    def test_mobile_floating_controls_are_removed(self):
        zip_start = SOURCE.index("function ensureMobileZipFloatingButton")
        zip_end = SOURCE.index("function refreshImageDownloadButtons", zip_start)
        zip_section = SOURCE[zip_start:zip_end]
        self.assertIn("document.getElementById(MOBILE_ZIP_FLOAT_ID)?.remove();", zip_section)
        self.assertNotIn("document.createElement('button')", zip_section)

        sidebar_start = SOURCE.index("function ensureMobileSidebarHandle")
        sidebar_end = SOURCE.index("function installMobileSidebarSwipe", sidebar_start)
        sidebar_section = SOURCE[sidebar_start:sidebar_end]
        self.assertIn("document.getElementById(MOBILE_SIDEBAR_HANDLE_ID)?.remove();", sidebar_section)
        self.assertNotIn("document.createElement('button')", sidebar_section)

    def test_mobile_zip_button_ignores_old_hidden_desktop_setting(self):
        start = SOURCE.index("function ensureImageDownloadButton")
        section = SOURCE[start:start + 4200]
        self.assertIn("isMobileZipMode() || workPackageButtonVisible", section)

    def test_swipe_zone_is_inside_android_system_edge(self):
        self.assertIn("const MOBILE_SWIPE_EDGE_PX = 96;", SOURCE)
        swipe = SOURCE[SOURCE.index("function installMobileSidebarSwipe"):]
        self.assertIn("startX <= MOBILE_SWIPE_EDGE_PX", swipe)
        self.assertIn("startX >= innerWidth - MOBILE_SWIPE_EDGE_PX", swipe)

if __name__ == "__main__":
    unittest.main()
