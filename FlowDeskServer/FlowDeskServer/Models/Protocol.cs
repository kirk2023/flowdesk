using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace FlowDesk.Models
{
    // 设备发现广播
    public class DiscoveryBeacon
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = ""; // "whoami" | "iam" | "bye"

        [JsonPropertyName("id")]
        public string Id { get; set; } = "";

        [JsonPropertyName("alias")]
        public string? Alias { get; set; }

        [JsonPropertyName("port")]
        public int Port { get; set; }

        [JsonPropertyName("proto")]
        public string Proto { get; set; } = "flowdesk-v1";

        [JsonPropertyName("ts")]
        public long Ts { get; set; }
    }

    // 配对握手
    public class PairingHello
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = "pair-hello";

        [JsonPropertyName("id")]
        public string Id { get; set; } = "";

        [JsonPropertyName("pubKey")]
        public string PubKey { get; set; } = "";

        [JsonPropertyName("pin")]
        public string Pin { get; set; } = "";

        [JsonPropertyName("proto")]
        public string Proto { get; set; } = "flowdesk-v1";

        [JsonPropertyName("ts")]
        public long Ts { get; set; }

        [JsonPropertyName("nonce")]
        public string Nonce { get; set; } = "";
    }

    public class PairingAccept
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = "pair-accept";

        [JsonPropertyName("id")]
        public string Id { get; set; } = "";

        [JsonPropertyName("pubKey")]
        public string PubKey { get; set; } = "";

        [JsonPropertyName("ts")]
        public long Ts { get; set; }

        [JsonPropertyName("nonce")]
        public string Nonce { get; set; } = "";

        [JsonPropertyName("screenW")]
        public int ScreenW { get; set; }

        [JsonPropertyName("screenH")]
        public int ScreenH { get; set; }
    }

    public class PairingReject
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = "pair-reject";

        [JsonPropertyName("id")]
        public string Id { get; set; } = "";

        [JsonPropertyName("reason")]
        public string Reason { get; set; } = "";

        [JsonPropertyName("ts")]
        public long Ts { get; set; }
    }

    // 屏幕流元数据
    public class StreamMeta
    {
        [JsonPropertyName("width")]
        public int Width { get; set; }

        [JsonPropertyName("height")]
        public int Height { get; set; }

        [JsonPropertyName("fps")]
        public int Fps { get; set; }

        [JsonPropertyName("codec")]
        public string Codec { get; set; } = "jpeg";

        [JsonPropertyName("bitrate")]
        public int Bitrate { get; set; }
    }

    // 屏幕帧包
    public class ScreenFrame
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = "frame";

        [JsonPropertyName("seq")]
        public long Seq { get; set; }

        [JsonPropertyName("data")]
        public byte[] Data { get; set; } = Array.Empty<byte>();

        [JsonPropertyName("ts")]
        public long Ts { get; set; }
    }

    // 输入事件
    public class InputEventMessage
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = "input";

        [JsonPropertyName("event")]
        public string Event { get; set; } = ""; // mouse-down, key-down, etc.

        [JsonPropertyName("x")]
        public double? X { get; set; }

        [JsonPropertyName("y")]
        public double? Y { get; set; }

        [JsonPropertyName("button")]
        public string? Button { get; set; }

        [JsonPropertyName("dx")]
        public int? Dx { get; set; }

        [JsonPropertyName("dy")]
        public int? Dy { get; set; }

        [JsonPropertyName("code")]
        public int? Code { get; set; }

        [JsonPropertyName("modifiers")]
        public int? Modifiers { get; set; }

        [JsonPropertyName("text")]
        public string? Text { get; set; }

        [JsonPropertyName("ts")]
        public long Ts { get; set; }
    }

    // 修饰键位掩码（与鸿蒙端对齐）
    public static class ModifierMask
    {
        public const int SHIFT = 1 << 0;
        public const int CTRL = 1 << 1;
        public const int ALT = 1 << 2;
        public const int META = 1 << 3;
    }
}
