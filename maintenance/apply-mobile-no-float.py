from pathlib import Path

path = Path("chatgpt-conversation-tree.user.js")
source = path.read_text(encoding="utf-8")

source = source.replace("// @version      1.18.2-mobile.3", "// @version      1.18.3-mobile.4", 1)
source = source.replace("const SCRIPT_VERSION = '1.18.2-mobile.3';", "const SCRIPT_VERSION = '1.18.3-mobile.4';", 1)


def replace_function(source_text, name, next_name, replacement):
    start = source_text.index(f"  function {name}")
    end = source_text.index(f"  function {next_name}", start)
    return source_text[:start] + replacement + "\n\n" + source_text[end:]

source = replace_function(
    source,
    "ensureMobileZipFloatingButton()",
    "refreshImageDownloadButtons()",
    "  function ensureMobileZipFloatingButton() {\n    // 1.18.3+: 不再展示右下角悬浮 ZIP 按钮，仅清理旧版本遗留节点。\n    document.getElementById(MOBILE_ZIP_FLOAT_ID)?.remove();\n  }",
)

source = replace_function(
    source,
    "ensureMobileSidebarHandle()",
    "installMobileSidebarSwipe()",
    "  function ensureMobileSidebarHandle() {\n    // 1.18.3+: 不再展示左侧悬浮侧边栏把手；保留无 UI 的左右滑手势。\n    document.getElementById(MOBILE_SIDEBAR_HANDLE_ID)?.remove();\n  }",
)

path.write_text(source, encoding="utf-8")
print("mobile floating controls removed")
