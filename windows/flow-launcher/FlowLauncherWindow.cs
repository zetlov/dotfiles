using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Dotfiles {
  public static class FlowLauncherWindow {
    private delegate bool EnumWindowCallback(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowCallback callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, StringBuilder text, int capacity);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    public static IntPtr Find(uint processId) {
      IntPtr result = IntPtr.Zero;
      EnumWindows(delegate(IntPtr window, IntPtr parameter) {
        uint owner;
        GetWindowThreadProcessId(window, out owner);
        if (owner != processId) return true;
        var title = new StringBuilder(256);
        GetWindowText(window, title, title.Capacity);
        if (title.ToString() != "Flow.Launcher") return true;
        result = window;
        return false;
      }, IntPtr.Zero);
      return result;
    }

    public static bool RequestClose(uint processId) {
      const uint WM_CLOSE = 0x0010;
      IntPtr window = Find(processId);
      return window != IntPtr.Zero && PostMessage(window, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }
  }
}
