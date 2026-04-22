"""Read hardware sensors via LibreHardwareMonitorLib (requires admin for full access)."""
import sys
import os
import json

# pythonnet setup for .NET Framework (net472)
os.environ["PYTHONNET_RUNTIME"] = "netfx"
import clr

LHM_PATH = os.path.join(os.environ["TEMP"], "LHM")
sys.path.insert(0, LHM_PATH)
clr.AddReference("LibreHardwareMonitorLib")

from LibreHardwareMonitor.Hardware import Computer, SensorType

def main():
    c = Computer()
    c.IsCpuEnabled = True
    c.IsGpuEnabled = True
    c.IsMemoryEnabled = True
    c.IsMotherboardEnabled = True
    c.IsStorageEnabled = True
    c.IsNetworkEnabled = True
    c.IsPsuEnabled = True
    c.Open()

    results = {}
    for hw in c.Hardware:
        hw.Update()
        hw_name = str(hw.Name)
        hw_type = str(hw.HardwareType)
        sensors = {}
        for sensor in hw.Sensors:
            stype = str(sensor.SensorType)
            sname = str(sensor.Name)
            sval = sensor.Value
            if sval is not None:
                key = f"{stype}/{sname}"
                sensors[key] = round(float(sval), 2)
        # Also check sub-hardware (e.g. GPU sub-components)
        for sub in hw.SubHardware:
            sub.Update()
            for sensor in sub.Sensors:
                stype = str(sensor.SensorType)
                sname = str(sensor.Name)
                sval = sensor.Value
                if sval is not None:
                    key = f"[{sub.Name}] {stype}/{sname}"
                    sensors[key] = round(float(sval), 2)
        results[f"{hw_type}: {hw_name}"] = sensors

    c.Close()

    # Print organized output
    for hw, sensors in results.items():
        print(f"\n{'='*60}")
        print(f"  {hw}")
        print(f"{'='*60}")

        # Group by sensor type
        grouped = {}
        for key, val in sensors.items():
            parts = key.split("/", 1)
            stype = parts[0].strip("[] ").split("] ")[-1] if "]" in parts[0] else parts[0]
            full_key = key
            if stype not in grouped:
                grouped[stype] = []
            grouped[stype].append((full_key, val))

        for stype in sorted(grouped.keys()):
            print(f"\n  [{stype}]")
            for key, val in sorted(grouped[stype], key=lambda x: x[0]):
                name_part = key.split("/", 1)[1] if "/" in key else key
                prefix = ""
                if "]" in key.split("/")[0]:
                    prefix = key.split("]")[0] + "] "
                unit = ""
                if "Temperature" in stype: unit = "°C"
                elif "Power" in stype: unit = "W"
                elif "Voltage" in stype: unit = "V"
                elif "Clock" in stype: unit = "MHz"
                elif "Load" in stype: unit = "%"
                elif "Fan" in stype: unit = "RPM"
                elif "Data" in stype or "SmallData" in stype: unit = "GB"
                elif "Throughput" in stype: unit = "KB/s"
                elif "Factor" in stype: unit = ""
                print(f"    {prefix}{name_part:40s} {val:>10.2f} {unit}")

if __name__ == "__main__":
    main()
