from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "chatgpt-conversation-tree.user.js").read_text(encoding="utf-8")

class MobileZipUserscriptTests(unittest.TestCase):
    def test_mobile_branch_has_own_update_channel(self):
        self.assertIn("// @version      1.18.0-mobile.1", SOURCE)
        self.assertIn("raw.githubusercontent.com/zwmopen/scripts/mobile-via-zip/chatgpt-conversation-tree.user.js", SOURCE)

    def test_mobile_mode_bypasses_windows_helper(self):
        start = SOURCE.index("async function triggerWorkPackageButton")
        section = SOURCE[start:start + 1700]
        self.assertIn("if (isMobileZipMode())", section)
        self.assertLess(section.index("triggerMobileZipPackage(button)"), section.index("ensureWorkPackageHelperReady()"))

    def test_mobile_package_requires_valid_clipboard_copy(self):
        start = SOURCE.index("async function triggerMobileZipPackage")
        section = SOURCE[start:start + 8000]
        self.assertIn("navigator.clipboard?.readText", SOURCE)
        self.assertIn("if (!isValidMobilePackageText(copyText))", section)
        self.assertIn("未识别到有效文案", section)

    def test_mobile_zip_contains_copy_and_metadata(self):
        start = SOURCE.index("async function triggerMobileZipPackage")
        section = SOURCE[start:start + 8000]
        self.assertIn("文案.txt", section)
        self.assertIn("meta.json", section)
        self.assertIn("application/zip", SOURCE)

    def test_mobile_zip_fetch_can_cross_origin(self):
        self.assertIn("// @connect      *", SOURCE)
        self.assertIn("GM_xmlhttpRequest", SOURCE)
        self.assertIn("responseType: 'arraybuffer'", SOURCE)

    def test_windows_protocol_is_still_preserved(self):
        self.assertIn("const WORK_PACKAGE_PROTOCOL_URL = 'cgpt-workpkg://run';", SOURCE)
        self.assertIn("openWorkPackageProtocol(protocolUrl);", SOURCE)

if __name__ == "__main__":
    unittest.main()
