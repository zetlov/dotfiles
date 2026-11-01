Set-StrictMode -Version Latest

if (-not ("Dotfiles.Kanata.ImeBridge" -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace Dotfiles.Kanata {
    public sealed class ImeKeyState {
        private int pressed;
        public static bool Matches(int code, int message, uint key, uint flags) {
            return code == 0 && key == 26 && (flags & 0x10) == 0 &&
                (message == 0x100 || message == 0x101 ||
                 message == 0x104 || message == 0x105);
        }
        public int Transition(bool down) {
            if (Interlocked.Exchange(ref pressed, down ? 1 : 0) == (down ? 1 : 0)) return 0;
            return down ? 1 : 2;
        }
        public void Reset() { Interlocked.Exchange(ref pressed, 0); }
    }

    public sealed class ImeBridge : IDisposable {
        private const int QueueCapacity = 64;
        private readonly int port;
        private readonly BlockingCollection<bool> events =
            new BlockingCollection<bool>(QueueCapacity);
        private readonly ManualResetEventSlim hookReady = new ManualResetEventSlim();
        private readonly ImeKeyState keyState = new ImeKeyState();
        private readonly HookCallback callback;
        private Thread hookThread, senderThread;
        private uint hookThreadId;
        private volatile bool stopping, ready;
        private string error = "";
        private IntPtr hook;
        public string Error { get { return error; } }
        public bool IsRunning {
            get { return !stopping && hookThread != null && hookThread.IsAlive &&
                senderThread != null && senderThread.IsAlive; }
        }

        public ImeBridge(int port) {
            if (port < 1 || port > 65535) throw new ArgumentOutOfRangeException("port");
            this.port = port;
            callback = OnKey;
        }

        public static string Payload(bool down) {
            return "{\"ActOnFakeKey\":{\"name\":\"surface-imeoff\",\"action\":\"" +
                (down ? "Press" : "Release") + "\"}}";
        }

        public static bool ValidateEndpoint(string greeting, string names) {
            return greeting != null && names != null &&
                Regex.IsMatch(greeting, "^\\s*\\{\\s*\"LayerChange\"\\s*:") &&
                Regex.IsMatch(names, "^\\s*\\{\\s*\"FakeKeyNames\"\\s*:") &&
                Regex.IsMatch(names, "\"surface-imeoff\"");
        }

        public void Start() {
            hookThread = new Thread(HookLoop);
            hookThread.IsBackground = true;
            hookThread.Start();
            if (!hookReady.Wait(2000) || hook == IntPtr.Zero) {
                Dispose();
                throw new InvalidOperationException("IME bridge hook failed: " + error);
            }
            senderThread = new Thread(SenderLoop);
            senderThread.IsBackground = true;
            senderThread.Start();
        }

        private void HookLoop() {
            try {
                hookThreadId = GetCurrentThreadId();
                Message message;
                // Ensure PostThreadMessage can stop this thread even before GetMessage.
                PeekMessage(out message, IntPtr.Zero, 0, 0, 0);
                hook = SetWindowsHookEx(13, callback, GetModuleHandle(null), 0);
                if (hook == IntPtr.Zero) throw new Win32Exception();
                hookReady.Set();
                int result;
                while ((result = GetMessage(out message, IntPtr.Zero, 0, 0)) > 0) {
                    TranslateMessage(ref message);
                    DispatchMessage(ref message);
                }
                if (result < 0) throw new Win32Exception();
            } catch (Exception ex) {
                error = "IME hook: " + ex.Message;
            } finally {
                ready = false;
                if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
                hook = IntPtr.Zero;
                hookReady.Set();
            }
        }

        private IntPtr OnKey(int code, IntPtr message, IntPtr data) {
            if (code == 0 && ready && !stopping) {
                KeyData key = (KeyData)Marshal.PtrToStructure(data, typeof(KeyData));
                if (ImeKeyState.Matches(code, message.ToInt32(), key.Key, key.Flags)) {
                    bool down = (key.Flags & 0x80) == 0;
                    int transition = keyState.Transition(down);
                    if (transition != 0 && !events.TryAdd(down)) {
                        ready = false;
                        error = "IME event queue overflow; reconnecting.";
                        return CallNextHookEx(hook, code, message, data);
                    }
                    return new IntPtr(1);
                }
            }
            return CallNextHookEx(hook, code, message, data);
        }

        private TcpClient Connect() {
            TcpClient client = new TcpClient(AddressFamily.InterNetwork);
            try {
                IAsyncResult pending = client.BeginConnect(IPAddress.Loopback, port, null, null);
                using (pending.AsyncWaitHandle) {
                    if (!pending.AsyncWaitHandle.WaitOne(500))
                        throw new IOException("Timed out connecting to Kanata.");
                    client.EndConnect(pending);
                }
                client.NoDelay = true;
                client.ReceiveTimeout = client.SendTimeout = 500;
                return client;
            } catch {
                client.Close();
                throw;
            }
        }

        private static string ReadLine(StreamReader reader) {
            StringBuilder line = new StringBuilder();
            while (line.Length <= 16384) {
                int value = reader.Read();
                if (value < 0) throw new IOException("Kanata endpoint closed.");
                if (value == '\n') return line.ToString().TrimEnd('\r');
                line.Append((char)value);
            }
            throw new IOException("Kanata endpoint response exceeds 16384 characters.");
        }

        private void SenderLoop() {
            while (!stopping) {
                try {
                    using (TcpClient client = Connect())
                    using (NetworkStream stream = client.GetStream())
                    using (StreamReader reader = new StreamReader(stream, new UTF8Encoding(false)))
                    using (StreamWriter writer = new StreamWriter(stream, new UTF8Encoding(false))) {
                        writer.AutoFlush = true;
                        string greeting = ReadLine(reader);
                        writer.WriteLine("{\"RequestFakeKeyNames\":{}}");
                        string names = ReadLine(reader);
                        if (!ValidateEndpoint(greeting, names))
                            throw new IOException("Kanata endpoint lacks surface-imeoff virtual key.");
                        // A prior connection may have failed with the layer held.
                        writer.WriteLine(Payload(false));
                        bool discarded;
                        while (events.TryTake(out discarded)) { }
                        keyState.Reset();
                        if (!hookThread.IsAlive || hook == IntPtr.Zero)
                            throw new IOException("IME keyboard hook is no longer running.");
                        ready = true;
                        error = "";
                        try {
                            SendEvents(client, reader, writer);
                        } finally {
                            ready = false;
                            writer.WriteLine(Payload(false));
                        }
                    }
                } catch (Exception ex) {
                    ready = false;
                    error = "IME bridge: " + ex.Message;
                    if (!stopping) Thread.Sleep(100);
                }
            }
        }

        private void SendEvents(TcpClient client, StreamReader reader, StreamWriter writer) {
            while (!stopping && ready && hookThread.IsAlive) {
                bool down;
                if (events.TryTake(out down, 10)) writer.WriteLine(Payload(down));
                if (client.Client.Poll(0, SelectMode.SelectRead)) {
                    if (client.Available == 0)
                        throw new IOException("Kanata connection closed.");
                    // Drain layer-change notifications so the socket cannot fill.
                    ReadLine(reader);
                }
            }
        }

        public void Dispose() {
            ready = false;
            stopping = true;
            if (hookThreadId != 0) PostThreadMessage(hookThreadId, 0x12, IntPtr.Zero, IntPtr.Zero);
            if (hookThread != null && !hookThread.Join(2000))
                throw new InvalidOperationException("IME hook thread did not stop.");
            if (senderThread != null && !senderThread.Join(2000))
                throw new InvalidOperationException("IME sender thread did not stop.");
        }

        private delegate IntPtr HookCallback(int code, IntPtr message, IntPtr data);
        [StructLayout(LayoutKind.Sequential)]
        private struct KeyData { public uint Key, Scan, Flags, Time; public UIntPtr Extra; }
        [StructLayout(LayoutKind.Sequential)]
        private struct Message {
            public IntPtr Window; public uint Id; public UIntPtr WParam;
            public IntPtr LParam; public uint Time; public int X, Y; public uint Private;
        }
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int id, HookCallback callback, IntPtr module, uint thread);
        [DllImport("user32.dll")]
        private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern int GetMessage(out Message message, IntPtr window, uint min, uint max);
        [DllImport("user32.dll")]
        private static extern bool PeekMessage(out Message message, IntPtr window, uint min, uint max, uint remove);
        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(ref Message message);
        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage(ref Message message);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool PostThreadMessage(uint thread, uint message, IntPtr wparam, IntPtr lparam);
        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string name);
    }
}
'@
}

$script:imeBridge = $null

function Start-KanataImeBridge {
  param([ValidateRange(1, 65535)][int]$Port = 5829)

  if ($null -ne $script:imeBridge) {
    if ($script:imeBridge.IsRunning) { return }
    Stop-KanataImeBridge
  }
  $bridge = New-Object Dotfiles.Kanata.ImeBridge($Port)
  $bridge.Start()
  $script:imeBridge = $bridge
}

function Stop-KanataImeBridge {
  if ($null -eq $script:imeBridge) { return }
  $script:imeBridge.Dispose()
  $script:imeBridge = $null
}

function Get-KanataImeBridgeError {
  if ($null -ne $script:imeBridge) { return $script:imeBridge.Error }
  return ""
}

Export-ModuleMember -Function `
  Start-KanataImeBridge, Stop-KanataImeBridge, Get-KanataImeBridgeError
