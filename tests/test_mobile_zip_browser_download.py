from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "chatgpt-conversation-tree.user.js").read_text(encoding="utf-8")

class MobileZipBrowserDownloadTests(unittest.TestCase):
    def test_version_bumped(self):
        self.assertIn("// @version      1.18.6-mobile.7", SOURCE)
        self.assertIn("const SCRIPT_VERSION = '1.18.6-mobile.7';", SOURCE)

    def test_via_flow_does_not_open_new_window(self):
        self.assertNotIn("function openMobileZipDownloadSink", SOURCE)
        self.assertNotIn("window.open('about:blank'", SOURCE)
        self.assertNotIn("sink.location.replace(url)", SOURCE)

    def test_current_page_progress_ui_exists(self):
        self.assertIn("function ensureMobileZipProgressBar", SOURCE)
        self.assertIn("function updateMobileZipProgress", SOURCE)
        start = SOURCE.index("async function triggerMobileZipPackage")
        end = SOURCE.index("function setWorkPackageButtonState", start)
        block = SOURCE[start:end]
        self.assertIn("ensureMobileZipProgressBar()", block)
        self.assertIn("updateMobileZipProgress", block)

    def test_via_download_prefers_gm_download_then_current_page_anchor(self):
        start = SOURCE.index("function dispatchMobileZipBrowserDownload")
        end = SOURCE.index("async function triggerMobileZipPackage", start)
        block = SOURCE[start:end]
        self.assertIn("typeof GM_download === 'function'", block)
        self.assertIn("GM_download({", block)
        self.assertIn("url,", block)
        self.assertIn("name: filename", block)
        self.assertIn("onload", block)
        self.assertIn("onerror", block)
        self.assertIn("anchor.download = filename", block)
        self.assertIn("anchor.click()", block)
        self.assertNotIn("anchor.target = '_blank'", block)

    def test_manual_fallback_stays_in_current_page(self):
        start = SOURCE.index("function showMobileZipManualDownload")
        end = SOURCE.index("function dispatchMobileZipBrowserDownload", start)
        block = SOURCE[start:end]
        self.assertIn("document.body.append", block)
        self.assertIn("link.download = filename", block)
        self.assertNotIn("window.open", block)

    def test_success_message_reports_browser_handoff(self):
        start = SOURCE.index("async function triggerMobileZipPackage")
        end = SOURCE.index("function setWorkPackageButtonState", start)
        block = SOURCE[start:end]
        self.assertNotIn("ZIP 下载完成", block)
        self.assertIn("已交给Via下载", block)

if __name__ == "__main__":
    unittest.main()
