using System.Windows;

namespace ProfileSwitcher;

public partial class SettingsWindow : Window
{
    public AppConfig Config { get; private set; }
    public bool Saved { get; private set; }

    public SettingsWindow(AppConfig config)
    {
        InitializeComponent();
        Config = config;
        LoadFromConfig();

        btnSave.Click += (_, _) => SaveAndClose();
        btnCancel.Click += (_, _) => { Saved = false; Close(); };
    }

    private void LoadFromConfig()
    {
        // NETIO
        tbNetioHost.Text = Config.Netio.Host;
        tbNetioUser.Text = Config.Netio.User;
        tbNetioPass.Password = Config.Netio.Pass;
        tbNetioOutput.Text = Config.Netio.OutputName;

        // Hardware
        tbCpu.Text = Config.Hardware.Cpu;
        tbGpu.Text = Config.Hardware.Gpu;
        tbNicPattern.Text = Config.Hardware.NicPattern;

        // PowerSaver
        var ps = Config.Profiles.PowerSaver;
        tbPsCpuMax.Text = ps.CpuMax.ToString();
        tbPsCpuMin.Text = ps.CpuMin.ToString();
        tbPsPpt.Text = ps.Ppt.ToString();
        tbPsTdc.Text = ps.Tdc.ToString();
        tbPsEdc.Text = ps.Edc.ToString();
        tbPsHtc.Text = ps.Htc.ToString();
        tbPsGpuPower.Text = ps.GpuPowerLimit.ToString();
        tbPsGpuFreq.Text = ps.GpuMaxFreq.ToString();
        tbPsGpuVolt.Text = ps.GpuVoltage.ToString();
        tbPsParkMax.Text = ps.CoreParkMax.ToString();
        tbPsParkMin.Text = ps.CoreParkMin.ToString();

        // GamingMode
        var gm = Config.Profiles.GamingMode;
        tbGmCpuMax.Text = gm.CpuMax.ToString();
        tbGmCpuMin.Text = gm.CpuMin.ToString();
        tbGmPpt.Text = gm.Ppt.ToString();
        tbGmTdc.Text = gm.Tdc.ToString();
        tbGmEdc.Text = gm.Edc.ToString();
        tbGmHtc.Text = gm.Htc.ToString();
        tbGmParkMax.Text = gm.CoreParkMax.ToString();
        tbGmParkMin.Text = gm.CoreParkMin.ToString();
    }

    private void SaveAndClose()
    {
        // NETIO
        Config.Netio.Host = tbNetioHost.Text.Trim();
        Config.Netio.User = tbNetioUser.Text.Trim();
        Config.Netio.Pass = tbNetioPass.Password;
        Config.Netio.OutputName = tbNetioOutput.Text.Trim();

        // Hardware
        Config.Hardware.Cpu = tbCpu.Text.Trim();
        Config.Hardware.Gpu = tbGpu.Text.Trim();
        Config.Hardware.NicPattern = tbNicPattern.Text.Trim();

        // PowerSaver
        var ps = Config.Profiles.PowerSaver;
        if (int.TryParse(tbPsCpuMax.Text, out var v)) ps.CpuMax = v;
        if (int.TryParse(tbPsCpuMin.Text, out v)) ps.CpuMin = v;
        if (int.TryParse(tbPsPpt.Text, out v)) ps.Ppt = v;
        if (int.TryParse(tbPsTdc.Text, out v)) ps.Tdc = v;
        if (int.TryParse(tbPsEdc.Text, out v)) ps.Edc = v;
        if (int.TryParse(tbPsHtc.Text, out v)) ps.Htc = v;
        if (int.TryParse(tbPsGpuPower.Text, out v)) ps.GpuPowerLimit = v;
        if (int.TryParse(tbPsGpuFreq.Text, out v)) ps.GpuMaxFreq = v;
        if (int.TryParse(tbPsGpuVolt.Text, out v)) ps.GpuVoltage = v;
        if (int.TryParse(tbPsParkMax.Text, out v)) ps.CoreParkMax = v;
        if (int.TryParse(tbPsParkMin.Text, out v)) ps.CoreParkMin = v;

        // GamingMode
        var gm = Config.Profiles.GamingMode;
        if (int.TryParse(tbGmCpuMax.Text, out v)) gm.CpuMax = v;
        if (int.TryParse(tbGmCpuMin.Text, out v)) gm.CpuMin = v;
        if (int.TryParse(tbGmPpt.Text, out v)) gm.Ppt = v;
        if (int.TryParse(tbGmTdc.Text, out v)) gm.Tdc = v;
        if (int.TryParse(tbGmEdc.Text, out v)) gm.Edc = v;
        if (int.TryParse(tbGmHtc.Text, out v)) gm.Htc = v;
        if (int.TryParse(tbGmParkMax.Text, out v)) gm.CoreParkMax = v;
        if (int.TryParse(tbGmParkMin.Text, out v)) gm.CoreParkMin = v;

        // --- Safety checks ---
        var warnings = new System.Collections.Generic.List<string>();
        CheckProfile(warnings, "PowerSaver", ps);
        CheckProfile(warnings, "GamingMode", gm);

        if (warnings.Count > 0)
        {
            var msg = "⚠ WARNING — The following settings may damage your hardware:\n\n"
                + string.Join("\n", warnings)
                + "\n\nAre you sure you want to save these values?";
            var result = MessageBox.Show(msg, "Dangerous Settings Detected",
                MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (result != MessageBoxResult.Yes)
                return;
        }

        Saved = true;
        Close();
    }

    private static void CheckProfile(System.Collections.Generic.List<string> warnings, string name, ProfileValues p)
    {
        // CPU PPT — stock 5900X is 142W, anything above 200W is extreme
        if (p.Ppt > 200)
            warnings.Add($"[{name}] PPT = {p.Ppt}W is very high (stock desktop max ~142W). Risk of CPU overheating.");
        // TDC
        if (p.Tdc > 160)
            warnings.Add($"[{name}] TDC = {p.Tdc}A is very high (stock ~95A). Risk of VRM damage.");
        // EDC
        if (p.Edc > 200)
            warnings.Add($"[{name}] EDC = {p.Edc}A is very high (stock ~140A). Risk of VRM damage.");
        // HTC too high — thermal protection disabled
        if (p.Htc > 100)
            warnings.Add($"[{name}] HTC = {p.Htc}°C is dangerously high. CPU thermal protection may be insufficient.");
        // HTC too low — will throttle constantly
        if (p.Htc > 0 && p.Htc < 50)
            warnings.Add($"[{name}] HTC = {p.Htc}°C is very low. CPU will throttle constantly.");
        // GPU voltage too high
        if (p.GpuVoltage > 1175)
            warnings.Add($"[{name}] GPU voltage = {p.GpuVoltage}mV exceeds factory max (1175mV). Risk of GPU damage.");
        // GPU frequency too high
        if (p.GpuMaxFreq > 2800)
            warnings.Add($"[{name}] GPU max freq = {p.GpuMaxFreq}MHz is extreme overclocking territory. Risk of instability/damage.");
        // GPU power limit too high
        if (p.GpuPowerLimit > 15)
            warnings.Add($"[{name}] GPU power limit = +{p.GpuPowerLimit}% exceeds factory max (+15%). Risk of GPU damage.");
    }
}
