using System;
using System.Net;
using System.Text;
using ZenStates.Core;

class Program
{
    static Cpu? cpu;

    static void Main(string[] args)
    {
        if (!IsAdministrator())
        {
            Console.Error.WriteLine("ERROR: Must run as Administrator!");
            Environment.Exit(1);
        }

        try
        {
            cpu = new Cpu();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to initialize CPU: {ex.Message}");
            Environment.Exit(1);
        }

        Console.WriteLine("=== ZenControl - AMD SMU Power Tool ===");
        Console.WriteLine($"CPU: {cpu.info.cpuName}");
        Console.WriteLine($"CodeName: {cpu.info.codeName}");
        Console.WriteLine($"Family: {cpu.info.family} Model: 0x{cpu.info.model:X}");
        Console.WriteLine($"SMU Version: 0x{cpu.smu.Version:X8}");
        Console.WriteLine($"SMU Table Version: 0x{cpu.smu.TableVersion:X8}");
        Console.WriteLine($"Package: {cpu.info.packageType}");
        Console.WriteLine();

        // Topology
        var topo = cpu.info.topology;
        Console.WriteLine("=== CPU Topology ===");
        Console.WriteLine($"CCDs: {topo.ccds}");
        Console.WriteLine($"CCXs: {topo.ccxs}");
        Console.WriteLine($"Cores/CCX: {topo.coresPerCcx}");
        Console.WriteLine($"Physical Cores: {topo.cores}");
        Console.WriteLine($"Logical Cores: {topo.logicalCores}");
        Console.WriteLine($"Threads/Core: {topo.threadsPerCore}");
        Console.WriteLine($"CCD Enable Map: 0x{topo.ccdEnableMap:X}");
        Console.WriteLine($"CCD Disable Map: 0x{topo.ccdDisableMap:X}");
        if (topo.coreDisableMap != null)
        {
            for (int i = 0; i < topo.coreDisableMap.Length; i++)
                Console.WriteLine($"CCD{i} Core Disable Map: 0x{topo.coreDisableMap[i]:X2} (binary: {Convert.ToString(topo.coreDisableMap[i], 2).PadLeft(8, '0')})");
        }
        if (topo.performanceOfCore != null)
        {
            Console.Write("Core Performance Ranking: ");
            for (int i = 0; i < topo.performanceOfCore.Length; i++)
                Console.Write($"C{i}={topo.performanceOfCore[i]} ");
            Console.WriteLine();
        }
        Console.WriteLine();

        // SMU Command IDs
        Console.WriteLine("=== SMU Command IDs (RSMU) ===");
        Console.WriteLine($"SetPPTLimit:    0x{cpu.smu.Rsmu.SMU_MSG_SetPPTLimit:X2}");
        Console.WriteLine($"SetTDCVDDLimit: 0x{cpu.smu.Rsmu.SMU_MSG_SetTDCVDDLimit:X2}");
        Console.WriteLine($"SetEDCVDDLimit: 0x{cpu.smu.Rsmu.SMU_MSG_SetEDCVDDLimit:X2}");
        Console.WriteLine($"SetHTCLimit:    0x{cpu.smu.Rsmu.SMU_MSG_SetHTCLimit:X2}");
        Console.WriteLine($"SetFreqAll:     0x{cpu.smu.Rsmu.SMU_MSG_SetOverclockFrequencyAllCores:X2}");
        Console.WriteLine($"SetFreqPer:     0x{cpu.smu.Rsmu.SMU_MSG_SetOverclockFrequencyPerCore:X2}");
        Console.WriteLine($"EnableOC:       0x{cpu.smu.Rsmu.SMU_MSG_EnableOcMode:X2}");
        Console.WriteLine($"DisableOC:      0x{cpu.smu.Rsmu.SMU_MSG_DisableOcMode:X2}");
        Console.WriteLine($"SetBoostAll:    0x{cpu.smu.Rsmu.SMU_MSG_SetBoostLimitFrequencyAllCores:X2}");
        Console.WriteLine($"SetPBOScalar:   0x{cpu.smu.Rsmu.SMU_MSG_SetPBOScalar:X2}");
        Console.WriteLine();

        if (args.Length == 0)
        {
            PrintUsage();
            cpu.Dispose();
            return;
        }

        string command = args[0].ToLower();
        switch (command)
        {
            case "info":
                break;

            case "ppt":
                if (args.Length < 2) { Console.WriteLine("Usage: ppt <watts>"); break; }
                SetPPT(uint.Parse(args[1]));
                break;

            case "tdc":
                if (args.Length < 2) { Console.WriteLine("Usage: tdc <amps>"); break; }
                SetTDC(uint.Parse(args[1]));
                break;

            case "edc":
                if (args.Length < 2) { Console.WriteLine("Usage: edc <amps>"); break; }
                SetEDC(uint.Parse(args[1]));
                break;

            case "htc":
                if (args.Length < 2) { Console.WriteLine("Usage: htc <celsius>"); break; }
                SetHTC(uint.Parse(args[1]));
                break;

            case "powersave":
                var pptW = args.Length >= 2 ? uint.Parse(args[1]) : 45u;
                Console.WriteLine($">>> Applying PowerSave profile (PPT={pptW}W)...");
                ReadNetio("BEFORE");
                SetPPT(pptW);
                SetTDC(pptW <= 45 ? 35u : 60u);
                SetEDC(pptW <= 45 ? 50u : 90u);
                SetHTC(70);
                Console.WriteLine("Waiting 5s for power to settle...");
                System.Threading.Thread.Sleep(5000);
                ReadNetio("AFTER");
                break;

            case "default":
                Console.WriteLine(">>> Restoring 5900X default power limits...");
                ReadNetio("BEFORE");
                SetPPT(142);
                SetTDC(95);
                SetEDC(140);
                SetHTC(90);
                Console.WriteLine("Waiting 5s for power to settle...");
                System.Threading.Thread.Sleep(5000);
                ReadNetio("AFTER");
                break;

            case "ultralow":
                Console.WriteLine(">>> Applying UltraLow profile (PPT=30W)...");
                ReadNetio("BEFORE");
                SetPPT(30);
                SetTDC(25);
                SetEDC(35);
                SetHTC(65);
                Console.WriteLine("Waiting 5s for power to settle...");
                System.Threading.Thread.Sleep(5000);
                ReadNetio("AFTER");
                break;

            case "smu":
                if (args.Length < 3) { Console.WriteLine("Usage: smu <rsmu|mp1> <cmd_hex> [arg_hex]"); break; }
                SendRawSmu(args);
                break;

            case "netio":
                ReadNetio("CURRENT");
                break;

            default:
                PrintUsage();
                break;
        }

        cpu.Dispose();
    }

    static void PrintUsage()
    {
        Console.WriteLine("Usage: ZenControl <command> [args]");
        Console.WriteLine();
        Console.WriteLine("Commands:");
        Console.WriteLine("  info                  Show CPU info and topology");
        Console.WriteLine("  ppt <watts>           Set PPT limit");
        Console.WriteLine("  tdc <amps>            Set TDC limit");
        Console.WriteLine("  edc <amps>            Set EDC limit");
        Console.WriteLine("  htc <celsius>         Set HTC temp limit");
        Console.WriteLine("  powersave [watts]     Power save profile (default 45W PPT)");
        Console.WriteLine("  ultralow              Ultra-low profile (30W PPT)");
        Console.WriteLine("  default               Restore 5900X stock limits");
        Console.WriteLine("  smu <rsmu|mp1> <cmd> [arg]  Raw SMU command (hex)");
        Console.WriteLine("  netio                 Read NETIO power");
    }

    static SMU.Status SendSmuCmd(uint cmd, uint arg, bool useRsmu = true)
    {
        uint[] args = new uint[6];
        args[0] = arg;
        return useRsmu
            ? cpu!.smu.SendRsmuCommand(cmd, ref args)
            : cpu!.smu.SendMp1Command(cmd, ref args);
    }

    static void SetPPT(uint watts)
    {
        uint cmd = cpu!.smu.Rsmu.SMU_MSG_SetPPTLimit;
        if (cmd == 0) { Console.WriteLine("PPT command not available"); return; }
        var status = SendSmuCmd(cmd, watts * 1000);
        Console.WriteLine($"  SetPPT({watts}W): {status}");
    }

    static void SetTDC(uint amps)
    {
        uint cmd = cpu!.smu.Rsmu.SMU_MSG_SetTDCVDDLimit;
        if (cmd == 0) { Console.WriteLine("TDC command not available"); return; }
        var status = SendSmuCmd(cmd, amps * 1000);
        Console.WriteLine($"  SetTDC({amps}A): {status}");
    }

    static void SetEDC(uint amps)
    {
        uint cmd = cpu!.smu.Rsmu.SMU_MSG_SetEDCVDDLimit;
        if (cmd == 0) { Console.WriteLine("EDC command not available"); return; }
        var status = SendSmuCmd(cmd, amps * 1000);
        Console.WriteLine($"  SetEDC({amps}A): {status}");
    }

    static void SetHTC(uint celsius)
    {
        uint cmd = cpu!.smu.Rsmu.SMU_MSG_SetHTCLimit;
        if (cmd == 0) { Console.WriteLine("HTC command not available"); return; }
        var status = SendSmuCmd(cmd, celsius);
        Console.WriteLine($"  SetHTC({celsius}C): {status}");
    }

    static void SendRawSmu(string[] args)
    {
        bool useRsmu = args[1].ToLower() == "rsmu";
        uint cmd = Convert.ToUInt32(args[2], 16);
        uint arg = args.Length >= 4 ? Convert.ToUInt32(args[3], 16) : 0;
        Console.WriteLine($"Sending {(useRsmu ? "RSMU" : "MP1")} cmd=0x{cmd:X2} arg=0x{arg:X8}...");
        uint[] smuArgs = new uint[6];
        smuArgs[0] = arg;
        var status = useRsmu
            ? cpu!.smu.SendRsmuCommand(cmd, ref smuArgs)
            : cpu!.smu.SendMp1Command(cmd, ref smuArgs);
        Console.WriteLine($"  Status: {status}");
        Console.Write("  Response: ");
        for (int i = 0; i < smuArgs.Length; i++)
            Console.Write($"[{i}]=0x{smuArgs[i]:X8} ");
        Console.WriteLine();
    }

    static void ReadNetio(string label)
    {
        try
        {
            string cred = Convert.ToBase64String(Encoding.ASCII.GetBytes("netio:netio"));
            using var client = new WebClient();
            client.Headers.Add("Authorization", "Basic " + cred);
            string json = client.DownloadString("http://192.168.178.118/netio.json");
            int idx = json.IndexOf("\"Current\"");
            if (idx > 0)
            {
                int colon = json.IndexOf(':', idx);
                int comma = json.IndexOf(',', colon);
                string currentStr = json.Substring(colon + 1, comma - colon - 1).Trim();

                idx = json.IndexOf("\"PowerFactor\"", comma);
                colon = json.IndexOf(':', idx);
                comma = json.IndexOf(',', colon);
                if (comma < 0) comma = json.IndexOf('}', colon);
                string pfStr = json.Substring(colon + 1, comma - colon - 1).Trim();

                idx = json.IndexOf("\"Load\"");
                colon = json.IndexOf(':', idx);
                comma = json.IndexOf(',', colon);
                string loadStr = json.Substring(colon + 1, comma - colon - 1).Trim();

                Console.WriteLine($"  NETIO {label}: {loadStr}W (Current: {currentStr}A, PF: {pfStr})");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  NETIO error: {ex.Message}");
        }
    }

    static bool IsAdministrator()
    {
        var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
        var principal = new System.Security.Principal.WindowsPrincipal(identity);
        return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
    }
}
