using System;
using System.Collections.Generic;
using System.Net.NetworkInformation;
using System.Diagnostics;

namespace NetMonitor
{
    public class TrafficSample
    {
        public string Interface { get; set; }
        public long DownloadBytes { get; set; }
        public long UploadBytes { get; set; }
        public long TotalBytes { get; set; }
    }

    public static class TrafficNative
    {
        // Оригинални кешеви 
        private static readonly Dictionary<string, long> lastDownload = new Dictionary<string, long>();
        private static readonly Dictionary<string, long> lastUpload = new Dictionary<string, long>();
        private static readonly Dictionary<string, string> wifiCache = new Dictionary<string, string>();

        private static DateTime lastSSIDCheck = DateTime.MinValue;
        private static DateTime lastInterfaceScan = DateTime.MinValue;

        private static NetworkInterface[] cachedInterfaces = null;

        // ULTRA-optimized 
        public static List<TrafficSample> SampleAll()
        {
            // Освежи интерфејси само на 10 секунди 
            if (cachedInterfaces == null || (DateTime.UtcNow - lastInterfaceScan).TotalSeconds > 10)
            {
                try
                {
                    // GetAllNetworkInterfaces е релативно скап повик, така што го кешираме
                    cachedInterfaces = NetworkInterface.GetAllNetworkInterfaces();
                    lastInterfaceScan = DateTime.UtcNow;
                }
                catch
                {
                    // Ако не може да го врати интерфејсите - вратиме празна листа (логички слично на original)
                    return new List<TrafficSample>();
                }
            }

            var samples = new List<TrafficSample>();

            try
            {
                foreach (var ni in cachedInterfaces)
                {
                    // Null-safety и локални променливи за да се намалат речиците
                    if (ni == null) continue;

                    string name = ni.Name ?? string.Empty;
                    string desc = ni.Description ?? string.Empty;

                    // --- FILTER: Исклучи виртуелни адаптери
                    if (
                        name.IndexOf("vmnet", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("vmware", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("virtualbox", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("vbox", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("veth", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("wsl", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("hyper-v", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("vethernet", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("docker", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("tap", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.IndexOf("tun", StringComparison.OrdinalIgnoreCase) >= 0 ||

                        desc.IndexOf("vmware", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        desc.IndexOf("virtualbox", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        desc.IndexOf("hyper-v", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        desc.IndexOf("docker", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        desc.IndexOf("wsl", StringComparison.OrdinalIgnoreCase) >= 0 ||

                        ni.NetworkInterfaceType == NetworkInterfaceType.Loopback ||
                        ni.NetworkInterfaceType == NetworkInterfaceType.Tunnel
                    )
                        continue;
                    // --- END FILTER ---

                    if (ni.OperationalStatus != OperationalStatus.Up)
                        continue;

                    // displayName - логиката е неизменета: ако е Wi-Fi, се обидува да користи SSID 
                    string displayName = name;

                    if (ni.NetworkInterfaceType == NetworkInterfaceType.Wireless80211)
                    {
                        // GetWifiSSIDCached 
                        string cached = GetWifiSSIDCached(name);
                        if (!string.IsNullOrEmpty(cached))
                            displayName = cached;
                    }

                    // Земи IPv4 статистики 
                    var stats = ni.GetIPv4Statistics();
                    long currentDL = stats.BytesReceived;
                    long currentUL = stats.BytesSent;

                    // Прво мерење → set baseline 
                    if (!lastDownload.TryGetValue(displayName, out long lastDL))
                    {
                        lastDownload[displayName] = currentDL;
                        lastUpload[displayName] = currentUL;
                        continue;
                    }

                    // Корисни оптимизации:
                    // - директно користи out вредност за lastDL
                    lastUpload.TryGetValue(displayName, out long lastUL);

                    long deltaDL = currentDL - lastDL;
                    if (deltaDL < 0) deltaDL = 0;

                    long deltaUL = currentUL - lastUL;
                    if (deltaUL < 0) deltaUL = 0;

                    // Ажурирај baseline 
                    lastDownload[displayName] = currentDL;
                    lastUpload[displayName] = currentUL;

                    // Додај во резултати
                    samples.Add(new TrafficSample
                    {
                        Interface = displayName,
                        DownloadBytes = deltaDL,
                        UploadBytes = deltaUL,
                        TotalBytes = deltaDL + deltaUL
                    });
                }
            }
            catch
            {
                // Враќаме празна листа ако нешто тргне наопаку 
                return new List<TrafficSample>();
            }

            return samples;
        }

        // SSID кеш на 30 секунди 
        private static string GetWifiSSIDCached(string interfaceName)
        {
            if (wifiCache.TryGetValue(interfaceName, out string cached) &&
                (DateTime.UtcNow - lastSSIDCheck).TotalSeconds < 30)
            {
                return cached;
            }

            string ssid = GetWifiSSID();
            if (!string.IsNullOrEmpty(ssid))
            {
                wifiCache[interfaceName] = ssid;
            }

            lastSSIDCheck = DateTime.UtcNow;
            return ssid ?? interfaceName;
        }

        private static string GetWifiSSID()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "netsh",
                    Arguments = "wlan show interfaces",
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using (var process = Process.Start(psi))
                {
                    if (process == null)
                        return null;

                    // ReadToEnd е блокирачки, но останува дел од логиката 
                    string output = process.StandardOutput.ReadToEnd();
                    process.WaitForExit();

                    if (string.IsNullOrWhiteSpace(output))
                        return null;

                    // Парсинг: избегнуваме Split за да намалиме алокации, правиме едноставен parse по линија
                    int pos = 0;
                    while (pos < output.Length)
                    {
                        int next = output.IndexOfAny(new char[] { '\r', '\n' }, pos);
                        string line;
                        if (next >= 0)
                        {
                            line = output.Substring(pos, next - pos).Trim();
                            // прескокни CRLF
                            pos = next + 1;
                            // ако следниот е пар од CRLF, прескокни уште еден
                            if (pos < output.Length && output[pos - 1] == '\r' && output[pos] == '\n') pos++;
                        }
                        else
                        {
                            line = output.Substring(pos).Trim();
                            pos = output.Length;
                        }

                        if (line.Length == 0) continue;

                        // Логика за SSID: започнува со "SSID" но не "BSSID" 
                        if (line.StartsWith("SSID", StringComparison.OrdinalIgnoreCase) &&
                            !line.StartsWith("BSSID", StringComparison.OrdinalIgnoreCase))
                        {
                            int colon = line.IndexOf(':');
                            if (colon >= 0 && colon + 1 < line.Length)
                            {
                                string value = line.Substring(colon + 1).Trim();
                                if (value.Length > 0)
                                    return value;
                            }
                        }
                    }
                }
            }
            catch
            {
                // Silent fail 
                return null;
            }

            return null;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////// Net Monitor DLL File Script End.