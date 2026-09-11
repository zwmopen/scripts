from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "chatgpt-conversation-tree.user.js").read_text(encoding="utf-8")

class MobileZipBrowserDownloadTests(unittest.TestCase):
    def test_version_bumped(self):
        self.assertIn("// @version      1.18.5-mobile.6", SOURCE)
        self.assertIn("const SCRIPT_VERSION = '1.18.5-mobile.6';", SOURCE)

    def test_download_sink_is_opened_before_first_await(self):
        start = SOURCE.index("async function triggerMobileZipPackage")
        end = SOURCE.index("function setWorkPackageButtonState", start)
        block = SOURCE[start:end]
        self.assertLess(block.index("openMobileZipDownloadSink()"), block.index("await readMobilePackageClipboardText()"))

    def test_browser_sink_navigation_exists(self):
        start = SOURCE.index("function dispatchMobileZipBrowserDownload")
        end = SOURCE.index("async function triggerMobileZipPackage", start)
        block = SOURCE[start:end]
        self.assertIn("sink.location.replace(url)", block)
        self.assertIn("anchor.download = filename", block)
        self.assertIn("anchor.click()", block)

    def test_invalid_text_closes_preopened_sink(self):
        start = SOURCE.index("async function triggerMobileZipPackage")
        end = SOURCE.index("function setWorkPackageButtonState", start)
        block = SOURCE[start:end]
        self.assertIn("closeMobileZipDownloadSink(downloadSink)", block)

    def test_success_message_does_not_claim_download_complete(self):
        start = SOURCE.index("async function triggerMobileZipPackage")
        end = SOURCE.index("function setWorkPackageButtonState", start)
        block = SOURCE[start:end]
        self.assertNotIn("ZIP 下载完成", block)
        self.assertIn("已触发浏览器下载", block)

if __name__ == "__main__":
    unittest.main()
