from pathlib import Path
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
