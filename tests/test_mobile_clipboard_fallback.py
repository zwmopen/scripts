from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "chatgpt-conversation-tree.user.js").read_text(encoding="utf-8")

class MobileClipboardFallbackTests(unittest.TestCase):
    def test_version_bumped(self):
        self.assertIn("// @version      1.18.4-mobile.5", SOURCE)
        self.assertIn("const SCRIPT_VERSION = '1.18.4-mobile.5';", SOURCE)

    def test_copy_cache_exists(self):
        self.assertIn("let recentMobileCopiedText = '';", SOURCE)
        self.assertIn("function rememberMobileCopiedText", SOURCE)
        self.assertIn("function installMobileCopyCapture", SOURCE)

    def test_manual_copy_event_is_captured(self):
        block = SOURCE[SOURCE.index("function installMobileCopyCapture"):]
        self.assertIn("document.addEventListener('copy'", block)
        self.assertIn("window.getSelection", block)
        self.assertIn("rememberMobileCopiedText", block)

    def test_chatgpt_copy_button_is_captured(self):
        block = SOURCE[SOURCE.index("function installMobileCopyCapture"):]
        self.assertIn("document.addEventListener('click'", block)
        self.assertIn("textCardForCopyButton", block)
        self.assertIn("textContentForDownload", block)

    def test_zip_uses_clipboard_then_cache(self):
        start = SOURCE.index("async function readMobilePackageClipboardText")
        end = SOURCE.index("function mobilePackageImageUrls", start)
        block = SOURCE[start:end]
        self.assertIn("recentMobileCopiedText", block)
        self.assertIn("navigator.clipboard?.readText", block)
        self.assertIn("return cleanMobilePackageText(recentMobileCopiedText)", block)

    def test_capture_installed_at_startup(self):
        startup = SOURCE[SOURCE.rindex("// 启动引导"):]
        self.assertIn("installMobileCopyCapture();", startup)

if __name__ == "__main__":
    unittest.main()
