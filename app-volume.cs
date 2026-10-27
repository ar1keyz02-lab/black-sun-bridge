// Громкость отдельных приложений (как в микшере громкости Windows) через Core Audio API.
// Подключается из media-bridge.ps1 через Add-Type.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace AR1KEYZ {
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCom {}

  [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    int EnumAudioEndpoints();
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
  }
  [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice {
    [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
  }
  [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionManager2 {
    int GetAudioSessionControl();
    int GetSimpleAudioVolume();
    [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
  }
  [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionEnumerator {
    [PreserveSig] int GetCount(out int count);
    [PreserveSig] int GetSession(int index, out IAudioSessionControl2 session);
  }
  [Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionControl2 {
    // IAudioSessionControl
    int GetState(); int GetDisplayName(); int SetDisplayName(); int GetIconPath(); int SetIconPath();
    int GetGroupingParam(); int SetGroupingParam(); int RegisterAudioSessionNotification(); int UnregisterAudioSessionNotification();
    // IAudioSessionControl2
    int GetSessionIdentifier(); int GetSessionInstanceIdentifier();
    [PreserveSig] int GetProcessId(out uint pid);
  }
  [Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface ISimpleAudioVolume {
    [PreserveSig] int SetMasterVolume(float level, ref Guid ctx);
    [PreserveSig] int GetMasterVolume(out float level);
  }

  public static class AppVolume {
    // процесс -> его регуляторы громкости (у процесса может быть несколько аудиосеансов)
    static Dictionary<uint, List<ISimpleAudioVolume>> Sessions() {
      var map = new Dictionary<uint, List<ISimpleAudioVolume>>();
      var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
      IMMDevice dev;
      Marshal.ThrowExceptionForHR(en.GetDefaultAudioEndpoint(0, 1, out dev)); // вывод, мультимедиа
      Guid iid = typeof(IAudioSessionManager2).GUID;
      object o;
      Marshal.ThrowExceptionForHR(dev.Activate(ref iid, 23, IntPtr.Zero, out o));
      IAudioSessionEnumerator se;
      Marshal.ThrowExceptionForHR(((IAudioSessionManager2)o).GetSessionEnumerator(out se));
      int n; se.GetCount(out n);
      for (int i = 0; i < n; i++) {
        IAudioSessionControl2 c;
        if (se.GetSession(i, out c) != 0) continue;
        uint pid; c.GetProcessId(out pid);
        if (pid == 0) continue; // системные звуки
        if (!map.ContainsKey(pid)) map[pid] = new List<ISimpleAudioVolume>();
        map[pid].Add((ISimpleAudioVolume)c);
      }
      return map;
    }
    public static uint[] Pids() { return new List<uint>(Sessions().Keys).ToArray(); }
    public static float Get(uint pid) {
      List<ISimpleAudioVolume> v;
      if (!Sessions().TryGetValue(pid, out v)) return -1;
      float level; v[0].GetMasterVolume(out level); return level;
    }
    public static int Set(uint pid, float level) {
      List<ISimpleAudioVolume> v;
      if (!Sessions().TryGetValue(pid, out v)) return 0;
      Guid ctx = Guid.Empty;
      foreach (var s in v) s.SetMasterVolume(Math.Max(0f, Math.Min(1f, level)), ref ctx);
      return v.Count;
    }
  }
}
