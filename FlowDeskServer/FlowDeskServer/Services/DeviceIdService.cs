using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using FlowDesk.Common;

namespace FlowDesk.Services
{
    /// <summary>
    /// 设备身份管理：首次启动生成本机 DeviceID + AccessKey，本地加密保存
    /// </summary>
    public class DeviceIdService
    {
        private const string STORE_FILE = "device_identity.json";
        private static readonly byte[] ENTROPY = Encoding.UTF8.GetBytes("FlowDesk.DeviceIdentity.v1");

        public string DeviceId { get; private set; } = "";
        public string AccessKey { get; private set; } = ""; // base64
        public string Alias { get; private set; } = "";

        private string StorePath => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "FlowDesk", STORE_FILE);

        public async Task InitializeAsync()
        {
            Directory.CreateDirectory(Path.GetDirectoryName(StorePath)!);

            if (File.Exists(StorePath))
            {
                try
                {
                    var json = await File.ReadAllTextAsync(StorePath);
                    var data = JsonSerializer.Deserialize<IdentityData>(json);
                    if (data != null && Constants.IsValidDeviceId(data.DeviceId))
                    {
                        DeviceId = data.DeviceId;
                        AccessKey = data.AccessKey;
                        Alias = data.Alias ?? Environment.MachineName;
                        Logger.Info("DeviceId", $"loaded existing id={DeviceId}");
                        return;
                    }
                }
                catch (Exception ex)
                {
                    Logger.Warn("DeviceId", $"failed to load identity, regenerating: {ex.Message}");
                }
            }

            // 生成新身份
            DeviceId = Constants.GenerateDeviceId();
            AccessKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
            Alias = Environment.MachineName;

            var newData = new IdentityData
            {
                DeviceId = DeviceId,
                AccessKey = AccessKey,
                Alias = Alias,
                CreatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            };
            await File.WriteAllTextAsync(StorePath, JsonSerializer.Serialize(newData));
            Logger.Info("DeviceId", $"generated new id={DeviceId}, alias={Alias}");
        }

        private class IdentityData
        {
            public string DeviceId { get; set; } = "";
            public string AccessKey { get; set; } = "";
            public string Alias { get; set; } = "";
            public long CreatedAt { get; set; }
        }
    }
}
