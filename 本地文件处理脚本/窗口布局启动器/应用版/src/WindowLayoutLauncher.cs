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
using System.IO.Compression;

namespace WindowLayoutLauncher
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            try
            {
                TrySetDpiAwareness();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

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
        [DataMember(Name = "name")]
        public string Name { get; set; }

        [DataMember(Name = "saved_at")]
        public string SavedAt { get; set; }

        [DataMember(Name = "items")]
        public List<LayoutItem> Items { get; set; }
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
    }

    public class LayoutSummary
    {
        public string Name { get; set; }
        public string Path { get; set; }
        public string SavedAt { get; set; }
        public int Count { get; set; }
        public string Display
        {
            get { return Name + "    " + Count + " 个窗口"; }
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
                        Count = layout.Items == null ? 0 : layout.Items.Count
                    });
                }
                catch
                {
                }
            }
            return result;
        }

        public LayoutConfig SaveCurrent(string name)
        {
            var safeName = SafeName(name);
            var topWindows = WindowTools.GetTopLevelWindows();
            var items = new List<LayoutItem>();

            foreach (var explorer in WindowTools.GetExplorerWindows(topWindows, false).OrderBy(w => w.X).ThenBy(w => w.Y))
            {
                items.Add(new LayoutItem
                {
                    Kind = "explorer",
                    Path = explorer.Path,
                    X = explorer.X,
                    Y = explorer.Y,
                    W = explorer.W,
                    H = explorer.H
                });
            }

            foreach (var browser in topWindows
                .Where(w => (EqualsIgnoreCase(w.ProcessName, "msedge") || EqualsIgnoreCase(w.ProcessName, "chrome")) &&
                            ContainsIgnoreCase(w.Title, "ChatGPT") &&
                            !w.IsMinimized)
                .OrderBy(w => w.X).ThenBy(w => w.Y))
            {
                items.Add(new LayoutItem
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
                });
            }

            var layout = new LayoutConfig
            {
                Name = safeName,
                SavedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                Items = items
            };

            WriteLayout(GetLayoutPath(safeName), layout);
            return layout;
        }

        public RestoreResult Restore(string nameOrPath)
        {
            var path = File.Exists(nameOrPath) ? nameOrPath : GetLayoutPath(SafeName(nameOrPath));
            if (!File.Exists(path))
            {
                return new RestoreResult { Ok = 0, Failed = 1, Message = "没有找到这个布局" };
            }

            var layout = ReadLayout(path);
            var topWindows = WindowTools.GetTopLevelWindows();
            var explorerWindows = WindowTools.GetExplorerWindows(topWindows, true);
            var used = new HashSet<IntPtr>();
            int ok = 0;
            int failed = 0;

            foreach (var item in layout.Items ?? new List<LayoutItem>())
            {
                IntPtr hwnd = IntPtr.Zero;
                if (EqualsIgnoreCase(item.Kind, "explorer"))
                {
                    hwnd = FindOrOpenExplorer(item.Path, explorerWindows);
                }
                else if (EqualsIgnoreCase(item.Kind, "browser"))
                {
                    hwnd = FindOrOpenBrowser(item, topWindows, used);
                }

                if (hwnd == IntPtr.Zero)
                {
                    failed++;
                    continue;
                }

                if (WindowTools.MoveWindow(hwnd, item.X, item.Y, item.W, item.H))
                {
                    ok++;
                    used.Add(hwnd);
                }
                else
                {
                    failed++;
                }
            }

            return new RestoreResult
            {
                Ok = ok,
                Failed = failed,
                Message = failed > 0 ? "已恢复 " + ok + "，失败 " + failed : "已恢复窗口布局 " + ok
            };
        }

        public void DeleteLayout(LayoutSummary summary)
        {
            if (summary == null || string.IsNullOrWhiteSpace(summary.Path)) return;
            if (File.Exists(summary.Path)) File.Delete(summary.Path);
        }

        public string ExportSharePackage(LayoutSummary summary)
        {
            if (summary == null || !File.Exists(summary.Path))
            {
                throw new InvalidOperationException("先选择一个布局。");
            }

            var exportRoot = System.IO.Path.Combine(baseDir, "exports");
            Directory.CreateDirectory(exportRoot);
            var safeName = SafeName(summary.Name);
            var stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            var tempRoot = System.IO.Path.Combine(Path.GetTempPath(), "WindowLayoutShare_" + stamp);
            var packageRoot = System.IO.Path.Combine(tempRoot, "窗口布局启动器-" + safeName);
            var packageLayoutDir = System.IO.Path.Combine(packageRoot, "layouts");
            Directory.CreateDirectory(packageLayoutDir);

            var exePath = Application.ExecutablePath;
            File.Copy(exePath, System.IO.Path.Combine(packageRoot, System.IO.Path.GetFileName(exePath)), true);
            File.Copy(summary.Path, System.IO.Path.Combine(packageLayoutDir, safeName + ".json"), true);
            File.WriteAllText(System.IO.Path.Combine(packageRoot, "使用说明.txt"),
                "1. 双击“窗口布局启动器.exe”。\r\n" +
                "2. 选择布局后点击“打开布局”。\r\n" +
                "3. 如果文件夹路径和你的电脑不一样，请先摆好窗口，再点“保存为新布局”。\r\n" +
                "4. 浏览器窗口主要按浏览器类型和标题关键字匹配，例如 ChatGPT。\r\n",
                Encoding.UTF8);

            var zipPath = System.IO.Path.Combine(exportRoot, "窗口布局启动器-" + safeName + "-" + stamp + ".zip");
            if (File.Exists(zipPath)) File.Delete(zipPath);
            ZipFile.CreateFromDirectory(packageRoot, zipPath);

            try { Directory.Delete(tempRoot, true); } catch { }
            return zipPath;
        }

        public string GetLayoutPath(string name)
        {
            return System.IO.Path.Combine(layoutDir, SafeName(name) + ".json");
        }

        private IntPtr FindOrOpenExplorer(string path, List<ExplorerInfo> existing)
        {
            if (string.IsNullOrWhiteSpace(path)) return IntPtr.Zero;
            var target = FullPathTrim(path);
            var found = existing.FirstOrDefault(w => EqualsIgnoreCase(FullPathTrim(w.Path), target));
            if (found != null) return found.Hwnd;
            if (!Directory.Exists(path)) return IntPtr.Zero;

            Process.Start("explorer.exe", "\"" + path + "\"");
            var created = WaitFor(() =>
            {
                return WindowTools.GetExplorerWindows(WindowTools.GetTopLevelWindows(), true)
                    .FirstOrDefault(w => EqualsIgnoreCase(FullPathTrim(w.Path), target));
            }, 3500);
            return created == null ? IntPtr.Zero : created.Hwnd;
        }

        private IntPtr FindOrOpenBrowser(LayoutItem item, List<WindowInfo> existing, HashSet<IntPtr> used)
        {
            var processName = EqualsIgnoreCase(item.Browser, "edge") ? "msedge" :
                              EqualsIgnoreCase(item.Browser, "chrome") ? "chrome" : item.Browser;
            var keyword = string.IsNullOrWhiteSpace(item.TitleKeyword) ? "ChatGPT" : item.TitleKeyword;
            var found = existing
                .Where(w => EqualsIgnoreCase(w.ProcessName, processName) && !used.Contains(w.Hwnd))
                .Where(w => string.IsNullOrWhiteSpace(keyword) || ContainsIgnoreCase(w.Title, keyword))
                .OrderBy(w => w.X).ThenBy(w => w.Y)
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
            catch
            {
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
            }, 4500);

            return created == null ? IntPtr.Zero : created.Hwnd;
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

        private static string FullPathTrim(string path)
        {
            try { return System.IO.Path.GetFullPath(path).TrimEnd('\\'); }
            catch { return (path ?? "").TrimEnd('\\'); }
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
        public static readonly Color Sidebar = Color.FromArgb(218, 228, 236);
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
        private ListBox listBox;
        private Label statusLabel;
        private GlassPanel card;

        public MainForm(LayoutManager manager)
        {
            this.manager = manager;
            Initialize();
            RefreshLayouts();
        }

        private void Initialize()
        {
            AutoScaleMode = AutoScaleMode.None;
            Text = "窗口布局启动器";
            StartPosition = FormStartPosition.CenterScreen;
            Size = UiTheme.DpiSize(790, 545);
            MinimumSize = UiTheme.DpiSize(760, 520);
            BackColor = UiTheme.WindowBottom;
            Font = new Font("Microsoft YaHei UI", 9F);
            DoubleBuffered = true;
            Shown += (s, e) => CenterOnPrimaryScreen();

            var sidebar = new GlassPanel();
            sidebar.Left = 14;
            sidebar.Top = 14;
            sidebar.Width = 220;
            sidebar.Height = 492;
            sidebar.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Bottom;
            sidebar.Radius = 30;
            sidebar.FillColor = UiTheme.Sidebar;
            Controls.Add(sidebar);

            var brand = new Label();
            brand.Text = "窗口布局启动器";
            brand.Left = 24;
            brand.Top = 24;
            brand.Width = 178;
            brand.Height = 30;
            brand.Font = new Font("Microsoft YaHei UI", 11.5F, FontStyle.Bold);
            brand.ForeColor = UiTheme.Blue;
            brand.BackColor = Color.Transparent;
            sidebar.Controls.Add(brand);

            var role = new Label();
            role.Text = "保存和恢复工作窗口";
            role.Left = 24;
            role.Top = 55;
            role.Width = 160;
            role.Height = 20;
            role.ForeColor = UiTheme.Muted;
            role.BackColor = Color.Transparent;
            sidebar.Controls.Add(role);

            AddSidebarLine(sidebar, "已保存布局", 110, true);
            AddSidebarLine(sidebar, "保存当前窗口", 162, false);
            AddSidebarLine(sidebar, "导出分享包", 214, false);
            AddSidebarLine(sidebar, "打开布局文件夹", 266, false);

            var sidebarTip = new Label();
            sidebarTip.Text = "已经打开或最小化的窗口会直接复用；没打开的窗口才会重新打开。";
            sidebarTip.Left = 24;
            sidebarTip.Top = 378;
            sidebarTip.Width = 162;
            sidebarTip.Height = 54;
            sidebarTip.ForeColor = UiTheme.Muted;
            sidebarTip.BackColor = Color.Transparent;
            sidebarTip.Font = new Font("Microsoft YaHei UI", 8.5F);
            sidebarTip.TextAlign = ContentAlignment.TopLeft;
            sidebar.Controls.Add(sidebarTip);

            var version = new Label();
            version.Text = "V 1.1  悬浮拟态版";
            version.Left = 24;
            version.Top = 444;
            version.Width = 162;
            version.Height = 24;
            version.ForeColor = Color.FromArgb(122, 139, 158);
            version.BackColor = Color.Transparent;
            version.Font = new Font("Microsoft YaHei UI", 8F);
            sidebar.Controls.Add(version);

            var title = new Label();
            title.Text = "窗口布局中心";
            title.Left = 262;
            title.Top = 30;
            title.Width = 390;
            title.Height = 36;
            title.Font = new Font("Microsoft YaHei UI", 14.5F, FontStyle.Bold);
            title.ForeColor = UiTheme.Ink;
            title.BackColor = Color.Transparent;
            Controls.Add(title);

            var hint = new Label();
            hint.Text = "保存不同工作的窗口位置，需要时一键恢复到对应位置。";
            hint.Left = 264;
            hint.Top = 64;
            hint.Width = 460;
            hint.Height = 24;
            hint.ForeColor = UiTheme.Muted;
            hint.BackColor = Color.Transparent;
            Controls.Add(hint);

            card = new GlassPanel();
            card.Left = 246;
            card.Top = 92;
            card.Width = 514;
            card.Height = 336;
            card.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right | AnchorStyles.Bottom;
            card.FillColor = UiTheme.Panel;
            Controls.Add(card);

            var cardTitle = new Label();
            cardTitle.Text = "已保存布局";
            cardTitle.Left = 28;
            cardTitle.Top = 24;
            cardTitle.Width = 180;
            cardTitle.Height = 22;
            cardTitle.Font = new Font("Microsoft YaHei UI", 9.5F, FontStyle.Bold);
            cardTitle.ForeColor = UiTheme.Ink;
            cardTitle.BackColor = Color.Transparent;
            card.Controls.Add(cardTitle);

            var cardHint = new Label();
            cardHint.Text = "选择后操作";
            cardHint.Left = 360;
            cardHint.Top = 24;
            cardHint.Width = 140;
            cardHint.Height = 22;
            cardHint.Font = new Font("Microsoft YaHei UI", 8F);
            cardHint.ForeColor = UiTheme.Muted;
            cardHint.BackColor = Color.Transparent;
            cardHint.TextAlign = ContentAlignment.MiddleRight;
            cardHint.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            card.Controls.Add(cardHint);

            listBox = new ListBox();
            listBox.Left = 28;
            listBox.Top = 58;
            listBox.Width = 302;
            listBox.Height = 238;
            listBox.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Bottom;
            listBox.DisplayMember = "Display";
            listBox.BackColor = UiTheme.Panel;
            listBox.ForeColor = UiTheme.Ink;
            listBox.BorderStyle = BorderStyle.None;
            listBox.DrawMode = DrawMode.OwnerDrawFixed;
            listBox.ItemHeight = 54;
            listBox.IntegralHeight = false;
            listBox.DrawItem += DrawLayoutItem;
            listBox.DoubleClick += (s, e) => RestoreSelected();
            card.Controls.Add(listBox);

            AddButton(card, "打开布局", 354, 58, true, (s, e) => RestoreSelected());
            AddButton(card, "保存为新布局", 354, 99, false, (s, e) => SaveNew());
            AddButton(card, "覆盖所选布局", 354, 140, false, (s, e) => OverwriteSelected());
            AddButton(card, "导出分享包", 354, 181, false, (s, e) => ExportSelected());
            AddButton(card, "删除所选布局", 354, 222, false, (s, e) => DeleteSelected());
            AddButton(card, "布局文件夹", 354, 263, false, (s, e) => Process.Start("explorer.exe", manager.LayoutDir));

            var statusCard = new GlassPanel();
            statusCard.Left = 246;
            statusCard.Top = 442;
            statusCard.Width = 514;
            statusCard.Height = 64;
            statusCard.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
            statusCard.Radius = 20;
            statusCard.FillColor = UiTheme.Panel;
            Controls.Add(statusCard);

            statusLabel = new Label();
            statusLabel.Left = 24;
            statusLabel.Top = 22;
            statusLabel.Width = 456;
            statusLabel.Height = 24;
            statusLabel.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top;
            statusLabel.ForeColor = UiTheme.Muted;
            statusLabel.BackColor = Color.Transparent;
            statusCard.Controls.Add(statusLabel);
        }

        private void CenterOnPrimaryScreen()
        {
            var area = Screen.PrimaryScreen.WorkingArea;
            int x = area.Left + Math.Max(0, (area.Width - Width) / 2);
            int y = area.Top + Math.Max(0, (area.Height - Height) / 2);
            Location = new Point(x, y);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            using (var brush = new LinearGradientBrush(ClientRectangle, UiTheme.WindowTop, UiTheme.WindowBottom, 90F))
            {
                e.Graphics.FillRectangle(brush, ClientRectangle);
            }
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var b1 = new SolidBrush(Color.FromArgb(34, 48, 126, 255)))
            using (var b2 = new SolidBrush(Color.FromArgb(52, 255, 255, 255)))
            using (var b3 = new SolidBrush(Color.FromArgb(24, 65, 213, 207)))
            {
                e.Graphics.FillEllipse(b1, new Rectangle(Width - 250, -110, 320, 260));
                e.Graphics.FillEllipse(b2, new Rectangle(-130, Height - 220, 280, 260));
                e.Graphics.FillEllipse(b3, new Rectangle(Width - 260, Height - 170, 180, 150));
            }
        }

        private void TryEnableBackdrop()
        {
            try
            {
                int backdrop = 2;
                Native.DwmSetWindowAttribute(Handle, 38, ref backdrop, sizeof(int));
            }
            catch
            {
            }
        }

        private void AddButton(Control parent, string text, int left, int top, bool primary, EventHandler handler)
        {
            var button = new GlassButton();
            button.Text = text;
            button.Left = left;
            button.Top = top;
            button.Width = 136;
            button.Height = 34;
            button.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            button.Primary = primary;
            button.SurfaceColor = UiTheme.Panel;
            button.BackColor = UiTheme.Panel;
            button.Font = new Font("Microsoft YaHei UI", 9F, primary ? FontStyle.Bold : FontStyle.Regular);
            button.Click += handler;
            parent.Controls.Add(button);
        }

        private void AddSidebarLine(Control parent, string text, int top, bool active)
        {
            Control host = parent;
            int labelLeft = 26;
            int labelTop = top;
            if (active)
            {
                var nav = new GlassPanel();
                nav.Left = 10;
                nav.Top = top - 12;
                nav.Width = 194;
                nav.Height = 48;
                nav.Radius = 16;
                nav.FillColor = UiTheme.PanelLight;
                parent.Controls.Add(nav);
                host = nav;
                labelLeft = 24;
                labelTop = 13;
            }

            var label = new Label();
            label.Text = text;
            label.Left = labelLeft;
            label.Top = labelTop;
            label.Width = active ? 148 : 160;
            label.Height = 24;
            label.Font = new Font("Microsoft YaHei UI", 9F, active ? FontStyle.Bold : FontStyle.Regular);
            label.ForeColor = active ? UiTheme.Ink : Color.FromArgb(66, 78, 92);
            label.BackColor = Color.Transparent;
            label.TextAlign = ContentAlignment.MiddleLeft;
            host.Controls.Add(label);
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
            var rect = new Rectangle(e.Bounds.Left + 4, e.Bounds.Top + 5, e.Bounds.Width - 8, e.Bounds.Height - 10);
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
            var meta = item == null ? "" : (item.Count + " 个窗口  " + item.SavedAt);
            int textLeft = rect.Left + (selected ? 22 : 14);
            using (var nameFont = new Font("Microsoft YaHei UI", 10F, FontStyle.Bold))
            using (var metaFont = new Font("Microsoft YaHei UI", 8F))
            {
                TextRenderer.DrawText(e.Graphics, name, nameFont, new Rectangle(textLeft, rect.Top + 7, rect.Width - 28, 18), UiTheme.Ink, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
                TextRenderer.DrawText(e.Graphics, meta, metaFont, new Rectangle(textLeft, rect.Top + 29, rect.Width - 28, 16), UiTheme.Muted, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
            }
        }

        private void RefreshLayouts()
        {
            listBox.Items.Clear();
            foreach (var layout in manager.GetLayouts())
            {
                listBox.Items.Add(layout);
            }
            if (listBox.Items.Count > 0) listBox.SelectedIndex = 0;
            statusLabel.Text = listBox.Items.Count > 0 ? "已加载 " + listBox.Items.Count + " 个布局。" : "还没有布局。先摆好窗口，然后点“保存为新布局”。";
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

            statusLabel.Text = "正在恢复：" + selected.Name;
            Refresh();
            var sw = Stopwatch.StartNew();
            var result = manager.Restore(selected.Name);
            sw.Stop();
            statusLabel.Text = result.Message + "，用时 " + sw.Elapsed.TotalSeconds.ToString("0.0") + " 秒。";
        }

        private void SaveNew()
        {
            var name = PromptForm.Ask("保存为新布局", "给这个布局起个名字：", "新布局");
            if (string.IsNullOrWhiteSpace(name))
            {
                statusLabel.Text = "已取消。";
                return;
            }
            var layout = manager.SaveCurrent(name);
            RefreshLayouts();
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
            var layout = manager.SaveCurrent(selected.Name);
            RefreshLayouts();
            statusLabel.Text = "已覆盖：" + layout.Name + "（" + layout.Items.Count + " 个窗口）。";
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
                var zip = manager.ExportSharePackage(selected);
                statusLabel.Text = "已导出分享包：" + zip;
                Process.Start("explorer.exe", "/select,\"" + zip + "\"");
            }
            catch (Exception ex)
            {
                statusLabel.Text = "导出失败：" + ex.Message;
            }
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
