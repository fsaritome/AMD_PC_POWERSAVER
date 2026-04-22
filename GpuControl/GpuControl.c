/*
 * GpuControl - AMD GPU Power & Clock Control via ADLX SDK
 * For AMD RX 6000/7000 (RDNA2/3) GPUs on Windows
 *
 * Uses the AMD ADLX (AMD Device Library eXtra) C API to control:
 *   - GPU power limit (%)
 *   - GPU TDC limit (%)
 *   - GPU min/max frequency (MHz)
 *   - GPU voltage (mV)
 *   - Factory reset
 *
 * Build: gcc -O2 -o GpuControl.exe GpuControl.c ADLXHelper.c WinAPIs.c -I<SDK> -lole32
 * Requires: AMD GPU driver with amdadlx64.dll
 *
 * Copyright (C) 2026 - GPL-3.0
 */

#include "SDK/ADLXHelper/Windows/C/ADLXHelper.h"
#include "SDK/Include/IGPUManualPowerTuning.h"
#include "SDK/Include/IGPUManualGFXTuning.h"
#include "SDK/Include/IGPUTuning.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_usage(void) {
    printf("GpuControl - AMD GPU Power & Clock Control via ADLX\n");
    printf("Usage: GpuControl.exe <command> [value]\n\n");
    printf("Commands:\n");
    printf("  info                  Show GPU info, supported features & current values\n");
    printf("  powerlimit <%%>        Set GPU power limit (%% of TDP, e.g. -10 or 15)\n");
    printf("  tdclimit <%%>          Set GPU TDC limit (%%)\n");
    printf("  minfreq <MHz>         Set GPU minimum frequency\n");
    printf("  maxfreq <MHz>         Set GPU maximum frequency\n");
    printf("  voltage <mV>          Set GPU voltage\n");
    printf("  powersave             Apply power-saving preset (min power, low clocks)\n");
    printf("  default               Reset GPU to factory defaults\n");
    printf("  netio                 Read NETIO power socket\n");
}

/* Read NETIO power (same as ZenControl) */
static void cmd_netio(void) {
    printf("=== NETIO Power Reading ===\n");
    /* We'll shell out to PowerShell for the NETIO reading */
    system("powershell -NoProfile -Command \""
           "$cred=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('netio:netio'));"
           "$r=Invoke-RestMethod -Uri 'http://192.168.178.118/netio.json' -Headers @{Authorization=\\\"Basic $cred\\\"};"
           "Write-Host ('Output: ' + $r.Outputs[0].Name);"
           "Write-Host ('Power:  ' + $r.Outputs[0].Load + 'W');"
           "Write-Host ('Current:' + $r.Outputs[0].Current + 'A');"
           "Write-Host ('PF:     ' + $r.Outputs[0].PowerFactor)\"");
}

/* Show GPU info and all tuning states */
static int cmd_info(IADLXGPUTuningServices* gpuTuningService, IADLXGPU* gpu) {
    ADLX_RESULT res;
    const char* gpuName = NULL;
    const char* vendorId = NULL;
    const char* deviceId = NULL;
    adlx_uint vram = 0;
    const char* vramType = NULL;
    adlx_bool supported = 0;

    gpu->pVtbl->Name(gpu, &gpuName);
    gpu->pVtbl->VendorId(gpu, &vendorId);
    gpu->pVtbl->DeviceId(gpu, &deviceId);
    gpu->pVtbl->TotalVRAM(gpu, &vram);
    gpu->pVtbl->VRAMType(gpu, &vramType);

    printf("=== GPU Info ===\n");
    printf("  Name:      %s\n", gpuName ? gpuName : "unknown");
    printf("  Vendor:    %s\n", vendorId ? vendorId : "unknown");
    printf("  Device ID: %s\n", deviceId ? deviceId : "unknown");
    printf("  VRAM:      %u MB (%s)\n", vram, vramType ? vramType : "?");

    printf("\n=== Supported Features ===\n");
    gpuTuningService->pVtbl->IsSupportedManualPowerTuning(gpuTuningService, gpu, &supported);
    printf("  Manual Power Tuning:    %s\n", supported ? "YES" : "no");

    gpuTuningService->pVtbl->IsSupportedManualGFXTuning(gpuTuningService, gpu, &supported);
    printf("  Manual GFX Tuning:      %s\n", supported ? "YES" : "no");

    gpuTuningService->pVtbl->IsSupportedManualVRAMTuning(gpuTuningService, gpu, &supported);
    printf("  Manual VRAM Tuning:     %s\n", supported ? "YES" : "no");

    gpuTuningService->pVtbl->IsSupportedManualFanTuning(gpuTuningService, gpu, &supported);
    printf("  Manual Fan Tuning:      %s\n", supported ? "YES" : "no");

    gpuTuningService->pVtbl->IsSupportedPresetTuning(gpuTuningService, gpu, &supported);
    printf("  Preset Tuning:          %s\n", supported ? "YES" : "no");

    gpuTuningService->pVtbl->IsSupportedAutoTuning(gpuTuningService, gpu, &supported);
    printf("  Auto Tuning:            %s\n", supported ? "YES" : "no");

    adlx_bool isFactory = 0;
    gpuTuningService->pVtbl->IsAtFactory(gpuTuningService, gpu, &isFactory);
    printf("  At Factory Defaults:    %s\n", isFactory ? "YES" : "no");

    /* Power tuning details */
    printf("\n=== Power Tuning ===\n");
    IADLXInterface* powerIfc = NULL;
    res = gpuTuningService->pVtbl->GetManualPowerTuning(gpuTuningService, gpu, &powerIfc);
    if (ADLX_SUCCEEDED(res) && powerIfc) {
        IADLXManualPowerTuning* powerTuning = NULL;
        res = powerIfc->pVtbl->QueryInterface(powerIfc, IID_IADLXManualPowerTuning(), (void**)&powerTuning);
        if (ADLX_SUCCEEDED(res) && powerTuning) {
            ADLX_IntRange powerRange = {0};
            adlx_int powerLimit = 0;
            powerTuning->pVtbl->GetPowerLimitRange(powerTuning, &powerRange);
            powerTuning->pVtbl->GetPowerLimit(powerTuning, &powerLimit);
            printf("  Power Limit:  %d%% (range: %d%% to %d%%, step: %d)\n",
                   powerLimit, powerRange.minValue, powerRange.maxValue, powerRange.step);

            adlx_bool tdcSupported = 0;
            powerTuning->pVtbl->IsSupportedTDCLimit(powerTuning, &tdcSupported);
            if (tdcSupported) {
                ADLX_IntRange tdcRange = {0};
                adlx_int tdcLimit = 0;
                powerTuning->pVtbl->GetTDCLimitRange(powerTuning, &tdcRange);
                powerTuning->pVtbl->GetTDCLimit(powerTuning, &tdcLimit);
                printf("  TDC Limit:    %d%% (range: %d%% to %d%%, step: %d)\n",
                       tdcLimit, tdcRange.minValue, tdcRange.maxValue, tdcRange.step);
            } else {
                printf("  TDC Limit:    not supported\n");
            }
            powerTuning->pVtbl->Release(powerTuning);
        }
        powerIfc->pVtbl->Release(powerIfc);
    }

    /* GFX tuning details (post-Navi) */
    printf("\n=== GFX Tuning (Clocks & Voltage) ===\n");
    IADLXInterface* gfxIfc = NULL;
    res = gpuTuningService->pVtbl->GetManualGFXTuning(gpuTuningService, gpu, &gfxIfc);
    if (ADLX_SUCCEEDED(res) && gfxIfc) {
        IADLXManualGraphicsTuning2* gfxTuning2 = NULL;
        res = gfxIfc->pVtbl->QueryInterface(gfxIfc, IID_IADLXManualGraphicsTuning2(), (void**)&gfxTuning2);
        if (ADLX_SUCCEEDED(res) && gfxTuning2) {
            ADLX_IntRange minFreqRange = {0}, maxFreqRange = {0}, voltRange = {0};
            adlx_int minFreq = 0, maxFreq = 0, volt = 0;

            gfxTuning2->pVtbl->GetGPUMinFrequencyRange(gfxTuning2, &minFreqRange);
            gfxTuning2->pVtbl->GetGPUMinFrequency(gfxTuning2, &minFreq);
            printf("  Min Freq:     %d MHz (range: %d-%d, step: %d)\n",
                   minFreq, minFreqRange.minValue, minFreqRange.maxValue, minFreqRange.step);

            gfxTuning2->pVtbl->GetGPUMaxFrequencyRange(gfxTuning2, &maxFreqRange);
            gfxTuning2->pVtbl->GetGPUMaxFrequency(gfxTuning2, &maxFreq);
            printf("  Max Freq:     %d MHz (range: %d-%d, step: %d)\n",
                   maxFreq, maxFreqRange.minValue, maxFreqRange.maxValue, maxFreqRange.step);

            gfxTuning2->pVtbl->GetGPUVoltageRange(gfxTuning2, &voltRange);
            gfxTuning2->pVtbl->GetGPUVoltage(gfxTuning2, &volt);
            printf("  Voltage:      %d mV (range: %d-%d, step: %d)\n",
                   volt, voltRange.minValue, voltRange.maxValue, voltRange.step);

            gfxTuning2->pVtbl->Release(gfxTuning2);
        } else {
            printf("  Post-Navi (Tuning2) not available, trying pre-Navi...\n");
        }
        gfxIfc->pVtbl->Release(gfxIfc);
    }

    return 0;
}

/* Set power limit */
static int cmd_powerlimit(IADLXGPUTuningServices* svc, IADLXGPU* gpu, int value) {
    IADLXInterface* ifc = NULL;
    ADLX_RESULT res = svc->pVtbl->GetManualPowerTuning(svc, gpu, &ifc);
    if (ADLX_FAILED(res) || !ifc) { printf("ERROR: Cannot get power tuning interface\n"); return 1; }

    IADLXManualPowerTuning* pt = NULL;
    res = ifc->pVtbl->QueryInterface(ifc, IID_IADLXManualPowerTuning(), (void**)&pt);
    if (ADLX_FAILED(res) || !pt) { ifc->pVtbl->Release(ifc); printf("ERROR: QueryInterface failed\n"); return 1; }

    ADLX_IntRange range = {0};
    pt->pVtbl->GetPowerLimitRange(pt, &range);
    if (value < range.minValue || value > range.maxValue) {
        printf("ERROR: Value %d out of range (%d to %d)\n", value, range.minValue, range.maxValue);
        pt->pVtbl->Release(pt);
        ifc->pVtbl->Release(ifc);
        return 1;
    }

    res = pt->pVtbl->SetPowerLimit(pt, value);
    if (res == 4 /* ADLX_RESET_NEEDED */) {
        printf("Reset needed, resetting to factory first...\n");
        svc->pVtbl->ResetToFactory(svc, gpu);
        res = pt->pVtbl->SetPowerLimit(pt, value);
    }

    adlx_int cur = 0;
    pt->pVtbl->GetPowerLimit(pt, &cur);
    printf("Power limit set to %d%% (result: %d)\n", cur, res);

    pt->pVtbl->Release(pt);
    ifc->pVtbl->Release(ifc);
    return ADLX_SUCCEEDED(res) ? 0 : 1;
}

/* Set TDC limit */
static int cmd_tdclimit(IADLXGPUTuningServices* svc, IADLXGPU* gpu, int value) {
    IADLXInterface* ifc = NULL;
    ADLX_RESULT res = svc->pVtbl->GetManualPowerTuning(svc, gpu, &ifc);
    if (ADLX_FAILED(res) || !ifc) { printf("ERROR: Cannot get power tuning interface\n"); return 1; }

    IADLXManualPowerTuning* pt = NULL;
    res = ifc->pVtbl->QueryInterface(ifc, IID_IADLXManualPowerTuning(), (void**)&pt);
    if (ADLX_FAILED(res) || !pt) { ifc->pVtbl->Release(ifc); printf("ERROR: QueryInterface failed\n"); return 1; }

    adlx_bool supported = 0;
    pt->pVtbl->IsSupportedTDCLimit(pt, &supported);
    if (!supported) {
        printf("TDC limit not supported on this GPU\n");
        pt->pVtbl->Release(pt);
        ifc->pVtbl->Release(ifc);
        return 1;
    }

    ADLX_IntRange range = {0};
    pt->pVtbl->GetTDCLimitRange(pt, &range);
    if (value < range.minValue || value > range.maxValue) {
        printf("ERROR: Value %d out of range (%d to %d)\n", value, range.minValue, range.maxValue);
        pt->pVtbl->Release(pt);
        ifc->pVtbl->Release(ifc);
        return 1;
    }

    res = pt->pVtbl->SetTDCLimit(pt, value);
    if (res == 4) {
        svc->pVtbl->ResetToFactory(svc, gpu);
        res = pt->pVtbl->SetTDCLimit(pt, value);
    }

    adlx_int cur = 0;
    pt->pVtbl->GetTDCLimit(pt, &cur);
    printf("TDC limit set to %d%% (result: %d)\n", cur, res);

    pt->pVtbl->Release(pt);
    ifc->pVtbl->Release(ifc);
    return ADLX_SUCCEEDED(res) ? 0 : 1;
}

/* Set GPU min/max frequency or voltage */
static int cmd_gfx_set(IADLXGPUTuningServices* svc, IADLXGPU* gpu, const char* what, int value) {
    IADLXInterface* ifc = NULL;
    ADLX_RESULT res = svc->pVtbl->GetManualGFXTuning(svc, gpu, &ifc);
    if (ADLX_FAILED(res) || !ifc) { printf("ERROR: Cannot get GFX tuning interface\n"); return 1; }

    IADLXManualGraphicsTuning2* gfx = NULL;
    res = ifc->pVtbl->QueryInterface(ifc, IID_IADLXManualGraphicsTuning2(), (void**)&gfx);
    if (ADLX_FAILED(res) || !gfx) {
        ifc->pVtbl->Release(ifc);
        printf("ERROR: Post-Navi GFX tuning not available\n");
        return 1;
    }

    ADLX_IntRange range = {0};
    if (strcmp(what, "minfreq") == 0) {
        gfx->pVtbl->GetGPUMinFrequencyRange(gfx, &range);
        if (value < range.minValue || value > range.maxValue) {
            printf("ERROR: %d MHz out of range (%d-%d)\n", value, range.minValue, range.maxValue);
        } else {
            res = gfx->pVtbl->SetGPUMinFrequency(gfx, value);
            if (res == 4) { svc->pVtbl->ResetToFactory(svc, gpu); res = gfx->pVtbl->SetGPUMinFrequency(gfx, value); }
            adlx_int cur = 0; gfx->pVtbl->GetGPUMinFrequency(gfx, &cur);
            printf("GPU min frequency set to %d MHz (result: %d)\n", cur, res);
        }
    } else if (strcmp(what, "maxfreq") == 0) {
        gfx->pVtbl->GetGPUMaxFrequencyRange(gfx, &range);
        if (value < range.minValue || value > range.maxValue) {
            printf("ERROR: %d MHz out of range (%d-%d)\n", value, range.minValue, range.maxValue);
        } else {
            res = gfx->pVtbl->SetGPUMaxFrequency(gfx, value);
            if (res == 4) { svc->pVtbl->ResetToFactory(svc, gpu); res = gfx->pVtbl->SetGPUMaxFrequency(gfx, value); }
            adlx_int cur = 0; gfx->pVtbl->GetGPUMaxFrequency(gfx, &cur);
            printf("GPU max frequency set to %d MHz (result: %d)\n", cur, res);
        }
    } else if (strcmp(what, "voltage") == 0) {
        gfx->pVtbl->GetGPUVoltageRange(gfx, &range);
        if (value < range.minValue || value > range.maxValue) {
            printf("ERROR: %d mV out of range (%d-%d)\n", value, range.minValue, range.maxValue);
        } else {
            res = gfx->pVtbl->SetGPUVoltage(gfx, value);
            if (res == 4) { svc->pVtbl->ResetToFactory(svc, gpu); res = gfx->pVtbl->SetGPUVoltage(gfx, value); }
            adlx_int cur = 0; gfx->pVtbl->GetGPUVoltage(gfx, &cur);
            printf("GPU voltage set to %d mV (result: %d)\n", cur, res);
        }
    }

    gfx->pVtbl->Release(gfx);
    ifc->pVtbl->Release(ifc);
    return ADLX_SUCCEEDED(res) ? 0 : 1;
}

/* Power-save preset: min power limit, low max clock */
static int cmd_powersave(IADLXGPUTuningServices* svc, IADLXGPU* gpu) {
    printf("=== Applying GPU PowerSave Preset ===\n");

    /* Set power limit to minimum */
    IADLXInterface* pifc = NULL;
    ADLX_RESULT res = svc->pVtbl->GetManualPowerTuning(svc, gpu, &pifc);
    if (ADLX_SUCCEEDED(res) && pifc) {
        IADLXManualPowerTuning* pt = NULL;
        res = pifc->pVtbl->QueryInterface(pifc, IID_IADLXManualPowerTuning(), (void**)&pt);
        if (ADLX_SUCCEEDED(res) && pt) {
            ADLX_IntRange range = {0};
            pt->pVtbl->GetPowerLimitRange(pt, &range);
            /* Set to minimum allowed power limit */
            res = pt->pVtbl->SetPowerLimit(pt, range.minValue);
            if (res == 4) { svc->pVtbl->ResetToFactory(svc, gpu); pt->pVtbl->SetPowerLimit(pt, range.minValue); }
            adlx_int cur = 0; pt->pVtbl->GetPowerLimit(pt, &cur);
            printf("  Power limit: %d%% (min)\n", cur);
            pt->pVtbl->Release(pt);
        }
        pifc->pVtbl->Release(pifc);
    }

    /* Lower max GPU frequency */
    IADLXInterface* gifc = NULL;
    res = svc->pVtbl->GetManualGFXTuning(svc, gpu, &gifc);
    if (ADLX_SUCCEEDED(res) && gifc) {
        IADLXManualGraphicsTuning2* gfx = NULL;
        res = gifc->pVtbl->QueryInterface(gifc, IID_IADLXManualGraphicsTuning2(), (void**)&gfx);
        if (ADLX_SUCCEEDED(res) && gfx) {
            /* Set max freq to ~1500 MHz (a safe low value for 6900XT) */
            ADLX_IntRange maxRange = {0};
            gfx->pVtbl->GetGPUMaxFrequencyRange(gfx, &maxRange);
            int target = 1500;
            if (target < maxRange.minValue) target = maxRange.minValue;
            if (target > maxRange.maxValue) target = maxRange.maxValue;
            res = gfx->pVtbl->SetGPUMaxFrequency(gfx, target);
            if (res == 4) { svc->pVtbl->ResetToFactory(svc, gpu); gfx->pVtbl->SetGPUMaxFrequency(gfx, target); }
            adlx_int cur = 0; gfx->pVtbl->GetGPUMaxFrequency(gfx, &cur);
            printf("  Max frequency: %d MHz\n", cur);

            /* Try to lower voltage too */
            ADLX_IntRange voltRange = {0};
            gfx->pVtbl->GetGPUVoltageRange(gfx, &voltRange);
            int vTarget = voltRange.minValue + (voltRange.maxValue - voltRange.minValue) / 4;
            res = gfx->pVtbl->SetGPUVoltage(gfx, vTarget);
            if (res == 4) { svc->pVtbl->ResetToFactory(svc, gpu); gfx->pVtbl->SetGPUVoltage(gfx, vTarget); }
            adlx_int vCur = 0; gfx->pVtbl->GetGPUVoltage(gfx, &vCur);
            printf("  Voltage: %d mV\n", vCur);

            gfx->pVtbl->Release(gfx);
        }
        gifc->pVtbl->Release(gifc);
    }

    printf("GPU PowerSave applied.\n");
    return 0;
}

/* Reset to factory defaults */
static int cmd_default(IADLXGPUTuningServices* svc, IADLXGPU* gpu) {
    ADLX_RESULT res = svc->pVtbl->ResetToFactory(svc, gpu);
    printf("Reset to factory defaults: %s (result: %d)\n",
           ADLX_SUCCEEDED(res) ? "OK" : "FAILED", res);
    return ADLX_SUCCEEDED(res) ? 0 : 1;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        print_usage();
        return 1;
    }

    /* Handle netio without ADLX init */
    if (strcmp(argv[1], "netio") == 0) {
        cmd_netio();
        return 0;
    }

    /* Initialize ADLX */
    ADLX_RESULT res = ADLXHelper_Initialize();
    if (ADLX_FAILED(res)) {
        printf("ERROR: ADLX initialization failed (result: %d)\n", res);
        printf("Make sure AMD GPU drivers are installed.\n");
        return 1;
    }

    IADLXSystem* sys = ADLXHelper_GetSystemServices();
    if (!sys) {
        printf("ERROR: Cannot get system services\n");
        ADLXHelper_Terminate();
        return 1;
    }

    /* Get GPU tuning services */
    IADLXGPUTuningServices* gpuTuningService = NULL;
    res = sys->pVtbl->GetGPUTuningServices(sys, &gpuTuningService);
    if (ADLX_FAILED(res) || !gpuTuningService) {
        printf("ERROR: Cannot get GPU tuning services (result: %d)\n", res);
        ADLXHelper_Terminate();
        return 1;
    }

    /* Get GPU list and select first GPU */
    IADLXGPUList* gpus = NULL;
    res = sys->pVtbl->GetGPUs(sys, &gpus);
    if (ADLX_FAILED(res) || !gpus) {
        printf("ERROR: Cannot get GPU list\n");
        gpuTuningService->pVtbl->Release(gpuTuningService);
        ADLXHelper_Terminate();
        return 1;
    }

    IADLXGPU* gpu = NULL;
    res = gpus->pVtbl->At_GPUList(gpus, 0, &gpu);
    if (ADLX_FAILED(res) || !gpu) {
        printf("ERROR: Cannot get GPU at index 0\n");
        gpus->pVtbl->Release(gpus);
        gpuTuningService->pVtbl->Release(gpuTuningService);
        ADLXHelper_Terminate();
        return 1;
    }

    const char* gpuName = NULL;
    gpu->pVtbl->Name(gpu, &gpuName);
    printf("GPU: %s\n\n", gpuName ? gpuName : "unknown");

    /* Dispatch command */
    int ret = 0;
    if (strcmp(argv[1], "info") == 0) {
        ret = cmd_info(gpuTuningService, gpu);
    } else if (strcmp(argv[1], "powerlimit") == 0 && argc >= 3) {
        ret = cmd_powerlimit(gpuTuningService, gpu, atoi(argv[2]));
    } else if (strcmp(argv[1], "tdclimit") == 0 && argc >= 3) {
        ret = cmd_tdclimit(gpuTuningService, gpu, atoi(argv[2]));
    } else if (strcmp(argv[1], "minfreq") == 0 && argc >= 3) {
        ret = cmd_gfx_set(gpuTuningService, gpu, "minfreq", atoi(argv[2]));
    } else if (strcmp(argv[1], "maxfreq") == 0 && argc >= 3) {
        ret = cmd_gfx_set(gpuTuningService, gpu, "maxfreq", atoi(argv[2]));
    } else if (strcmp(argv[1], "voltage") == 0 && argc >= 3) {
        ret = cmd_gfx_set(gpuTuningService, gpu, "voltage", atoi(argv[2]));
    } else if (strcmp(argv[1], "powersave") == 0) {
        ret = cmd_powersave(gpuTuningService, gpu);
    } else if (strcmp(argv[1], "default") == 0) {
        ret = cmd_default(gpuTuningService, gpu);
    } else {
        print_usage();
        ret = 1;
    }

    /* Cleanup */
    gpu->pVtbl->Release(gpu);
    gpus->pVtbl->Release(gpus);
    gpuTuningService->pVtbl->Release(gpuTuningService);
    ADLXHelper_Terminate();

    return ret;
}
