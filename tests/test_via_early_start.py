from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "chatgpt-conversation-tree.user.js").read_text(encoding="utf-8")


class ViaEarlyStartTests(unittest.TestCase):
    def test_mobile_cleanup_controls_do_not_require_document_body(self):
        sidebar_start = SOURCE.index("function ensureMobileSidebarHandle")
        sidebar_end = SOURCE.index("function installMobileSidebarSwipe", sidebar_start)
        sidebar = SOURCE[sidebar_start:sidebar_end]
        self.assertIn("document.getElementById(MOBILE_SIDEBAR_HANDLE_ID)?.remove();", sidebar)
        self.assertNotIn("document.body.append", sidebar)

        zip_start = SOURCE.index("function ensureMobileZipFloatingButton")
        zip_end = SOURCE.index("function refreshImageDownloadButtons", zip_start)
        zip_section = SOURCE[zip_start:zip_end]
        self.assertIn("document.getElementById(MOBILE_ZIP_FLOAT_ID)?.remove();", zip_section)
        self.assertNotIn("document.body.append", zip_section)

    def test_prompt_core_initializes_before_mobile_extras(self):
        startup = SOURCE[SOURCE.rindex("// 启动引导"):]
        self.assertLess(startup.index("ensurePromptButton();"), startup.index("initMobileEnhancementsSafely();"))

    def test_mobile_extras_are_fault_isolated(self):
        self.assertIn("function initMobileEnhancementsSafely()", SOURCE)
        block = SOURCE[SOURCE.index("function initMobileEnhancementsSafely()"):]
        self.assertIn("try {", block)
        self.assertIn("console.warn('[ChatGPT 作品助手] 手机版增强初始化失败：'", block)


if __name__ == "__main__":
    unittest.main()
