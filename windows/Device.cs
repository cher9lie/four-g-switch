using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.IO.Ports;
using System.Linq;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace FourGSwitch {
// SetupAPI only enumerates present, exact-model AT interfaces. Never probe arbitrary COM ports.
static class Devices {
    [StructLayout(LayoutKind.Sequential)] struct Info { public int Size; public Guid Class; public int DevInst; public IntPtr Reserved; }
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, string enumerator, IntPtr hwnd, uint flags);
    [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiEnumDeviceInfo(IntPtr h, uint index, ref Info info);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool SetupDiGetDeviceInstanceId(IntPtr h, ref Info info, StringBuilder text, int size, out int required);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool SetupDiGetDeviceRegistryProperty(IntPtr h, ref Info info, uint property, out uint type, byte[] data, uint size, out uint required);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr h);
    internal static bool IsTarget(string id) { return id.StartsWith("USB\\VID_2CA3&PID_4006&MI_02\\", StringComparison.OrdinalIgnoreCase); }
    internal static string NetworkCompatibility() {
        Guid guid=new Guid("4d36e972-e325-11ce-bfc1-08002be10318");
        IntPtr h=SetupDiGetClassDevs(ref guid,null,IntPtr.Zero,2);
        if(h==new IntPtr(-1))return null;
        try {
            for(uint index=0;;index++) {
                Info info=new Info();info.Size=Marshal.SizeOf(typeof(Info));
                if(!SetupDiEnumDeviceInfo(h,index,ref info))break;
                var id=new StringBuilder(1024);int required;
                if(!SetupDiGetDeviceInstanceId(h,ref info,id,id.Capacity,out required) || !id.ToString().StartsWith("USB\\VID_2CA3&PID_4006&MI_04\\",StringComparison.OrdinalIgnoreCase))continue;
                byte[] bytes=new byte[4096];uint type,size;
                if(SetupDiGetDeviceRegistryProperty(h,ref info,2,out type,bytes,(uint)bytes.Length,out size))return Encoding.Unicode.GetString(bytes,0,(int)size).TrimEnd('\0').Replace('\0',';');
            }
        } finally {SetupDiDestroyDeviceInfoList(h);}
        return null;
    }
    internal static bool ProtocolMatches(string compatibility,int mode) {
        if(compatibility==null)return false;
        return compatibility.IndexOf(mode==1?"Class_02&SubClass_06":"Class_ff&SubClass_ff&Prot_ff",StringComparison.OrdinalIgnoreCase)>=0;
    }
    public static string Find() {
        Guid guid = new Guid("4d36e978-e325-11ce-bfc1-08002be10318");
        IntPtr h = SetupDiGetClassDevs(ref guid, null, IntPtr.Zero, 2);
        if (h == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
        var ports = new List<string>();
        try {
            for (uint index=0; ;index++) {
                Info info = new Info(); info.Size = Marshal.SizeOf(typeof(Info));
                if (!SetupDiEnumDeviceInfo(h, index, ref info)) {
                    int error = Marshal.GetLastWin32Error(); if (error != 259) throw new Win32Exception(error); break;
                }
                var id = new StringBuilder(1024); int required;
                if (!SetupDiGetDeviceInstanceId(h, ref info, id, id.Capacity, out required) || !IsTarget(id.ToString())) continue;
                byte[] bytes = new byte[2048]; uint type, size;
                if (!SetupDiGetDeviceRegistryProperty(h, ref info, 12, out type, bytes, (uint)bytes.Length, out size)) continue;
                var match = Regex.Match(Encoding.Unicode.GetString(bytes), @"\((COM\d+)\)", RegexOptions.IgnoreCase);
                if (match.Success) ports.Add(match.Groups[1].Value);
            }
        } finally { SetupDiDestroyDeviceInfoList(h); }
        if (ports.Count > 1) throw new InvalidOperationException("发现多张同型号网卡，请只连接需要切换的那一张。");
        if (ports.Count == 0) throw new InvalidOperationException("未发现网卡的控制接口。请插入大疆 4G 模块，等待几秒；若仍未识别，请检查 Quectel 串口驱动。");
        return ports[0];
    }
}

interface IAt : IDisposable { string Send(string command, int timeout); }
sealed class At : IAt {
    readonly SerialPort port;
    internal static Action<string> Trace {get;set;}
    public At(string name) {
        port = new SerialPort(name, 115200, Parity.None, 8, StopBits.One);
        port.Handshake=Handshake.None; port.DtrEnable=true; port.RtsEnable=true;
        port.ReadTimeout=300; port.WriteTimeout=2000; port.Encoding=Encoding.ASCII;
        try { port.Open(); } catch { port.Dispose(); throw; }
    }
    internal static bool Complete(string response) { return Regex.IsMatch(response, @"(?:^|\r?\n)OK\r?(?:\n|$)"); }
    internal static bool Failed(string response) { return Regex.IsMatch(response, @"(?:^|\r?\n)(?:ERROR|\+CM[ES] ERROR[^\r\n]*)\r?(?:\n|$)"); }
    public string Send(string command, int timeout) {
        var elapsed=Stopwatch.StartNew();if(Trace!=null)Trace("SEND "+command);
        try {var answer=SendCore(command,timeout);if(Trace!=null)Trace("OK "+command+" "+elapsed.ElapsedMilliseconds+"ms");return answer;}
        catch(Exception e) {if(Trace!=null)Trace("INTERRUPTED "+command+" "+elapsed.ElapsedMilliseconds+"ms "+e.Message);throw;}
    }
    string SendCore(string command,int timeout) {
        port.DiscardInBuffer(); port.Write(command+"\r");
        var result = new StringBuilder(); var watch=Stopwatch.StartNew();
        while (watch.ElapsedMilliseconds < timeout) {
            result.Append(port.ReadExisting());
            string response=result.ToString();
            if (Failed(response)) throw new InvalidOperationException("网卡拒绝了设置：" + command);
            if (Complete(response)) return response;
            Thread.Sleep(15);
        }
        throw new TimeoutException("网卡响应超时。若正在重启，请等待后刷新。");
    }
    public void Dispose() { port.Dispose(); }
}

sealed class State {
    public string Port; public int Mode; public int Auto; public string Address;
    public string Describe() { return "设备：DJI 4G / 2CA3:4006\r\n控制接口："+Port+"\r\nusbnet="+Mode+"\r\nqcautoconnect="+Auto+"\r\n网卡 IPv4："+(Address ?? "尚未获取")+"\r\n"; }
}
static class Modem {
    internal static int Value(string response, string key) {
        if (!At.Complete(response) || At.Failed(response)) throw new InvalidOperationException("网卡没有返回有效确认。");
        var m=Regex.Match(response, "\\+QCFG:\\s*\""+Regex.Escape(key)+"\"\\s*,\\s*(\\d+)");
        int value;
        if (!m.Success || !int.TryParse(m.Groups[1].Value, out value) || value < 0 || value > 1) throw new InvalidOperationException("暂不支持网卡当前的配置，请停止切换并检查设备。");
        return value;
    }
    public static string Address() {
        foreach(var n in NetworkInterface.GetAllNetworkInterfaces()) {
            if (n.Description.IndexOf("Quectel", StringComparison.OrdinalIgnoreCase)<0 || n.OperationalStatus != OperationalStatus.Up) continue;
            var p=n.GetIPProperties();
            if (!p.GatewayAddresses.Any(g=>g.Address.AddressFamily==AddressFamily.InterNetwork && g.Address.ToString()!="0.0.0.0")) continue;
            foreach(var a in p.UnicastAddresses) {
                string v=a.Address.ToString();
                if(a.Address.AddressFamily==AddressFamily.InterNetwork && !v.StartsWith("169.254.") && !v.StartsWith("127.") && v!="0.0.0.0") return v;
            }
        }
        return null;
    }
    public static State Read() {
        string name=Devices.Find();
        try {
            using(var at=new At(name)) {
                return ReadFrom(at,name);
            }
        } catch (UnauthorizedAccessException) { throw new InvalidOperationException("网卡控制接口被占用，请先关闭其他网卡管理工具，再点刷新。"); }
    }
    static State ReadFrom(IAt at,string name) {
        // Both typed query replies confirm the AT interface; a separate AT round trip is redundant.
        return new State { Port=name, Mode=Value(at.Send("AT+QCFG=\"usbnet\"",2500),"usbnet"), Auto=Value(at.Send("AT+QCFG=\"qcautoconnect\"",2500),"qcautoconnect"), Address=Address() };
    }
    // Set auto-connect first: usbnet can immediately re-enumerate the USB device.
    internal static void Write(IAt at, int target, int current, int auto, bool reboot=true) {
        if (target!=0 && target!=1) throw new ArgumentOutOfRangeException("target");
        if (auto!=1) {
            at.Send("AT+QCFG=\"qcautoconnect\",1",3000);
            if(Value(at.Send("AT+QCFG=\"qcautoconnect\"",2500),"qcautoconnect")!=1) throw new InvalidOperationException("自动联网设置未生效，已停止切换。");
        }
        if (current!=target) {
            try { at.Send("AT+QCFG=\"usbnet\","+target,4000); }
            catch (IOException) { return; } // Never infer success: caller must read back after reconnect.
            catch (InvalidOperationException e) { if (e.Message.StartsWith("网卡拒绝")) throw; return; }
            catch (TimeoutException) { return; }
        }
        if(reboot && (current!=target || auto!=1)) {
            try { at.Send("AT+CFUN=1,1",4000); }
            catch(IOException) {} catch(TimeoutException) {}
            catch(InvalidOperationException e) { if(e.Message.StartsWith("网卡拒绝")) throw; }
        }
    }
    internal static bool Verified(State s, int target) { return s!=null && s.Mode==target && s.Auto==1; }
    static void Reboot(string name) {
        using(var at=new At(name)) {
            try {at.Send("AT+CFUN=1,1",4000);}
            catch(IOException){}catch(TimeoutException){}
            catch(InvalidOperationException e){if(e.Message.StartsWith("网卡拒绝"))throw;}
        }
    }
    static State RestartAndRead(string name,int target,Action<string> progress) {
        Reboot(name);
        // CFUN returns before USB disconnects. Do not reopen the disappearing serial handle.
        var elapsed=Stopwatch.StartNew();bool absent=false;
        while(elapsed.ElapsedMilliseconds<10000) {
            string compatibility=Devices.NetworkCompatibility();
            if(compatibility==null)absent=true;
            if(absent && Devices.ProtocolMatches(compatibility,target))break;
            Thread.Sleep(100);
        }
        var after=WaitForAppliedMode(target,progress);
        if(!Verified(after,target))throw new InvalidOperationException("重启后的配置未通过验证，请刷新后检查。");
        return after;
    }
    static State WaitForAppliedMode(int target,Action<string> progress) {
        var elapsed=Stopwatch.StartNew();bool rebooted=false;
        while(elapsed.ElapsedMilliseconds<90000) {
            // Do not touch the old COM handle while the USB function is being replaced.
            // Reading it during re-enumeration can make the Quectel serial driver stall on close.
            bool protocolApplied=Devices.ProtocolMatches(Devices.NetworkCompatibility(),target);
            if(!protocolApplied && elapsed.ElapsedMilliseconds<5000) {Thread.Sleep(100);continue;}
            State observed=null;try {observed=Read();}catch {}
            if(observed!=null && observed.Mode==target) {
                if(protocolApplied)return observed;
                // Other firmware may save the setting without applying it. Preserve a restart fallback.
                if(!rebooted && elapsed.ElapsedMilliseconds>=5000) {
                    progress("正在重启以应用网卡模式…");Reboot(observed.Port);rebooted=true;
                }
            }
            Thread.Sleep(300);
        }
        throw new TimeoutException("尚未确认 USB 接口切换，请保持连接并刷新后检查。");
    }
    internal static State WaitForMode(Func<State> read, Action wait, int attempts, int target, bool requireAuto) {
        State s=null;var elapsed=Stopwatch.StartNew();
        for(int i=0;i<attempts;i++) {
            // Probe immediately, then retry promptly. Keep an independent wall-clock recovery budget.
            try { s=read(); } catch { s=null; }
            if(s!=null && s.Mode==target && (!requireAuto || Verified(s,target))) return s;
            if(elapsed.ElapsedMilliseconds>=90000)break;
            if(i+1<attempts)wait();
        }
        throw new TimeoutException("尚未确认切换结果，请保持连接后点刷新。若仍无响应，可拔插模块后重新检查；现在请勿直接拿去连接 iPad。");
    }
    public static State Switch(int target, Action<string> progress) {
        if(target!=0 && target!=1)throw new ArgumentOutOfRangeException("target");
        State before;string name=Devices.Find();
        progress("正在保存模式…");
        using(var at=new At(name)) {
            before=ReadFrom(at,name);
            if(Verified(before,target) && (target==1 || before.Address!=null) && Devices.ProtocolMatches(Devices.NetworkCompatibility(),target))return before;
            Write(at,target,before.Mode,before.Auto,false);
        }
        progress("正在等待网卡重新连接，请勿拔出…");
        var after=WaitForAppliedMode(target,progress);
        // This DJI firmware can reset qcautoconnect while changing usbnet.
        // Reapply only after observing the requested USB mode, then verify again.
        bool restoredAuto=after.Auto!=1;
        if(restoredAuto) {
            progress("正在恢复自动联网设置…");
            using(var at=new At(after.Port)) { Write(at,target,target,after.Auto,false); }
            after=WaitForMode(Read, ()=>Thread.Sleep(300), 300, target, true);
        }
        if(!Verified(after,target)) throw new InvalidOperationException("模式或自动联网设置未通过验证，请刷新后检查。");
        if(target==0 && restoredAuto && after.Address==null) {
            // This DJI firmware needs one restart after restoring qcautoconnect for the NDIS host path.
            // The USB mode has already been verified; avoid the earlier additional pre-verification reboot.
            progress("正在恢复 Windows 网卡连接…");
            after=RestartAndRead(after.Port,target,progress);
        }
        if(target==0 && after.Address==null) {
            progress("Windows 模式已确认，正在等待网络地址…");
            var networkWait=Stopwatch.StartNew();
            while(after.Address==null && networkWait.ElapsedMilliseconds<60000) {
                after.Address=Address();
                if(after.Address==null)Thread.Sleep(250);
            }
        }
        return after;
    }
}

static class Tests {
    sealed class Fake : IAt {
        public readonly List<string> Calls=new List<string>(); public bool Disconnect; public bool Reject;
        public string Send(string c,int t) { Calls.Add(c); if(Reject && c.Contains("usbnet")) throw new InvalidOperationException("网卡拒绝了设置："+c); if(Disconnect && c.Contains("usbnet")) throw new IOException(); return c=="AT+QCFG=\"qcautoconnect\""?"\r\n+QCFG: \"qcautoconnect\",1\r\nOK\r\n":"\r\nOK\r\n"; }
        public void Dispose(){}
    }
    static void Check(bool ok) { if(!ok) throw new Exception("Self-test assertion failed"); }
    static void Throws(Action a) { bool threw=false;try{a();}catch{threw=true;}Check(threw); }
    public static void Run() {
        Check(At.Complete("AT\r\r\nOK\r\n")); Check(!At.Complete("NOTOK\r\n")); Check(At.Failed("\r\n+CME ERROR: 10\r\n"));
        Check(Modem.Value("\r\n+QCFG: \"usbnet\",1\r\nOK\r\n","usbnet")==1);
        Throws(()=>Modem.Value("\r\n+QCFG: \"usbnet\",2\r\nOK\r\n","usbnet"));
        Throws(()=>Modem.Value("\r\n+QCFG: \"usbnet\",0\r\nERROR\r\n","usbnet"));
        Throws(()=>Modem.Value("\r\n+QCFG: \"usbnet\",0\r\n","usbnet"));
        Check(Devices.IsTarget("USB\\VID_2CA3&PID_4006&MI_02\\abc")); Check(!Devices.IsTarget("USB\\VID_2CA3&PID_4006&MI_00\\abc")); Check(!Devices.IsTarget("BTHENUM\\COM11"));
        var f=new Fake(); Modem.Write(f,0,1,0); Check(f.Calls[0]=="AT+QCFG=\"qcautoconnect\",1"); Check(f.Calls[2]=="AT+QCFG=\"usbnet\",0"); Check(f.Calls[3]=="AT+CFUN=1,1");
        f=new Fake(); Modem.Write(f,1,1,1); Check(f.Calls.Count==0);
        f=new Fake{Disconnect=true}; Modem.Write(f,1,0,1); Check(f.Calls.Count==1);
        f=new Fake{Reject=true}; Throws(()=>Modem.Write(f,1,0,1));
        Check(!Modem.Verified(new State{Mode=1,Auto=0},1));
        int reads=0; var verified=Modem.WaitForMode(()=>{ reads++; if(reads==1)throw new IOException(); return new State{Mode=1,Auto=1};},()=>{},3,1,true); Check(verified.Mode==1&&reads==2);
        int waits=0;Modem.WaitForMode(()=>new State{Mode=0,Auto=1},()=>waits++,3,0,true);Check(waits==0);
        waits=0;reads=0;Modem.WaitForMode(()=>{reads++;return new State{Mode=reads==1?1:0,Auto=1};},()=>waits++,3,0,true);Check(waits==1&&reads==2);
        Throws(()=>Modem.WaitForMode(()=>new State{Mode=0,Auto=1},()=>{},3,1,true));
        Check(Modem.WaitForMode(()=>new State{Mode=0,Auto=0},()=>{},1,0,false).Auto==0);
        Throws(()=>Modem.WaitForMode(()=>new State{Mode=0,Auto=0},()=>{},1,0,true));
        f=new Fake(); Modem.Write(f,0,0,0); Check(f.Calls.Count==3); Check(!f.Calls.Any(c=>c.Contains("usbnet")));
        f=new Fake();Modem.Write(f,0,1,1,false);Check(f.Calls.Count==1&&f.Calls[0]=="AT+QCFG=\"usbnet\",0");
        f=new Fake();Modem.Write(f,0,0,0,false);Check(f.Calls.Count==2&&!f.Calls.Any(c=>c.Contains("CFUN")));
        Check(Devices.ProtocolMatches("USB\\Class_02&SubClass_06&Prot_00",1));Check(!Devices.ProtocolMatches("USB\\Class_02&SubClass_06&Prot_00",0));
        Check(Devices.ProtocolMatches("USB\\Class_ff&SubClass_ff&Prot_ff",0));Check(!Devices.ProtocolMatches(null,1));
    }
}
}
