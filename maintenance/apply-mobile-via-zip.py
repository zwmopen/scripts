from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "chatgpt-conversation-tree.user.js"
TEST = ROOT / "tests" / "test_mobile_zip_userscript.py"

TEST_CONTENT = r'''from pathlib import Path
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
'''

TEST.parent.mkdir(parents=True, exist_ok=True)
TEST.write_text(TEST_CONTENT, encoding="utf-8")

# TDD RED: the unmodified 1.17.0 source must fail the new mobile feature tests.
red = subprocess.run([sys.executable, str(TEST)], cwd=ROOT)
if red.returncode == 0:
    raise SystemExit("RED phase failed: mobile tests unexpectedly passed before production patch")

source = SCRIPT.read_text(encoding="utf-8")

replacements = {
    "// @version      1.17.0": "// @version      1.18.0-mobile.1",
    "const SCRIPT_VERSION = '1.17.0';": "const SCRIPT_VERSION = '1.18.0-mobile.1';",
    "// @updateURL    https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-conversation-tree.user.js": "// @updateURL    https://raw.githubusercontent.com/zwmopen/scripts/mobile-via-zip/chatgpt-conversation-tree.user.js",
    "// @downloadURL  https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-conversation-tree.user.js": "// @downloadURL  https://raw.githubusercontent.com/zwmopen/scripts/mobile-via-zip/chatgpt-conversation-tree.user.js",
    "// @connect      raw.githubusercontent.com\n": "// @connect      raw.githubusercontent.com\n// @connect      *\n",
}
for old, new in replacements.items():
    if old not in source:
        raise SystemExit(f"Patch anchor missing: {old}")
    source = source.replace(old, new, 1)

anchor = "  function setWorkPackageButtonState(button, state = 'idle', detail = {}) {"
if anchor not in source:
    raise SystemExit("setWorkPackageButtonState anchor missing")

mobile_block = r'''  function isMobileZipMode() {
    const ua = String(navigator.userAgent || '');
    return /Android|iPhone|iPad|iPod|Mobile/i.test(ua);
  }

  function cleanMobilePackageText(text = '') {
    const titleMarker = new RegExp(`<!--${WORK_PACKAGE_TITLE_MARKER}[A-Za-z0-9+/=]+-->`, 'g');
    const metadataMarker = new RegExp(`<!--${WORK_PACKAGE_METADATA_MARKER}[A-Za-z0-9+/=]+-->`, 'g');
    return String(text || '')
      .replace(titleMarker, '')
      .replace(metadataMarker, '')
      .replace(/\u200B/g, '')
      .trim();
  }

  function isValidMobilePackageText(text = '') {
    const cleaned = cleanMobilePackageText(text);
    return cleaned.length >= 20 && cleaned.replace(/\s+/g, '').length >= 12;
  }

  async function readMobilePackageClipboardText() {
    if (!navigator.clipboard?.readText) return '';
    try {
      return cleanMobilePackageText(await navigator.clipboard.readText());
    } catch (error) {
      addDiagnosticLog('mobile-zip:clipboard-read-failed', {
        message: error?.message || String(error),
      });
      return '';
    }
  }

  function mobilePackageImageUrls(button) {
    const slot = button?.closest?.(`.${IMAGE_DOWNLOAD_SLOT_CLASS}`);
    const imageButton = slot?.querySelector?.(`.${IMAGE_DOWNLOAD_CLASS}`);
    const container = imageButton?.__cgptImageDownloadContainer
      || button?.closest?.('[data-cgpt-image-download-container]')
      || button?.closest?.('[data-testid^="conversation-turn"], [data-message-author-role], article, [class*="group/conversation-turn"]')
      || document;
    let images = Array.isArray(imageButton?.__cgptImageDownloadImages)
      ? imageButton.__cgptImageDownloadImages.filter((img) => img?.isConnected)
      : [];
    if (!images.length) images = groupImageElements(container);
    return uniqueImageUrls(images);
  }

  function mobileZipCrc32(bytes) {
    let crc = 0xffffffff;
    for (let i = 0; i < bytes.length; i += 1) {
      crc ^= bytes[i];
      for (let bit = 0; bit < 8; bit += 1) {
        crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
      }
    }
    return (crc ^ 0xffffffff) >>> 0;
  }

  function mobileZipDosDateTime(date = new Date()) {
    const year = Math.max(1980, date.getFullYear());
    return {
      time: ((date.getHours() & 31) << 11) | ((date.getMinutes() & 63) << 5) | ((Math.floor(date.getSeconds() / 2)) & 31),
      date: (((year - 1980) & 127) << 9) | (((date.getMonth() + 1) & 15) << 5) | (date.getDate() & 31),
    };
  }

  function mobileZipBuild(entries) {
    const encoder = new TextEncoder();
    const localParts = [];
    const centralParts = [];
    const { time, date } = mobileZipDosDateTime();
    let offset = 0;
    let centralSize = 0;

    entries.forEach((entry) => {
      const nameBytes = encoder.encode(String(entry.name || 'file.bin'));
      const data = entry.data instanceof Uint8Array ? entry.data : encoder.encode(String(entry.data ?? ''));
      if (data.byteLength > 0xffffffff || offset > 0xffffffff) throw new Error('ZIP 文件过大，手机端暂不支持 ZIP64');
      const crc = mobileZipCrc32(data);
      const flags = 0x0800;

      const local = new Uint8Array(30);
      const lv = new DataView(local.buffer);
      lv.setUint32(0, 0x04034b50, true);
      lv.setUint16(4, 20, true);
      lv.setUint16(6, flags, true);
      lv.setUint16(8, 0, true);
      lv.setUint16(10, time, true);
      lv.setUint16(12, date, true);
      lv.setUint32(14, crc, true);
      lv.setUint32(18, data.byteLength, true);
      lv.setUint32(22, data.byteLength, true);
      lv.setUint16(26, nameBytes.byteLength, true);
      lv.setUint16(28, 0, true);
      localParts.push(local, nameBytes, data);

      const central = new Uint8Array(46);
      const cv = new DataView(central.buffer);
      cv.setUint32(0, 0x02014b50, true);
      cv.setUint16(4, 20, true);
      cv.setUint16(6, 20, true);
      cv.setUint16(8, flags, true);
      cv.setUint16(10, 0, true);
      cv.setUint16(12, time, true);
      cv.setUint16(14, date, true);
      cv.setUint32(16, crc, true);
      cv.setUint32(20, data.byteLength, true);
      cv.setUint32(24, data.byteLength, true);
      cv.setUint16(28, nameBytes.byteLength, true);
      cv.setUint16(30, 0, true);
      cv.setUint16(32, 0, true);
      cv.setUint16(34, 0, true);
      cv.setUint16(36, 0, true);
      cv.setUint32(38, 0, true);
      cv.setUint32(42, offset, true);
      centralParts.push(central, nameBytes);

      offset += local.byteLength + nameBytes.byteLength + data.byteLength;
      centralSize += central.byteLength + nameBytes.byteLength;
    });

    const end = new Uint8Array(22);
    const ev = new DataView(end.buffer);
    ev.setUint32(0, 0x06054b50, true);
    ev.setUint16(4, 0, true);
    ev.setUint16(6, 0, true);
    ev.setUint16(8, entries.length, true);
    ev.setUint16(10, entries.length, true);
    ev.setUint32(12, centralSize, true);
    ev.setUint32(16, offset, true);
    ev.setUint16(20, 0, true);
    return new Blob([...localParts, ...centralParts, end], { type: 'application/zip' });
  }

  function mobileImageExtension(url, contentType = '') {
    const type = String(contentType || '').toLowerCase();
    if (type.includes('png')) return 'png';
    if (type.includes('webp')) return 'webp';
    if (type.includes('gif')) return 'gif';
    if (type.includes('avif')) return 'avif';
    if (type.includes('jpeg') || type.includes('jpg')) return 'jpg';
    try {
      const match = new URL(url, location.href).pathname.match(/\.([a-z0-9]{3,5})$/i);
      if (match?.[1] && /^(?:jpe?g|png|webp|gif|avif)$/i.test(match[1])) return match[1].toLowerCase().replace('jpeg', 'jpg');
    } catch {}
    return 'jpg';
  }

  async function mobileFetchImageBytes(url) {
    try {
      const response = await fetch(url, { credentials: 'include', cache: 'no-store' });
      if (response.ok) {
        return {
          bytes: new Uint8Array(await response.arrayBuffer()),
          contentType: response.headers.get('content-type') || '',
        };
      }
    } catch {}

    if (typeof GM_xmlhttpRequest !== 'function') throw new Error('当前脚本环境无法读取图片文件');
    return new Promise((resolve, reject) => {
      GM_xmlhttpRequest({
        method: 'GET',
        url,
        responseType: 'arraybuffer',
        timeout: 45000,
        onload: async (response) => {
          if (Number(response.status || 0) < 200 || Number(response.status || 0) >= 300) {
            reject(new Error(`图片请求失败：HTTP ${response.status || '?'}`));
            return;
          }
          try {
            let buffer = response.response;
            if (buffer instanceof Blob) buffer = await buffer.arrayBuffer();
            if (ArrayBuffer.isView(buffer)) buffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
            if (!(buffer instanceof ArrayBuffer)) throw new Error('图片响应不是二进制数据');
            const typeMatch = String(response.responseHeaders || '').match(/^content-type:\s*([^\r\n]+)/im);
            resolve({ bytes: new Uint8Array(buffer), contentType: typeMatch?.[1] || '' });
          } catch (error) {
            reject(error);
          }
        },
        onerror: () => reject(new Error('图片请求失败')),
        ontimeout: () => reject(new Error('图片请求超时')),
      });
    });
  }

  function mobileZipDownloadName(task) {
    const base = compactTitle(task?.copyTitle || task?.conversationTitle || 'ChatGPT作品')
      .replace(/[\\/:*?"<>|]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 52) || 'ChatGPT作品';
    const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');
    return `${base}-${stamp}.zip`;
  }

  async function triggerMobileZipPackage(button) {
    if (!button || button.disabled) return;
    setWorkPackageButtonState(button, 'preparing');
    const copyText = await readMobilePackageClipboardText();
    if (!isValidMobilePackageText(copyText)) {
      showImageDownloadToast('未识别到有效文案，禁止打包', false);
      setWorkPackageButtonState(button, 'needs-text');
      window.alert('未识别到有效文案。请先复制完整文案，再点击“下载ZIP”。\n\n没有文案时不会下载图片，也不会生成 ZIP。');
      window.setTimeout(() => {
        if (button.dataset.cgptWorkPackageState === 'needs-text') setWorkPackageButtonState(button, 'idle');
      }, 2600);
      return;
    }

    const imageUrls = mobilePackageImageUrls(button);
    if (!imageUrls.length) {
      showImageDownloadToast('没有识别到当前作品的图片，未生成 ZIP', false);
      window.alert('没有识别到当前作品的图片，已停止打包。');
      setWorkPackageButtonState(button, 'idle');
      return;
    }

    const batchId = newDownloadBatchId();
    const task = {
      schemaVersion: 1,
      taskId: batchId,
      batchId,
      status: 'packed-mobile',
      createdAt: new Date().toISOString(),
      expectedImages: imageUrls.length,
      copyTitle: compactTitle(copyText.split(/\r?\n/).find((line) => line.trim()) || '').slice(0, 160),
      conversationTitle: currentWorkPackageConversationTitle(),
      accountName: currentWorkPackageAccountName(),
      conversationUrl: currentWorkPackageConversationUrl(),
      pageUrl: location.href,
      scriptVersion: SCRIPT_VERSION,
      packageMode: 'mobile-zip',
    };

    try {
      const entries = [];
      setWorkPackageButtonState(button, 'downloading', { current: 0, total: imageUrls.length });
      for (let index = 0; index < imageUrls.length; index += 1) {
        const item = await mobileFetchImageBytes(imageUrls[index]);
        if (!item.bytes?.byteLength) throw new Error(`第 ${index + 1} 张图片为空`);
        const ext = mobileImageExtension(imageUrls[index], item.contentType);
        entries.push({
          name: `${String(index + 1).padStart(2, '0')}.${ext}`,
          data: item.bytes,
        });
        setWorkPackageButtonState(button, 'downloading', { current: index + 1, total: imageUrls.length });
      }

      entries.push({ name: '文案.txt', data: `${copyText}\n` });
      entries.push({ name: 'meta.json', data: `${JSON.stringify(task, null, 2)}\n` });
      setWorkPackageButtonState(button, 'packaging');
      const zipBlob = mobileZipBuild(entries);
      const url = URL.createObjectURL(zipBlob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = mobileZipDownloadName(task);
      anchor.rel = 'noopener';
      anchor.style.display = 'none';
      document.body.append(anchor);
      anchor.click();
      anchor.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 10000);
      setWorkPackageButtonState(button, 'done', { total: imageUrls.length });
      showImageDownloadToast(`ZIP 下载完成：${imageUrls.length} 张图片 + 文案`, true);
      addDiagnosticLog('mobile-zip:done', {
        batchId,
        images: imageUrls.length,
        zipBytes: zipBlob.size,
      });
    } catch (error) {
      console.warn('[ChatGPT 手机版 ZIP] 打包失败：', error);
      addDiagnosticLog('mobile-zip:failed', {
        batchId,
        message: error?.message || String(error),
      });
      showImageDownloadToast('ZIP 打包失败，未生成不完整作品包', false);
      window.alert(`ZIP 打包失败：${error?.message || String(error)}\n\n没有生成不完整的作品包。`);
      setWorkPackageButtonState(button, 'idle');
    }
  }

'''
source = source.replace(anchor, mobile_block + anchor, 1)

old_idle = '''    button.innerHTML = `${icons.package}<span class=\"cgpt-work-package-label\">下载并打包</span>`;
    button.title = '下载本组全部图片，并打包成作品文件夹';
    button.setAttribute('aria-label', '下载本组图片并打包成文件夹');'''
new_idle = '''    const idleLabel = isMobileZipMode() ? '下载ZIP' : '下载并打包';
    button.innerHTML = `${icons.package}<span class=\"cgpt-work-package-label\">${idleLabel}</span>`;
    button.title = isMobileZipMode()
      ? '将本组图片、已复制文案和元数据打包为 ZIP 下载到手机'
      : '下载本组全部图片，并打包成作品文件夹';
    button.setAttribute('aria-label', isMobileZipMode() ? '下载手机作品 ZIP' : '下载本组图片并打包成文件夹');'''
if old_idle not in source:
    raise SystemExit("idle label anchor missing")
source = source.replace(old_idle, new_idle, 1)

old_packaging = '''      button.innerHTML = `${icons.package}<span class=\"cgpt-work-package-label\">打包中</span>`;
      button.title = '图片已下载，正在调用本地作品助手打包';
      button.setAttribute('aria-label', '正在打包作品文件夹');'''
new_packaging = '''      button.innerHTML = `${icons.package}<span class=\"cgpt-work-package-label\">${isMobileZipMode() ? '生成ZIP' : '打包中'}</span>`;
      button.title = isMobileZipMode() ? '图片已读取，正在生成手机 ZIP' : '图片已下载，正在调用本地作品助手打包';
      button.setAttribute('aria-label', isMobileZipMode() ? '正在生成手机 ZIP' : '正在打包作品文件夹');'''
if old_packaging not in source:
    raise SystemExit("packaging label anchor missing")
source = source.replace(old_packaging, new_packaging, 1)

trigger_anchor = '''    event?.stopImmediatePropagation?.();
    if (!await ensureWorkPackageHelperReady()) {'''
trigger_replacement = '''    event?.stopImmediatePropagation?.();
    if (isMobileZipMode()) {
      await triggerMobileZipPackage(button);
      return;
    }
    if (!await ensureWorkPackageHelperReady()) {'''
if trigger_anchor not in source:
    raise SystemExit("triggerWorkPackageButton anchor missing")
source = source.replace(trigger_anchor, trigger_replacement, 1)

SCRIPT.write_text(source, encoding="utf-8")

# GREEN: new tests must pass after the production patch.
green = subprocess.run([sys.executable, str(TEST)], cwd=ROOT)
if green.returncode != 0:
    raise SystemExit("GREEN phase failed")

# Syntax verification for the userscript.
syntax = subprocess.run(["node", "--check", str(SCRIPT)], cwd=ROOT)
if syntax.returncode != 0:
    raise SystemExit("node --check failed")

print("mobile ZIP patch applied; tests and syntax check passed")
