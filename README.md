# AMD PC Power Analyzer & Optimizer

> **From 152W to 91W idle — a 40% reduction in wall power, verified by hardware measurement.**
> 
> **With GPU tuning: down to 91W idle** (CPU + GPU combined optimization)

A power analysis and optimization toolkit for AMD Ryzen + Radeon desktop systems that goes beyond software estimation. This project combines **real-time hardware power measurement** via a NETIO smart power socket with **direct AMD SMU firmware control** (CPU) and **ADLX SDK control** (GPU) to achieve aggressive, verifiable power savings without sacrificing usability.

### What It Does

- **Measures** actual wall power draw via NETIO 4KF smart socket JSON API
- **Controls** CPU power limits (PPT/TDC/EDC/HTC) through direct SMU firmware commands
- **Controls** GPU power limit, clocks, and voltage through AMD ADLX SDK
- **Provides** one-click PowerSaver and GamingMode profiles with before/after verification
- **Includes** `ZenControl` (CPU SMU) and `GpuControl` (GPU ADLX) custom CLI tools

### Why Not Just Use RyzenAdj?

RyzenAdj doesn't support desktop Zen 3 chips (Family 19h Model 33 = "unsupported"). This project builds a custom tool on ZenStates-Core v1.75 that talks directly to the SMU firmware via WinRing0, giving full control over power limits on chips RyzenAdj can't touch.

## Hardware Profile

| Component | Model | TDP/Notes |
|-----------|-------|-----------|
| CPU | AMD Ryzen 9 5900X (12C/24T, 2 CCDs, Zen 3) | 105W TDP, boost 4.8GHz |
| GPU | AMD Radeon RX 6900 XT (16GB, Navi 21 XTX) | 300W TDP |
| Motherboard | ASRock X570 Pro4 | X570 chipset ~11W |
| RAM | 2x G.Skill Trident Z RGB 32GB DDR4-3200 CL16 | ~6W + RGB |
| NVMe | Samsung 980 PRO 1TB PCIe 4.0 | ~6W active |
| HDD | Toshiba HDWE140 4TB 7200RPM | ~8W spin / ~1W idle |
| NIC (onboard) | Intel I211 1GbE | ~1W |
| NIC (add-in) | Intel X520-2 dual 10GbE SFP+ | ~15W each (31W total) |
| PSU | Unknown (ATX) | — |
| Monitor | MSI G24C6 E2 (1080p 120Hz) | Separate PSU |

## Power Measurement

**NETIO 4KF** smart power socket ("PowerBOX-82") at `192.168.178.118`
- JSON API with Basic auth (`netio:netio`)
- Output 1: "PC RIG" — the measured system
- Outputs 2-4: BAMBU X1C, ENDER5, AUX

```powershell
# Quick power reading
$cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("netio:netio"))
$r = Invoke-RestMethod -Uri "http://192.168.178.118/netio.json" -Headers @{Authorization="Basic $cred"}
$r.Outputs[0] | Select-Object Name, Load, Current, PowerFactor
```

## Power Journey

| State | Wall Power | Change | Method |
|-------|-----------|--------|--------|
| Stock (all defaults) | 152W | baseline | — |
| Disable X520-2 NICs | 121W | -31W | `Disable-NetAdapter` |
| CPU 99% cap (no boost) | 105W | -16W | `powercfg PROCTHROTTLEMAX 99` |
| + ASPM max, HDD 3min, USB suspend | 97W | -8W | `powercfg` |
| + Process cleanup | 99-101W | ±0 | Killed 78 non-essential processes |
| + SMU PPT=30W ultralow | 92W | -5-8W | ZenControl via ZenStates-Core SMU |
| + GPU downclock 1000MHz/825mV/-10% | 91W | -14W vs stock GPU | GpuControl via ADLX SDK |
| **Best idle (PowerSaver)** | **~86-91W** | **-61-66W** | All combined (CPU+GPU) |

## Benchmark Results (12-thread CPU stress, NETIO measured)

| Metric | GamingMode | PowerSaver | Delta |
|--------|-----------|------------|-------|
| **Idle** | 119W | 91W | **-28W (24%)** |
| **Load @2s** | 246W | 109W | **-137W (56%)** |
| **Load @4s** | 236W | 109W | **-127W (54%)** |
| **Load @6s** | 232W | 109W | **-123W (53%)** |
| **Post-load** | 130W | 86W | **-44W (34%)** |
| **SMU PPT** | 142W (stock) | 45W | -97W cap |
| **SMU TDC** | 95A (stock) | 35A | -60A cap |
| **SMU EDC** | 140A (stock) | 50A | -90A cap |
| **CPU Boost** | Yes (4.8GHz) | No (99% cap) | — |
| **Core Parking** | Off (100%) | Aggressive (50%) | — |
| **ASPM** | Off | Max savings | — |

## Tools

### PowerSaver.ps1
Maximum power savings for normal work. Run as admin.
- Disables X520-2 NICs (-31W)
- CPU 99% max, 5% min (no boost)
- SMU: PPT=45W, TDC=35A, EDC=50A, HTC=70°C
- GPU: Max 1000MHz, 825mV, power limit -10% (via ADLX)
- Core parking 50%, ASPM max, USB suspend, HDD 3min timeout

### GamingMode.ps1
Maximum performance for gaming. Run as admin.
- CPU 100% max+min (full boost to 4.8GHz, no parking)
- SMU: PPT=142W, TDC=95A, EDC=140A, HTC=90°C (stock)
- GPU: Reset to factory defaults (2514MHz, 1175mV, full boost)
- ASPM off, USB suspend off, no timeouts
- X520-2 stays disabled unless `-EnableX520` flag

### ZenControl (C# / .NET 8)
Custom CLI tool built on [ZenStates-Core](https://github.com/irusanov/ZenStates-Core) v1.75.
Talks directly to AMD SMU firmware via WinRing0 kernel driver.

```
ZenControl.exe info          # CPU topology, SMU version, CCD fuse maps
ZenControl.exe ppt 45        # Set PPT to 45W (firmware enforced)
ZenControl.exe tdc 35        # Set TDC to 35A
ZenControl.exe edc 50        # Set EDC to 50A
ZenControl.exe htc 70        # Set temp limit to 70°C
ZenControl.exe powersave     # PPT=45W profile
ZenControl.exe ultralow      # PPT=30W profile
ZenControl.exe default       # Restore stock 5900X limits
ZenControl.exe netio         # Read NETIO power socket
ZenControl.exe smu rsmu 53 AF # Raw SMU command (hex)
```

**Requires admin.** Built from `ZenControl/` directory:
```
cd ZenControl
dotnet build -c Release
```
Runtime deps in `bin/Release/net8.0-windows/`: `inpoutx64.dll`, `WinRing0x64.dll`, `WinRing0x64.sys` (copied from RyzenAdj).

### GpuControl (C / GCC / ADLX SDK)
Custom CLI tool built on [AMD ADLX SDK](https://github.com/GPUOpen-LibrariesAndSDKs/ADLX) v1.5.
Controls GPU power, clocks, and voltage via the AMD driver's ADLX interface.

```
GpuControl.exe info          # GPU info, supported features, current values
GpuControl.exe powerlimit -10 # Set power limit to -10% of TDP
GpuControl.exe maxfreq 1000  # Cap GPU max frequency to 1000 MHz
GpuControl.exe minfreq 500   # Set GPU min frequency to 500 MHz
GpuControl.exe voltage 825   # Set GPU voltage to 825 mV (undervolt)
GpuControl.exe powersave     # Apply power-saving preset
GpuControl.exe default       # Reset GPU to factory defaults
GpuControl.exe netio         # Read NETIO power socket
```

**Does NOT require admin.** Built from `GpuControl/` directory:
```
cd GpuControl
gcc -O2 -o GpuControl.exe GpuControl.c %TEMP%\ADLX\SDK\ADLXHelper\Windows\C\ADLXHelper.c %TEMP%\ADLX\SDK\Platform\Windows\WinAPIs.c -I%TEMP%\ADLX -lole32
```
Requires AMD GPU driver (uses `amdadlx64.dll` from `C:\Windows\System32`).

#### GPU Tuning Ranges (RX 6900 XT)
| Parameter | Min | Stock | Max |
|-----------|-----|-------|-----|
| Power Limit | -10% | 0% | +15% |
| GPU Frequency | 500 MHz | 2514 MHz | 3000 MHz |
| GPU Voltage | 825 mV | 1175 mV | 1175 mV |

### read_sensors.py
LibreHardwareMonitor sensor reader via pythonnet (.NET Framework).
Reads CPU/GPU power, temps, clocks. Requires admin for CPU power data.

## CPU SMU Details (Vermeer / Zen 3)

- Family: `FAMILY_19H`, Model: `0x21`, CodeName: `Vermeer`
- SMU Version: `0x00384C00`, Table Version: `0x00380805`
- Socket: AM4, Package: `AM4`
- CCDs: 2, CCXs: 2, Cores/CCX: 6
- CCD0 core fuse: `0x30` (cores 4,5 disabled in silicon)
- CCD1 core fuse: `0x14` (cores 2,4 disabled in silicon)

### RSMU Command IDs
| Command | ID | Unit |
|---------|------|------|
| SetPPTLimit | 0x53 | mW |
| SetTDCVDDLimit | 0x54 | mA |
| SetEDCVDDLimit | 0x55 | mA |
| SetHTCLimit | 0x56 | °C |
| SetFreqAllCores | 0x5C | MHz |
| SetFreqPerCore | 0x5D | MHz |
| EnableOcMode | 0x5A | — |
| DisableOcMode | 0x5B | — |
| SetPBOScalar | 0x58 | — |

### Core Disabling
- **Software core parking** (powercfg CPMAXCORES) only hints the scheduler — cores still draw idle power
- **True CCD disable** requires BIOS: ASRock X570 Pro4 → Advanced → AMD CBS → Zen Common Options
- **Core fuse maps are hardware-burned** at the factory and cannot be changed via software

## Dependencies
- .NET 8 SDK (for building ZenControl)
- GCC / MinGW-w64 (for building GpuControl) — `winget install BrechtSanders.WinLibs.POSIX.UCRT`
- AMD ADLX SDK v1.5 (`git clone https://github.com/GPUOpen-LibrariesAndSDKs/ADLX`) — headers only, runtime uses driver's `amdadlx64.dll`
- Python 3.12+ with `pythonnet`, `psutil` (for read_sensors.py)
- LibreHardwareMonitor DLL at `%TEMP%\LHM`
- ZenStates-Core v1.75 built at `%TEMP%\ZenStates-Core`
- WinRing0 / inpoutx64 drivers (from RyzenAdj or ZenStates)

## System Notes
- OS: Windows (German locale — "Ausbalanciert" = Balanced power plan)
- Hyper-V enabled (vmcompute, vmms active, vEthernet Default Switch)
- AMD Ryzen Master + RyzenMasterSDK installed
- RyzenAdj does NOT support desktop Zen 3 (Fam19h model 33 = "unsupported")

## Credits & Acknowledgments

This project stands on the shoulders of these excellent open-source projects:

| Project | Author | License | Used For |
|---------|--------|---------|----------|
| [ZenStates-Core](https://github.com/irusanov/ZenStates-Core) | [irusanov](https://github.com/irusanov) | GPL-3.0 | SMU firmware communication — the engine behind ZenControl |
| [AMD ADLX SDK](https://github.com/GPUOpen-LibrariesAndSDKs/ADLX) | AMD / GPUOpen | AMD ADLX License | GPU tuning via driver API — the engine behind GpuControl |
| [RyzenAdj](https://github.com/FlyGoat/RyzenAdj) | [FlyGoat](https://github.com/FlyGoat) | LGPL-3.0 | WinRing0 / inpoutx64 kernel driver binaries |
| [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) | LibreHardwareMonitor team | MPL-2.0 | Hardware sensor reading (CPU/GPU temps, power, clocks) |
| [pythonnet](https://github.com/pythonnet/pythonnet) | pythonnet contributors | MIT | .NET ↔ Python bridge for sensor reading |
| [psutil](https://github.com/giampaolo/psutil) | [Giampaolo Rodola](https://github.com/giampaolo) | BSD-3-Clause | System/process monitoring |
| [WinRing0](https://github.com/GermanAizek/WinRing0) | Noriyuki MIYAZAKI / CoolerMaster | BSD-like | Low-level hardware access (ring-0 I/O) |

Special thanks to [NETIO Products](https://www.netio-products.com/) for making smart power sockets with a sane JSON API.

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.

GPL-3.0 is required because ZenControl links against [ZenStates-Core](https://github.com/irusanov/ZenStates-Core) (GPL-3.0).
You are free to use, modify, and redistribute this software under the terms of the GPL-3.0.
