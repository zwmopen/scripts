using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace WindowLayoutLauncher
{
    static class Program
    {
        public const string Version = "3.0.2";
        public const string AppName = "窗口布局启动器";
        public const string RepoUrl = "https://github.com/zwmopen/scripts/tree/master/本地文件处理脚本/窗口布局启动器/应用版";
        public const string VersionCheckUrl = "https://raw.githubusercontent.com/zwmopen/scripts/master/本地文件处理脚本/窗口布局启动器/应用版/version.json";
        public static readonly int ShowMainWindowMessage = Native.RegisterWindowMessage("WindowLayoutLauncher.ShowMainWindow.v3");
        private static Mutex appMutex;

        [STAThread]
        static void Main(string[] args)
        {
            try
            {
                TrySetDpiAwareness();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                if (args.Length == 0)
                {
                    bool createdNew;
                    appMutex = new Mutex(true, "Local\\WindowLayoutLauncher.v3", out createdNew);
                    if (!createdNew)
                    {
                        ActivateExistingInstance();
                        return;
                    }
                }

                var manager = new LayoutManager(AppDomain.CurrentDomain.BaseDirectory);
                if (args.Length >= 2 && string.Equals(args[0], "--restore", StringComparison.OrdinalIgnoreCase))
                {
                    manager.Restore(args[1]);
                    return;
                }

                Application.Run(new MainForm(manager));
            }
            catch (Exception ex)
            {
                WriteCrashLog(ex);
                if (args.Length == 0)
                {
                    MessageBox.Show("窗口布局启动器遇到错误，已写入 crash.log。", "窗口布局启动器", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private static void ActivateExistingInstance()
        {
            IntPtr found = IntPtr.Zero;
            Native.EnumWindows((hWnd, lParam) =>
            {
                int length = Native.GetWindowTextLength(hWnd);
                if (length <= 0) return true;
                var title = new StringBuilder(length + 1);
                Native.GetWindowText(hWnd, title, title.Capacity);
                if (!string.Equals(title.ToString(), AppName, StringComparison.Ordinal)) return true;
                found = hWnd;
                return false;
            }, IntPtr.Zero);
            if (found != IntPtr.Zero)
            {
                Native.PostMessage(found, ShowMainWindowMessage, IntPtr.Zero, IntPtr.Zero);
            }
        }

        private static void WriteCrashLog(Exception ex)
        {
            try
            {
                var path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "crash.log");
                var lines = new List<string>();
                lines.Add(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                lines.Add(ex == null ? "null exception" : ex.GetType().FullName);
                lines.Add(ex == null ? "" : ex.Message);
                lines.Add(ex == null ? "" : ex.StackTrace);
                if (ex != null && ex.InnerException != null)
                {
                    lines.Add("Inner:");
                    lines.Add(ex.InnerException.GetType().FullName);
                    lines.Add(ex.InnerException.Message);
                    lines.Add(ex.InnerException.StackTrace);
                }
                File.WriteAllLines(path, lines.ToArray(), Encoding.UTF8);
            }
            catch
            {
            }
        }

        private static void TrySetDpiAwareness()
        {
            try
            {
                Native.SetProcessDpiAwareness(1);
                return;
            }
            catch
            {
            }

            try
            {
                Native.SetProcessDPIAware();
            }
            catch
            {
            }
        }
    }

    [DataContract]
    public class LayoutConfig
    {
        [DataMember(Name = "format_version", EmitDefaultValue = false)]
        public int FormatVersion { get; set; }

        [DataMember(Name = "name")]
        public string Name { get; set; }

        [DataMember(Name = "task_mode", EmitDefaultValue = false)]
        public string TaskMode { get; set; }

        [DataMember(Name = "saved_at")]
        public string SavedAt { get; set; }

        [DataMember(Name = "items")]
        public List<LayoutItem> Items { get; set; }

        [DataMember(Name = "screens", EmitDefaultValue = false)]
        public List<SavedScreen> Screens { get; set; }
    }

    [DataContract]
    public class SavedScreen
    {
        [DataMember(Name = "device")]
        public string Device { get; set; }

        [DataMember(Name = "index")]
        public int Index { get; set; }

        [DataMember(Name = "x")]
        public int X { get; set; }

        [DataMember(Name = "y")]
        public int Y { get; set; }

        [DataMember(Name = "w")]
        public int W { get; set; }

        [DataMember(Name = "h")]
        public int H { get; set; }

        [DataMember(Name = "primary")]
        public bool Primary { get; set; }
    }

    [DataContract]
    public class LayoutItem
    {
        [DataMember(Name = "kind")]
        public string Kind { get; set; }

        [DataMember(Name = "path", EmitDefaultValue = false)]
        public string Path { get; set; }

        [DataMember(Name = "browser", EmitDefaultValue = false)]
        public string Browser { get; set; }

        [DataMember(Name = "exe_path", EmitDefaultValue = false)]
        public string ExePath { get; set; }

        [DataMember(Name = "process_name", EmitDefaultValue = false)]
        public string ProcessName { get; set; }

        [DataMember(Name = "title", EmitDefaultValue = false)]
        public string Title { get; set; }

        [DataMember(Name = "url", EmitDefaultValue = false)]
        public string Url { get; set; }

        [DataMember(Name = "title_keyword", EmitDefaultValue = false)]
        public string TitleKeyword { get; set; }

        [DataMember(Name = "x")]
        public int X { get; set; }

        [DataMember(Name = "y")]
        public int Y { get; set; }

        [DataMember(Name = "w")]
        public int W { get; set; }

        [DataMember(Name = "h")]
        public int H { get; set; }

        [DataMember(Name = "screen_device", EmitDefaultValue = false)]
        public string ScreenDevice { get; set; }

        [DataMember(Name = "screen_index", EmitDefaultValue = false)]
        public int ScreenIndex { get; set; }

        [DataMember(Name = "relative_x", EmitDefaultValue = false)]
        public double RelativeX { get; set; }

        [DataMember(Name = "relative_y", EmitDefaultValue = false)]
        public double RelativeY { get; set; }

        [DataMember(Name = "relative_w", EmitDefaultValue = false)]
        public double RelativeW { get; set; }

        [DataMember(Name = "relative_h", EmitDefaultValue = false)]
        public double RelativeH { get; set; }
    }

    public class LayoutSummary
    {
        public string Name { get; set; }
        public string Path { get; set; }
        public string SavedAt { get; set; }
        public int Count { get; set; }
        public string TaskMode { get; set; }
        public List<LayoutItem> Items { get; set; }
        public List<SavedScreen> Screens { get; set; }
        public string Display
        {
            get { return Name + "    " + Count + " 个窗口"; }
        }
    }

    public class HealthIssue
    {
        public string Level { get; set; }
        public string Message { get; set; }
    }

    public class HealthReport
    {
        public List<HealthIssue> Issues { get; set; }
        public bool HasBlockingIssues
        {
            get { return Issues != null && Issues.Any(x => string.Equals(x.Level, "error", StringComparison.OrdinalIgnoreCase)); }
        }
    }

    public class WindowInfo
    {
        public IntPtr Hwnd { get; set; }
        public int ProcessId { get; set; }
        public string ProcessName { get; set; }
        public string Title { get; set; }
        public string ExePath { get; set; }
        public bool IsMinimized { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
        public int W { get; set; }
        public int H { get; set; }
    }

    public class ExplorerInfo
    {
        public IntPtr Hwnd { get; set; }
        public string Path { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
        public int W { get; set; }
        public int H { get; set; }
    }

    public class LayoutManager
    {
        private readonly string baseDir;
        private readonly string layoutDir;

        public string LayoutDir { get { return layoutDir; } }
        public LayoutManager(string baseDir)
        {
            this.baseDir = baseDir;
            layoutDir = System.IO.Path.Combine(baseDir, "layouts");
            Directory.CreateDirectory(layoutDir);
        }

        public List<LayoutSummary> GetLayouts()
        {
            Directory.CreateDirectory(layoutDir);
            var result = new List<LayoutSummary>();
            foreach (var file in Directory.GetFiles(layoutDir, "*.json").OrderBy(x => x))
            {
                try
                {
                    var layout = ReadLayout(file);
                    result.Add(new LayoutSummary
                    {
                        Name = string.IsNullOrWhiteSpace(layout.Name) ? System.IO.Path.GetFileNameWithoutExtension(file) : layout.Name,
                        Path = file,
                        SavedAt = layout.SavedAt,
                        Count = layout.Items == null ? 0 : layout.Items.Count,
                        TaskMode = string.IsNullOrWhiteSpace(layout.TaskMode) ? InferTaskMode(layout.Name) : layout.TaskMode,
                        Items = layout.Items ?? new List<LayoutItem>(),
                        Screens = layout.Screens ?? new List<SavedScreen>()
                    });
                }
                catch
                {
                }
            }
            return result;
        }

        public LayoutConfig SaveCurrent(string name, string taskMode = null)
        {
            var safeName = SafeName(name);
            var topWindows = WindowTools.GetTopLevelWindows();
            var items = new List<LayoutItem>();
            var screens = WindowTools.GetSavedScreens();
            var captured = new HashSet<IntPtr>();
            var currentExe = FullPathTrim(Application.ExecutablePath);

            foreach (var explorer in WindowTools.GetExplorerWindows(topWindows, false).OrderBy(w => w.X).ThenBy(w => w.Y))
            {
                var item = new LayoutItem
                {
                    Kind = "explorer",
                    Path = explorer.Path,
                    X = explorer.X,
                    Y = explorer.Y,
                    W = explorer.W,
                    H = explorer.H
                };
                WindowTools.AttachScreenPosition(item, screens);
                items.Add(item);
                captured.Add(explorer.Hwnd);
            }

            foreach (var browser in topWindows
                .Where(w => (EqualsIgnoreCase(w.ProcessName, "msedge") || EqualsIgnoreCase(w.ProcessName, "chrome")) &&
                            ContainsIgnoreCase(w.Title, "ChatGPT") &&
                            !w.IsMinimized)
                .OrderBy(w => w.X).ThenBy(w => w.Y))
            {
                var item = new LayoutItem
                {
                    Kind = "browser",
                    Browser = EqualsIgnoreCase(browser.ProcessName, "msedge") ? "edge" : "chrome",
                    ExePath = WindowTools.GetProcessPath(browser.ProcessId),
                    Url = "https://chatgpt.com/",
                    TitleKeyword = "ChatGPT",
                    X = browser.X,
                    Y = browser.Y,
                    W = browser.W,
                    H = browser.H
                };
                WindowTools.AttachScreenPosition(item, screens);
                items.Add(item);
                captured.Add(browser.Hwnd);
            }

            foreach (var app in topWindows
                .Where(w => !w.IsMinimized && !captured.Contains(w.Hwnd))
                .OrderBy(w => w.X).ThenBy(w => w.Y))
            {
                var exePath = WindowTools.GetProcessPath(app.ProcessId);
                if (IsIgnoredAppWindow(app, exePath, currentExe)) continue;

                var item = new LayoutItem
                {
                    Kind = "app",
                    ProcessName = app.ProcessName,
                    ExePath = exePath,
                    Title = app.Title,
                    TitleKeyword = TitleKeywordFromTitle(app.Title),
                    X = app.X,
                    Y = app.Y,
                    W = app.W,
                    H = app.H
                };
                WindowTools.AttachScreenPosition(item, screens);
                items.Add(item);
            }

            var layout = new LayoutConfig
            {
                FormatVersion = 3,
                Name = safeName,
                TaskMode = string.IsNullOrWhiteSpace(taskMode) ? InferTaskMode(safeName) : taskMode,
                SavedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                Items = items,
                Screens = screens
            };

            WriteLayout(GetLayoutPath(safeName), layout);
            return layout;
        }

        public RestoreResult Restore(string nameOrPath)
        {
            var path = File.Exists(nameOrPath) ? nameOrPath : GetLayoutPath(SafeName(nameOrPath));
            if (!File.Exists(path))
            {
                return new RestoreResult { Ok = 0, Failed = 1, Message = "没有找到这个布局", FailDetails = new List<string> { "布局文件不存在: " + path } };
            }

            var layout = ReadLayout(path);
            var topWindows = WindowTools.GetTopLevelWindows();
            var explorerWindows = WindowTools.GetExplorerWindows(topWindows, true);
            var used = new HashSet<IntPtr>();
            int ok = 0;
            int failed = 0;
            var failDetails = new List<string>();
            var logLines = new List<string>();
            logLines.Add("===== 恢复布局: " + (layout.Name ?? Path.GetFileNameWithoutExtension(path)) + " =====");
            logLines.Add("时间: " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            logLines.Add("");

            int idx = 0;
            foreach (var item in layout.Items ?? new List<LayoutItem>())
            {
                idx++;
                string itemDesc = DescribeItem(item);
                logLines.Add("[" + idx + "] " + itemDesc);

                IntPtr hwnd = IntPtr.Zero;
                string failReason = null;

                if (EqualsIgnoreCase(item.Kind, "explorer"))
                {
                    hwnd = FindOrOpenExplorer(item.Path, explorerWindows, out failReason);
                }
                else if (EqualsIgnoreCase(item.Kind, "browser"))
                {
                    hwnd = FindOrOpenBrowser(item, topWindows, used, out failReason);
                }
                else if (EqualsIgnoreCase(item.Kind, "app"))
                {
                    hwnd = FindOrOpenApp(item, topWindows, used, out failReason);
                }
                else
                {
                    failReason = "未知类型: " + item.Kind;
                }

                if (hwnd == IntPtr.Zero)
                {
                    failed++;
                    var detail = itemDesc + " → " + (failReason ?? "未找到窗口");
                    failDetails.Add(detail);
                    logLines.Add("    ✗ 失败: " + (failReason ?? "未找到窗口"));
                    continue;
                }

                var target = WindowTools.GetTargetBounds(item, layout.Screens);
                if (WindowTools.MoveWindow(hwnd, target.X, target.Y, target.Width, target.Height))
                {
                    ok++;
                    used.Add(hwnd);
                    logLines.Add("    ✓ 已移动到 (" + target.X + "," + target.Y + ") " + target.Width + "x" + target.Height);
                }
                else
                {
                    failed++;
                    var detail = itemDesc + " → 移动窗口失败";
                    failDetails.Add(detail);
                    logLines.Add("    ✗ 移动窗口失败");
                }
            }

            logLines.Add("");
            logLines.Add("结果: 成功 " + ok + "，失败 " + failed);
            if (failDetails.Count > 0)
            {
                logLines.Add("失败详情:");
                foreach (var d in failDetails)
                {
                    logLines.Add("  - " + d);
                }
            }

            try
            {
                var logDir = Path.Combine(baseDir, "logs");
                Directory.CreateDirectory(logDir);
                var logPath = Path.Combine(logDir, "restore_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".log");
                File.WriteAllLines(logPath, logLines.ToArray(), Encoding.UTF8);
            }
            catch { }

            return new RestoreResult
            {
                Ok = ok,
                Failed = failed,
                Message = failed > 0 ? "已恢复 " + ok + "，失败 " + failed : "已恢复窗口布局 " + ok,
                FailDetails = failDetails
            };
        }

        private static string DescribeItem(LayoutItem item)
        {
            if (EqualsIgnoreCase(item.Kind, "explorer"))
            {
                return "资源管理器: " + item.Path;
            }
            if (EqualsIgnoreCase(item.Kind, "browser"))
            {
                return "浏览器: " + (item.Browser ?? "") + " - " + (item.Url ?? "");
            }
            if (EqualsIgnoreCase(item.Kind, "app"))
            {
                return "应用: " + (item.ProcessName ?? "") + " - " + (item.Title ?? "");
            }
            return item.Kind + ": " + (item.Title ?? "");
        }

        public void DeleteLayout(LayoutSummary summary)
        {
            if (summary == null || string.IsNullOrWhiteSpace(summary.Path)) return;
            if (File.Exists(summary.Path)) File.Delete(summary.Path);
        }

        public LayoutConfig GetLayout(LayoutSummary summary)
        {
            if (summary == null || string.IsNullOrWhiteSpace(summary.Path) || !File.Exists(summary.Path)) return null;
            return ReadLayout(summary.Path);
        }

        public HealthReport CheckHealth(LayoutSummary summary)
        {
            var report = new HealthReport { Issues = new List<HealthIssue>() };
            var layout = GetLayout(summary);
            if (layout == null)
            {
                report.Issues.Add(new HealthIssue { Level = "error", Message = "布局文件不存在或无法读取。" });
                return report;
            }

            var openWindows = WindowTools.GetTopLevelWindows();
            foreach (var item in layout.Items ?? new List<LayoutItem>())
            {
                if (EqualsIgnoreCase(item.Kind, "explorer") && !string.IsNullOrWhiteSpace(item.Path) && !Directory.Exists(item.Path))
                {
                    report.Issues.Add(new HealthIssue { Level = "error", Message = "文件夹不存在：" + item.Path });
                }
                else if (EqualsIgnoreCase(item.Kind, "app") && !string.IsNullOrWhiteSpace(item.ExePath) && !File.Exists(item.ExePath))
                {
                    var isOpen = openWindows.Any(w => EqualsIgnoreCase(w.ProcessName, item.ProcessName));
                    if (!isOpen)
                    {
                        report.Issues.Add(new HealthIssue { Level = "warning", Message = "软件路径失效：" + (item.Title ?? item.ProcessName ?? item.ExePath) });
                    }
                }
                else if (EqualsIgnoreCase(item.Kind, "browser"))
                {
                    report.Issues.Add(new HealthIssue { Level = "info", Message = "网页会复用同域名窗口；账号登录状态需要浏览器自行保持。" });
                }
            }

            var savedCount = layout.Screens == null ? 0 : layout.Screens.Count;
            var currentCount = Screen.AllScreens.Length;
            if (savedCount > 0 && savedCount != currentCount)
            {
                report.Issues.Add(new HealthIssue { Level = "warning", Message = "保存时有 " + savedCount + " 台显示器，当前有 " + currentCount + " 台；窗口会自动适配。" });
            }
            return report;
        }

        public LayoutConfig RenameLayout(LayoutSummary summary, string newName)
        {
            if (summary == null || string.IsNullOrWhiteSpace(summary.Path) || !File.Exists(summary.Path))
            {
                throw new InvalidOperationException("先选择一个布局。");
            }

            var safeName = SafeName(newName);
            var newPath = GetLayoutPath(safeName);
            var oldPath = summary.Path;
            if (!EqualsIgnoreCase(oldPath, newPath) && File.Exists(newPath))
            {
                throw new InvalidOperationException("已经有同名布局。");
            }

            var layout = ReadLayout(oldPath);
            layout.Name = safeName;
            WriteLayout(newPath, layout);
            if (!EqualsIgnoreCase(oldPath, newPath) && File.Exists(oldPath))
            {
                File.Delete(oldPath);
            }
            return layout;
        }

        public string ExportLayoutJson(LayoutSummary summary)
        {
            if (summary == null || !File.Exists(summary.Path))
            {
                throw new InvalidOperationException("先选择一个布局。");
            }

            var exportRoot = System.IO.Path.Combine(baseDir, "exports");
            Directory.CreateDirectory(exportRoot);
            var safeName = SafeName(summary.Name);
            var stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            var jsonPath = System.IO.Path.Combine(exportRoot, safeName + "-" + stamp + ".json");
            File.Copy(summary.Path, jsonPath, false);
            return jsonPath;
        }

        public LayoutConfig ImportLayoutJson(string sourcePath)
        {
            if (string.IsNullOrWhiteSpace(sourcePath) || !File.Exists(sourcePath))
            {
                throw new InvalidOperationException("没有找到要导入的布局文件。");
            }

            var imported = ReadLayout(sourcePath);
            var baseName = string.IsNullOrWhiteSpace(imported.Name)
                ? System.IO.Path.GetFileNameWithoutExtension(sourcePath)
                : imported.Name;
            var safeName = SafeName(baseName);
            var targetPath = GetUniqueLayoutPath(safeName, out safeName);
            imported.Name = safeName;
            if (string.IsNullOrWhiteSpace(imported.SavedAt))
            {
                imported.SavedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            }
            WriteLayout(targetPath, imported);
            return imported;
        }

        public string GetLayoutPath(string name)
        {
            return System.IO.Path.Combine(layoutDir, SafeName(name) + ".json");
        }

        private string GetUniqueLayoutPath(string name, out string finalName)
        {
            var baseName = SafeName(name);
            finalName = baseName;
            var path = GetLayoutPath(finalName);
            if (!File.Exists(path)) return path;

            for (int i = 2; i < 1000; i++)
            {
                finalName = baseName + "-" + i.ToString("00");
                path = GetLayoutPath(finalName);
                if (!File.Exists(path)) return path;
            }

            finalName = baseName + "-" + DateTime.Now.ToString("yyyyMMdd_HHmmss");
            return GetLayoutPath(finalName);
        }

        private IntPtr FindOrOpenExplorer(string path, List<ExplorerInfo> existing, out string failReason)
        {
            failReason = null;
            if (string.IsNullOrWhiteSpace(path))
            {
                failReason = "路径为空";
                return IntPtr.Zero;
            }
            var target = FullPathTrim(path);
            var found = existing.FirstOrDefault(w => EqualsIgnoreCase(FullPathTrim(w.Path), target));
            if (found != null) return found.Hwnd;
            if (!Directory.Exists(path))
            {
                failReason = "文件夹不存在: " + path;
                return IntPtr.Zero;
            }

            try
            {
                Process.Start("explorer.exe", "\"" + path + "\"");
            }
            catch (Exception ex)
            {
                failReason = "启动资源管理器失败: " + ex.Message;
                return IntPtr.Zero;
            }

            var created = WaitFor(() =>
            {
                return WindowTools.GetExplorerWindows(WindowTools.GetTopLevelWindows(), true)
                    .FirstOrDefault(w => EqualsIgnoreCase(FullPathTrim(w.Path), target));
            }, 4500);
            if (created == null)
            {
                failReason = "等待资源管理器窗口超时";
                return IntPtr.Zero;
            }
            return created.Hwnd;
        }

        private IntPtr FindOrOpenBrowser(LayoutItem item, List<WindowInfo> existing, HashSet<IntPtr> used, out string failReason)
        {
            failReason = null;
            var processName = EqualsIgnoreCase(item.Browser, "edge") ? "msedge" :
                              EqualsIgnoreCase(item.Browser, "chrome") ? "chrome" : item.Browser;
            var keyword = string.IsNullOrWhiteSpace(item.TitleKeyword) ? "ChatGPT" : item.TitleKeyword;
            var domain = GetDomain(item.Url);

            var found = existing
                .Where(w => EqualsIgnoreCase(w.ProcessName, processName) && !used.Contains(w.Hwnd))
                .Where(w => string.IsNullOrWhiteSpace(keyword) || ContainsIgnoreCase(w.Title, keyword) ||
                            (!string.IsNullOrWhiteSpace(domain) && ContainsIgnoreCase(w.Title, domain)))
                .OrderBy(w => w.IsMinimized ? 1 : 0)
                .ThenBy(w => w.X).ThenBy(w => w.Y)
                .FirstOrDefault();
            if (found != null) return found.Hwnd;

            var before = new HashSet<IntPtr>(existing.Where(w => EqualsIgnoreCase(w.ProcessName, processName)).Select(w => w.Hwnd));
            var exe = item.ExePath;
            if (string.IsNullOrWhiteSpace(exe) || !File.Exists(exe))
            {
                exe = EqualsIgnoreCase(processName, "msedge") ? "msedge.exe" : "chrome.exe";
            }
            var url = string.IsNullOrWhiteSpace(item.Url) ? "https://chatgpt.com/" : item.Url;
            try
            {
                Process.Start(exe, "--new-window " + Quote(url));
            }
            catch (Exception ex)
            {
                failReason = "启动浏览器失败: " + ex.Message;
                return IntPtr.Zero;
            }

            var created = WaitFor(() =>
            {
                var latest = WindowTools.GetTopLevelWindows();
                var fresh = latest
                    .Where(w => EqualsIgnoreCase(w.ProcessName, processName) && !before.Contains(w.Hwnd))
                    .OrderBy(w => w.X).ThenBy(w => w.Y)
                    .FirstOrDefault();
                if (fresh != null) return fresh;
                return latest
                    .Where(w => EqualsIgnoreCase(w.ProcessName, processName) && !used.Contains(w.Hwnd))
                    .Where(w => string.IsNullOrWhiteSpace(keyword) || ContainsIgnoreCase(w.Title, keyword))
                    .OrderBy(w => w.X).ThenBy(w => w.Y)
                    .FirstOrDefault();
            }, 6000);

            if (created == null)
            {
                failReason = "等待浏览器窗口超时 (exe=" + exe + ")";
                return IntPtr.Zero;
            }
            return created.Hwnd;
        }

        private IntPtr FindOrOpenApp(LayoutItem item, List<WindowInfo> existing, HashSet<IntPtr> used, out string failReason)
        {
            failReason = null;
            var processName = item.ProcessName;
            var exePath = FullPathTrim(item.ExePath);
            var keyword = string.IsNullOrWhiteSpace(item.TitleKeyword) ? item.Title : item.TitleKeyword;

            var found = FindBestAppWindow(existing, processName, exePath, keyword, used, null);
            if (found != null) return found.Hwnd;

            if (string.IsNullOrWhiteSpace(processName) && string.IsNullOrWhiteSpace(exePath))
            {
                failReason = "进程名和路径都为空，无法定位";
                return IntPtr.Zero;
            }

            bool hasExe = !string.IsNullOrWhiteSpace(item.ExePath) && File.Exists(item.ExePath);
            bool isUwp = !string.IsNullOrWhiteSpace(item.ExePath) &&
                         ContainsIgnoreCase(item.ExePath, "\\WindowsApps\\");

            if (!hasExe && !isUwp && string.IsNullOrWhiteSpace(processName))
            {
                failReason = "程序路径不存在且无进程名: " + (item.ExePath ?? "(空)");
                return IntPtr.Zero;
            }

            var before = new HashSet<IntPtr>(existing
                .Where(w => IsSameAppWindow(w, processName, exePath))
                .Select(w => w.Hwnd));

            bool launched = false;
            string launchError = null;

            if (hasExe)
            {
                try
                {
                    Process.Start(item.ExePath);
                    launched = true;
                }
                catch (Exception ex)
                {
                    launchError = ex.Message;
                }
            }

            if (!launched && isUwp)
            {
                try
                {
                    var psi = new ProcessStartInfo();
                    psi.FileName = "explorer.exe";
                    psi.Arguments = "shell:appsFolder\\" + GetUwpAppUserModelId(item.ExePath, processName);
                    psi.UseShellExecute = true;
                    Process.Start(psi);
                    launched = true;
                }
                catch (Exception ex)
                {
                    launchError = (launchError ?? "") + " UWP启动也失败: " + ex.Message;
                }
            }

            if (!launched && !string.IsNullOrWhiteSpace(processName))
            {
                var existingProc = Process.GetProcessesByName(processName)
                    .FirstOrDefault(p => !before.Contains(GetMainWindowHandleSafe(p)));
                if (existingProc != null && existingProc.MainWindowHandle != IntPtr.Zero)
                {
                    return existingProc.MainWindowHandle;
                }

                failReason = "无法启动程序，路径不存在或无权限: " + (item.ExePath ?? "(空)") +
                             (launchError != null ? " (" + launchError + ")" : "");
                return IntPtr.Zero;
            }

            if (!launched)
            {
                failReason = "无法启动: " + (launchError ?? "未知原因");
                return IntPtr.Zero;
            }

            var created = WaitFor(() =>
            {
                var latest = WindowTools.GetTopLevelWindows();
                var fresh = FindBestAppWindow(latest, processName, exePath, keyword, used, before);
                if (fresh != null) return fresh;
                return FindBestAppWindow(latest, processName, exePath, "", used, before);
            }, 8000);

            if (created == null)
            {
                failReason = "等待程序窗口超时 (进程=" + (processName ?? "?") + ")";
                return IntPtr.Zero;
            }
            return created.Hwnd;
        }

        private static IntPtr GetMainWindowHandleSafe(Process p)
        {
            try { return p.MainWindowHandle; }
            catch { return IntPtr.Zero; }
        }

        private static string GetUwpAppUserModelId(string exePath, string processName)
        {
            var path = exePath ?? "";
            var idx = path.IndexOf("\\WindowsApps\\", StringComparison.OrdinalIgnoreCase);
            if (idx < 0) return processName ?? "";

            var after = path.Substring(idx + "\\WindowsApps\\".Length);
            var parts = after.Split('\\');
            if (parts.Length >= 2)
            {
                var pkgName = parts[0];
                var underscoreIdx = pkgName.IndexOf('_');
                if (underscoreIdx > 0)
                {
                    var pubPart = pkgName.Substring(underscoreIdx + 1);
                    var nextUnderscore = pubPart.IndexOf('_');
                    if (nextUnderscore > 0)
                    {
                        var publisher = pubPart.Substring(nextUnderscore + 1);
                        return pkgName.Substring(0, underscoreIdx) + "_" + publisher + "!" +
                               (processName ?? "App");
                    }
                }
            }
            return processName ?? "";
        }

        private static WindowInfo FindBestAppWindow(List<WindowInfo> windows, string processName, string exePath, string keyword, HashSet<IntPtr> used, HashSet<IntPtr> exclude)
        {
            var candidates = windows
                .Where(w => !used.Contains(w.Hwnd))
                .Where(w => exclude == null || !exclude.Contains(w.Hwnd))
                .Where(w => IsSameAppWindow(w, processName, exePath))
                .ToList();

            if (!string.IsNullOrWhiteSpace(keyword))
            {
                var titled = candidates
                    .Where(w => ContainsIgnoreCase(w.Title, keyword))
                    .OrderBy(w => w.IsMinimized ? 1 : 0)
                    .ThenBy(w => w.X).ThenBy(w => w.Y)
                    .FirstOrDefault();
                if (titled != null) return titled;
            }

            return candidates
                .OrderBy(w => w.IsMinimized ? 1 : 0)
                .ThenBy(w => w.X).ThenBy(w => w.Y)
                .FirstOrDefault();
        }

        private static bool IsSameAppWindow(WindowInfo window, string processName, string exePath)
        {
            if (!string.IsNullOrWhiteSpace(processName) && EqualsIgnoreCase(window.ProcessName, processName))
            {
                return true;
            }

            if (!string.IsNullOrWhiteSpace(exePath))
            {
                var windowExe = FullPathTrim(string.IsNullOrWhiteSpace(window.ExePath) ? WindowTools.GetProcessPath(window.ProcessId) : window.ExePath);
                return EqualsIgnoreCase(windowExe, exePath);
            }

            return false;
        }

        private static T WaitFor<T>(Func<T> getter, int timeoutMs) where T : class
        {
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < timeoutMs)
            {
                var value = getter();
                if (value != null) return value;
                Thread.Sleep(100);
            }
            return null;
        }

        private static string Quote(string value)
        {
            return "\"" + (value ?? "").Replace("\"", "\\\"") + "\"";
        }

        private static string GetDomain(string url)
        {
            try
            {
                Uri uri;
                return Uri.TryCreate(url, UriKind.Absolute, out uri) ? uri.Host.Replace("www.", "") : "";
            }
            catch { return ""; }
        }

        private static string FullPathTrim(string path)
        {
            try { return System.IO.Path.GetFullPath(path).TrimEnd('\\'); }
            catch { return (path ?? "").TrimEnd('\\'); }
        }

        private static bool IsIgnoredAppWindow(WindowInfo window, string exePath, string currentExe)
        {
            if (window == null) return true;
            if (string.IsNullOrWhiteSpace(window.Title)) return true;
            if (window.W < 120 || window.H < 90) return true;
            if (EqualsIgnoreCase(window.Title, "Program Manager")) return true;

            var processName = window.ProcessName ?? "";
            var ignoredProcesses = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "explorer",
                "dwm",
                "sihost",
                "ShellExperienceHost",
                "StartMenuExperienceHost",
                "SearchHost",
                "TextInputHost",
                "ApplicationFrameHost",
                "SystemSettings",
                "RuntimeBroker",
                "LockApp"
            };

            if (ignoredProcesses.Contains(processName)) return true;
            if (!string.IsNullOrWhiteSpace(exePath) && EqualsIgnoreCase(FullPathTrim(exePath), currentExe)) return true;
            return false;
        }

        private static string TitleKeywordFromTitle(string title)
        {
            var value = (title ?? "").Trim();
            if (value.Length > 60)
            {
                value = value.Substring(0, 60);
            }
            return value;
        }

        public static string SafeName(string name)
        {
            var value = string.IsNullOrWhiteSpace(name) ? "未命名布局" : name.Trim();
            foreach (var c in System.IO.Path.GetInvalidFileNameChars())
            {
                value = value.Replace(c, '_');
            }
            value = value.Trim(' ', '.');
            return string.IsNullOrWhiteSpace(value) ? "未命名布局" : value;
        }

        public static string InferTaskMode(string name)
        {
            var value = name ?? "";
            if (ContainsIgnoreCase(value, "素材")) return "素材处理";
            if (ContainsIgnoreCase(value, "小红书") || ContainsIgnoreCase(value, "写作") || ContainsIgnoreCase(value, "文案")) return "写小红书";
            if (ContainsIgnoreCase(value, "剪辑") || ContainsIgnoreCase(value, "视频")) return "剪辑";
            if (ContainsIgnoreCase(value, "团建") || ContainsIgnoreCase(value, "方案")) return "做团建方案";
            if (ContainsIgnoreCase(value, "客服")) return "客服工作";
            if (ContainsIgnoreCase(value, "运营")) return "运营";
            return "工作";
        }

        private static bool EqualsIgnoreCase(string a, string b)
        {
            return string.Equals(a ?? "", b ?? "", StringComparison.OrdinalIgnoreCase);
        }

        private static bool ContainsIgnoreCase(string text, string value)
        {
            if (string.IsNullOrEmpty(value)) return true;
            return (text ?? "").IndexOf(value, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static LayoutConfig ReadLayout(string path)
        {
            var text = File.ReadAllText(path, Encoding.UTF8);
            if (!string.IsNullOrEmpty(text) && text[0] == '\uFEFF')
            {
                text = text.Substring(1);
            }
            using (var stream = new MemoryStream(Encoding.UTF8.GetBytes(text)))
            {
                var serializer = new DataContractJsonSerializer(typeof(LayoutConfig));
                return (LayoutConfig)serializer.ReadObject(stream);
            }
        }

        private static void WriteLayout(string path, LayoutConfig layout)
        {
            using (var stream = File.Create(path))
            {
                var serializer = new DataContractJsonSerializer(typeof(LayoutConfig));
                serializer.WriteObject(stream, layout);
            }
        }
    }

    public class RestoreResult
    {
        public int Ok { get; set; }
        public int Failed { get; set; }
        public string Message { get; set; }
        public List<string> FailDetails { get; set; }
    }

    public static class WindowTools
    {
        public static List<WindowInfo> GetTopLevelWindows()
        {
            var result = new List<WindowInfo>();
            Native.EnumWindows((hWnd, lParam) =>
            {
                if (!Native.IsWindowVisible(hWnd)) return true;
                bool isMinimized = Native.IsIconic(hWnd);
                int length = Native.GetWindowTextLength(hWnd);
                if (length <= 0) return true;

                var builder = new StringBuilder(length + 1);
                Native.GetWindowText(hWnd, builder, builder.Capacity);
                var title = builder.ToString();
                if (string.IsNullOrWhiteSpace(title)) return true;

                Native.RECT rect;
                if (!Native.GetWindowRect(hWnd, out rect)) return true;
                int width = rect.Right - rect.Left;
                int height = rect.Bottom - rect.Top;
                if (!isMinimized && (width < 100 || height < 80)) return true;

                uint pid;
                Native.GetWindowThreadProcessId(hWnd, out pid);
                Process process = null;
                try { process = Process.GetProcessById((int)pid); }
                catch { return true; }

                result.Add(new WindowInfo
                {
                    Hwnd = hWnd,
                    ProcessId = (int)pid,
                    ProcessName = process.ProcessName,
                    Title = title,
                    ExePath = "",
                    IsMinimized = isMinimized,
                    X = rect.Left,
                    Y = rect.Top,
                    W = width,
                    H = height
                });
                return true;
            }, IntPtr.Zero);
            return result;
        }

        public static string GetProcessPath(int processId)
        {
            try
            {
                return Process.GetProcessById(processId).MainModule.FileName;
            }
            catch
            {
                return "";
            }
        }

        public static List<ExplorerInfo> GetExplorerWindows(List<WindowInfo> topWindows, bool includeMinimized)
        {
            var result = new List<ExplorerInfo>();
            var visible = new HashSet<IntPtr>(topWindows
                .Where(w => string.Equals(w.ProcessName, "explorer", StringComparison.OrdinalIgnoreCase) &&
                            !string.Equals(w.Title, "Program Manager", StringComparison.OrdinalIgnoreCase) &&
                            (includeMinimized || !w.IsMinimized))
                .Select(w => w.Hwnd));

            try
            {
                Type shellType = Type.GetTypeFromProgID("Shell.Application");
                dynamic shell = Activator.CreateInstance(shellType);
                foreach (object rawWindow in shell.Windows())
                {
                    try
                    {
                        dynamic window = rawWindow;
                        string fullName = Convert.ToString(window.FullName);
                        if (!string.Equals(System.IO.Path.GetFileName(fullName), "explorer.exe", StringComparison.OrdinalIgnoreCase))
                            continue;

                        IntPtr hwnd = new IntPtr(Convert.ToInt64(window.HWND));
                        if (!visible.Contains(hwnd)) continue;

                        string path = Convert.ToString(window.Document.Folder.Self.Path);
                        if (string.IsNullOrWhiteSpace(path)) continue;

                        Native.RECT rect;
                        if (!Native.GetWindowRect(hwnd, out rect)) continue;
                        result.Add(new ExplorerInfo
                        {
                            Hwnd = hwnd,
                            Path = path,
                            X = rect.Left,
                            Y = rect.Top,
                            W = rect.Right - rect.Left,
                            H = rect.Bottom - rect.Top
                        });
                    }
                    catch
                    {
                    }
                }
            }
            catch
            {
            }
            return result;
        }

        public static List<SavedScreen> GetSavedScreens()
        {
            var result = new List<SavedScreen>();
            var screens = Screen.AllScreens;
            for (int i = 0; i < screens.Length; i++)
            {
                var area = screens[i].WorkingArea;
                result.Add(new SavedScreen
                {
                    Device = screens[i].DeviceName,
                    Index = i,
                    X = area.X,
                    Y = area.Y,
                    W = area.Width,
                    H = area.Height,
                    Primary = screens[i].Primary
                });
            }
            return result;
        }

        public static void AttachScreenPosition(LayoutItem item, List<SavedScreen> screens)
        {
            if (item == null || screens == null || screens.Count == 0) return;
            var center = new Point(item.X + Math.Max(1, item.W) / 2, item.Y + Math.Max(1, item.H) / 2);
            var screen = screens.FirstOrDefault(s => new Rectangle(s.X, s.Y, s.W, s.H).Contains(center)) ?? screens.FirstOrDefault(s => s.Primary) ?? screens[0];
            item.ScreenDevice = screen.Device;
            item.ScreenIndex = screen.Index;
            item.RelativeX = screen.W <= 0 ? 0 : (item.X - screen.X) / (double)screen.W;
            item.RelativeY = screen.H <= 0 ? 0 : (item.Y - screen.Y) / (double)screen.H;
            item.RelativeW = screen.W <= 0 ? 0 : item.W / (double)screen.W;
            item.RelativeH = screen.H <= 0 ? 0 : item.H / (double)screen.H;
        }

        public static Rectangle GetTargetBounds(LayoutItem item, List<SavedScreen> savedScreens)
        {
            var fallback = new Rectangle(item.X, item.Y, Math.Max(240, item.W), Math.Max(160, item.H));
            var current = Screen.AllScreens;
            if (current == null || current.Length == 0) return fallback;

            Screen target = current.FirstOrDefault(s => string.Equals(s.DeviceName, item.ScreenDevice, StringComparison.OrdinalIgnoreCase));
            if (target == null && item.ScreenIndex >= 0 && item.ScreenIndex < current.Length) target = current[item.ScreenIndex];
            if (target == null) target = Screen.PrimaryScreen ?? current[0];
            var area = target.WorkingArea;

            bool hasRelative = item.RelativeW > 0.05 && item.RelativeH > 0.05;
            var rect = hasRelative
                ? new Rectangle(
                    area.X + (int)Math.Round(item.RelativeX * area.Width),
                    area.Y + (int)Math.Round(item.RelativeY * area.Height),
                    (int)Math.Round(item.RelativeW * area.Width),
                    (int)Math.Round(item.RelativeH * area.Height))
                : fallback;

            rect.Width = Math.Max(240, Math.Min(rect.Width, area.Width));
            rect.Height = Math.Max(160, Math.Min(rect.Height, area.Height));
            rect.X = Math.Max(area.Left, Math.Min(rect.X, area.Right - rect.Width));
            rect.Y = Math.Max(area.Top, Math.Min(rect.Y, area.Bottom - rect.Height));
            return rect;
        }

        public static bool MoveWindow(IntPtr hwnd, int x, int y, int width, int height)
        {
            if (hwnd == IntPtr.Zero || width <= 0 || height <= 0) return false;
            bool wasMinimized = Native.IsIconic(hwnd);
            Native.ShowWindowAsync(hwnd, 9);
            if (wasMinimized) Thread.Sleep(60);
            return Native.MoveWindow(hwnd, x, y, width, height, true);
        }
    }

    public static class Native
    {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll")]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern int RegisterWindowMessage(string lpString);

        [DllImport("user32.dll")]
        public static extern bool PostMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();

        [DllImport("shcore.dll")]
        public static extern int SetProcessDpiAwareness(int awareness);
    }

    public static class UiTheme
    {
        public static readonly Color WindowTop = Color.FromArgb(229, 237, 243);
        public static readonly Color WindowBottom = Color.FromArgb(209, 220, 229);
        public static readonly Color Panel = Color.FromArgb(226, 235, 241);
        public static readonly Color PanelLight = Color.FromArgb(238, 244, 248);
        public static readonly Color Ink = Color.FromArgb(28, 41, 56);
        public static readonly Color Muted = Color.FromArgb(96, 111, 128);
        public static readonly Color Blue = Color.FromArgb(48, 126, 255);
        public static readonly Color BlueDark = Color.FromArgb(25, 93, 222);
        public static readonly Color Cyan = Color.FromArgb(65, 213, 207);
        public static readonly Color Amber = Color.FromArgb(236, 170, 28);
        public static readonly Color Border = Color.FromArgb(195, 208, 220);
        public static readonly Color Selection = Color.FromArgb(215, 226, 237);

        public static GraphicsPath RoundedRect(Rectangle rect, int radius)
        {
            var path = new GraphicsPath();
            if (rect.Width <= 0 || rect.Height <= 0)
            {
                return path;
            }
            radius = Math.Max(1, Math.Min(radius, Math.Min(rect.Width, rect.Height) / 2));
            int d = radius * 2;
            path.AddArc(rect.X, rect.Y, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        public static int Dpi(int value)
        {
            try
            {
                using (var g = Graphics.FromHwnd(IntPtr.Zero))
                {
                    return (int)Math.Round(value * g.DpiX / 96F);
                }
            }
            catch
            {
                return value;
            }
        }

        public static Size DpiSize(int width, int height)
        {
            return new Size(Dpi(width), Dpi(height));
        }
    }

    public class GlassPanel : Panel
    {
        public int Radius { get; set; }

        public GlassPanel()
        {
            Radius = 22;
            FillColor = UiTheme.Panel;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        public Color FillColor { get; set; }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = new Rectangle(9, 9, Width - 18, Height - 18);
            using (var path = UiTheme.RoundedRect(rect, Radius))
            using (var lightPath = UiTheme.RoundedRect(new Rectangle(rect.X - 3, rect.Y - 3, rect.Width, rect.Height), Radius))
            using (var darkPath = UiTheme.RoundedRect(new Rectangle(rect.X + 6, rect.Y + 7, rect.Width, rect.Height), Radius))
            using (var light = new SolidBrush(Color.FromArgb(120, 255, 255, 255)))
            using (var shadow = new SolidBrush(Color.FromArgb(35, 118, 135, 155)))
            using (var fill = new SolidBrush(FillColor))
            using (var pen = new Pen(Color.FromArgb(150, 255, 255, 255)))
            using (var edge = new Pen(Color.FromArgb(80, 164, 181, 198)))
            {
                e.Graphics.FillPath(light, lightPath);
                e.Graphics.FillPath(shadow, darkPath);
                e.Graphics.FillPath(fill, path);
                e.Graphics.DrawPath(pen, path);
                e.Graphics.DrawPath(edge, path);
            }
            base.OnPaint(e);
        }
    }

    public class GlassButton : Button
    {
        private bool hover;
        private bool down;

        public bool Primary { get; set; }
        public Color SurfaceColor { get; set; }

        public GlassButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            UseVisualStyleBackColor = false;
            SurfaceColor = UiTheme.Panel;
            BackColor = SurfaceColor;
            Cursor = Cursors.Hand;
            Height = 36;
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            hover = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            hover = false;
            down = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            down = true;
            Invalidate();
            base.OnMouseDown(e);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            down = false;
            Invalidate();
            base.OnMouseUp(e);
        }

        protected override void OnPaint(PaintEventArgs pevent)
        {
            pevent.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            pevent.Graphics.Clear(SurfaceColor);
            var rect = new Rectangle(4, 4, Width - 9, Height - 9);
            Color fill;
            Color text;
            Color border;
            if (Primary)
            {
                fill = down ? UiTheme.BlueDark : hover ? Color.FromArgb(66, 142, 255) : UiTheme.Blue;
                text = Color.White;
                border = Color.FromArgb(100, 255, 255, 255);
            }
            else
            {
                fill = down ? Color.FromArgb(214, 225, 234) : hover ? Color.FromArgb(232, 240, 246) : UiTheme.PanelLight;
                text = UiTheme.Ink;
                border = Color.FromArgb(130, 255, 255, 255);
            }

            using (var path = UiTheme.RoundedRect(rect, 16))
            using (var lightPath = UiTheme.RoundedRect(new Rectangle(rect.X - 2, rect.Y - 2, rect.Width, rect.Height), 16))
            using (var darkPath = UiTheme.RoundedRect(new Rectangle(rect.X + 3, rect.Y + 4, rect.Width, rect.Height), 16))
            using (var light = new SolidBrush(Color.FromArgb(Primary ? 50 : 115, 255, 255, 255)))
            using (var shadow = new SolidBrush(Color.FromArgb(Primary ? 30 : 42, 112, 130, 150)))
            using (var brush = new SolidBrush(fill))
            using (var pen = new Pen(border))
            {
                if (!down)
                {
                    pevent.Graphics.FillPath(light, lightPath);
                    pevent.Graphics.FillPath(shadow, darkPath);
                }
                pevent.Graphics.FillPath(brush, path);
                pevent.Graphics.DrawPath(pen, path);
                TextRenderer.DrawText(pevent.Graphics, Text, Font, rect, text, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            }
        }
    }

    public class MainForm : Form
    {
        private readonly LayoutManager manager;
        private Label titleLabel;
        private Label sectionLabel;
        private Label hintLabel;
        private ListBox listBox;
        private Label statusLabel;
        private GlassPanel card;
        private GlassButton openButton;
        private NotifyIcon trayIcon;
        private ContextMenuStrip trayMenu;
        private bool allowExit;
        private string pendingTaskMode;

        public MainForm(LayoutManager manager)
        {
            this.manager = manager;
            Initialize();
            RefreshLayouts();
            InitializeTray();
        }

        private void Initialize()
        {
            AutoScaleMode = AutoScaleMode.None;
            Text = "窗口布局启动器";
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(820, 650);
            MinimumSize = new Size(640, 500);
            BackColor = UiTheme.WindowBottom;
            Font = new Font("Microsoft YaHei UI", 9F);
            DoubleBuffered = true;
            KeyPreview = true;
            TrySetWindowIcon();
            Shown += (s, e) => CenterOnPrimaryScreen();

            var root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.BackColor = Color.Transparent;
            root.Padding = new Padding(38, 28, 38, 26);
            root.ColumnCount = 1;
            root.RowCount = 5;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 34F));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 30F));
            Controls.Add(root);

            titleLabel = new Label();
            titleLabel.Text = "窗口布局中心";
            titleLabel.Dock = DockStyle.Fill;
            titleLabel.Font = new Font("Microsoft YaHei UI", 14.5F, FontStyle.Bold);
            titleLabel.ForeColor = UiTheme.Ink;
            titleLabel.BackColor = Color.Transparent;
            titleLabel.TextAlign = ContentAlignment.MiddleLeft;
            root.Controls.Add(titleLabel, 0, 0);

            sectionLabel = new Label();
            sectionLabel.Text = "选择一个工作布局";
            sectionLabel.Dock = DockStyle.Fill;
            sectionLabel.Font = new Font("Microsoft YaHei UI", 10F, FontStyle.Bold);
            sectionLabel.ForeColor = UiTheme.Ink;
            sectionLabel.BackColor = Color.Transparent;
            sectionLabel.TextAlign = ContentAlignment.MiddleLeft;
            root.Controls.Add(sectionLabel, 0, 1);

            hintLabel = new Label();
            hintLabel.Text = "保存不同工作流的窗口位置和大小，下次一键恢复。";
            hintLabel.Dock = DockStyle.Fill;
            hintLabel.ForeColor = UiTheme.Muted;
            hintLabel.BackColor = Color.Transparent;
            hintLabel.TextAlign = ContentAlignment.TopLeft;
            root.Controls.Add(hintLabel, 0, 2);

            var body = new TableLayoutPanel();
            body.Dock = DockStyle.Fill;
            body.BackColor = Color.Transparent;
            body.ColumnCount = 2;
            body.RowCount = 1;
            body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            body.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 214F));
            body.Margin = new Padding(0, 8, 0, 10);
            root.Controls.Add(body, 0, 3);

            card = new GlassPanel();
            card.Dock = DockStyle.Fill;
            card.Margin = new Padding(0, 0, 20, 0);
            card.Padding = new Padding(22);
            card.FillColor = UiTheme.Panel;
            body.Controls.Add(card, 0, 0);

            listBox = new ListBox();
            listBox.Dock = DockStyle.Fill;
            listBox.DisplayMember = "Display";
            listBox.BackColor = UiTheme.Panel;
            listBox.ForeColor = UiTheme.Ink;
            listBox.BorderStyle = BorderStyle.None;
            listBox.DrawMode = DrawMode.OwnerDrawFixed;
            listBox.ItemHeight = 104;
            listBox.IntegralHeight = false;
            listBox.DrawItem += DrawLayoutItem;
            listBox.DoubleClick += (s, e) => RestoreSelected();
            listBox.SelectedIndexChanged += (s, e) => UpdateSelectedLayoutUi();
            listBox.KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.Enter)
                {
                    RestoreSelected();
                    e.Handled = true;
                    e.SuppressKeyPress = true;
                }
                else if (e.KeyCode == Keys.F5)
                {
                    RefreshLayouts();
                    e.Handled = true;
                }
            };
            card.Controls.Add(listBox);

            var actionScroll = new Panel();
            actionScroll.Dock = DockStyle.Fill;
            actionScroll.BackColor = Color.Transparent;
            actionScroll.AutoScroll = true;
            actionScroll.AutoScrollMinSize = new Size(0, 412);
            actionScroll.Margin = new Padding(0);
            body.Controls.Add(actionScroll, 1, 0);

            var actions = new TableLayoutPanel();
            actions.Dock = DockStyle.Top;
            actions.Height = 412;
            actions.BackColor = Color.Transparent;
            actions.AutoScroll = false;
            actions.ColumnCount = 1;
            actions.RowCount = 9;
            actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 38F));
            actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 12F));
            actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 144F));
            actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 12F));
            actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 72F));
            actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 12F));
            actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 72F));
            actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 12F));
            actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 38F));
            actionScroll.Controls.Add(actions);

            openButton = AddButton(actions, "打开布局", 0, 0, true, (s, e) => RestoreSelected());
            openButton.Dock = DockStyle.Top;
            openButton.Margin = new Padding(8, 0, 8, 0);
            actions.Controls.Add(openButton, 0, 0);

            var manageGroup = AddActionGroup(
                new[] { "保存为新布局", "覆盖所选布局", "重命名布局", "删除布局" },
                new EventHandler[] { (s, e) => SaveNew(), (s, e) => OverwriteSelected(), (s, e) => RenameSelected(), (s, e) => DeleteSelected() });
            manageGroup.Dock = DockStyle.Fill;
            manageGroup.Margin = new Padding(0);
            actions.Controls.Add(manageGroup, 0, 2);

            var shareGroup = AddActionGroup(
                new[] { "导出 JSON", "导入 JSON" },
                new EventHandler[] { (s, e) => ExportSelected(), (s, e) => ImportLayout() });
            shareGroup.Dock = DockStyle.Fill;
            shareGroup.Margin = new Padding(0);
            actions.Controls.Add(shareGroup, 0, 4);

            var fileGroup = AddActionGroup(
                new[] { "打开布局文件夹", "刷新布局" },
                new EventHandler[] { (s, e) => Process.Start("explorer.exe", manager.LayoutDir), (s, e) => RefreshLayouts() });
            fileGroup.Dock = DockStyle.Fill;
            fileGroup.Margin = new Padding(0);
            actions.Controls.Add(fileGroup, 0, 6);

            var aboutButton = AddButton(actions, "关于 / 检查更新", 0, 0, false, (s, e) => ShowAbout());
            aboutButton.Dock = DockStyle.Top;
            aboutButton.Margin = new Padding(8, 0, 8, 0);
            aboutButton.Height = 34;
            actions.Controls.Add(aboutButton, 0, 8);
            actionScroll.HorizontalScroll.Enabled = false;
            actionScroll.HorizontalScroll.Visible = false;
            actionScroll.HorizontalScroll.Maximum = 0;
            actionScroll.SizeChanged += (s, e) =>
            {
                actionScroll.HorizontalScroll.Maximum = 0;
                actionScroll.HorizontalScroll.Visible = false;
            };

            statusLabel = new Label();
            statusLabel.Dock = DockStyle.Fill;
            statusLabel.ForeColor = UiTheme.Muted;
            statusLabel.BackColor = Color.Transparent;
            statusLabel.AutoEllipsis = true;
            statusLabel.TextAlign = ContentAlignment.MiddleLeft;
            root.Controls.Add(statusLabel, 0, 4);

            Shown += OnFirstShown;
            KeyDown += (s, e) =>
            {
                if (e.Control && e.KeyCode == Keys.N)
                {
                    SaveNew();
                    e.Handled = true;
                    e.SuppressKeyPress = true;
                }
                else if (e.KeyCode == Keys.F5)
                {
                    RefreshLayouts();
                    e.Handled = true;
                }
            };
        }

        private void OnFirstShown(object sender, EventArgs e)
        {
            Shown -= OnFirstShown;
            if (listBox.Items.Count == 0)
            {
                using (var wizard = new SetupWizardForm())
                {
                    if (wizard.ShowDialog(this) == DialogResult.OK)
                    {
                        pendingTaskMode = wizard.TaskMode;
                        hintLabel.Text = "先打开需要的窗口并摆好位置，然后保存为“" + pendingTaskMode + "”布局。";
                        statusLabel.Text = "准备好了以后，点击“保存为新布局”。";
                    }
                }
            }
        }

        private void ShowAbout()
        {
            using (var about = new AboutForm())
            {
                about.ShowDialog(this);
            }
        }

        private void CenterOnPrimaryScreen()
        {
            var area = Screen.PrimaryScreen.WorkingArea;
            int x = area.Left + Math.Max(0, (area.Width - Width) / 2);
            int y = area.Top + Math.Max(0, (area.Height - Height) / 2);
            Location = new Point(x, y);
        }

        private void TrySetWindowIcon()
        {
            try
            {
                var iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "assets", "app.ico");
                if (File.Exists(iconPath))
                {
                    Icon = new Icon(iconPath);
                    return;
                }

                var associated = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
                if (associated != null)
                {
                    Icon = associated;
                }
            }
            catch
            {
            }
        }

        private void InitializeTray()
        {
            trayMenu = new ContextMenuStrip();
            trayMenu.Font = new Font("Microsoft YaHei UI", 9F);
            trayIcon = new NotifyIcon();
            trayIcon.Text = "窗口布局启动器";
            trayIcon.Icon = Icon ?? Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            trayIcon.ContextMenuStrip = trayMenu;
            trayIcon.Visible = true;
            trayIcon.DoubleClick += (s, e) => ShowMainWindow();
            RebuildTrayMenu();
        }

        private void RebuildTrayMenu()
        {
            if (trayMenu == null) return;
            trayMenu.Items.Clear();
            trayMenu.Items.Add("打开窗口布局中心", null, (s, e) => ShowMainWindow());
            trayMenu.Items.Add(new ToolStripSeparator());
            var layouts = manager.GetLayouts();
            foreach (var layout in layouts)
            {
                var captured = layout;
                trayMenu.Items.Add("开始" + (string.IsNullOrWhiteSpace(captured.TaskMode) ? captured.Name : captured.TaskMode) + "  ·  " + captured.Name,
                    null, (s, e) => RestoreLayout(captured));
            }
            if (layouts.Count == 0)
            {
                var empty = trayMenu.Items.Add("还没有保存布局");
                empty.Enabled = false;
            }
            trayMenu.Items.Add(new ToolStripSeparator());
            trayMenu.Items.Add("退出", null, (s, e) => { allowExit = true; Close(); });
        }

        private void ShowMainWindow()
        {
            ShowInTaskbar = true;
            Show();
            WindowState = FormWindowState.Normal;
            Activate();
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Program.ShowMainWindowMessage)
            {
                BeginInvoke((Action)(() => ShowMainWindow()));
            }
            base.WndProc(ref m);
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (WindowState == FormWindowState.Minimized)
            {
                ShowInTaskbar = false;
                Hide();
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!allowExit && e.CloseReason != CloseReason.WindowsShutDown &&
                e.CloseReason != CloseReason.TaskManagerClosing &&
                e.CloseReason != CloseReason.ApplicationExitCall)
            {
                e.Cancel = true;
                ShowInTaskbar = false;
                Hide();
                return;
            }
            if (trayIcon != null) trayIcon.Visible = false;
            base.OnFormClosing(e);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (trayIcon != null)
                {
                    trayIcon.Visible = false;
                    trayIcon.Dispose();
                    trayIcon = null;
                }
                if (trayMenu != null)
                {
                    trayMenu.Dispose();
                    trayMenu = null;
                }
            }
            base.Dispose(disposing);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            using (var brush = new LinearGradientBrush(ClientRectangle, UiTheme.WindowTop, UiTheme.WindowBottom, 90F))
            {
                e.Graphics.FillRectangle(brush, ClientRectangle);
            }
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        }

        private GlassButton AddButton(Control parent, string text, int left, int top, bool primary, EventHandler handler)
        {
            var button = new GlassButton();
            button.Text = text;
            button.Left = left;
            button.Top = top;
            button.Width = 136;
            button.Height = 34;
            button.Primary = primary;
            if (parent is MainForm)
            {
                button.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            }
            var panel = parent as GlassPanel;
            var surface = panel == null ? parent.BackColor : panel.FillColor;
            if (surface == Color.Transparent || surface.A == 0)
            {
                surface = UiTheme.WindowBottom;
            }
            button.SurfaceColor = surface;
            button.BackColor = surface;
            button.Font = new Font("Microsoft YaHei UI", 9F, primary ? FontStyle.Bold : FontStyle.Regular);
            button.Click += handler;
            if (!(parent is TableLayoutPanel))
            {
                parent.Controls.Add(button);
            }
            return button;
        }

        private Control AddActionGroup(string[] labels, EventHandler[] handlers)
        {
            var group = new TableLayoutPanel();
            group.BackColor = Color.Transparent;
            group.ColumnCount = 1;
            group.RowCount = labels.Length;
            group.Margin = new Padding(0);
            for (int i = 0; i < labels.Length; i++)
            {
                group.RowStyles.Add(new RowStyle(SizeType.Absolute, 36F));
            }

            for (int i = 0; i < labels.Length; i++)
            {
                var button = AddButton(group, labels[i], 0, 0, false, handlers[i]);
                button.Dock = DockStyle.Fill;
                button.Margin = new Padding(6, 2, 6, 2);
                group.Controls.Add(button, 0, i);
            }
            return group;
        }

        private void DrawLayoutItem(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var back = new SolidBrush(listBox.BackColor))
            {
                e.Graphics.FillRectangle(back, e.Bounds);
            }

            var item = listBox.Items[e.Index] as LayoutSummary;
            var rect = new Rectangle(e.Bounds.Left + 4, e.Bounds.Top + 6, e.Bounds.Width - 8, e.Bounds.Height - 12);
            bool selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
            using (var path = UiTheme.RoundedRect(rect, 14))
            using (var lightPath = UiTheme.RoundedRect(new Rectangle(rect.X - 2, rect.Y - 2, rect.Width, rect.Height), 14))
            using (var darkPath = UiTheme.RoundedRect(new Rectangle(rect.X + 3, rect.Y + 4, rect.Width, rect.Height), 14))
            using (var light = new SolidBrush(Color.FromArgb(selected ? 128 : 50, 255, 255, 255)))
            using (var shadow = new SolidBrush(Color.FromArgb(selected ? 36 : 0, 112, 130, 150)))
            using (var fill = new SolidBrush(selected ? UiTheme.Selection : UiTheme.Panel))
            using (var border = new Pen(selected ? Color.FromArgb(150, 255, 255, 255) : Color.FromArgb(0, 255, 255, 255)))
            {
                if (selected)
                {
                    e.Graphics.FillPath(light, lightPath);
                    e.Graphics.FillPath(shadow, darkPath);
                }
                e.Graphics.FillPath(fill, path);
                if (selected) e.Graphics.DrawPath(border, path);
            }

            if (selected)
            {
                using (var accent = new SolidBrush(UiTheme.Blue))
                using (var accentPath = UiTheme.RoundedRect(new Rectangle(rect.Left + 9, rect.Top + 13, 4, rect.Height - 26), 2))
                {
                    e.Graphics.FillPath(accent, accentPath);
                }
            }

            var name = item == null ? listBox.Items[e.Index].ToString() : item.Name;
            var meta = item == null ? "" : (item.Count + " 个窗口｜" + FormatSavedAt(item.SavedAt));
            var mode = item == null ? "工作" : (string.IsNullOrWhiteSpace(item.TaskMode) ? "工作" : item.TaskMode);
            int textLeft = rect.Left + (selected ? 22 : 14);
            int previewWidth = rect.Width >= 330 ? Math.Min(112, rect.Width / 3) : 0;
            int textWidth = rect.Width - 30 - (previewWidth > 0 ? previewWidth + 12 : 0);
            using (var nameFont = new Font("Microsoft YaHei UI", 10F, FontStyle.Bold))
            using (var metaFont = new Font("Microsoft YaHei UI", 8.5F))
            {
                TextRenderer.DrawText(e.Graphics, name, nameFont, new Rectangle(textLeft, rect.Top + 13, textWidth, 24), UiTheme.Ink, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
                TextRenderer.DrawText(e.Graphics, "开始" + mode, metaFont, new Rectangle(textLeft, rect.Top + 40, textWidth, 20), UiTheme.BlueDark, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
                TextRenderer.DrawText(e.Graphics, meta, metaFont, new Rectangle(textLeft, rect.Top + 62, textWidth, 20), UiTheme.Muted, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            }
            if (previewWidth > 0 && item != null)
            {
                DrawLayoutPreview(e.Graphics, item, new Rectangle(rect.Right - previewWidth - 12, rect.Top + 13, previewWidth, rect.Height - 26));
            }
        }

        private void DrawLayoutPreview(Graphics g, LayoutSummary summary, Rectangle bounds)
        {
            using (var screenPath = UiTheme.RoundedRect(bounds, 8))
            using (var screenBrush = new SolidBrush(Color.FromArgb(202, 215, 226)))
            using (var screenPen = new Pen(Color.FromArgb(150, 166, 183, 198)))
            {
                g.FillPath(screenBrush, screenPath);
                g.DrawPath(screenPen, screenPath);
            }
            var items = summary.Items ?? new List<LayoutItem>();
            if (items.Count == 0) return;
            int minX = items.Min(x => x.X);
            int minY = items.Min(x => x.Y);
            int maxX = items.Max(x => x.X + Math.Max(1, x.W));
            int maxY = items.Max(x => x.Y + Math.Max(1, x.H));
            double scaleX = (bounds.Width - 12) / (double)Math.Max(1, maxX - minX);
            double scaleY = (bounds.Height - 12) / (double)Math.Max(1, maxY - minY);
            double scale = Math.Min(scaleX, scaleY);
            int usedW = (int)Math.Round((maxX - minX) * scale);
            int usedH = (int)Math.Round((maxY - minY) * scale);
            int offsetX = bounds.X + (bounds.Width - usedW) / 2;
            int offsetY = bounds.Y + (bounds.Height - usedH) / 2;
            for (int i = 0; i < items.Count; i++)
            {
                var item = items[i];
                var r = new Rectangle(
                    offsetX + (int)Math.Round((item.X - minX) * scale),
                    offsetY + (int)Math.Round((item.Y - minY) * scale),
                    Math.Max(4, (int)Math.Round(item.W * scale)),
                    Math.Max(4, (int)Math.Round(item.H * scale)));
                r.Intersect(new Rectangle(bounds.X + 4, bounds.Y + 4, bounds.Width - 8, bounds.Height - 8));
                var fill = string.Equals(item.Kind, "explorer", StringComparison.OrdinalIgnoreCase)
                    ? Color.FromArgb(119, 180, 255)
                    : string.Equals(item.Kind, "browser", StringComparison.OrdinalIgnoreCase)
                        ? Color.FromArgb(72, 205, 190)
                        : Color.FromArgb(151, 164, 184);
                using (var brush = new SolidBrush(fill))
                using (var pen = new Pen(Color.FromArgb(180, 255, 255, 255)))
                {
                    g.FillRectangle(brush, r);
                    g.DrawRectangle(pen, r);
                }
            }
        }

        private static string FormatSavedAt(string value)
        {
            DateTime parsed;
            if (DateTime.TryParse(value, out parsed))
            {
                return parsed.ToString("yyyy-MM-dd HH:mm");
            }
            return value ?? "";
        }

        private void RefreshLayouts(string selectName = null)
        {
            listBox.Items.Clear();
            foreach (var layout in manager.GetLayouts())
            {
                listBox.Items.Add(layout);
            }

            if (listBox.Items.Count > 0)
            {
                var selectedIndex = 0;
                if (!string.IsNullOrWhiteSpace(selectName))
                {
                    for (int i = 0; i < listBox.Items.Count; i++)
                    {
                        var item = listBox.Items[i] as LayoutSummary;
                        if (item != null && string.Equals(item.Name, selectName, StringComparison.OrdinalIgnoreCase))
                        {
                            selectedIndex = i;
                            break;
                        }
                    }
                }
                listBox.SelectedIndex = selectedIndex;
            }
            statusLabel.Text = listBox.Items.Count > 0 ? "已加载 " + listBox.Items.Count + " 个布局。" : "还没有布局。先摆好窗口，然后点“保存为新布局”。";
            UpdateSelectedLayoutUi();
            RebuildTrayMenu();
        }

        private void UpdateSelectedLayoutUi()
        {
            var selected = SelectedLayout();
            if (openButton == null) return;
            openButton.Text = selected == null ? "打开布局" : "开始" + (string.IsNullOrWhiteSpace(selected.TaskMode) ? "工作" : selected.TaskMode);
        }

        private LayoutSummary SelectedLayout()
        {
            return listBox.SelectedItem as LayoutSummary;
        }

        private void RestoreSelected()
        {
            var selected = SelectedLayout();
            if (selected == null)
            {
                statusLabel.Text = "先选一个布局。";
                return;
            }

            RestoreLayout(selected);
        }

        private void RestoreLayout(LayoutSummary selected)
        {
            if (selected == null) return;
            var health = manager.CheckHealth(selected);
            var visibleIssues = health.Issues
                .Where(x => !string.Equals(x.Level, "info", StringComparison.OrdinalIgnoreCase))
                .Select(x => "• " + x.Message)
                .Distinct()
                .ToList();
            if (visibleIssues.Count > 0)
            {
                ShowMainWindow();
                var answer = MessageBox.Show(this,
                    "打开前发现以下情况：\n\n" + string.Join("\n", visibleIssues.ToArray()) + "\n\n仍然继续吗？",
                    "布局健康检查",
                    MessageBoxButtons.YesNo,
                    health.HasBlockingIssues ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
                if (answer != DialogResult.Yes)
                {
                    statusLabel.Text = "已取消，先处理布局健康检查中的问题。";
                    return;
                }
            }

            statusLabel.Text = "正在恢复：" + selected.Name;
            Refresh();
            var sw = Stopwatch.StartNew();
            var result = manager.Restore(selected.Name);
            sw.Stop();

            if (result.Failed > 0 && result.FailDetails != null && result.FailDetails.Count > 0)
            {
                var detailText = string.Join(Environment.NewLine, result.FailDetails);
                statusLabel.Text = result.Message + "，用时 " + sw.Elapsed.TotalSeconds.ToString("0.0") + " 秒。点击查看失败详情";

                var logDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "logs");
                if (Directory.Exists(logDir))
                {
                    try
                    {
                        var latestLog = Directory.GetFiles(logDir, "restore_*.log")
                            .OrderByDescending(f => f)
                            .FirstOrDefault();
                        if (!string.IsNullOrEmpty(latestLog))
                        {
                            detailText += Environment.NewLine + Environment.NewLine + "详细日志: " + latestLog;
                        }
                    }
                    catch { }
                }

                BeginInvoke((Action)(() =>
                {
                    MessageBox.Show(this, detailText, "恢复失败详情", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }));
            }
            else
            {
                statusLabel.Text = result.Message + "，用时 " + sw.Elapsed.TotalSeconds.ToString("0.0") + " 秒。";
            }
        }

        private void SaveNew()
        {
            var name = PromptForm.Ask("保存为新布局", "给这个布局起个名字：", "新布局");
            if (string.IsNullOrWhiteSpace(name))
            {
                statusLabel.Text = "已取消。";
                return;
            }
            var taskMode = string.IsNullOrWhiteSpace(pendingTaskMode) ? LayoutManager.InferTaskMode(name) : pendingTaskMode;
            var layout = manager.SaveCurrent(name, taskMode);
            pendingTaskMode = null;
            RefreshLayouts(layout.Name);
            statusLabel.Text = "已保存：" + layout.Name + "（" + layout.Items.Count + " 个窗口）。";
        }

        private void OverwriteSelected()
        {
            var selected = SelectedLayout();
            if (selected == null)
            {
                statusLabel.Text = "先选一个要覆盖的布局。";
                return;
            }
            var layout = manager.SaveCurrent(selected.Name, selected.TaskMode);
            RefreshLayouts(layout.Name);
            statusLabel.Text = "已覆盖：" + layout.Name + "（" + layout.Items.Count + " 个窗口）。";
        }

        private void RenameSelected()
        {
            var selected = SelectedLayout();
            if (selected == null)
            {
                statusLabel.Text = "先选一个要重命名的布局。";
                return;
            }

            var name = PromptForm.Ask("重命名布局", "新的布局名称：", selected.Name);
            if (string.IsNullOrWhiteSpace(name))
            {
                statusLabel.Text = "已取消。";
                return;
            }

            try
            {
                var layout = manager.RenameLayout(selected, name);
                RefreshLayouts(layout.Name);
                statusLabel.Text = "已重命名：" + layout.Name;
            }
            catch (Exception ex)
            {
                statusLabel.Text = "重命名失败：" + ex.Message;
            }
        }

        private void DeleteSelected()
        {
            var selected = SelectedLayout();
            if (selected == null)
            {
                statusLabel.Text = "先选一个要删除的布局。";
                return;
            }
            var ok = MessageBox.Show(this, "删除布局“" + selected.Name + "”？", "确认删除", MessageBoxButtons.OKCancel, MessageBoxIcon.Question);
            if (ok != DialogResult.OK) return;
            manager.DeleteLayout(selected);
            RefreshLayouts();
            statusLabel.Text = "已删除：" + selected.Name;
        }

        private void ExportSelected()
        {
            var selected = SelectedLayout();
            if (selected == null)
            {
                statusLabel.Text = "先选一个要导出的布局。";
                return;
            }
            try
            {
                var json = manager.ExportLayoutJson(selected);
                statusLabel.Text = "已导出 JSON：" + json;
            }
            catch (Exception ex)
            {
                statusLabel.Text = "导出失败：" + ex.Message;
            }
        }

        private void ImportLayout()
        {
            using (var dialog = new OpenFileDialog())
            {
                dialog.Title = "导入布局 JSON";
                dialog.Filter = "布局 JSON (*.json)|*.json|所有文件 (*.*)|*.*";
                dialog.Multiselect = false;
                dialog.CheckFileExists = true;
                dialog.InitialDirectory = Directory.Exists(manager.LayoutDir) ? manager.LayoutDir : AppDomain.CurrentDomain.BaseDirectory;
                if (dialog.ShowDialog(this) != DialogResult.OK)
                {
                    statusLabel.Text = "已取消。";
                    return;
                }

                try
                {
                    var layout = manager.ImportLayoutJson(dialog.FileName);
                    RefreshLayouts(layout.Name);
                    statusLabel.Text = "已导入：" + layout.Name;
                }
                catch (Exception ex)
                {
                    statusLabel.Text = "导入失败：" + ex.Message;
                }
            }
        }

    }

    [DataContract]
    public class VersionInfo
    {
        [DataMember(Name = "version")]
        public string Version { get; set; }

        [DataMember(Name = "download_url")]
        public string DownloadUrl { get; set; }

        [DataMember(Name = "release_notes")]
        public string ReleaseNotes { get; set; }

        [DataMember(Name = "published_at")]
        public string PublishedAt { get; set; }
    }

    public static class UpdateChecker
    {
        public static VersionInfo CheckForUpdate(out string error)
        {
            error = null;
            try
            {
                EnableModernTls();
                var url = Program.VersionCheckUrl;
                var request = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url);
                request.Timeout = 8000;
                request.ReadWriteTimeout = 8000;
                request.Method = "GET";
                request.UserAgent = "WindowLayoutLauncher/" + Program.Version;
                request.AutomaticDecompression = System.Net.DecompressionMethods.GZip | System.Net.DecompressionMethods.Deflate;
                request.Headers.Add("Cache-Control", "no-cache");

                using (var response = request.GetResponse())
                using (var stream = response.GetResponseStream())
                using (var reader = new StreamReader(stream, Encoding.UTF8))
                {
                    var json = reader.ReadToEnd();
                    if (string.IsNullOrWhiteSpace(json))
                    {
                        error = "版本信息为空";
                        return null;
                    }

                    using (var ms = new MemoryStream(Encoding.UTF8.GetBytes(json)))
                    {
                        var serializer = new DataContractJsonSerializer(typeof(VersionInfo));
                        var info = (VersionInfo)serializer.ReadObject(ms);
                        if (info == null || string.IsNullOrWhiteSpace(info.Version))
                        {
                            error = "版本信息格式错误";
                            return null;
                        }
                        return info;
                    }
                }
            }
            catch (Exception ex)
            {
                error = ex.Message;
                return null;
            }
        }

        public static bool IsNewerVersion(string remoteVersion, string currentVersion)
        {
            try
            {
                var r = NormalizeVersion(remoteVersion);
                var c = NormalizeVersion(currentVersion);
                if (r == null || c == null) return false;
                return r > c;
            }
            catch
            {
                return false;
            }
        }

        private static Version NormalizeVersion(string v)
        {
            if (string.IsNullOrWhiteSpace(v)) return null;
            var cleaned = new StringBuilder();
            foreach (var ch in v)
            {
                if (char.IsDigit(ch) || ch == '.')
                    cleaned.Append(ch);
            }
            var parts = cleaned.ToString().Split(new[] { '.' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0) return null;
            var nums = new List<int>();
            for (int i = 0; i < 4; i++)
            {
                nums.Add(i < parts.Length ? int.Parse(parts[i]) : 0);
            }
            return new Version(nums[0], nums[1], nums[2], nums[3]);
        }

        public static string DownloadUpdate(string url, string targetPath, Action<int> progressCallback)
        {
            try
            {
                EnableModernTls();
                using (var client = new System.Net.WebClient())
                {
                    client.Headers[System.Net.HttpRequestHeader.UserAgent] = "WindowLayoutLauncher/" + Program.Version;
                    var done = false;
                    client.DownloadProgressChanged += (s, e) =>
                    {
                        if (progressCallback != null) progressCallback(e.ProgressPercentage);
                    };
                    client.DownloadFileCompleted += (s, e) =>
                    {
                        done = true;
                    };
                    client.DownloadFileAsync(new Uri(url), targetPath);
                    while (!done)
                    {
                        Application.DoEvents();
                        Thread.Sleep(50);
                    }
                }
                if (File.Exists(targetPath) && new FileInfo(targetPath).Length > 0)
                {
                    return null;
                }
                return "下载文件为空";
            }
            catch (Exception ex)
            {
                return ex.Message;
            }
        }

        private static void EnableModernTls()
        {
            const System.Net.SecurityProtocolType tls12 = (System.Net.SecurityProtocolType)3072;
            System.Net.ServicePointManager.SecurityProtocol = System.Net.ServicePointManager.SecurityProtocol | tls12;
        }

        public static bool ApplyUpdate(string newExePath)
        {
            try
            {
                var currentExe = Application.ExecutablePath;
                var dir = Path.GetDirectoryName(currentExe);
                var batPath = Path.Combine(dir, "update.bat");
                var oldExeBackup = Path.Combine(dir, "窗口布局启动器_old.exe");

                var sb = new StringBuilder();
                sb.AppendLine("@echo off");
                sb.AppendLine("echo 正在更新窗口布局启动器...");
                sb.AppendLine("timeout /t 2 /nobreak >nul");
                sb.AppendLine("if exist \"" + oldExeBackup + "\" del \"" + oldExeBackup + "\"");
                sb.AppendLine("ren \"" + currentExe + "\" \"" + Path.GetFileName(oldExeBackup) + "\"");
                sb.AppendLine("move /Y \"" + newExePath + "\" \"" + currentExe + "\"");
                sb.AppendLine("echo 更新完成，正在启动新版本...");
                sb.AppendLine("start \"\" \"" + currentExe + "\"");
                sb.AppendLine("del \"%~f0\"");
                File.WriteAllText(batPath, sb.ToString(), Encoding.Default);

                Process.Start(new ProcessStartInfo
                {
                    FileName = batPath,
                    WorkingDirectory = dir,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    CreateNoWindow = true
                });

                return true;
            }
            catch
            {
                return false;
            }
        }
    }

    public class AboutForm : Form
    {
        private Label titleLabel;
        private Label versionLabel;
        private Label descLabel;
        private LinkLabel repoLink;
        private GlassButton checkUpdateButton;
        private GlassButton closeButton;
        private Label updateStatusLabel;

        public AboutForm()
        {
            AutoScaleMode = AutoScaleMode.None;
            Text = "关于 " + Program.AppName;
            StartPosition = FormStartPosition.CenterParent;
            Size = UiTheme.DpiSize(480, 360);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            Font = new Font("Microsoft YaHei UI", 9F);
            BackColor = UiTheme.WindowTop;

            titleLabel = new Label();
            titleLabel.Text = Program.AppName;
            titleLabel.Font = new Font("Microsoft YaHei UI", 16F, FontStyle.Bold);
            titleLabel.ForeColor = UiTheme.Ink;
            titleLabel.BackColor = Color.Transparent;
            titleLabel.AutoSize = true;
            titleLabel.Left = 30;
            titleLabel.Top = 25;
            Controls.Add(titleLabel);

            versionLabel = new Label();
            versionLabel.Text = "版本 v" + Program.Version;
            versionLabel.Font = new Font("Microsoft YaHei UI", 10F);
            versionLabel.ForeColor = UiTheme.Muted;
            versionLabel.BackColor = Color.Transparent;
            versionLabel.AutoSize = true;
            versionLabel.Left = 32;
            versionLabel.Top = 60;
            Controls.Add(versionLabel);

            descLabel = new Label();
            descLabel.Text = "保存不同工作流的窗口位置和大小，下次一键恢复。\n支持文件资源管理器、浏览器和普通应用窗口。";
            descLabel.Font = new Font("Microsoft YaHei UI", 9.5F);
            descLabel.ForeColor = UiTheme.Ink;
            descLabel.BackColor = Color.Transparent;
            descLabel.Left = 32;
            descLabel.Top = 95;
            descLabel.Width = 400;
            descLabel.Height = 60;
            Controls.Add(descLabel);

            repoLink = new LinkLabel();
            repoLink.Text = "开源地址：" + Program.RepoUrl;
            repoLink.Font = new Font("Microsoft YaHei UI", 9F);
            repoLink.ForeColor = UiTheme.Blue;
            repoLink.LinkColor = UiTheme.Blue;
            repoLink.BackColor = Color.Transparent;
            repoLink.Left = 32;
            repoLink.Top = 160;
            repoLink.Width = 400;
            repoLink.AutoSize = true;
            repoLink.LinkClicked += (s, e) =>
            {
                try { Process.Start(Program.RepoUrl); }
                catch { }
            };
            Controls.Add(repoLink);

            updateStatusLabel = new Label();
            updateStatusLabel.Text = "";
            updateStatusLabel.Font = new Font("Microsoft YaHei UI", 9F);
            updateStatusLabel.ForeColor = UiTheme.Muted;
            updateStatusLabel.BackColor = Color.Transparent;
            updateStatusLabel.Left = 32;
            updateStatusLabel.Top = 195;
            updateStatusLabel.Width = 400;
            updateStatusLabel.Height = 25;
            updateStatusLabel.AutoSize = false;
            Controls.Add(updateStatusLabel);

            checkUpdateButton = new GlassButton();
            checkUpdateButton.Text = "检查更新";
            checkUpdateButton.Left = 30;
            checkUpdateButton.Top = 235;
            checkUpdateButton.Width = 110;
            checkUpdateButton.Height = 36;
            checkUpdateButton.Primary = false;
            checkUpdateButton.SurfaceColor = UiTheme.WindowTop;
            checkUpdateButton.BackColor = UiTheme.WindowTop;
            checkUpdateButton.Click += CheckUpdateButton_Click;
            Controls.Add(checkUpdateButton);

            closeButton = new GlassButton();
            closeButton.Text = "关闭";
            closeButton.Left = 340;
            closeButton.Top = 235;
            closeButton.Width = 90;
            closeButton.Height = 36;
            closeButton.Primary = true;
            closeButton.SurfaceColor = UiTheme.WindowTop;
            closeButton.BackColor = UiTheme.WindowTop;
            closeButton.DialogResult = DialogResult.OK;
            Controls.Add(closeButton);

            AcceptButton = closeButton;
            CancelButton = closeButton;
        }

        private void CheckUpdateButton_Click(object sender, EventArgs e)
        {
            checkUpdateButton.Enabled = false;
            updateStatusLabel.Text = "正在检查更新...";
            updateStatusLabel.ForeColor = UiTheme.Muted;
            Refresh();

            string error;
            var info = UpdateChecker.CheckForUpdate(out error);

            if (info == null)
            {
                updateStatusLabel.Text = "检查失败：" + (error ?? "未知错误");
                updateStatusLabel.ForeColor = Color.FromArgb(220, 80, 80);
                checkUpdateButton.Enabled = true;
                return;
            }

            if (UpdateChecker.IsNewerVersion(info.Version, Program.Version))
            {
                updateStatusLabel.Text = "发现新版本 v" + info.Version;
                updateStatusLabel.ForeColor = UiTheme.Blue;
                var result = MessageBox.Show(this,
                    "发现新版本 v" + info.Version + "\n\n" +
                    (info.ReleaseNotes ?? "暂无更新说明") + "\n\n" +
                    "是否立即更新？",
                    "发现新版本",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Information);

                if (result == DialogResult.Yes)
                {
                    DoUpdate(info);
                }
            }
            else
            {
                updateStatusLabel.Text = "当前已是最新版本";
                updateStatusLabel.ForeColor = Color.FromArgb(60, 160, 100);
            }
            checkUpdateButton.Enabled = true;
        }

        private void DoUpdate(VersionInfo info)
        {
            var tempDir = Path.Combine(Path.GetTempPath(), "WLL_Update");
            Directory.CreateDirectory(tempDir);
            var newExe = Path.Combine(tempDir, "窗口布局启动器_new.exe");

            var progressForm = new Form();
            progressForm.Text = "正在下载更新";
            progressForm.Size = UiTheme.DpiSize(360, 120);
            progressForm.StartPosition = FormStartPosition.CenterParent;
            progressForm.FormBorderStyle = FormBorderStyle.FixedDialog;
            progressForm.MaximizeBox = false;
            progressForm.MinimizeBox = false;
            progressForm.BackColor = UiTheme.WindowTop;
            progressForm.Font = new Font("Microsoft YaHei UI", 9F);

            var progressLabel = new Label();
            progressLabel.Text = "正在下载新版本...";
            progressLabel.Left = 25;
            progressLabel.Top = 20;
            progressLabel.Width = 300;
            progressLabel.ForeColor = UiTheme.Ink;
            progressLabel.BackColor = Color.Transparent;
            progressForm.Controls.Add(progressLabel);

            var progressBar = new ProgressBar();
            progressBar.Left = 25;
            progressBar.Top = 50;
            progressBar.Width = 300;
            progressBar.Height = 20;
            progressBar.Style = ProgressBarStyle.Continuous;
            progressForm.Controls.Add(progressBar);

            progressForm.Shown += (s, e) =>
            {
                var error = UpdateChecker.DownloadUpdate(info.DownloadUrl, newExe, p =>
                {
                    try
                    {
                        progressBar.Value = Math.Max(0, Math.Min(100, p));
                        progressLabel.Text = "正在下载... " + p + "%";
                    }
                    catch { }
                });

                progressForm.DialogResult = string.IsNullOrEmpty(error) ? DialogResult.OK : DialogResult.Abort;
                progressForm.Close();
            };

            var result = progressForm.ShowDialog(this);
            if (result != DialogResult.OK)
            {
                updateStatusLabel.Text = "下载失败";
                updateStatusLabel.ForeColor = Color.FromArgb(220, 80, 80);
                return;
            }

            var confirm = MessageBox.Show(this,
                "下载完成，是否立即安装更新？\n（安装时会自动关闭当前程序）",
                "更新下载完成",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);

            if (confirm == DialogResult.Yes)
            {
                if (UpdateChecker.ApplyUpdate(newExe))
                {
                    Application.Exit();
                }
                else
                {
                    MessageBox.Show(this, "更新失败，请手动下载替换。", "更新失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }
    }

    public class SetupWizardForm : Form
    {
        private ComboBox modeBox;
        public string TaskMode { get { return Convert.ToString(modeBox.SelectedItem); } }

        public SetupWizardForm()
        {
            AutoScaleMode = AutoScaleMode.None;
            Text = "第一次使用";
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(500, 310);
            MinimumSize = new Size(460, 290);
            Font = new Font("Microsoft YaHei UI", 9F);
            BackColor = UiTheme.WindowTop;

            var root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(34, 28, 34, 24);
            root.ColumnCount = 1;
            root.RowCount = 6;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 52F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42F));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42F));
            Controls.Add(root);

            var title = new Label { Text = "你要创建哪种工作布局？", Dock = DockStyle.Fill, Font = new Font("Microsoft YaHei UI", 14F, FontStyle.Bold), ForeColor = UiTheme.Ink };
            root.Controls.Add(title, 0, 0);
            var guide = new Label { Text = "选择工作类型后，打开需要的文件夹、网页和软件，把窗口摆好，再回到这里保存。", Dock = DockStyle.Fill, ForeColor = UiTheme.Muted };
            root.Controls.Add(guide, 0, 1);
            var label = new Label { Text = "工作类型", Dock = DockStyle.Fill, ForeColor = UiTheme.Ink, TextAlign = ContentAlignment.BottomLeft };
            root.Controls.Add(label, 0, 2);

            modeBox = new ComboBox();
            modeBox.Dock = DockStyle.Top;
            modeBox.DropDownStyle = ComboBoxStyle.DropDownList;
            modeBox.Items.AddRange(new object[] { "素材处理", "GPT 双开", "剪辑", "写小红书", "运营", "客服工作", "做团建方案", "其他工作" });
            modeBox.SelectedIndex = 0;
            root.Controls.Add(modeBox, 0, 3);

            var tip = new Label { Text = "这一步不会替你打开固定软件，只负责确定这套布局以后显示成“开始什么工作”。", Dock = DockStyle.Fill, ForeColor = UiTheme.Muted, TextAlign = ContentAlignment.TopLeft };
            root.Controls.Add(tip, 0, 4);

            var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft, WrapContents = false };
            var ok = new GlassButton { Text = "开始准备", Width = 110, Height = 36, Primary = true, SurfaceColor = UiTheme.WindowTop, BackColor = UiTheme.WindowTop, DialogResult = DialogResult.OK };
            var cancel = new GlassButton { Text = "稍后再说", Width = 100, Height = 36, SurfaceColor = UiTheme.WindowTop, BackColor = UiTheme.WindowTop, DialogResult = DialogResult.Cancel };
            buttons.Controls.Add(ok);
            buttons.Controls.Add(cancel);
            root.Controls.Add(buttons, 0, 5);
            AcceptButton = ok;
            CancelButton = cancel;
        }
    }

    public class PromptForm : Form
    {
        private TextBox textBox;
        public string Value { get { return textBox.Text; } }

        public static string Ask(string title, string message, string defaultValue)
        {
            using (var form = new PromptForm(title, message, defaultValue))
            {
                return form.ShowDialog() == DialogResult.OK ? form.Value : null;
            }
        }

        private PromptForm(string title, string message, string defaultValue)
        {
            AutoScaleMode = AutoScaleMode.None;
            Text = title;
            StartPosition = FormStartPosition.CenterParent;
            Size = UiTheme.DpiSize(420, 178);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            Font = new Font("Microsoft YaHei UI", 9F);
            BackColor = UiTheme.WindowTop;

            var label = new Label();
            label.Text = message;
            label.Left = 24;
            label.Top = 22;
            label.Width = 350;
            label.Height = 24;
            label.ForeColor = UiTheme.Ink;
            label.BackColor = Color.Transparent;
            Controls.Add(label);

            textBox = new TextBox();
            textBox.Left = 24;
            textBox.Top = 54;
            textBox.Width = 354;
            textBox.Height = 26;
            textBox.BorderStyle = BorderStyle.FixedSingle;
            textBox.Text = defaultValue;
            Controls.Add(textBox);

            var ok = new GlassButton();
            ok.Text = "确定";
            ok.Left = 212;
            ok.Top = 100;
            ok.Width = 78;
            ok.Height = 34;
            ok.Primary = true;
            ok.SurfaceColor = UiTheme.WindowTop;
            ok.BackColor = UiTheme.WindowTop;
            ok.DialogResult = DialogResult.OK;
            Controls.Add(ok);

            var cancel = new GlassButton();
            cancel.Text = "取消";
            cancel.Left = 300;
            cancel.Top = 100;
            cancel.Width = 78;
            cancel.Height = 34;
            cancel.SurfaceColor = UiTheme.WindowTop;
            cancel.BackColor = UiTheme.WindowTop;
            cancel.DialogResult = DialogResult.Cancel;
            Controls.Add(cancel);

            AcceptButton = ok;
            CancelButton = cancel;
            Shown += (s, e) => { textBox.SelectAll(); textBox.Focus(); };
        }
    }
}
