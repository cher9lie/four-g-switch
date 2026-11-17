using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using System.Windows.Threading;
using Microsoft.Win32;
using Forms=System.Windows.Forms;
using Drawing=System.Drawing;



namespace FourGSwitch {
static class Entry {
    [STAThread] static int Main(string[] args) {
        try {
            AppContext.SetSwitch("Switch.System.Windows.DoNotScaleForDpiChanges",false);
            AppContext.SetSwitch("Switch.System.Windows.DoNotUsePresentationDpiCapabilityTier2OrGreater",false);
            if(args.Length==2 && args[0]=="--diagnose") { File.WriteAllText(args[1],Modem.Read().Describe(),Encoding.UTF8); return 0; }
            if(args.Length==2 && args[0]=="--self-test") {
                Tests.Run(); WidgetTests.Run(); ProtocolFixtures.Run(); File.WriteAllText(args[1],"PASS: modem protocol, shared fixtures, reconnect, auto-connect recovery, verified green state",Encoding.UTF8); return 0;
            }
            if(args.Length==2 && args[0]=="--render-previews") { Previews.Render(args[1]); return 0; }
            if(args.Length==2 && args[0]=="--write-icon") { using(var icon=TrayArt.Make("#8d8d8d"))using(var file=File.Create(args[1]))icon.Save(file);return 0; }
            bool first;
            using(var mutex=new Mutex(true,"Local\\FourGSwitch.Native.v3",out first)) {
                if(!first) {
                    try { using(var signal=EventWaitHandle.OpenExisting("Local\\FourGSwitch.Native.Show")) signal.Set(); }
                    catch(WaitHandleCannotBeOpenedException) { MessageBox.Show("请先退出旧版网卡开关，再打开新版。","4G 网卡"); }
                    return 0;
                }
                var app=new Application { ShutdownMode=ShutdownMode.OnExplicitShutdown };
                using(var widget=new WidgetHost(app)) { widget.Start(args.Contains("--background")); app.Run(); }
            }
            return 0;
        } catch(Exception e) {
            if(args.Length==2) File.WriteAllText(args[1]+".error.txt",e.ToString(),Encoding.UTF8);
            else MessageBox.Show(e.Message,"4G 网卡");
            return 1;
        }
    }
}

// All UI colors below are Radix Colors gray, green and amber scale values.
sealed class Palette {
    public bool Dark;
    public string Surface,Ink,Muted,Off,Hover,Green,OnInk,Amber,AmberInk,Focus;
    public static Palette For(bool dark) {
        return dark ? new Palette { Dark=true, Surface="#191919",Ink="#eeeeee",Muted="#b4b4b4",Off="#2a2a2a",Hover="#313131",Green="#30a46c",OnInk="#fcfcfc",Amber="#302008",AmberInk="#ffca16",Focus="#3e9b4f" }
                    : new Palette { Dark=false,Surface="#f9f9f9",Ink="#202020",Muted="#646464",Off="#e8e8e8",Hover="#f0f0f0",Green="#30a46c",OnInk="#fcfcfc",Amber="#fff7c2",AmberInk="#ab6400",Focus="#3e9b4f" };
    }
    public static bool SystemDark() { return Convert.ToInt32(Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize","AppsUseLightTheme",1))==0; }
    public static SolidColorBrush Brush(string hex) { return new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); }
    public void Apply(FrameworkElement root) {
        root.Resources["Surface"]=Brush(Surface); root.Resources["Ink"]=Brush(Ink); root.Resources["Muted"]=Brush(Muted);root.Resources["Off"]=Brush(Off);root.Resources["Hover"]=Brush(Hover);root.Resources["Focus"]=Brush(Focus);
    }
}

static class VisualState {
    public static bool Green(State s) { return s!=null && s.Mode==0 && s.Auto==1 && !string.IsNullOrEmpty(s.Address); }
    public static bool AppleReady(State s) { return s!=null && s.Mode==1 && s.Auto==1; }
}

sealed class WidgetWindow : Window {
    public readonly Grid Root;
    public readonly Button Power,Refresh,More;
    readonly TextBlock headline,status,notice,detail;
    readonly Border surface;
    Palette palette;
    State current; bool busy; string progress,error;
    public bool ExitRequested;
    public WidgetWindow(bool preview,bool dark) {
        Title="4G 网卡开关"; Width=328; SizeToContent=SizeToContent.Height; ResizeMode=ResizeMode.NoResize;
        WindowStyle=WindowStyle.None; ShowInTaskbar=false; Background=Brushes.Transparent;
        UseLayoutRounding=true; SnapsToDevicePixels=true;
        TextOptions.SetTextFormattingMode(this,TextFormattingMode.Display);
        using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("Widget.xaml")) Root=(Grid)XamlReader.Load(stream);
        Content=Root;
        Power=(Button)Root.FindName("Power"); Refresh=(Button)Root.FindName("Refresh");More=(Button)Root.FindName("More");
        headline=(TextBlock)Root.FindName("Headline");status=(TextBlock)Root.FindName("Status");notice=(TextBlock)Root.FindName("Notice");detail=(TextBlock)Root.FindName("Detail");surface=(Border)Root.FindName("Surface");
        ((Button)Root.FindName("Hide")).Click+=(s,e)=>Hide();
        ((Grid)Root.FindName("TitleArea")).MouseLeftButtonDown+=(s,e)=>{ if(e.OriginalSource==Root.FindName("TitleText") || e.OriginalSource==s) { try { DragMove(); } catch(InvalidOperationException) {} } };
        if(!preview) {
            WindowChrome.SetWindowChrome(this,new WindowChrome { CaptionHeight=0,ResizeBorderThickness=new Thickness(0),GlassFrameThickness=new Thickness(-1),UseAeroCaptionButtons=false,CornerRadius=new CornerRadius(8) });
            SourceInitialized+=(s,e)=>ApplyBackdrop();
            Closing+=(s,e)=>{ if(!ExitRequested) { e.Cancel=true;Hide(); } };
            KeyDown+=(s,e)=>{ if(e.Key==Key.Escape)Hide(); };
        }
        ApplyTheme(dark); Apply(null,false,null,null);
    }
    public void ApplyTheme(bool dark) {
        palette=Palette.For(dark);palette.Apply(Root);Render();
        if(IsLoaded)ApplyBackdrop();
    }
    void ApplyBackdrop() {
        bool applied=NativeBackdrop.Apply(this,palette.Dark);
        var brush=Palette.Brush(palette.Surface); if(applied) brush.Opacity=0.66;
        surface.Background=brush;
    }
    public void Apply(State s,bool working,string phase,string failure) { current=s;busy=working;progress=phase;error=failure;Render(); }
    void Render() {
        if(palette==null)return;
        bool green=!busy && error==null && VisualState.Green(current);
        bool waiting=busy || (current!=null && current.Mode==0 && !green && error==null);
        Power.Background=Palette.Brush(green?palette.Green:waiting?palette.Amber:palette.Off);
        Power.Foreground=Palette.Brush(green?palette.OnInk:waiting?palette.AmberInk:palette.Muted);
        Power.IsEnabled=!busy && current!=null; Refresh.IsEnabled=!busy;
        notice.Visibility=Visibility.Collapsed;notice.Text="";
        if(busy) { headline.Text="正在切换";status.Text="请勿拔出网卡";notice.Text=ShortProgress(progress);notice.Visibility=Visibility.Visible; }
        else if(error!=null) { bool absent=error.StartsWith("请连接");headline.Text=absent?"未连接网卡":"状态待确认";status.Text=absent?"插入后自动识别":"刷新后重试";notice.Text=error;notice.Visibility=Visibility.Visible; }
        else if(current==null) { headline.Text="正在识别";status.Text="请稍候"; }
        else if(green) { headline.Text="本机使用";status.Text="Windows 已连接"; }
        else if(VisualState.AppleReady(current)) { headline.Text="iPad / Mac";status.Text="可以拔下网卡"; }
        else if(current.Mode==0 && current.Auto==1) { headline.Text="等待网络";status.Text="Windows 模式已开启"; }
        else { headline.Text="需要重新连接";status.Text="点击按钮恢复设置"; }
        detail.Text="DJI 4G";
        string action=current!=null&&current.Mode==0&&current.Auto==1?"切换为 iPad / Mac 模式":"开启 Windows 本机使用";
        Power.ToolTip=action;AutomationProperties.SetName(Power,action);
        AutomationProperties.SetHelpText(Power,headline.Text+"，"+status.Text);
    }
    static string ShortProgress(string p) {
        if(string.IsNullOrEmpty(p))return "正在读取网卡配置";
        if(p.Contains("重启"))return "正在等待模块重启";
        if(p.Contains("数据连接"))return "正在建立数据连接";
        if(p.Contains("网络地址"))return "正在等待网络地址";
        if(p.Contains("自动联网"))return "正在恢复自动联网";
        if(p.Contains("重新连接"))return "正在等待网卡重连";
        return "正在保存网卡模式";
    }
    public void ShowPanel() {
        if(!IsVisible) {
            var area=SystemParameters.WorkArea;
            Left=Math.Max(area.Left+8,area.Right-Width-16);
            Top=Math.Max(area.Top+8,area.Bottom-260);
            Show();UpdateLayout();Top=Math.Max(area.Top+8,area.Bottom-ActualHeight-16);
        }
        Activate();
    }
}

static class NativeBackdrop {
    [StructLayout(LayoutKind.Sequential)] struct Margins { public int Left,Right,Top,Bottom; }
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd,int attribute,ref int value,int size);
    [DllImport("dwmapi.dll")] static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd,ref Margins margins);
    public static bool Apply(Window w,bool dark) {
        if(SystemParameters.HighContrast)return false;
        try {
            IntPtr handle=new WindowInteropHelper(w).Handle;if(handle==IntPtr.Zero)return false;
            int mode=dark?1:0;DwmSetWindowAttribute(handle,20,ref mode,4);
            int corners=2;DwmSetWindowAttribute(handle,33,ref corners,4);
            int backdrop=3;int result=DwmSetWindowAttribute(handle,38,ref backdrop,4);
            if(result!=0)return false;
            var margins=new Margins { Left=-1,Right=-1,Top=-1,Bottom=-1 };
            DwmExtendFrameIntoClientArea(handle,ref margins);
            var source=HwndSource.FromHwnd(handle);if(source!=null)source.CompositionTarget.BackgroundColor=Colors.Transparent;
            return true;
        } catch(DllNotFoundException) { return false; } catch(EntryPointNotFoundException) { return false; }
    }
}

sealed class WidgetHost : IDisposable {
    readonly Application app;readonly WidgetWindow window;readonly Forms.NotifyIcon tray;
    readonly DispatcherTimer timer;readonly SemaphoreSlim gate=new SemaphoreSlim(1,1);
    readonly EventWaitHandle signal,quitSignal;readonly RegisteredWaitHandle registration,quitRegistration;
    readonly Forms.ToolStripMenuItem pin;
    State state;bool busy;string error;Drawing.Icon icon;
    public WidgetHost(Application application) {
        app=application;window=new WidgetWindow(false,Palette.SystemDark());
        tray=new Forms.NotifyIcon { Text="4G 网卡" };
        var menu=new Forms.ContextMenuStrip();menu.Items.Add("打开小面板",null,(s,e)=>window.ShowPanel());
        menu.Items.Add("刷新状态",null,async(s,e)=>await Refresh());
        pin=new Forms.ToolStripMenuItem("面板置顶") { CheckOnClick=true };pin.CheckedChanged+=(s,e)=>window.Topmost=pin.Checked;menu.Items.Add(pin);
        menu.Items.Add("复制诊断",null,(s,e)=>Copy());menu.Items.Add(new Forms.ToolStripSeparator());menu.Items.Add("退出",null,(s,e)=>Exit());
        tray.ContextMenuStrip=menu;
        tray.MouseClick+=async(s,e)=>{ if(e.Button==Forms.MouseButtons.Left) { if(state==null)window.ShowPanel();else await Change(); } };
        window.Power.Click+=async(s,e)=>await Change();window.Refresh.Click+=async(s,e)=>await Refresh();
        window.More.Click+=(s,e)=>{ var position=window.More.PointToScreen(new Point(0,window.More.ActualHeight));menu.Show((int)position.X,(int)position.Y); };
        signal=new EventWaitHandle(false,EventResetMode.AutoReset,"Local\\FourGSwitch.Native.Show");
        registration=ThreadPool.RegisterWaitForSingleObject(signal,(s,t)=>app.Dispatcher.BeginInvoke((Action)(()=>window.ShowPanel())),null,-1,false);
        quitSignal=new EventWaitHandle(false,EventResetMode.AutoReset,"Local\\FourGSwitch.Native.Quit");
        quitRegistration=ThreadPool.RegisterWaitForSingleObject(quitSignal,(s,t)=>app.Dispatcher.BeginInvoke((Action)(()=>Exit())),null,-1,false);
        timer=new DispatcherTimer { Interval=TimeSpan.FromSeconds(5) };timer.Tick+=async(s,e)=>await Refresh();
        SystemEvents.UserPreferenceChanged+=ThemeChanged;
        Paint();tray.Visible=true;
    }
    public void Start(bool background) { if(!background)window.ShowPanel();timer.Start();app.Dispatcher.BeginInvoke((Action)(async()=>await Refresh())); }
    void ThemeChanged(object s,UserPreferenceChangedEventArgs e) { app.Dispatcher.BeginInvoke((Action)(()=>{window.ApplyTheme(Palette.SystemDark());Paint();})); }
    void Paint() {
        window.Apply(state,busy,busy?error:null,busy?null:error);
        bool ready=!busy&&error==null&&VisualState.Green(state);
        var next=TrayArt.Make(ready?"#30a46c":busy?"#ffc53d":"#8d8d8d");tray.Icon=next;if(icon!=null)icon.Dispose();icon=next;
        tray.Text=busy?"4G 网卡：正在切换，请勿拔出":ready?"4G 网卡：Windows 已连接，点击切回 iPad / Mac":VisualState.AppleReady(state)?"4G 网卡：iPad / Mac 模式，点击在本机使用":"4G 网卡：点击打开或切换模式";
    }
    async Task Refresh() {
        if(busy)return;
        if(!await gate.WaitAsync(0))return;
        try { state=await Task.Run(()=>Modem.Read());error=null; }
        catch(Exception e) { state=null;error=Friendly(e.Message); }
        finally { Paint();gate.Release(); }
    }
    async Task Change() {
        if(state==null || busy)return;
        busy=true;error="正在读取网卡配置";Paint();
        // A background read must not silently consume a user's click. Queue behind it once.
        await gate.WaitAsync();
        if(state==null) {busy=false;error="状态待确认，请刷新后重试。";Paint();gate.Release();return;}
        // Unverified auto-connect settings are repaired before treating the button as an off action.
        int target=state.Mode==0&&state.Auto==1?1:0;
        try {
            state=await Task.Run(()=>Modem.Switch(target,t=>app.Dispatcher.BeginInvoke((Action)(()=>{error=t;Paint();}))));error=null;
        } catch(Exception e) { state=null;error=Friendly(e.Message);window.ShowPanel(); }
        finally {busy=false;Paint();gate.Release();}
    }
    static string Friendly(string text) {
        if(text.StartsWith("未发现网卡"))return "请连接大疆 4G 模块。";
        if(text.Contains("被占用"))return "控制接口被占用，请先关闭其他网卡工具。";
        return text;
    }
    void Copy() { try { Clipboard.SetText((state==null?"未读取到配置\r\n":state.Describe())+"状态："+(error??"已读取")+"\r\n版本：3.0.0"); } catch {} }
    void Exit() { if(busy) { window.ShowPanel();return; }window.ExitRequested=true;window.Close();app.Shutdown(); }
    public void Dispose() {timer.Stop();SystemEvents.UserPreferenceChanged-=ThemeChanged;registration.Unregister(null);quitRegistration.Unregister(null);signal.Dispose();quitSignal.Dispose();tray.Visible=false;tray.Dispose();if(icon!=null)icon.Dispose();}
}

static class TrayArt {
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    public static Drawing.Icon Make(string color) {
        using(var bmp=new Drawing.Bitmap(32,32))using(var g=Drawing.Graphics.FromImage(bmp)) {
            g.SmoothingMode=Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using(var b=new Drawing.SolidBrush(Drawing.ColorTranslator.FromHtml(color)))g.FillEllipse(b,1,1,30,30);
            using(var pen=new Drawing.Pen(Drawing.ColorTranslator.FromHtml("#fcfcfc"),2.6f)) {pen.StartCap=Drawing.Drawing2D.LineCap.Round;pen.EndCap=Drawing.Drawing2D.LineCap.Round;g.DrawArc(pen,8,8,16,16,-45,270);g.DrawLine(pen,16,6,16,15);}
            IntPtr raw=bmp.GetHicon();try {using(var borrowed=Drawing.Icon.FromHandle(raw))return (Drawing.Icon)borrowed.Clone();}finally{DestroyIcon(raw);}
        }
    }
}

static class WidgetTests {
    public static void Run() {
        if(VisualState.Green(null)||VisualState.Green(new State{Mode=0,Auto=1})||VisualState.Green(new State{Mode=0,Auto=0,Address="10.0.0.2"})||VisualState.Green(new State{Mode=1,Auto=1,Address="10.0.0.2"}))throw new Exception("Unverified green state");
        if(!VisualState.Green(new State{Mode=0,Auto=1,Address="10.0.0.2"}))throw new Exception("Verified state not green");
    }
}

static class Previews {
    public static void Render(string directory) {
        Directory.CreateDirectory(directory);var report=new StringBuilder();
        var scenarios=new[] {"on","off","waiting","busy","error","long-error"};
        foreach(bool dark in new[]{false,true})foreach(string scenario in scenarios) {
            var w=new WidgetWindow(true,dark);
            if(scenario=="on")w.Apply(new State{Mode=0,Auto=1,Address="10.0.0.2"},false,null,null);
            if(scenario=="off")w.Apply(new State{Mode=1,Auto=1},false,null,null);
            if(scenario=="waiting")w.Apply(new State{Mode=0,Auto=1},false,null,null);
            if(scenario=="busy")w.Apply(new State{Mode=1,Auto=1},true,"正在恢复自动联网设置…",null);
            if(scenario=="error")w.Apply(null,false,null,"请连接大疆 4G 模块。");
            if(scenario=="long-error")w.Apply(null,false,null,"尚未确认切换结果，请保持连接后刷新。若仍无响应，可拔插模块后重新检查；现在请勿直接拿去连接 iPad。");
            var root=w.Root;root.Width=328;
            root.Measure(new Size(328,double.PositiveInfinity));root.Arrange(new Rect(root.DesiredSize));root.UpdateLayout();
            Audit(root);
            foreach(double scale in new[]{1.0,1.25,1.5,2.0}) {
                var image=new RenderTargetBitmap((int)Math.Ceiling(root.ActualWidth*scale),(int)Math.Ceiling(root.ActualHeight*scale),96*scale,96*scale,PixelFormats.Pbgra32);image.Render(root);
                var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(image));
                string name=(dark?"dark-":"light-")+scenario+"-"+(int)(scale*100)+".png";
                using(var f=File.Create(Path.Combine(directory,name)))png.Save(f);
                report.AppendLine(name+": "+root.ActualWidth+"x"+root.ActualHeight+" DIP; text layout PASS");
            }
        }
        File.WriteAllText(Path.Combine(directory,"layout-report.txt"),report.ToString(),Encoding.UTF8);
    }
    static void Audit(DependencyObject parent) {
        for(int i=0;i<VisualTreeHelper.GetChildrenCount(parent);i++) {
            var child=VisualTreeHelper.GetChild(parent,i);var text=child as TextBlock;
            if(text!=null && text.Visibility==Visibility.Visible) {
                double expected=text.DesiredSize.Height-text.Margin.Top-text.Margin.Bottom;
                if(text.ActualHeight+1<expected)throw new Exception("Text clipped: "+text.Text);
                if(text.FontSize<12)throw new Exception("Text below 12 DIP");
            }
            Audit(child);
        }
    }
}
}
