using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;

namespace ProfileSwitcher;

public partial class MainWindow : Window
{
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(3) };
    private readonly DispatcherTimer _timer;
    private readonly string _scriptDir;
    private string? _activeProfile;

    private static readonly SolidColorBrush GreenBrush = new(Color.FromRgb(0x00, 0xC8, 0x53));
    private static readonly SolidColorBrush RedBrush   = new(Color.FromRgb(0xFF, 0x17, 0x44));
    private static readonly SolidColorBrush DimBrush   = new(Color.FromRgb(0x55, 0x55, 0x55));
    private static readonly SolidColorBrush YellowBrush = new(Color.FromRgb(0xFF, 0xD6, 0x00));
    private static readonly SolidColorBrush BlueBrush  = new(Color.FromRgb(0x44, 0x8A, 0xFF));
    private static readonly SolidColorBrush TextDim    = new(Color.FromRgb(0x9E, 0x9E, 0x9E));
    private static readonly SolidColorBrush OrangeBrush = new(Color.FromRgb(0xFF, 0x9E, 0x00));

    public MainWindow()
    {
        InitializeComponent();

        // Script directory = parent of ProfileSwitcher/
        _scriptDir = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, ".."));

        // Wire up buttons
        btnPowerSaver.Click += async (_, _) => await ApplyProfile("PowerSaver.ps1", "PowerSaver");
        btnGamingMode.Click += async (_, _) => await ApplyProfile("GamingMode.ps1", "GamingMode");

        // NETIO poll timer (every 5 seconds)
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        _timer.Tick += async (_, _) => await RefreshPower();
        _timer.Start();

        // Initial read
        Loaded += async (_, _) => await RefreshPower();
    }

    private async Task RefreshPower()
    {
        try
        {
            var authBytes = System.Text.Encoding.ASCII.GetBytes("netio:netio");
            var authHeader = Convert.ToBase64String(authBytes);

            using var request = new HttpRequestMessage(HttpMethod.Get, "http://192.168.178.118/netio.json");
            request.Headers.TryAddWithoutValidation("Authorization", $"Basic {authHeader}");

            var response = await _http.SendAsync(request);
            response.EnsureSuccessStatusCode();
            var json = await response.Content.ReadAsStringAsync();

            using var doc = JsonDocument.Parse(json);
            var outputs = doc.RootElement.GetProperty("Outputs");
            double watts = 0;

            foreach (var output in outputs.EnumerateArray())
            {
                if (output.TryGetProperty("Name", out var name) && name.GetString() == "PC RIG")
                {
                    watts = output.GetProperty("Current").GetDouble();
                    break;
                }
            }
            if (watts == 0 && outputs.GetArrayLength() > 0)
                watts = outputs[0].GetProperty("Current").GetDouble();

            txtPower.Text = $"{watts:F1}W";
            txtPowerLabel.Text = "live from NETIO 4KF";

            // Color code: green < 100W, blue 100-130W, orange 130-180W, red > 180W
            txtPower.Foreground = watts switch
            {
                < 100 => GreenBrush,
                < 130 => BlueBrush,
                < 180 => OrangeBrush,
                _ => RedBrush
            };
        }
        catch
        {
            txtPower.Text = "---";
            txtPowerLabel.Text = "NETIO unavailable";
            txtPower.Foreground = TextDim;
        }
    }

    private async Task ApplyProfile(string scriptName, string label)
    {
        var scriptPath = Path.Combine(_scriptDir, scriptName);
        if (!File.Exists(scriptPath))
        {
            SetStatus($"{scriptName} not found in {_scriptDir}", RedBrush);
            return;
        }

        // Disable buttons during execution
        btnPowerSaver.IsEnabled = false;
        btnGamingMode.IsEnabled = false;
        SetStatus($"Applying {label}... (UAC prompt may appear)", YellowBrush);

        try
        {
            var exitCode = await Task.Run(() =>
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "pwsh.exe",
                    Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
                    Verb = "runas",
                    UseShellExecute = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };

                using var proc = Process.Start(psi);
                if (proc == null) return -1;
                proc.WaitForExit(120_000); // 2 min max
                return proc.HasExited ? proc.ExitCode : -2;
            });

            if (exitCode == 0)
            {
                _activeProfile = label;
                SetStatus($"{label} applied successfully", GreenBrush);
                UpdateDots();
            }
            else if (exitCode == -2)
            {
                SetStatus($"{label} timed out (still running?)", OrangeBrush);
            }
            else
            {
                SetStatus($"{label} finished with exit code {exitCode}", OrangeBrush);
                _activeProfile = label;
                UpdateDots();
            }
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            SetStatus("UAC prompt was cancelled", OrangeBrush);
        }
        catch (Exception ex)
        {
            SetStatus($"Error: {ex.Message}", RedBrush);
        }

        btnPowerSaver.IsEnabled = true;
        btnGamingMode.IsEnabled = true;

        // Refresh power after a brief delay
        await Task.Delay(2500);
        await RefreshPower();
    }

    private void SetStatus(string text, SolidColorBrush color)
    {
        txtStatus.Text = text;
        txtStatus.Foreground = color;
    }

    private void UpdateDots()
    {
        dotPowerSaver.Fill = _activeProfile == "PowerSaver" ? GreenBrush : DimBrush;
        dotGamingMode.Fill = _activeProfile == "GamingMode" ? RedBrush : DimBrush;
    }
}
