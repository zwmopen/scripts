from pathlib import Path

path = Path('chatgpt-conversation-tree.user.js')
source = path.read_text(encoding='utf-8')

source = source.replace('// @version      1.18.3-mobile.4', '// @version      1.18.4-mobile.5')
source = source.replace("const SCRIPT_VERSION = '1.18.3-mobile.4';", "const SCRIPT_VERSION = '1.18.4-mobile.5';")

state_anchor = "  let pendingImportMode = 'merge';"
if "let recentMobileCopiedText = '';" not in source:
    if state_anchor not in source:
        raise SystemExit('runtime state anchor not found')
    source = source.replace(
        state_anchor,
        state_anchor + "\n  let recentMobileCopiedText = '';\n  let mobileCopyCaptureInstalled = false;",
        1,
    )

old_reader = """  async function readMobilePackageClipboardText() {
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
"""

new_reader = """  function rememberMobileCopiedText(text = '', source = 'unknown') {
    const cleaned = cleanMobilePackageText(text);
    if (!isValidMobilePackageText(cleaned)) return false;
    recentMobileCopiedText = cleaned;
    try { sessionStorage.setItem(`${APP_ID}:mobile-copied-text`, cleaned); } catch {}
    addDiagnosticLog('mobile-zip:copy-captured', {
      source,
      length: cleaned.length,
    });
    return true;
  }

  function mobileCopiedTextFromButton(button) {
    if (!button) return '';
    const card = textCardForCopyButton(button);
    if (card) {
      const cardText = textContentForDownload(card);
      if (isValidMobilePackageText(cardText)) return cardText;
    }
    const turn = button.closest?.('[data-testid^="conversation-turn"], [data-message-author-role], article, [class*="group/conversation-turn"]');
    if (!turn) return '';
    const clone = turn.cloneNode(true);
    clone.querySelectorAll?.('button, svg, script, style, textarea, input, .cgpt-image-download-slot, .cgpt-text-download-slot')
      .forEach((element) => element.remove());
    return cleanMobilePackageText(clone.innerText || clone.textContent || '');
  }

  function installMobileCopyCapture() {
    if (mobileCopyCaptureInstalled) return;
    mobileCopyCaptureInstalled = true;

    document.addEventListener('copy', () => {
      const selectedText = String(window.getSelection?.()?.toString() || '');
      rememberMobileCopiedText(selectedText, 'selection-copy');
    }, true);

    document.addEventListener('click', (event) => {
      const button = event.target?.closest?.('button');
      if (!button) return;
      const label = elementText(button);
      if (!/复制|copy/i.test(label)) return;
      const copiedText = mobileCopiedTextFromButton(button);
      rememberMobileCopiedText(copiedText, 'copy-button');
    }, true);
  }

  async function readMobilePackageClipboardText() {
    if (navigator.clipboard?.readText) {
      try {
        const clipboardText = cleanMobilePackageText(await navigator.clipboard.readText());
        if (isValidMobilePackageText(clipboardText)) {
          rememberMobileCopiedText(clipboardText, 'clipboard-api');
          return clipboardText;
        }
      } catch (error) {
        addDiagnosticLog('mobile-zip:clipboard-read-failed', {
          message: error?.message || String(error),
        });
      }
    }

    if (isValidMobilePackageText(recentMobileCopiedText)) {
      return cleanMobilePackageText(recentMobileCopiedText);
    }

    try {
      const sessionText = cleanMobilePackageText(sessionStorage.getItem(`${APP_ID}:mobile-copied-text`) || '');
      if (isValidMobilePackageText(sessionText)) {
        recentMobileCopiedText = sessionText;
        return sessionText;
      }
    } catch {}

    return cleanMobilePackageText(recentMobileCopiedText);
  }
"""

if 'function installMobileCopyCapture()' not in source:
    if old_reader not in source:
        raise SystemExit('clipboard reader anchor not found')
    source = source.replace(old_reader, new_reader, 1)

startup_anchor = "  bindImageDownloadEvents();\n  ensurePromptButton();"
if '  installMobileCopyCapture();\n' not in source:
    if startup_anchor not in source:
        raise SystemExit('startup anchor not found')
    source = source.replace(
        startup_anchor,
        "  bindImageDownloadEvents();\n  installMobileCopyCapture();\n  ensurePromptButton();",
        1,
    )

path.write_text(source, encoding='utf-8')
print('mobile clipboard fallback applied')
