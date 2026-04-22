using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ProfileSwitcher;

public class AppConfig
{
    [JsonPropertyName("netio")]
    public NetioConfig Netio { get; set; } = new();

    [JsonPropertyName("hardware")]
    public HardwareConfig Hardware { get; set; } = new();

    [JsonPropertyName("profiles")]
    public ProfilesConfig Profiles { get; set; } = new();

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static AppConfig Load(string path)
    {
        if (!File.Exists(path))
            return new AppConfig();

        var json = File.ReadAllText(path);
        return JsonSerializer.Deserialize<AppConfig>(json, JsonOpts) ?? new AppConfig();
    }

    public void Save(string path)
    {
        var json = JsonSerializer.Serialize(this, JsonOpts);
        File.WriteAllText(path, json);
    }
}

public class NetioConfig
{
    [JsonPropertyName("host")]
    public string Host { get; set; } = "";

    [JsonPropertyName("user")]
    public string User { get; set; } = "";

    [JsonPropertyName("pass")]
    public string Pass { get; set; } = "";

    [JsonPropertyName("outputName")]
    public string OutputName { get; set; } = "PC RIG";
}

public class HardwareConfig
{
    [JsonPropertyName("cpu")]
    public string Cpu { get; set; } = "AMD Ryzen CPU";

    [JsonPropertyName("gpu")]
    public string Gpu { get; set; } = "AMD Radeon GPU";

    [JsonPropertyName("nicPattern")]
    public string NicPattern { get; set; } = "";
}

public class ProfilesConfig
{
    [JsonPropertyName("powerSaver")]
    public ProfileValues PowerSaver { get; set; } = new()
    {
        CpuMax = 99, CpuMin = 5,
        Ppt = 45, Tdc = 35, Edc = 50, Htc = 70,
        GpuPowerLimit = -10, GpuMaxFreq = 1000, GpuVoltage = 825,
        CoreParkMax = 50, CoreParkMin = 5
    };

    [JsonPropertyName("gamingMode")]
    public ProfileValues GamingMode { get; set; } = new()
    {
        CpuMax = 100, CpuMin = 100,
        Ppt = 142, Tdc = 95, Edc = 140, Htc = 90,
        CoreParkMax = 100, CoreParkMin = 100
    };
}

public class ProfileValues
{
    [JsonPropertyName("cpuMax")]
    public int CpuMax { get; set; }

    [JsonPropertyName("cpuMin")]
    public int CpuMin { get; set; }

    [JsonPropertyName("ppt")]
    public int Ppt { get; set; }

    [JsonPropertyName("tdc")]
    public int Tdc { get; set; }

    [JsonPropertyName("edc")]
    public int Edc { get; set; }

    [JsonPropertyName("htc")]
    public int Htc { get; set; }

    [JsonPropertyName("gpuPowerLimit")]
    public int GpuPowerLimit { get; set; }

    [JsonPropertyName("gpuMaxFreq")]
    public int GpuMaxFreq { get; set; }

    [JsonPropertyName("gpuVoltage")]
    public int GpuVoltage { get; set; }

    [JsonPropertyName("coreParkMax")]
    public int CoreParkMax { get; set; }

    [JsonPropertyName("coreParkMin")]
    public int CoreParkMin { get; set; }

    public string SummaryLine =>
        $"CPU {CpuMax}% · PPT {Ppt}W · GPU {GpuMaxFreq}MHz/{GpuVoltage}mV";
}
