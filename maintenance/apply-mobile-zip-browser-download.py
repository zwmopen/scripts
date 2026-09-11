from pathlib import Path

path = Path('chatgpt-conversation-tree.user.js')
text = path.read_text(encoding='utf-8')

text = text.replace('// @version      1.18.4-mobile.5', '// @version      1.18.5-mobile.6', 1)
text = text.replace("const SCRIPT_VERSION = '1.18.4-mobile.5';", "const SCRIPT_VERSION = '1.18.5-mobile.6';", 1)

marker = "  async function triggerMobileZipPackage(button) {\n"
if 'function openMobileZipDownloadSink()' not in text:
    helpers = r'''  function openMobileZipDownloadSink() {
    let sink = null;
    try {
      sink = window.open('about:blank', '_blank');
    } catch {}
    if (!sink) return null;
    try {
      sink.document.open();
      sink.document.write('<!doctype html><meta charset="utf-8"><title>正在准备 ZIP 下载</title><body style="font:16px/1.6 system-ui;padding:28px">ZIP 正在生成，完成后会自动交给浏览器下载…</body>');
      sink.document.close();
    } catch {}
    return sink;
  }

  function closeMobileZipDownloadSink(sink) {
    if (!sink) return;
    try {
      if (!sink.closed) sink.close();
    } catch {}
  }

  function showMobileZipManualDownload(url, filename) {
    const old = document.getElementById(`${APP_ID}-mobile-zip-manual-download`);
    old?.remove();
    const bar = document.createElement('div');
    bar.id = `${APP_ID}-mobile-zip-manual-download`;
    bar.style.cssText = 'position:fixed;left:12px;right:12px;bottom:18px;z-index:2147483647;padding:12px;border-radius:14px;background:var(--main-surface-primary,#fff);color:var(--text-primary,#111);box-shadow:0 10px 32px rgba(0,0,0,.24);display:flex;gap:10px;align-items:center;justify-content:space-between';
    const textNode = document.createElement('span');
    textNode.textContent = '浏览器拦截了自动下载，点这里下载 ZIP';
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.textContent = '下载ZIP';
    link.style.cssText = 'font-weight:700;text-decoration:underline;white-space:nowrap';
    link.addEventListener('click', () => {
      window.setTimeout(() => bar.remove(), 1200);
    }, { once: true });
    bar.append(textNode, link);
    document.body.append(bar);
    window.setTimeout(() => bar.remove(), 30000);
  }

  function dispatchMobileZipBrowserDownload(zipBlob, filename, sink) {
    const url = URL.createObjectURL(zipBlob);
    if (sink && !sink.closed) {
      try {
        sink.location.replace(url);
        window.setTimeout(() => closeMobileZipDownloadSink(sink), 5000);
        window.setTimeout(() => URL.revokeObjectURL(url), 30000);
        return { triggered: true, mode: 'preopened-window' };
      } catch (error) {
        addDiagnosticLog('mobile-zip:sink-navigation-failed', {
          message: error?.message || String(error),
        });
      }
    }

    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    anchor.target = '_blank';
    anchor.rel = 'noopener';
    anchor.style.display = 'none';
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    showMobileZipManualDownload(url, filename);
    window.setTimeout(() => URL.revokeObjectURL(url), 30000);
    return { triggered: true, mode: 'anchor-fallback' };
  }

'''
    text = text.replace(marker, helpers + marker, 1)

old_start = """  async function triggerMobileZipPackage(button) {\n    if (!button || button.disabled) return;\n    setWorkPackageButtonState(button, 'preparing');\n    const copyText = await readMobilePackageClipboardText();\n"""
new_start = """  async function triggerMobileZipPackage(button) {\n    if (!button || button.disabled) return;\n    const downloadSink = openMobileZipDownloadSink();\n    setWorkPackageButtonState(button, 'preparing');\n    const copyText = await readMobilePackageClipboardText();\n"""
if old_start not in text:
    raise SystemExit('trigger start pattern not found')
text = text.replace(old_start, new_start, 1)

text = text.replace("""      window.setTimeout(() => {\n        if (button.dataset.cgptWorkPackageState === 'needs-text') setWorkPackageButtonState(button, 'idle');\n      }, 2600);\n      return;\n""", """      closeMobileZipDownloadSink(downloadSink);\n      window.setTimeout(() => {\n        if (button.dataset.cgptWorkPackageState === 'needs-text') setWorkPackageButtonState(button, 'idle');\n      }, 2600);\n      return;\n""", 1)

text = text.replace("""      window.alert('没有识别到当前作品的图片，已停止打包。');\n      setWorkPackageButtonState(button, 'idle');\n      return;\n""", """      window.alert('没有识别到当前作品的图片，已停止打包。');\n      closeMobileZipDownloadSink(downloadSink);\n      setWorkPackageButtonState(button, 'idle');\n      return;\n""", 1)

old_download = """      const zipBlob = mobileZipBuild(entries);\n      const url = URL.createObjectURL(zipBlob);\n      const anchor = document.createElement('a');\n      anchor.href = url;\n      anchor.download = mobileZipDownloadName(task);\n      anchor.rel = 'noopener';\n      anchor.style.display = 'none';\n      document.body.append(anchor);\n      anchor.click();\n      anchor.remove();\n      window.setTimeout(() => URL.revokeObjectURL(url), 10000);\n      setWorkPackageButtonState(button, 'done', { total: imageUrls.length });\n      showImageDownloadToast(`ZIP 下载完成：${imageUrls.length} 张图片 + 文案`, true);\n      addDiagnosticLog('mobile-zip:done', {\n        batchId,\n        images: imageUrls.length,\n        zipBytes: zipBlob.size,\n      });\n"""
new_download = """      const zipBlob = mobileZipBuild(entries);\n      const filename = mobileZipDownloadName(task);\n      const delivery = dispatchMobileZipBrowserDownload(zipBlob, filename, downloadSink);\n      setWorkPackageButtonState(button, 'done', { total: imageUrls.length });\n      showImageDownloadToast(`ZIP 已生成，已触发浏览器下载：${imageUrls.length} 张图片 + 文案`, true);\n      addDiagnosticLog('mobile-zip:done', {\n        batchId,\n        images: imageUrls.length,\n        zipBytes: zipBlob.size,\n        deliveryMode: delivery.mode,\n      });\n"""
if old_download not in text:
    raise SystemExit('download dispatch pattern not found')
text = text.replace(old_download, new_download, 1)

text = text.replace("""    } catch (error) {\n      console.warn('[ChatGPT 手机版 ZIP] 打包失败：', error);\n""", """    } catch (error) {\n      closeMobileZipDownloadSink(downloadSink);\n      console.warn('[ChatGPT 手机版 ZIP] 打包失败：', error);\n""", 1)

path.write_text(text, encoding='utf-8')
print('mobile ZIP browser download trigger applied')
