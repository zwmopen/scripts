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
    }

    public static class UiTheme
    {
        public static readonly Color Ink = Color.FromArgb(34, 49, 44);
        public static readonly Color Muted = Color.FromArgb(100, 116, 112);
        public static readonly Color Green = Color.FromArgb(54, 143, 101);
        public static readonly Color GreenDeep = Color.FromArgb(24, 98, 68);
        public static readonly Color Glass = Color.FromArgb(218, 255, 255, 255);
        public static readonly Color GlassSoft = Color.FromArgb(168, 255, 255, 255);
        public static readonly Color Border = Color.FromArgb(150, 217, 229, 224);
        public static readonly Color Selection = Color.FromArgb(232, 246, 240);

        public static GraphicsPath RoundedRect(Rectangle rect, int radius)
        {
            int d = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(rect.X, rect.Y, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    public class GlassPanel : Panel
    {
        public int Radius { get; set; }

        public GlassPanel()
        {
            Radius = 24;
            DoubleBuffered = true;
            BackColor = Color.Transparent;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            using (var path = UiTheme.RoundedRect(rect, Radius))
            using (var shadow = new SolidBrush(Color.FromArgb(20, 40, 82, 60)))
            using (var fill = new SolidBrush(UiTheme.Glass))
            using (var pen = new Pen(UiTheme.Border))
            {
                var shadowRect = new Rectangle(rect.X + 2, rect.Y + 4, rect.Width - 2, rect.Height - 2);
                using (var shadowPath = UiTheme.RoundedRect(shadowRect, Radius))
                {
                    e.Graphics.FillPath(shadow, shadowPath);
                }
                e.Graphics.FillPath(fill, path);
                e.Graphics.DrawPath(pen, path);
            }
            base.OnPaint(e);
        }
    }

    public class GlassButton : Button
    {
        private bool hover;
        private bool down;

        public bool Primary { get; set; }

        public GlassButton()
        {
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
            Height = 38;
            DoubleBuffered = true;
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
            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            Color fill;
            Color text;
            if (Primary)
            {
                fill = down ? Color.FromArgb(35, 121, 83) : hover ? Color.FromArgb(63, 158, 113) : UiTheme.Green;
                text = Color.White;
            }
            else
            {
                fill = down ? Color.FromArgb(226, 241, 235) : hover ? Color.FromArgb(238, 248, 244) : Color.FromArgb(232, 255, 255, 255);
                text = UiTheme.GreenDeep;
            }

            using (var path = UiTheme.RoundedRect(rect, 16))
            using (var brush = new SolidBrush(fill))
            using (var pen = new Pen(Primary ? Color.FromArgb(70, 255, 255, 255) : UiTheme.Border))
            using (var textBrush = new SolidBrush(text))
            {
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
            Text = "窗口布局启动器";
            StartPosition = FormStartPosition.CenterScreen;
            Size = new Size(640, 480);
            MinimumSize = new Size(600, 440);
            BackColor = Color.White;
            Font = new Font("Microsoft YaHei UI", 9F);
            DoubleBuffered = true;
            Load += (s, e) => TryEnableBackdrop();

            var title = new Label();
            title.Text = "Window Layout";
            title.Left = 34;
            title.Top = 26;
            title.Width = 520;
            title.Height = 32;
            title.Font = new Font("Segoe UI Variable Display", 18F, FontStyle.Bold);
            title.ForeColor = UiTheme.Ink;
            title.BackColor = Color.Transparent;
            Controls.Add(title);

            var hint = new Label();
            hint.Text = "保存不同工作流的窗口位置，下次一键恢复。";
            hint.Left = 36;
            hint.Top = 60;
            hint.Width = 520;
            hint.Height = 24;
            hint.ForeColor = UiTheme.Muted;
            hint.BackColor = Color.Transparent;
            Controls.Add(hint);

            card = new GlassPanel();
            card.Left = 28;
            card.Top = 98;
            card.Width = 568;
            card.Height = 282;
            card.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right | AnchorStyles.Bottom;
            Controls.Add(card);

            listBox = new ListBox();
            listBox.Left = 24;
            listBox.Top = 26;
            listBox.Width = 340;
            listBox.Height = 216;
            listBox.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Bottom;
            listBox.DisplayMember = "Display";
            listBox.BackColor = Color.FromArgb(248, 252, 249);
            listBox.ForeColor = UiTheme.Ink;
            listBox.BorderStyle = BorderStyle.None;
            listBox.DrawMode = DrawMode.OwnerDrawFixed;
            listBox.ItemHeight = 46;
            listBox.IntegralHeight = false;
            listBox.DrawItem += DrawLayoutItem;
            listBox.DoubleClick += (s, e) => RestoreSelected();
            card.Controls.Add(listBox);

            AddButton(card, "打开布局", 394, 26, true, (s, e) => RestoreSelected());
            AddButton(card, "保存为新布局", 394, 66, false, (s, e) => SaveNew());
            AddButton(card, "覆盖所选布局", 394, 106, false, (s, e) => OverwriteSelected());
            AddButton(card, "导出分享包", 394, 146, false, (s, e) => ExportSelected());
            AddButton(card, "删除所选布局", 394, 186, false, (s, e) => DeleteSelected());
            AddButton(card, "打开布局文件夹", 394, 226, false, (s, e) => Process.Start("explorer.exe", manager.LayoutDir));

            statusLabel = new Label();
            statusLabel.Left = 38;
            statusLabel.Top = 400;
            statusLabel.Width = 540;
            statusLabel.Height = 28;
            statusLabel.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
            statusLabel.ForeColor = UiTheme.Muted;
            statusLabel.BackColor = Color.Transparent;
            Controls.Add(statusLabel);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            using (var brush = new LinearGradientBrush(ClientRectangle, Color.FromArgb(244, 250, 247), Color.FromArgb(224, 239, 232), 45F))
            {
                e.Graphics.FillRectangle(brush, ClientRectangle);
            }
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var b1 = new SolidBrush(Color.FromArgb(72, 196, 232, 210)))
            using (var b2 = new SolidBrush(Color.FromArgb(58, 255, 255, 255)))
            {
                e.Graphics.FillEllipse(b1, new Rectangle(Width - 220, -80, 260, 220));
                e.Graphics.FillEllipse(b2, new Rectangle(-80, Height - 190, 260, 220));
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
            button.Width = 140;
            button.Height = 34;
            button.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            button.Primary = primary;
            button.Font = new Font("Microsoft YaHei UI", 9F, primary ? FontStyle.Bold : FontStyle.Regular);
            button.Click += handler;
            parent.Controls.Add(button);
        }

        private void DrawLayoutItem(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            e.DrawBackground();
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var item = listBox.Items[e.Index] as LayoutSummary;
            var rect = new Rectangle(e.Bounds.Left + 4, e.Bounds.Top + 4, e.Bounds.Width - 8, e.Bounds.Height - 8);
            bool selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
            using (var path = UiTheme.RoundedRect(rect, 14))
            using (var fill = new SolidBrush(selected ? UiTheme.Selection : Color.FromArgb(0, 255, 255, 255)))
            using (var border = new Pen(selected ? Color.FromArgb(130, 84, 159, 119) : Color.FromArgb(0, 255, 255, 255)))
            {
                e.Graphics.FillPath(fill, path);
                if (selected) e.Graphics.DrawPath(border, path);
            }

            var name = item == null ? listBox.Items[e.Index].ToString() : item.Name;
            var meta = item == null ? "" : (item.Count + " 个窗口  " + item.SavedAt);
            TextRenderer.DrawText(e.Graphics, name, new Font("Microsoft YaHei UI", 10F, FontStyle.Bold), new Rectangle(rect.Left + 12, rect.Top + 5, rect.Width - 24, 18), UiTheme.Ink, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
            TextRenderer.DrawText(e.Graphics, meta, new Font("Microsoft YaHei UI", 8F), new Rectangle(rect.Left + 12, rect.Top + 25, rect.Width - 24, 16), UiTheme.Muted, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
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
            Text = title;
            StartPosition = FormStartPosition.CenterParent;
            Size = new Size(420, 178);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            Font = new Font("Microsoft YaHei UI", 9F);
            BackColor = Color.FromArgb(244, 250, 247);

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
            ok.Primary = true;
            ok.DialogResult = DialogResult.OK;
            Controls.Add(ok);

            var cancel = new GlassButton();
            cancel.Text = "取消";
            cancel.Left = 300;
            cancel.Top = 100;
            cancel.Width = 78;
            cancel.DialogResult = DialogResult.Cancel;
            Controls.Add(cancel);

            AcceptButton = ok;
            CancelButton = cancel;
            Shown += (s, e) => { textBox.SelectAll(); textBox.Focus(); };
        }
    }
}
