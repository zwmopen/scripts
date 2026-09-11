from pathlib import Path

path = Path('chatgpt-conversation-tree.user.js')
text = path.read_text(encoding='utf-8')

text = text.replace('// @version      1.18.5-mobile.6', '// @version      1.18.6-mobile.7', 1)
text = text.replace("const SCRIPT_VERSION = '1.18.5-mobile.6';", "const SCRIPT_VERSION = '1.18.6-mobile.7';", 1)

helper_start = text.index('  function openMobileZipDownloadSink() {')
trigger_start = text.index('  async function triggerMobileZipPackage(button) {', helper_start)
helpers = r'''  function ensureMobileZipProgressBar() {
    let bar = document.getElementById(`${APP_ID}-mobile-zip-manual-download`);
    if (!bar) {
      bar = document.createElement('div');
      bar.id = `${APP_ID}-mobile-zip-manual-download`;
      bar.style.cssText = 'position:fixed;left:12px;right:12px;bottom:18px;z-index:2147483647;padding:12px;border-radius:14px;background:var(--main-surface-primary,#fff);color:var(--text-primary,#111);box-shadow:0 10px 32px rgba(0,0,0,.24);display:flex;gap:10px;align-items:center;justify-content:space-between';
      const textNode = document.createElement('span');
      textNode.dataset.cgptMobileZipProgressText = '1';
      const link = document.createElement('a');
      link.dataset.cgptMobileZipDownloadLink = '1';
      link.textContent = '下载ZIP';
      link.style.cssText = 'font-weight:700;text-decoration:underline;white-space:nowrap;display:none';
      bar.append(textNode, link);
      document.body.append(bar);
    }
    return bar;
  }

  function updateMobileZipProgress(bar, message, showLink = false) {
    if (!bar) return;
    const textNode = bar.querySelector('[data-cgpt-mobile-zip-progress-text]');
    const link = bar.querySelector('[data-cgpt-mobile-zip-download-link]');
    if (textNode) textNode.textContent = message;
    if (link && !showLink) link.style.display = 'none';
  }

  function showMobileZipManualDownload(url, filename, bar = ensureMobileZipProgressBar()) {
    const link = bar.querySelector('[data-cgpt-mobile-zip-download-link]');
    if (!link) return;
    link.href = url;
    link.download = filename;
    link.removeAttribute('target');
    link.style.display = '';
    updateMobileZipProgress(bar, 'ZIP 已生成；若 Via 没有自动下载，点右侧“下载ZIP”', true);
    link.addEventListener('click', () => {
      updateMobileZipProgress(bar, '已再次触发 Via 浏览器下载', true);
      window.setTimeout(() => bar.remove(), 5000);
    }, { once: true });
  }

  function dispatchMobileZipBrowserDownload(zipBlob, filename, bar) {
    const url = URL.createObjectURL(zipBlob);
    const anchorFallback = () => {
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = filename;
      anchor.rel = 'noopener';
      anchor.style.display = 'none';
      document.body.append(anchor);
      anchor.click();
      anchor.remove();
      showMobileZipManualDownload(url, filename, bar);
      window.setTimeout(() => URL.revokeObjectURL(url), 120000);
      return { triggered: true, mode: 'anchor-fallback' };
    };

    showMobileZipManualDownload(url, filename, bar);
    if (typeof GM_download === 'function') {
      try {
        GM_download({
          url,
          name: filename,
          saveAs: false,
          onload: () => {
            updateMobileZipProgress(bar, 'Via 已接收 ZIP 下载任务', true);
            window.setTimeout(() => bar.remove(), 5000);
          },
          onerror: (error) => {
            addDiagnosticLog('mobile-zip:gm-download-failed', {
              message: error?.error || error?.message || String(error),
            });
            anchorFallback();
          },
          ontimeout: () => anchorFallback(),
        });
        return { triggered: true, mode: 'gm-download' };
      } catch (error) {
        addDiagnosticLog('mobile-zip:gm-download-threw', {
          message: error?.message || String(error),
        });
      }
    }
    return anchorFallback();
  }

'''
text = text[:helper_start] + helpers + text[trigger_start:]

text = text.replace("""  async function triggerMobileZipPackage(button) {\n    if (!button || button.disabled) return;\n    const downloadSink = openMobileZipDownloadSink();\n    setWorkPackageButtonState(button, 'preparing');\n    const copyText = await readMobilePackageClipboardText();\n""", """  async function triggerMobileZipPackage(button) {\n    if (!button || button.disabled) return;\n    const progress = ensureMobileZipProgressBar();\n    updateMobileZipProgress(progress, '正在检查已复制文案…');\n    setWorkPackageButtonState(button, 'preparing');\n    const copyText = await readMobilePackageClipboardText();\n""", 1)

text = text.replace("      closeMobileZipDownloadSink(downloadSink);\n", "", 3)

text = text.replace("""      setWorkPackageButtonState(button, 'downloading', { current: 0, total: imageUrls.length });\n      for (let index = 0; index < imageUrls.length; index += 1) {\n""", """      setWorkPackageButtonState(button, 'downloading', { current: 0, total: imageUrls.length });\n      updateMobileZipProgress(progress, `正在读取图片 0/${imageUrls.length}…`);\n      for (let index = 0; index < imageUrls.length; index += 1) {\n""", 1)

text = text.replace("""        setWorkPackageButtonState(button, 'downloading', { current: index + 1, total: imageUrls.length });\n      }\n\n      entries.push({ name: '文案.txt', data: `${copyText}\\n` });\n""", """        setWorkPackageButtonState(button, 'downloading', { current: index + 1, total: imageUrls.length });\n        updateMobileZipProgress(progress, `正在读取图片 ${index + 1}/${imageUrls.length}…`);\n      }\n\n      entries.push({ name: '文案.txt', data: `${copyText}\\n` });\n""", 1)

text = text.replace("""      setWorkPackageButtonState(button, 'packaging');\n      const zipBlob = mobileZipBuild(entries);\n      const filename = mobileZipDownloadName(task);\n      const delivery = dispatchMobileZipBrowserDownload(zipBlob, filename, downloadSink);\n      setWorkPackageButtonState(button, 'done', { total: imageUrls.length });\n      showImageDownloadToast(`ZIP 已生成，已触发浏览器下载：${imageUrls.length} 张图片 + 文案`, true);\n""", """      setWorkPackageButtonState(button, 'packaging');\n      updateMobileZipProgress(progress, '正在生成 ZIP…');\n      const zipBlob = mobileZipBuild(entries);\n      const filename = mobileZipDownloadName(task);\n      updateMobileZipProgress(progress, 'ZIP 已生成，正在交给 Via 下载…');\n      const delivery = dispatchMobileZipBrowserDownload(zipBlob, filename, progress);\n      setWorkPackageButtonState(button, 'done', { total: imageUrls.length });\n      showImageDownloadToast(`ZIP 已生成，已交给Via下载：${imageUrls.length} 张图片 + 文案`, true);\n""", 1)

text = text.replace("""    } catch (error) {\n      console.warn('[ChatGPT 手机版 ZIP] 打包失败：', error);\n""", """    } catch (error) {\n      updateMobileZipProgress(progress, `ZIP 打包失败：${error?.message || String(error)}`);\n      console.warn('[ChatGPT 手机版 ZIP] 打包失败：', error);\n""", 1)

path.write_text(text, encoding='utf-8')
print('Via in-page ZIP download patch applied')
