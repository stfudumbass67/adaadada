[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null
Clear-Host

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$currentFont = (Get-ItemProperty "HKCU:\Console" -ErrorAction SilentlyContinue).FaceName
if ($currentFont -notmatch "NSimSun|Gothic|Noto") {
    Write-Host "  Tip: To see all Unicode characters, set the terminal font to 'NSimSun'" -ForegroundColor DarkYellow
    Write-Host
}

$Banner = @"

  ███╗   ███╗███████╗ ██████╗ ██╗    ██╗  ███╗   ███╗ ██████╗ ██████╗
  ████╗ ████║██╔════╝██╔═══██╗██║    ██║  ████╗ ████║██╔═══██╗██╔══██╗
  ██╔████╔██║█████╗  ██║   ██║██║ █╗ ██║  ██╔████╔██║██║   ██║██║  ██║
  ██║╚██╔╝██║██╔══╝  ██║   ██║██║███╗██║  ██║╚██╔╝██║██║   ██║██║  ██║
  ██║ ╚═╝ ██║███████╗╚██████╔╝╚███╔███╔╝  ██║ ╚═╝ ██║╚██████╔╝██████╔╝
  ╚═╝     ╚═╝╚══════╝ ╚═════╝  ╚══╝╚══╝   ╚═╝     ╚═╝ ╚═════╝ ╚═════╝

   █████╗ ███╗   ██╗ █████╗ ██╗   ██╗   ██╗███████╗███████╗██████╗
  ██╔══██╗████╗  ██║██╔══██╗██║   ╚██╗ ██╔╝╚══███╔╝██╔════╝██╔══██╗
  ███████║██╔██╗ ██║███████║██║    ╚████╔╝   ███╔╝ █████╗  ██████╔╝
  ██╔══██║██║╚██╗██║██╔══██║██║     ╚██╔╝   ███╔╝  ██╔══╝  ██╔══██╗
  ██║  ██║██║ ╚████║██║  ██║███████╗ ██║   ███████╗███████╗██║  ██║
  ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝ ╚═╝   ╚══════╝╚══════╝╚═╝  ╚═╝

                         \    /\
                          )  ( ')
                         (  /  )
                          \(__)|

"@

Write-Host $Banner -ForegroundColor Cyan
Write-Host ""
Write-Host "                Made with " -ForegroundColor Gray -NoNewline
Write-Host "♥ " -ForegroundColor Red -NoNewline
Write-Host "by " -ForegroundColor Gray -NoNewline
Write-Host "MeowTonynoh" -ForegroundColor Cyan
Write-Host ""
Write-Host ("=" * 76) -ForegroundColor DarkCyan
Write-Host

# ---------------------------------------------------------------------------
#  Fast native helpers (C#) - used to speed up the scanning massively
# ---------------------------------------------------------------------------
if (-not ('MeowFast' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;

public class MeowPatternSet
{
    private string[] pats;
    private string[] anchors;
    private int[] offs;
    private bool[] wild;

    public MeowPatternSet(string[] patterns)
    {
        int n = patterns.Length;
        pats = patterns;
        anchors = new string[n];
        offs = new int[n];
        wild = new bool[n];
        for (int i = 0; i < n; i++)
        {
            string p = patterns[i];
            int bestStart = 0, bestLen = 0, curStart = 0;
            for (int k = 0; k <= p.Length; k++)
            {
                if (k == p.Length || p[k] == '.')
                {
                    int len = k - curStart;
                    if (len > bestLen) { bestLen = len; bestStart = curStart; }
                    curStart = k + 1;
                }
            }
            anchors[i] = p.Substring(bestStart, bestLen);
            offs[i] = bestStart;
            wild[i] = p.IndexOf('.') >= 0;
        }
    }

    private static bool IsLetter(char c)
    {
        return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
    }

    // Same semantics as the old regex: (?<![A-Za-z])(pattern)(?![A-Za-z]) where '.' is a wildcard
    public string[] Scan(string text)
    {
        Dictionary<string, bool> seen = new Dictionary<string, bool>(StringComparer.Ordinal);
        for (int i = 0; i < pats.Length; i++)
        {
            string a = anchors[i];
            string p = pats[i];
            int plen = p.Length;
            if (a.Length == 0 || text.Length < plen) continue;
            int from = 0;
            while (from <= text.Length - a.Length)
            {
                int pos = text.IndexOf(a, from, StringComparison.Ordinal);
                if (pos < 0) break;
                from = pos + 1;
                int start = pos - offs[i];
                if (start < 0 || start + plen > text.Length) continue;
                bool ok = true;
                for (int k = 0; k < plen; k++)
                {
                    char pc = p[k];
                    char tc = text[start + k];
                    if (pc == '.') { if (tc == '\n') { ok = false; break; } }
                    else if (pc != tc) { ok = false; break; }
                }
                if (!ok) continue;
                if (start > 0 && IsLetter(text[start - 1])) continue;
                int end = start + plen;
                if (end < text.Length && IsLetter(text[end])) continue;
                seen[text.Substring(start, plen)] = true;
                if (!wild[i]) break;
            }
        }
        string[] res = new string[seen.Count];
        seen.Keys.CopyTo(res, 0);
        return res;
    }
}

public static class MeowFast
{
    public static string[] FindAll(string text, string[] needles)
    {
        List<string> res = new List<string>();
        for (int i = 0; i < needles.Length; i++)
        {
            if (text.IndexOf(needles[i], StringComparison.Ordinal) >= 0) res.Add(needles[i]);
        }
        return res.ToArray();
    }

    public static bool HasByte(byte[] data, byte value)
    {
        return Array.IndexOf(data, value) >= 0;
    }

    public static byte[] ReadAll(Stream s)
    {
        MemoryStream ms = new MemoryStream();
        s.CopyTo(ms);
        return ms.ToArray();
    }
}
"@
}

# ---------------------------------------------------------------------------
#  hsperfdata parser - finds what Minecraft / JVM is really loading
# ---------------------------------------------------------------------------
function Get-HsPerfInfo {
    param([int]$ProcessId)

    $dirs = @()
    foreach ($base in @($env:TEMP, [System.IO.Path]::GetTempPath())) {
        if ($base -and (Test-Path -LiteralPath $base)) {
            $dirs += @(Get-ChildItem -LiteralPath $base -Directory -Filter "hsperfdata_*" -ErrorAction SilentlyContinue)
        }
    }

    foreach ($d in $dirs) {
        $f = Join-Path $d.FullName ([string]$ProcessId)
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            $fs = [System.IO.File]::Open($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            $bytes = [MeowFast]::ReadAll($fs)
            $fs.Close()
            $txt = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)

            $jc = [regex]::Match($txt, 'sun\.rt\.javaCommand\x00+([\x20-\x7E]+)')
            $va = [regex]::Match($txt, 'java\.rt\.vmArgs\x00+([\x20-\x7E]+)')

            return [PSCustomObject]@{
                File        = $f
                JavaCommand = if ($jc.Success) { $jc.Groups[1].Value.Trim() } else { $null }
                VmArgs      = if ($va.Success) { $va.Groups[1].Value.Trim() } else { $null }
            }
        } catch { }
    }
    return $null
}

function Get-JavaProcesses {
    return @(Get-CimInstance Win32_Process -Filter "name = 'javaw.exe' OR name = 'java.exe'" -ErrorAction SilentlyContinue)
}

function Get-MinecraftInstances {
    $found = @()
    foreach ($p in $script:javaProcs) {
        $perf    = Get-HsPerfInfo -ProcessId $p.ProcessId
        $gameDir = $null
        $source  = $null

        if ($perf -and $perf.JavaCommand) {
            $m = [regex]::Match($perf.JavaCommand, '--gameDir\s+(.+?)(?=\s+--[A-Za-z]|\s*$)')
            if ($m.Success) { $gameDir = $m.Groups[1].Value.Trim().Trim('"'); $source = "hsperfdata" }
        }
        if (-not $gameDir -and $p.CommandLine) {
            $m = [regex]::Match($p.CommandLine, '--gameDir\s+(?:"([^"]+)"|(\S+))')
            if ($m.Success) {
                $gameDir = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
                $source  = "process command line"
            }
        }
        if (-not $gameDir) { continue }

        $mods = Join-Path $gameDir "mods"
        $found += [PSCustomObject]@{
            ProcessId = $p.ProcessId
            Name      = $p.Name
            GameDir   = $gameDir
            ModsPath  = $mods
            Exists    = (Test-Path -LiteralPath $mods -PathType Container)
            Source    = $source
        }
    }
    return $found
}

$script:javaProcs = @(Get-JavaProcesses)
$mcInstances      = @(Get-MinecraftInstances)

# ---------------------------------------------------------------------------
#  Mods folder selection
# ---------------------------------------------------------------------------
if ($mcInstances.Count -gt 0) {
    Write-Host "Minecraft detected (hsperfdata):" -ForegroundColor Green
    foreach ($mi in $mcInstances) {
        Write-Host "  PID $($mi.ProcessId) ($($mi.Name)) -> " -ForegroundColor Gray -NoNewline
        Write-Host $mi.ModsPath -ForegroundColor White -NoNewline
        Write-Host "  [$($mi.Source)]" -ForegroundColor DarkGray
    }
    Write-Host
}

Write-Host "Enter path to the mods folder: " -NoNewline
Write-Host "(press Enter to auto-detect from the running Minecraft)" -ForegroundColor DarkGray
$modsPath = Read-Host "PATH"
Write-Host

if ([string]::IsNullOrWhiteSpace($modsPath)) {
    $usable = @($mcInstances | Where-Object { $_.Exists })
    if ($usable.Count -gt 1) {
        Write-Host "Multiple Minecraft instances found:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $usable.Count; $i++) {
            Write-Host "  [$($i + 1)] PID $($usable[$i].ProcessId) -> $($usable[$i].ModsPath)" -ForegroundColor Gray
        }
        $choice = Read-Host "Select instance (number)"
        $n = 0
        if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $usable.Count) {
            $modsPath = $usable[$n - 1].ModsPath
        } else {
            $modsPath = $usable[0].ModsPath
        }
        Write-Host "Continuing with " -NoNewline
        Write-Host $modsPath -ForegroundColor White -NoNewline
        Write-Host "  (auto-detected from the running JVM)" -ForegroundColor DarkGray
        Write-Host
    }
    elseif ($usable.Count -eq 1) {
        $modsPath = $usable[0].ModsPath
        Write-Host "Continuing with " -NoNewline
        Write-Host $modsPath -ForegroundColor White -NoNewline
        Write-Host "  (auto-detected from the running JVM, PID $($usable[0].ProcessId))" -ForegroundColor DarkGray
        Write-Host
    }
    else {
        $modsPath = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"
        if ($script:javaProcs.Count -gt 0) {
            Write-Host "Could not read the mods folder from the running JVM (hsperfdata unavailable or -XX:-UsePerfData used)." -ForegroundColor DarkYellow
        }
        Write-Host "Continuing with " -NoNewline
        Write-Host $modsPath -ForegroundColor White
        Write-Host
    }
}

if (-not (Test-Path $modsPath -PathType Container)) {
    Write-Host "❌ Invalid Path!" -ForegroundColor Red
    Write-Host "The directory does not exist or is not accessible." -ForegroundColor Yellow
    Write-Host
    Write-Host "Tried to access: $modsPath" -ForegroundColor Gray
    Write-Host
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "📁 Scanning directory: $modsPath" -ForegroundColor Green
Write-Host

$mcProcess = Get-Process javaw -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $mcProcess) {
    $mcProcess = Get-Process java -ErrorAction SilentlyContinue | Select-Object -First 1
}

if ($mcProcess) {
    try {
        $startTime = $mcProcess.StartTime
        $uptime = (Get-Date) - $startTime
        Write-Host "🕒 { Minecraft Uptime }" -ForegroundColor DarkCyan
        Write-Host "   $($mcProcess.Name) PID $($mcProcess.Id) started at $startTime" -ForegroundColor Gray
        Write-Host "   Running for: $($uptime.Hours)h $($uptime.Minutes)m $($uptime.Seconds)s" -ForegroundColor Gray
        Write-Host ""
    } catch { }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Verified Modrinth mods with this many downloads (or fewer) are flagged as possible "Modrinth method"
$lowDownloadThreshold = 1500

$suspiciousPatterns = @(
    "AimAssist", "AnchorTweaks", "AutoAnchor", "AutoCrystal", "AutoDoubleHand", "JDWP.VirtualMachine.AllModules",
    "AutoHitCrystal", "AutoPot", "AutoTotem", "AutoArmor", "InventoryTotem",
    "LegitTotem", "PingSpoof", "SelfDestruct",
    "ShieldBreaker", "TriggerBot", "AxeSpam", "WebMacro",
    "FastPlace", "WalskyOptimizer", "WalksyOptimizer", "walsky.optimizer",
    "WalksyCrystalOptimizerMod", "Donut", "Replace Mod",
    "ShieldDisabler", "SilentAim", "Totem Hit", "Wtap", "FakeLag", "dev.virel",
    "BlockESP", "dev.krypton", "dev/krypton", "skid.krypton", "skid/krypton",  "AntiMissClick",
    "LagReach", "PopSwitch", "SprintReset", "ChestSteal", "AntiBot",
    "ElytraSwap", "FastXP", "FastExp", "Refill",  "AirAnchor",
    "jnativehook", "FakeInv", "HoverTotem", "AutoClicker", "AutoFirework",
    "PackSpoof", "Antiknockback", "catlean", 
    "AuthBypass", "Asteria", "Prestige", "AutoEat", "AutoMine",
    "MaceSwap",  "Macro198", "StunSlam", "SafeAnchor", "DoubleAnchor", "AutoTPA", "BaseFinder", "Xenon", "gypsy",
    "AutoPotRefill", "WalksyOptimizer", "KeyPearl", "AimAssist", "AutoNethPot", "AutoDtap",
    "TriggerBot", "AutoWeb", "AnchorAction",
    
    "org.chainlibs.module.impl.modules.Crystal.Y",
    "org.chainlibs.module.impl.modules.Crystal.bF",
    "org.chainlibs.module.impl.modules.Crystal.bM",
    "org.chainlibs.module.impl.modules.Crystal.bY",
    "org.chainlibs.module.impl.modules.Crystal.bq",
    "org.chainlibs.module.impl.modules.Crystal.cv",
    "org.chainlibs.module.impl.modules.Crystal.o",
    "org.chainlibs.module.impl.modules.Blatant.I",
    "org.chainlibs.module.impl.modules.Blatant.bR",
    "org.chainlibs.module.impl.modules.Blatant.bx",
    "org.chainlibs.module.impl.modules.Blatant.cj",
    "org.chainlibs.module.impl.modules.Blatant.dk",
    "imgui.gl3", "imgui.glfw",
    "BowAim", "Criticals", "Fakenick", "FakeItem",
    "invsee", "ItemExploit", "Hellion", "hellion",
    "LicenseCheckMixin", "ClientPlayerInteractionManagerAccessor",
    "ClientPlayerEntityMixim", "dev.gambleclient", "obfuscatedAuth",
    "phantom-refmap.json", "xyz.greaj",
    "じ.class", "ふ.class", "ぶ.class", "ぷ.class", "た.class",
    "ね.class", "そ.class", "な.class", "ど.class", "ぐ.class",
    "ず.class", "で.class", "つ.class", "べ.class", "せ.class",
    "と.class", "み.class", "び.class", "す.class", "の.class"
)

$cheatStrings = @(
    "AutoCrystal", "autocrystal", "auto crystal", "cw crystal", "JDWP.VirtualMachine.AllModules",
    "dontPlaceCrystal", "dontBreakCrystal", "dev.virel",
    "AutoHitCrystal", "autohitcrystal", "canPlaceCrystalServer", "healPotSlot",
    "ＡｕｔｏＣｒｙｓｔａｌ", "Ａｕｔｏ Ｃｒｙｓｔａｌ",
    "ＡｕｔｏＨｉｔＣｒｙｓｔａｌ",
    "AutoAnchor", "autoanchor", "auto anchor", "DoubleAnchor",
     "HasAnchor", "anchortweaks", "anchor macro", "safe anchor", "safeanchor",
    "SafeAnchor", "AirAnchor",
    "ＡｕｔｏＡｎｃｈｏｒ", "Ａｕｔｏ Ａｎｃｈｏｒ",
    "ＤｏｕｂｌｅＡｎｃｈｏｒ", "Ｄｏｕｂｌｅ Ａｎｃｈｏｒ",
    "ＳａｆｅＡｎｃｈｏｒ", "Ｓａｆｅ Ａｎｃｈｏｒ",
    "Ａｎｃｈｏｒ Ｍａｃｒｏ", "anchorMacro",
    "AutoTotem", "autototem", "auto totem", "InventoryTotem",
    "inventorytotem", "HoverTotem", "hover totem", "legittotem",
    "ＡｕｔｏＴｏｔｅｍ", "Ａｕｔｏ Ｔｏｔｅｍ",
    "ＨｏｖｅｒＴｏｔｅｍ", "Ｈｏｖｅｒ Ｔｏｔｅｍ",
    "ＩｎｖｅｎｔｏｒｙＴｏｔｅｍ", "Ａｕｔｏ Ｉｎｖｅｎｔｏｒｙ Ｔｏｔｅｍ",
    "Ａｕｔｏ Ｔｏｔｅｍ Ｈｉｔ",
    "AutoPot", "autopot", "auto pot", "speedPotSlot", "strengthPotSlot",
    "AutoArmor", "autoarmor", "auto armor",
    "ＡｕｔｏＰｏｔ", "Ａｕｔｏ Ｐｏｔ",
    "Ａｕｔｏ Ｐｏｔ Ｒｅｆｉｌｌ", "AutoPotRefill",
    "ＡｕｔｏＡｒｍｏｒ", "Ａｕｔｏ Ａｒｍｏｒ",
    "preventSwordBlockBreaking", "preventSwordBlockAttack",
    "ShieldDisabler", "ShieldBreaker",
    "ＳｈｉｅｌｄＤｉｓａｂｌｅｒ", "Ｓｈｉｅｌｄ Ｄｉｓａｂｌｅｒ",
    "Breaking shield with axe...",
    "AutoDoubleHand", "autodoublehand", "auto double hand",
    "ＡｕｔｏＤｏｕｂｌｅＨａｎｄ", "Ａｕｔｏ Ｄｏｕｂｌｅ Ｈａｎｄ",
    "AutoClicker",
    "ＡｕｔｏＣｌｉｃｋｅｒ",
    "Failed to switch to mace after axe!",
    "AutoMace", "MaceSwap", "SpearSwap",
    "ＡｕｔｏＭａｃｅ", "Ａｕｔｏ Ｍａｃｅ",
    "ＭａｃｅＳｗａｐ", "Ｍａｃｅ Ｓｗａｐ",
    "Ｓｐｅａｒ Ｓｗａｐ", "Ａｕｔｏｍａｔｉｃａｌｌｙ ａｘｅ ａｎｄ ｍａｃｅ ｓｈｉｅｌｄｅｄ ｐｌａｙｅｒｓ",
    "Ｓｔｕｎ Ｓｌａｍ", "StunSlam",
    "Donut", "JumpReset", "axespam", "axe spam",
    
    "findKnockbackSword", "attackRegisteredThisClick",
    "AimAssist", "aimassist", "aim assist",
    "triggerbot", "trigger bot",
    "ＡｉｍＡｓｓｉｓｔ", "Ａｉｍ Ａｓｓｉｓｔ",
    "ＴｒｉｇｇｅｒＢｏｔ", "Ｔｒｉｇｇｅｒ Ｂｏｔ",
    "Silent Rotations", "SilentRotations",
    "Ｓｉｌｅｎｔ Ｒｏｔａｔｉｏｎｓ",
    "FakeInv", "swapBackToOriginalSlot",
    "FakeLag", "pingspoof", "ping spoof",
    "ＦａｋｅＬａｇ", "Ｆａｋｅ Ｌａｇ",
    "fakePunch", "Fake Punch",
    "Ｆａｋｅ Ｐｕｎｃｈ",
    "mace_swap", "quick_strike", "macro_198", "stun_slam",
    "safe_anchor", "double_anchor", "auto_pot_refill",
    "walksy_optimizer", "key_pearl", "aim_assist",
    "auto_neth_pot", "auto_dtap", "trigger_bot", "auto_web",
    "DOUBLE_ESCAPE", "DOUBLE_RIGHTCLICK_FIRST", "DOUBLE_RIGHTCLICK_SECOND",
    "POST_CYCLE_DELAY", "PLACE_OBI", "WAIT_OBI", "PLACE_CRYSTAL", "BREAK_CRYSTAL",
    "ROTATING_DOWN", "ROTATING_BACK", "REFILLING", "PLANTING", "BONEMEALING",
    "AnchorAction", "Places two anchors for massive damage",
    "REOFFHAND_TOTEM",
    "webmacro", "web macro",
    "AntiWeb", "AutoWeb",
    "Ａｎｔｉ Ｗｅｂ", "ＡｕｔｏＷｅｂ",
    "Ｐｌａｃｅｓ Ｗｅｂｓ Ｏｎ Ｅｎｅｍｉｅｓ",
    "lvstrng", "dqrkis", "selfdestruct", "self destruct",
    "WalksyCrystalOptimizerMod", "WalksyOptimizer", "WalskyOptimizer",
    "Ｗａｌｋｓｙ Ｏｐｔｉｍｉｚｅｒ",
    "autoCrystalPlaceClock",
    "AutoFirework", "ElytraSwap", "FastXP", "FastExp", "NoJumpDelay",
    "ＥｌｙｔｒａＳｗａｐ", "Ｅｌｙｔｒａ Ｓｗａｐ",
    "PackSpoof", "Antiknockback", "catlean",
    "AuthBypass", "obfuscatedAuth", "LicenseCheckMixin",
    "BaseFinder", "invsee", "ItemExploit",
    "FreezePlayer",
    "Ｆｒｅｅｃａｍ", "Ｍｏｖｅ ｆｒｅｅｌｙ ｔｈｒｏｕｇｈ ｗａｌｌｓ",
    "Ｎｏ Ｃｌｉｐ", "Ｆｒｅｅｚｅ Ｐｌａｙｅｒ",
    "LWFH Crystal", "JDWP.VirtualMachine.AllModules",
    "ＬＷＦＨ Ｃｒｙｓｔａｌ",
    "KeyPearl", "LootYeeter",
    "ＫｅｙＰｅａｒｌ", "Ｋｅｙ Ｐｅａｒｌ",
    "Ｌｏｏｔ Ｙｅｅｔｅｒ",
    "FastPlace",
    "Ｆａｓｔ Ｐｌａｃｅ", "Ｐｌａｃｅ ｂｌｏｃｋｓ ｆａｓｔｅｒ",
    "AutoBreach",
    "Ａｕｔｏ Ｂｒｅａｃｈ",
    "setBlockBreakingCooldown", "getBlockBreakingCooldown", "blockBreakingCooldown",
    "onBlockBreaking", "setItemUseCooldown",
    "invokeDoAttack", "invokeDoItemUse", "invokeOnMouseButton",
    "onPushOutOfBlocks", "onIsGlowing",
    "Automatically switches to sword when hitting with totem",
    "arrayOfString", "POT_CHEATS",
    "Dqrkis Client", "Entity.isGlowing",
    "Activate Key", "Ａｃｔｉｖａｔｅ Ｋｅｙ",
    "Click Simulation", "Ｃｌｉｃｋ Ｓｉｍｕｌａｔｉｏｎ",
    "On RMB", "Ｏｎ ＲＭＢ",
    "No Count Glitch", "Ｎｏ Ｃｏｕｎｔ Ｇｌｉｔｃｈ",
    "No Bounce", "NoBounce", "Ｎｏ Ｂｏｕｎｃｅ", "ＮｏＢｏｕｎｃｅ",
    "Ｒｅｍｏｖｅｓ ｔｈｅ ｃｒｙｓｔａｌ ｂｏｕｎｃｅ ａｎｉｍａｔｉｏｎ",
    "Place Delay", "Ｐｌａｃｅ Ｄｅｌａｙ",
    "Break Delay", "Ｂｒｅａｋ Ｄｅｌａｙ",
     "Ｆａｓｔ Ｍｏｄｅ",
    "Place Chance", "Ｐｌａｃｅ Ｃｈａｎｃｅ",
    "Break Chance", "Ｂｒｅａｋ Ｃｈａｎｃｅ",
    "Stop On Kill", "Ｓｔｏｐ Ｏｎ Ｋｉｌｌ",
    "Ｄａｍａｇｅ Ｔｉｃｋ", "damagetick",
    "Anti Weakness", "Ａｎｔｉ Ｗｅａｋｎｅｓｓ",
    "Particle Chance", "Ｐａｒｔｉｃｌｅ Ｃｈａｎｃｅ",
    "Trigger Key", "Ｔｒｉｇｇｅｒ Ｋｅｙ",
    "Switch Delay", "Ｓｗｉｔｃｈ Ｄｅｌａｙ",
    "Totem Slot", "Ｔｏｔｅｍ Ｓｌｏｔ",
    "Silent Rotations", "Ｓｉｌｅｎｔ Ｒｏｔａｔｉｏｎｓ",
    "Smooth Rotations", "Ｓｍｏｏｔｈ Ｒｏｔａｔｉｏｎｓ",
    "Rotation Speed", "Ｒｏｔａｔｉｏｎ Ｓｐｅｅｄ",
    "Use Easing", "Ｕｓｅ Ｅａｓｉｎｇ",
    "Easing Strength", "Ｅａｓｉｎｇ Ｓｔｒｅｎｇｔｈ",
    "While Use", "Ｗｈｉｌｅ Ｕｓｅ",
    "Stop on Kill", "Ｓｔｏｐ ｏｎ Ｋｉｌｌ",
    "Click Simulation", "Ｃｌｉｃｋ Ｓｉｍｕｌａｔｉｏｎ",
    "Glowstone Delay", "Ｇｌｏｗｓｔｏｎｅ Ｄｅｌａｙ",
    "Glowstone Chance", "Ｇｌｏｗｓｔｏｎｅ Ｃｈａｎｃｅ",
    "Explode Delay", "Ｅｘｐｌｏｄｅ Ｄｅｌａｙ",
    "Explode Chance", "Ｅｘｐｌｏｄｅ Ｃｈａｎｃｅ",
    "Explode Slot", "Ｅｘｐｌｏｄｅ Ｓｌｏｔ",
    "Only Charge", "Ｏｎｌｙ Ｃｈａｒｇｅ",
    "Anchor Macro", "Ａｎｃｈｏｒ Ｍａｃｒｏ",
    "Reach Distance", "Ｒｅａｃｈ Ｄｉｓｔａｎｃｅ",
    "Min Height", "Ｍｉｎ Ｈｅｉｇｈｔ",
    "Min Fall Speed", "Ｍｉｎ Ｆａｌｌ Ｓｐｅｅｄ",
    "Attack Delay", "Ａｔｔａｃｋ Ｄｅｌａｙ",
    "Breach Delay", "Ｂｒｅａｃｈ Ｄｅｌａｙ",
    "Require Elytra", "Ｒｅｑｕｉｒｅ Ｅｌｙｔｒａ",
    "Auto Switch Back", "Ａｕｔｏ Ｓｗｉｔｃｈ Ｂａｃｋ",
    "Check Line of Sight", "Ｃｈｅｃｋ Ｌｉｎｅ ｏｆ Ｓｉｇｈｔ",
    "Only When Falling", "Ｏｎｌｙ Ｗｈｅｎ Ｆａｌｌｉｎｇ",
    "Require Crit", "Ｒｅｑｕｉｒｅ Ｃｒｉｔ",
    "Show Status Display", "Ｓｈｏｗ Ｓｔａｔｕｓ Ｄｉｓｐｌａｙ",
    "Stop On Crystal", "Ｓｔｏｐ Ｏｎ Ｃｒｙｓｔａｌ",
    "Check Shield", "Ｃｈｅｃｋ Ｓｈｉｅｌｄ",
    "On Pop", "Ｏｎ Ｐｏｐ",
    "Predict Damage", "Ｐｒｅｄｉｃｔ Ｄａｍａｇｅ",
    "On Ground", "Ｏｎ Ｇｒｏｕｎｄ",
    "Check Players", "Ｃｈｅｃｋ Ｐｌａｙｅｒｓ",
    "Predict Crystals", "Ｐｒｅｄｉｃｔ Ｃｒｙｓｔａｌｓ",
    "Check Aim", "Ｃｈｅｃｋ Ａｉｍ",
    "Check Items", "Ｃｈｅｃｋ Ｉｔｅｍｓ",
    "Activates Above", "Ａｃｔｉｖａｔｅｓ Ａｂｏｖｅ",
    "Blatant", "Ｂｌａｔａｎｔ",
    "Force Totem", "Ｆｏｒｃｅ Ｔｏｔｅｍ",
    "Stay Open For", "Ｓｔａｙ Ｏｐｅｎ Ｆｏｒ",
    "Auto Inventory Totem", "Ａｕｔｏ Ｉｎｖｅｎｔｏｒｙ Ｔｏｔｅｍ",
    "Only On Pop", "Ｏｎｌｙ Ｏｎ Ｐｏｐ",
    "Vertical Speed", "Ｖｅｒｔｉｃａｌ Ｓｐｅｅｄ",
    "Hover Totem", "Ｈｏｖｅｒ Ｔｏｔｅｍ",
    "Swap Speed", "Ｓｗａｐ Ｓｐｅｅｄ",
    "Strict One-Tick", "Ｓｔｒｉｃｔ Ｏｎｅ－Ｔｉｃｋ",
    "Mace Priority", "Ｍａｃｅ Ｐｒｉｏｒｉｔｙ",
    "Min Totems", "Ｍｉｎ Ｔｏｔｅｍｓ",
    "Min Pearls", "Ｍｉｎ Ｐｅａｒｌｓ",
    "Totem First", "Ｔｏｔｅｍ Ｆｉｒｓｔ",
    "Drop Interval", "Ｄｒｏｐ Ｉｎｔｅｒｖａｌ",
    "Random Pattern", "Ｒａｎｄｏｍ Ｐａｔｔｅｒｎ",
    "Loot Yeeter", "Ｌｏｏｔ Ｙｅｅｔｅｒ",
    "Horizontal Aim Speed", "Ｈｏｒｉｚｏｎｔａｌ Ａｉｍ Ｓｐｅｅｄ",
    "Vertical Aim Speed", "Ｖｅｒｔｉｃａｌ Ａｉｍ Ｓｐｅｅｄ",
    "Include Head", "Ｉｎｃｌｕｄｅ Ｈｅａｄ",
    "Web Delay", "Ｗｅｂ Ｄｅｌａｙ",
    "Holding Web", "Ｈｏｌｄｉｎｇ Ｗｅｂ",
    "Not When Affects Player", "Ｎｏｔ Ｗｈｅｎ Ａｆｆｅｃｔｓ Ｐｌａｙｅｒ",
    "Hit Delay", "Ｈｉｔ Ｄｅｌａｙ",
    "Ｓｗｉｔｃｈ Ｂａｃｋ",
    "Require Hold Axe", "Ｒｅｑｕｉｒｅ Ｈｏｌｄ Ａｘｅ",
    "Fake Punch", "Ｆａｋｅ Ｐｕｎｃｈ",
    "placeInterval", "breakInterval", "stopOnKill",
    "activateOnRightClick", "holdCrystal",
    "ｐｌａｃｅＩｎｔｅｒｖａｌ", "ｂｒｅａｋＩｎｔｅｒｖａｌ",
    "ｓｔｏｐＯｎＫｉｌｌ", "ａｃｔｉｖａｔｅＯｎＲｉｇｈｔＣｌｉｃｋ",
    "ｄａｍａｇｅｔｉｃｋ", "ｈｏｌｄＣｒｙｓｔａｌ",
    "ｆａｋｅＰｕｎｃｈ",
    "Ｒｅｆｉｌｌｓ ｙｏｕｒ ｈｏｔｂａｒ ｗｉｔｈ ｐｏｔｉｏｎｓ",
    "Ｋｅｐｓ ｙｏｕ ｓｐｒｉｎｔｉｎｇ ａｔ ａｌｌ ｔｉｍｅｓ",
    "Ｐｌａｃｅｓ ａｎｃｈｏｒ， ｃｈａｒｇｅｓ ｉｔ， ｐｒｏｔｅｃｔｓ ｙｏｕ， ａｎｄ ｅｘｐｌｏｄｅｓ",
    "Ａｕｔｏ ｓｗａｐ ｔｏ ｓｐｅａｒ ｏｎ ａｔｔａｃｋ",
    "Macro Key", "Ａｕｔｏ Ｐｏｔ", "Ｍａｃｒｏ Ｋｅｙ",
    "KillAura", "ClickAura", "MultiAura", "ForceField", "LegitAura",
    "AimBot", "AutoAim", "SilentAim", "AimLock", "HeadSnap",
    "CrystalAura",
    "AnchorAura", "AnchorFill", "AnchorPlace",
    "BedAura", "AutoBed", "BedBomb", "BedPlace",
    "BowAimbot", "BowSpam", "AutoBow",
    "AutoCrit", "CritBypass", "AlwaysCrit", "CriticalHit",
    "ReachHack", "ExtendReach", "LongReach", "HitboxExpand",
    "AntiKB", "NoKnockback", "GrimVelocity", "GrimDisabler", "VelocitySpoof", "KBReduce",
    "OffhandTotem", "TotemSwitch",
    "AutoWeapon", "AutoSword", "AutoCity", "Burrow", "SelfTrap",
    "HoleFiller", "AntiSurround", "AntiBurrow",
    "WTap", "TargetStrafe", "AutoGap", "AutoPearl",
    "FlyHack", "CreativeFlight", "BoatFly", "PacketFly", "AirJump",
    "SpeedHack", "BHop", "BunnyHop",
    "AntiFall", "NoFallDamage", "SafeFall",
    "StepHack", "FastClimb", "AutoStep", "HighStep",
    "WaterWalk", "LiquidWalk", "LavaWalk",
    "NoSlow", "NoSlowdown", "NoWeb", "NoSoulSand",
    "WallHack",
    "ElytraSpeed", "InstantElytra",
    "ScaffoldWalk", "FastBridge", "BuildHelper", "AutoBridge",
    "Nuker", "NukerLegit", "InstantBreak",
    "GhostHand", "NoSwing",
    "PlaceAssist", "AirPlace", "AutoPlace", "InstantPlace",
    "PlayerESP", "MobESP", "ItemESP", "StorageESP", "ChestESP",
    "Tracers", "NameTagsHack",
    "XRayHack", "OreFinder", "CaveFinder", "OreESP",
    "NewChunks", "ChunkBorders", "TunnelFinder",
    "TargetHUD", "ReachDisplay",
    "DoubleClicker", "JitterClick", "ButterflyClick", "CPSBoost",
    "ChestStealer", "InvManager", "InvMovebypass",
    "AutoSprint", "AntiAFK", "AutoRespawn",
    "PopSwitch",
    "FakeLatency", "FakePing", "SpoofRotation", "PositionSpoof",
    "GameSpeed", "SpeedTimer",
     "GrimBypass", "VulcanBypass", "MatrixBypass",
    "AACBypass", "VerusDisabler", "IntaveBypass", "WatchdogBypass",
    "PacketMine", "PacketWalk", "PacketSneak", "PacketCancel", "PacketDupe", "PacketSpam",
    "SelfDestruct", "HideClient",
    "SessionStealer", "TokenLogger", "TokenGrabber", "DiscordToken",
    "RemoteAccess", "ReverseShell", "C2Server", "Backdoor", "KeyLogger",
    "StashFinder", "TrailFinder",
    "imgui.binding",
    "JNativeHook", "GlobalScreen", "NativeKeyListener",
    "client-refmap.json", "cheat-refmap.json",
    "aHR0cDovL2FwaS5ub3ZhY2xpZW50LmxvbC93ZWJob29rLnR4dA==",
    "meteordevelopment", "cc/novoline",
    "com/alan/clients", "club/maxstats", "wtf/moonlight",
    "me/zeroeightsix/kami", "net/ccbluex", "today/opai",
    "net/minecraft/injection", "org/chainlibs/module/impl/modules",
    "xyz/greaj", "com/cheatbreaker", "com/moonsworth",
    "doomsdayclient", "DoomsdayClient", "doomsday.jar",
    "novaclient", "api.novaclient.lol",
    "WalksyOptimizer", "LWFH Crystal",
    "vape.gg", "vapeclient", "VapeClient", "VapeLite",
    "intent.store", "IntentClient",
    "rise.today", "riseclient.com",
    "meteor-client", "meteorclient", "meteordevelopment.meteorclient",
    "liquidbounce", "fdp-client", "net.ccbluex",
    "novoware", "novoclient",
    "aristois", "impactclient", "azura",
    "pandaware", "skilled", "moonClient", "astolfo",
    "futureClient", "konas", "rusherhack", "exhibition",
    "dev.krypton", "dev/krypton", "skid.krypton", "skid/krypton",
     "VirginClient", "virgin client",
    "catlean", "CatleanClient", "catlean client",
     "ArgonClient", "argon client",
    "Asteria", "AsteriaClient", "asteria client",
    "Prestige", "PrestigeClient", "prestige client", "prestigeclient.vip",
    "gypsy", "GypsyClient", "gypsy client",
    "Xenon", "XenonClient", "xenon client",
     "GrimClient", "grim client",
    "phantom-refmap.json",
     "dqrkis.xyz", "Dqrkis Client"
)

# ---- Precomputed lookup structures (same detections, much faster matching) ----
[string[]]$patternsAll   = @($suspiciousPatterns | Select-Object -Unique)
[string[]]$patternsAscii = @($patternsAll | Where-Object { $_ -cnotmatch '[^\x00-\x7F]' })
$patSetAll   = [MeowPatternSet]::new($patternsAll)
$patSetAscii = [MeowPatternSet]::new($patternsAscii)

$cheatStringSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($s in $cheatStrings) { [void]$cheatStringSet.Add($s) }

[string[]]$cheatAscii    = @($cheatStringSet | Where-Object { $_ -cnotmatch '[^\x00-\x7F]' })
[string[]]$cheatNonAscii = @($cheatStringSet | Where-Object { $_ -cmatch '[^\x00-\x7F]' })
[string[]]$fwCheatPool   = @($cheatStrings | Where-Object { $_ -cmatch "[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]" })

$fullwidthRegex = [regex]::new(
    "[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]{2,}",
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)

$cheatObfuscators = @{
    "Skidfuscator"   = @("dev/skidfuscator", "Skidfuscator", "skidfuscator.dev")
    "Paramorphism"   = @("Paramorphism", "paramorphism-", "dev/paramorphism")
    "Radon"          = @("ItzSomebody/Radon", "me/itzsomebody/radon", "Radon Obfuscator")
    "Caesium"        = @("sim0n/Caesium", "Caesium Obfuscator", "dev/sim0n/caesium")
    "Bozar"          = @("vimasig/Bozar", "Bozar Obfuscator", "com/bozar")
    "Branchlock"     = @("Branchlock", "branchlock.dev")
    "Binscure"       = @("Binscure", "com/binscure")
    "SuperBlaubeere" = @("superblaubeere", "superblaubeere27")
    "Qprotect"       = @("Qprotect", "QProtect", "mdma.dev/qprotect")
    "Zelix"          = @("ZKMFLOW", "ZKM", "ZelixKlassMaster", "com/zelix")
    "Stringer"       = @("StringerJavaObfuscator", "com/licel/stringer")
    "JNIC"           = @("JNIC", "jnic.obf", "jnic-obfuscator")
    "Scuti"          = @("ScutiObf", "scuti.obf")
    "Smoke"          = @("SmokeObf", "smoke.obf")
}

$mavenPrefixes = @(
    "com_","org_","net_","io_","dev_","gs_","xyz_",
    "app_","me_","tv_","uk_","be_","fr_","de_"
)

$knownLegitModIds = @(
    "vmp-fabric","vmp","lithium","sodium","iris","fabric-api",
    "modmenu","ferrite-core","lazydfu","starlight","entityculling",
    "memoryleakfix","krypton","c2me-fabric","smoothboot-fabric",
    "immediatelyfast","noisium","threadtweak"
)

$scanCtx = @{
    PatSetAll        = $patSetAll
    PatSetAscii      = $patSetAscii
    CheatAscii       = $cheatAscii
    CheatNonAscii    = $cheatNonAscii
    FwPool           = $fwCheatPool
    FwRegex          = $fullwidthRegex
    CheatObfuscators = $cheatObfuscators
    MavenPrefixes    = $mavenPrefixes
    KnownLegit       = $knownLegitModIds
}

# ---------------------------------------------------------------------------
#  Hash / download source / online lookups
# ---------------------------------------------------------------------------
function Get-FileSHA1 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA1).Hash
}

function Get-DownloadSource {
    param([string]$Path)
    $zoneData = Get-Content -Raw -Stream Zone.Identifier $Path -ErrorAction SilentlyContinue
    if ($zoneData -match "HostUrl=(.+)") {
        $url = $matches[1].Trim()
        if ($url -match "mediafire\.com")                                        { return "MediaFire" }
        elseif ($url -match "discord\.com|discordapp\.com|cdn\.discordapp\.com") { return "Discord" }
        elseif ($url -match "dropbox\.com")                                      { return "Dropbox" }
        elseif ($url -match "drive\.google\.com")                                { return "Google Drive" }
        elseif ($url -match "mega\.nz|mega\.co\.nz")                             { return "MEGA" }
        elseif ($url -match "github\.com")                                       { return "GitHub" }
        elseif ($url -match "modrinth\.com")                                     { return "Modrinth" }
        elseif ($url -match "curseforge\.com")                                   { return "CurseForge" }
        elseif ($url -match "anydesk\.com")                                      { return "AnyDesk" }
        elseif ($url -match "doomsdayclient\.com")                               { return "DoomsdayClient" }
        elseif ($url -match "prestigeclient\.vip")                               { return "PrestigeClient" }
        elseif ($url -match "198macros\.com")                                    { return "198Macros" }
        elseif ($url -match "dqrkis\.xyz")                                       { return "Dqrkis" }
        else {
            if ($url -match "https?://(?:www\.)?([^/]+)") { return $matches[1] }
            return $url
        }
    }
    return $null
}

$modrinthUA = "MeowTonynoh-ModAnalyzer/2.0 (discord.gg/meowtools)"

# Single-file fallback (used only if the bulk endpoint fails)
function Query-Modrinth {
    param([string]$Hash)
    try {
        $versionInfo = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/version_file/$Hash" -Method Get -UseBasicParsing -UserAgent $modrinthUA -TimeoutSec 15 -ErrorAction Stop
        if ($versionInfo.project_id) {
            $projectInfo = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/project/$($versionInfo.project_id)" -Method Get -UseBasicParsing -UserAgent $modrinthUA -TimeoutSec 15 -ErrorAction Stop
            return @{ Name = $projectInfo.title; Slug = $projectInfo.slug; Downloads = [int64]$projectInfo.downloads }
        }
    } catch { }
    return @{ Name = ""; Slug = ""; Downloads = $null }
}

# Bulk lookup: 1 request for all hashes + 1 request per 50 projects (instead of 2 requests per mod)
# Returns hashtable  sha1(lowercase) -> @{ Name; Slug; Downloads }  or $null if the API failed
function Get-ModrinthBulk {
    param([string[]]$Hashes)

    $map = @{}
    if (-not $Hashes -or $Hashes.Count -eq 0) { return $map }

    try {
        $body = @{ hashes = @($Hashes); algorithm = "sha1" } | ConvertTo-Json -Compress
        $versions = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/version_files" -Method Post -Body $body -ContentType "application/json" -UseBasicParsing -UserAgent $modrinthUA -TimeoutSec 30 -ErrorAction Stop

        $hashToProject = @{}
        foreach ($prop in $versions.PSObject.Properties) {
            if ($prop.Value.project_id) { $hashToProject[$prop.Name.ToLower()] = $prop.Value.project_id }
        }

        $projectIds = @($hashToProject.Values | Select-Object -Unique)
        $projects = @{}
        for ($i = 0; $i -lt $projectIds.Count; $i += 50) {
            $chunk = @($projectIds[$i..([Math]::Min($i + 49, $projectIds.Count - 1))])
            $idsJson = '["' + ($chunk -join '","') + '"]'
            $uri = "https://api.modrinth.com/v2/projects?ids=" + [uri]::EscapeDataString($idsJson)
            $res = Invoke-RestMethod -Uri $uri -Method Get -UseBasicParsing -UserAgent $modrinthUA -TimeoutSec 30 -ErrorAction Stop
            foreach ($pr in @($res)) { $projects[$pr.id] = $pr }
        }

        foreach ($h in $hashToProject.Keys) {
            $pr = $projects[$hashToProject[$h]]
            if ($pr) {
                $map[$h] = @{ Name = $pr.title; Slug = $pr.slug; Downloads = [int64]$pr.downloads }
            }
        }
        return $map
    } catch {
        return $null
    }
}

function Query-Megabase {
    param([string]$Hash)
    try {
        $result = Invoke-RestMethod -Uri "https://megabase.vercel.app/api/query?hash=$Hash" -Method Get -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        if (-not $result.error) { return $result.data }
    } catch { }
    return $null
}

# ---------------------------------------------------------------------------
#  Deep scan (runs inside a runspace): patterns + strings + bypass + obfuscation
#  in ONE pass over each jar (each class is read and decoded only once)
# ---------------------------------------------------------------------------
$deepScanScript = {
    param([string]$FilePath, $ctx, [bool]$SkipDetect)

    $patSetAll        = $ctx.PatSetAll
    $patSetAscii      = $ctx.PatSetAscii
    $cheatAscii       = [string[]]$ctx.CheatAscii
    $cheatNonAscii    = [string[]]$ctx.CheatNonAscii
    $fwCheatPool      = [string[]]$ctx.FwPool
    $fwRegex          = $ctx.FwRegex
    $cheatObfuscators = $ctx.CheatObfuscators
    $mavenPrefixes    = $ctx.MavenPrefixes
    $knownLegitModIds = $ctx.KnownLegit

    $foundPatterns  = New-Object 'System.Collections.Generic.HashSet[string]'
    $foundStrings   = New-Object 'System.Collections.Generic.HashSet[string]'
    $foundFullwidth = New-Object 'System.Collections.Generic.HashSet[string]'
    $bypassFlags    = New-Object 'System.Collections.Generic.List[string]'
    $obfFlags       = New-Object 'System.Collections.Generic.List[string]'
    $innerZips      = New-Object 'System.Collections.Generic.List[object]'
    $ic             = [System.StringComparison]::OrdinalIgnoreCase

    $testSuspiciousJarName = {
        param([string]$JarName)
        $base = [System.IO.Path]::GetFileNameWithoutExtension($JarName)
        if ($base -match '\d') { return $false }
        foreach ($pfx in $mavenPrefixes) {
            if ($base.ToLower().StartsWith($pfx)) { return $false }
        }
        if ($base.Length -gt 20) { return $false }
        return $true
    }

    # obfuscation counters (outer jar only)
    $totalClass = 0; $numericCount = 0; $unicodeCount = 0; $fullwidthCount = 0; $japaneseCount = 0
    $singleLetterCount = 0; $twoLetterCount = 0; $gibberishCount = 0; $noVowelCount = 0
    $confusionCount = 0; $singleCharPkg = 0
    $contentSample = New-Object System.Text.StringBuilder
    $sampleSize = 0

    # bypass counters (outer + nested)
    $runtimeExecFound = $false; $httpDownloadFound = $false; $httpExfilFound = $false
    $obfuscatedCount = 0; $numericClassCount = 0; $unicodeClassCount = 0; $totalClassCount = 0
    $outerModId = ""
    $archive = $null

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        $outerEntries = @($archive.Entries)
        $outerCount   = $outerEntries.Count

        if (-not $SkipDetect) {
            foreach ($e in $outerEntries) {
                foreach ($v in $patSetAll.Scan($e.FullName)) { [void]$foundPatterns.Add($v) }
            }
        }

        $nestedJars = @($outerEntries | Where-Object { $_.FullName -match "^META-INF/jars/.+\.jar$" })
        $allEntries = New-Object 'System.Collections.Generic.List[object]'
        foreach ($e in $outerEntries) { $allEntries.Add($e) }

        foreach ($nj in $nestedJars) {
            try {
                $ns = $nj.Open()
                $nbytes = [MeowFast]::ReadAll($ns); $ns.Close()
                $ms = New-Object System.IO.MemoryStream(,$nbytes)
                $iz = [System.IO.Compression.ZipArchive]::new($ms, [System.IO.Compression.ZipArchiveMode]::Read)
                $innerZips.Add($iz)
                foreach ($ie in $iz.Entries) { $allEntries.Add($ie) }
            } catch { }
        }

        $outerClassCount = @($outerEntries | Where-Object { $_.FullName -match "\.class$" }).Count

        if (-not $SkipDetect) {
            foreach ($nj in $nestedJars) {
                $njBase = [System.IO.Path]::GetFileName($nj.FullName)
                if (& $testSuspiciousJarName $njBase) {
                    $bypassFlags.Add("Suspicious nested JAR — no version, unknown dependency: $njBase")
                }
            }
            if ($nestedJars.Count -eq 1 -and $outerClassCount -lt 3) {
                $njName = [System.IO.Path]::GetFileName(($nestedJars | Select-Object -First 1).FullName)
                $bypassFlags.Add("Hollow shell — only $outerClassCount own class(es), wraps: $njName")
            }

            $fmje = $outerEntries | Where-Object { $_.FullName -eq "fabric.mod.json" } | Select-Object -First 1
            if ($fmje) {
                try {
                    $s = $fmje.Open()
                    $r = New-Object System.IO.StreamReader($s)
                    $t = $r.ReadToEnd(); $r.Close(); $s.Close()
                    if ($t -match '"id"\s*:\s*"([^"]+)"') { $outerModId = $matches[1] }
                } catch { }
            }
        }

        $i = -1
        foreach ($entry in $allEntries) {
            $i++
            $isOuter = ($i -lt $outerCount)
            $name    = $entry.FullName
            $isClass = ($name -match "\.class$")
            $isTarget = $isClass -or ($name -match '\.json$') -or ($name -match 'MANIFEST\.MF')

            if ($isClass) {
                # ---- bypass name stats (outer + nested) ----
                $totalClassCount++
                $className = [System.IO.Path]::GetFileNameWithoutExtension(($name -split "/")[-1])

                if ($className -match "^\d+$") { $numericClassCount++ }
                if ($className -match "[^\x00-\x7F]") { $unicodeClassCount++ }

                $segs = ($name -replace "\.class$","") -split "/"
                $consecutiveSingle = 0
                $maxConsecutive    = 0
                foreach ($seg in $segs) {
                    if ($seg.Length -eq 1) {
                        $consecutiveSingle++
                        if ($consecutiveSingle -gt $maxConsecutive) { $maxConsecutive = $consecutiveSingle }
                    } else {
                        $consecutiveSingle = 0
                    }
                }
                if ($maxConsecutive -ge 3) { $obfuscatedCount++ }

                # ---- obfuscation name stats (outer only) ----
                if ($isOuter) {
                    $totalClass++
                    if ($className -match "^\d+$")                          { $numericCount++ }
                    if ($className -match "[^\x00-\x7F]")                   { $unicodeCount++ }
                    if ($className -match "[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]") { $fullwidthCount++ }
                    if ($className -match "[\u3040-\u309F\u30A0-\u30FF]")  { $japaneseCount++ }
                    if ($className -match "^[a-zA-Z]$")                     { $singleLetterCount++ }
                    if ($className -match "^[a-zA-Z]{2}$")                  { $twoLetterCount++ }
                    if ($className -match "^[Il1O0]+$" -or $className -match "^[_]+$") { $confusionCount++ }

                    if ($className.Length -ge 3 -and $className.Length -le 8 -and $className -match "^[a-zA-Z]+$") {
                        $vowels = [regex]::Matches($className, "[aeiouAEIOU]").Count
                        if ($vowels -eq 0) { $noVowelCount++ }
                        $hasCluster = $className -match "[bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ]{3,}"
                        if ($hasCluster -and ($vowels / $className.Length) -lt 0.3) { $gibberishCount++ }
                    }

                    $osegs = ($name -replace "\.class$", "") -split "/"
                    foreach ($seg in $osegs[0..($osegs.Count - 2)]) {
                        if ($seg.Length -eq 1) { $singleCharPkg++ }
                    }
                }
            }

            if (-not $isTarget) { continue }

            # ---- read + decode the entry ONCE ----
            $bytes = $null; $ascii = $null
            try {
                $st = $entry.Open()
                $bytes = [MeowFast]::ReadAll($st); $st.Close()
                $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
            } catch { continue }

            if (-not $SkipDetect) {
                foreach ($v in $patSetAscii.Scan($ascii)) { [void]$foundPatterns.Add($v) }
                foreach ($s2 in [MeowFast]::FindAll($ascii, $cheatAscii)) { [void]$foundStrings.Add($s2) }

                # fullwidth strings need 0xEF in the byte stream - skip the expensive UTF-8 work otherwise
                if ([MeowFast]::HasByte($bytes, [byte]0xEF)) {
                    $utf8 = [System.Text.Encoding]::UTF8.GetString($bytes)
                    foreach ($s2 in [MeowFast]::FindAll($utf8, $cheatNonAscii)) { [void]$foundStrings.Add($s2) }
                    foreach ($m in $fwRegex.Matches($utf8)) { [void]$foundFullwidth.Add($m.Value) }
                }
            }

            if ($isClass) {
                if (-not $SkipDetect) {
                    if (-not $runtimeExecFound) {
                        if ($ascii.IndexOf("java/lang/Runtime", $ic) -ge 0 -and
                            $ascii.IndexOf("getRuntime", $ic) -ge 0 -and
                            $ascii.IndexOf("exec", $ic) -ge 0) { $runtimeExecFound = $true }
                    }
                    if (-not $httpDownloadFound) {
                        if ($ascii.IndexOf("openConnection", $ic) -ge 0 -and
                            $ascii.IndexOf("HttpURLConnection", $ic) -ge 0 -and
                            $ascii.IndexOf("FileOutputStream", $ic) -ge 0) { $httpDownloadFound = $true }
                    }
                    if (-not $httpExfilFound) {
                        if ($ascii.IndexOf("openConnection", $ic) -ge 0 -and
                            $ascii.IndexOf("setDoOutput", $ic) -ge 0 -and
                            $ascii.IndexOf("getOutputStream", $ic) -ge 0 -and
                            $ascii.IndexOf("getProperty", $ic) -ge 0) { $httpExfilFound = $true }
                    }
                }

                if ($isOuter -and $sampleSize -lt 150000 -and $entry.Length -lt 100000 -and $entry.Length -gt 100) {
                    [void]$contentSample.Append($ascii)
                    $sampleSize += $ascii.Length
                }
            }
        }
    } catch { }

    foreach ($iz in $innerZips) { try { $iz.Dispose() } catch { } }
    if ($archive) { try { $archive.Dispose() } catch { } }

    # ---- resolve fullwidth hits against known fullwidth cheat strings ----
    $finalFullwidth = New-Object 'System.Collections.Generic.HashSet[string]'
    if (-not $SkipDetect) {
        $resolvedFullwidth = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($fw in @($foundFullwidth)) {
            if ($fw.Length -lt 3) { continue }
            $bestMatch = $null
            foreach ($cs in $fwCheatPool) {
                if ($cs.Contains($fw)) {
                    if ($null -eq $bestMatch -or $cs.Length -lt $bestMatch.Length) { $bestMatch = $cs }
                }
            }
            if ($null -ne $bestMatch) {
                [void]$resolvedFullwidth.Add($bestMatch)
            } elseif ($fw.Length -ge 6) {
                [void]$resolvedFullwidth.Add($fw)
            }
        }
        $resolved = @($resolvedFullwidth)
        foreach ($fw in $resolved) {
            $isRedundant = $false
            foreach ($other in $resolved) {
                if ($fw.Length -lt $other.Length -and $other.Contains($fw)) { $isRedundant = $true; break }
            }
            if (-not $isRedundant) { [void]$finalFullwidth.Add($fw) }
        }

        # ---- bypass verdicts ----
        $obfPct = if ($totalClassCount -ge 10) { [math]::Round(($obfuscatedCount   / $totalClassCount) * 100) } else { 0 }
        $numPct = if ($totalClassCount -ge 5)  { [math]::Round(($numericClassCount / $totalClassCount) * 100) } else { 0 }
        $uniPct = if ($totalClassCount -ge 5)  { [math]::Round(($unicodeClassCount / $totalClassCount) * 100) } else { 0 }

        if ($runtimeExecFound -and $obfPct -ge 25) {
            $bypassFlags.Add("Runtime.exec() in obfuscated code — can run arbitrary OS commands")
        }
        if ($httpDownloadFound) {
            $bypassFlags.Add("HTTP file download — fetches and writes files from a remote server at runtime")
        }
        if ($httpExfilFound) {
            $bypassFlags.Add("HTTP POST exfiltration — sends system data to an external server")
        }
        if ($totalClassCount -ge 10 -and $obfPct -ge 25) {
            $bypassFlags.Add("Heavy obfuscation — $obfPct% of classes use single-letter path segments (a/b/c style)")
        }
        if ($numPct -ge 20) {
            $bypassFlags.Add("Numeric class names — $numPct% of classes have numeric-only names (e.g. 1234.class)")
        }
        if ($uniPct -ge 10) {
            $bypassFlags.Add("Unicode class names — $uniPct% of classes use non-ASCII characters")
        }

        $dangerCount = @($bypassFlags | Where-Object {
            $_ -match "Runtime\.exec|HTTP file download|HTTP POST|Heavy obfuscation|Suspicious nested JAR"
        }).Count
        if ($outerModId -and ($knownLegitModIds -contains $outerModId) -and $dangerCount -gt 0) {
            $bypassFlags.Add("Fake mod identity — claims to be '$outerModId' but contains dangerous code")
        }
    }

    # ---- obfuscation verdicts ----
    if ($totalClass -ge 5) {
        $pct = { param($n) [math]::Round(($n / $totalClass) * 100) }

        $numPct   = & $pct $numericCount
        $uniPct   = & $pct $unicodeCount
        $fwPct    = & $pct $fullwidthCount
        $jpPct    = & $pct $japaneseCount
        $s1Pct    = & $pct $singleLetterCount
        $s2Pct    = & $pct $twoLetterCount
        $gibPct   = & $pct $gibberishCount
        $novPct   = & $pct $noVowelCount
        $confPct  = & $pct $confusionCount

        if ($numPct   -ge 20) { $obfFlags.Add("Numeric class names — $numPct% of classes have numeric-only names") }
        if ($uniPct   -ge 10) { $obfFlags.Add("Unicode class names — $uniPct% of classes use non-ASCII characters") }
        if ($fwPct    -gt  0) { $obfFlags.Add("Fullwidth Unicode class names — $fwPct% use ａｂｃ/ＡＢＣ/０１２ chars ($fullwidthCount classes)") }
        if ($jpPct    -gt  0) { $obfFlags.Add("Japanese obfuscation — $jpPct% use hiragana/katakana class names ($japaneseCount classes)") }
        if ($s1Pct    -ge 15) { $obfFlags.Add("Single-letter class names — $s1Pct% ($singleLetterCount classes)") }
        if ($s2Pct    -ge 20) { $obfFlags.Add("Two-letter class names — $s2Pct% ($twoLetterCount classes)") }
        if ($gibPct   -ge  5) { $obfFlags.Add("Gibberish class names — $gibPct% have no vowels / consonant clusters ($gibberishCount classes)") }
        if ($novPct   -ge  8) { $obfFlags.Add("No-vowel class names — $novPct% ($noVowelCount classes)") }
        if ($confPct  -ge  3) { $obfFlags.Add("Confusion-char names (Il1O0/_) — $confPct% ($confusionCount classes)") }
        if ($singleCharPkg -ge 6) { $obfFlags.Add("Single-char package paths — $singleCharPkg path segments like a/b/c") }

        $sampleStr = $contentSample.ToString()
        $fwStringMatches = [regex]::Matches($sampleStr, "[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]{2,}")
        if ($fwStringMatches.Count -gt 0) {
            $examples = ($fwStringMatches | Select-Object -First 3 | ForEach-Object { $_.Value }) -join ", "
            $obfFlags.Add("Fullwidth strings in class content — $($fwStringMatches.Count) occurrences (e.g. $examples)")
        }

        foreach ($obfName in $cheatObfuscators.Keys) {
            foreach ($pat in $cheatObfuscators[$obfName]) {
                if ($sampleStr.Contains($pat)) {
                    $obfFlags.Add("Known cheat obfuscator detected — $obfName (matched: $pat)")
                    break
                }
            }
        }
    }

    return [PSCustomObject]@{
        Patterns    = [string[]]@($foundPatterns)
        Strings     = [string[]]@($foundStrings)
        Fullwidth   = [string[]]@($finalFullwidth)
        BypassFlags = [string[]]@($bypassFlags)
        ObfFlags    = [string[]]@($obfFlags)
    }
}

# ---------------------------------------------------------------------------
#  JVM Inspector - Minecraft Screenshare Forensics
#  By Tonynoh - discord.gg/meowtools
# ---------------------------------------------------------------------------
function Get-RelevantArgs {
    param (
        [string[]]$ArgList
    )
    $relevantPatterns = @(
        "-javaagent*",
        "-Dfabric.addMods*",
        "-Dloader.addMods*",
        "-Dfabric.gameJarPath*",
        "-Dloader.gameJarPath*",
        "-Djava.library.path*",
        "-Djna.boot.library.path*",
        "-Djdk.attach.allowAttachSelf*",
        "--tweakClass*",
        "--launchTarget*"
    )
    $excludedPatterns = @(
        "-cp*",
        "-classpath*"
    )
    return $ArgList | Where-Object {
        $arg = $_
        $isRelevant = $relevantPatterns | Where-Object { $arg -like $_ }
        $isExcluded  = $excludedPatterns  | Where-Object { $arg -like $_ }
        $isRelevant -and -not $isExcluded
    }
}

function Get-ArgColor {
    param ([string]$Arg)
    switch -Wildcard ($Arg) {
        "-javaagent*"                    { return "Red" }
        "-Dfabric.addMods*"              { return "Yellow" }
        "-Dloader.addMods*"              { return "Yellow" }
        "-Dfabric.gameJarPath*"          { return "Yellow" }
        "-Dloader.gameJarPath*"          { return "Yellow" }
        "-Djdk.attach.allowAttachSelf*"  { return "Red" }
        "-Djava.library.path*"           { return "Cyan" }
        "-Djna.boot.library.path*"       { return "Cyan" }
        default                          { return "Gray" }
    }
}

function Get-JvmInspection {
    $results = @()
    foreach ($p in $script:javaProcs) {
        $cmd = $p.CommandLine
        $viaPerf = $false
        if (-not $cmd) {
            $perf = Get-HsPerfInfo -ProcessId $p.ProcessId
            if ($perf -and $perf.VmArgs) { $cmd = $perf.VmArgs; $viaPerf = $true }
        }

        $flagList = @()
        if ($cmd) {
            $argList  = $cmd -split ' (?=-)'
            $filtered = @(Get-RelevantArgs -ArgList $argList)
            foreach ($a in $filtered) {
                $clean = $a.Trim()
                $flagList += [PSCustomObject]@{ Text = $clean; Color = (Get-ArgColor -Arg $clean) }
            }
        }

        $results += [PSCustomObject]@{
            ProcessId  = $p.ProcessId
            Name       = $p.Name
            Accessible = [bool]$cmd
            ViaPerf    = $viaPerf
            Flags      = $flagList
        }
    }
    return $results
}

# ---------------------------------------------------------------------------
#  Output helpers (plain ASCII lines - no more broken box drawing)
# ---------------------------------------------------------------------------
function Write-Rule {
    param([string]$Char = "-", [int]$Width = 76, [ConsoleColor]$Color = "DarkGray")
    Write-Host ($Char * $Width) -ForegroundColor $Color
}

function Write-SectionHeader {
    param(
        [string]$Title,
        [int]$Count,
        [ConsoleColor]$DotColor,
        [ConsoleColor]$CountColor
    )
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "●" -ForegroundColor $DotColor -NoNewline
    Write-Host "  $Title  " -ForegroundColor White -NoNewline
    Write-Host "($Count)" -ForegroundColor $CountColor
    Write-Host ""
}

function Write-CardHeader {
    param([string]$Label, [ConsoleColor]$Fg, [ConsoleColor]$Bg, [string]$FileName)
    Write-Host "  " -NoNewline
    Write-Host " $Label " -ForegroundColor $Fg -BackgroundColor $Bg -NoNewline
    Write-Host "  $FileName" -ForegroundColor Yellow
}

function Write-CardList {
    param([string]$Title, [object[]]$Items, [ConsoleColor]$ItemColor, [string]$Prefix = "")
    Write-Host ""
    Write-Host "      $Title" -ForegroundColor DarkGray
    foreach ($it in $Items) {
        Write-Host "        - $Prefix$it" -ForegroundColor $ItemColor
    }
}

function Write-CardEnd {
    param([ConsoleColor]$Color)
    Write-Host ""
    Write-Rule "-" 76 $Color
    Write-Host ""
}

function Split-Flag {
    param([string]$Flag)
    if ($Flag -match "^(.+?) — (.+)$") { return @($matches[1], $matches[2]) }
    return @($Flag, "")
}

function Write-FlagCard {
    param($Mod, [string]$Label, [ConsoleColor]$LabelFg, [ConsoleColor]$LineColor, [ConsoleColor]$Bullet, [string]$BulletChar)

    Write-CardHeader -Label $Label -Fg $LabelFg -Bg $LineColor -FileName $Mod.FileName
    foreach ($flag in $Mod.Flags) {
        $parts = Split-Flag -Flag $flag
        Write-Host ""
        Write-Host "      $BulletChar " -ForegroundColor $Bullet -NoNewline
        Write-Host $parts[0] -ForegroundColor White
        if ($parts[1] -ne "") {
            Write-Host "        $($parts[1])" -ForegroundColor Gray
        }
    }
    Write-CardEnd -Color $LineColor
}

function Write-SuspiciousCard {
    param($Mod)

    Write-CardHeader -Label "FLAGGED" -Fg White -Bg DarkRed -FileName $Mod.FileName

    if ($Mod.Patterns.Count -gt 0) {
        Write-CardList -Title "PATTERNS" -Items @($Mod.Patterns | Sort-Object) -ItemColor Red
    }

    $uniqueStrings = @($Mod.Strings | Where-Object { $Mod.Patterns -notcontains $_ } | Sort-Object)
    if ($uniqueStrings.Count -gt 0) {
        Write-CardList -Title "STRINGS" -Items $uniqueStrings -ItemColor DarkYellow
    }

    if ($Mod.Fullwidth -and $Mod.Fullwidth.Count -gt 0) {
        Write-CardList -Title "FULLWIDTH UNICODE" -Items @($Mod.Fullwidth | Sort-Object) -ItemColor Cyan -Prefix "FULLWIDTH: "
    }

    Write-CardEnd -Color DarkRed
}

function Write-InjectionCard {
    param($Mod)
    Write-FlagCard -Mod $Mod -Label "INJECTION" -LabelFg White -LineColor DarkMagenta -Bullet Magenta -BulletChar "*"
}

function Write-ObfuscationCard {
    param($Mod)
    Write-FlagCard -Mod $Mod -Label "OBFUSCATED" -LabelFg Black -LineColor DarkYellow -Bullet Yellow -BulletChar "*"
}

function Write-LowDownloadCard {
    param($Mod)

    Write-CardHeader -Label "LOW DOWNLOADS" -Fg Black -Bg Cyan -FileName $Mod.FileName
    Write-Host ""
    Write-Host "      Modrinth project : " -ForegroundColor DarkGray -NoNewline
    Write-Host "$($Mod.ModName)" -ForegroundColor White -NoNewline
    Write-Host "  (https://modrinth.com/mod/$($Mod.Slug))" -ForegroundColor DarkGray
    Write-Host "      Total downloads  : " -ForegroundColor DarkGray -NoNewline
    Write-Host "$($Mod.Downloads)" -ForegroundColor Cyan -NoNewline
    Write-Host "  (limit: $lowDownloadThreshold)" -ForegroundColor DarkGray
    Write-Host "      Possible 'Modrinth method' - decompile it to be sure." -ForegroundColor Yellow
    Write-CardEnd -Color DarkCyan
}

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
$verifiedMods    = @()
$unknownMods     = @()
$suspiciousMods  = @()
$bypassMods      = @()
$obfuscatedMods  = @()
$lowDlMods       = @()

try {
    $jarFiles = Get-ChildItem -Path $modsPath -Filter *.jar -ErrorAction Stop
} catch {
    Write-Host "❌ Error accessing directory: $_" -ForegroundColor Red
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

if ($jarFiles.Count -eq 0) {
    Write-Host "⚠️  No JAR files found in: $modsPath" -ForegroundColor Yellow
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

$fileWord    = if ($jarFiles.Count -eq 1) { "file" } else { "files" }
Write-Host "🔍 Found $($jarFiles.Count) JAR $fileWord to analyze" -ForegroundColor Green
Write-Host

$spinnerFrames = @("⣾","⣽","⣻","⢿","⡿","⣟","⣯","⣷")
$totalFiles    = $jarFiles.Count
$idx           = 0

# ---------------- Pass 1: hash verification ----------------
Write-Host "🔍 Pass 1 — Hash verification (Modrinth + Megabase)..." -ForegroundColor Cyan

$jarHashes = @{}
foreach ($jar in $jarFiles) {
    $idx++
    $spinner = $spinnerFrames[$idx % $spinnerFrames.Length]
    Write-Host "`r[$spinner] Hashing: $idx/$totalFiles - $($jar.Name)" -ForegroundColor Yellow -NoNewline
    try {
        $h = Get-FileSHA1 -Path $jar.FullName
        if ($h) { $jarHashes[$jar.FullName] = $h.ToLower() }
    } catch { }
}
Write-Host "`r$(' ' * 110)`r" -NoNewline

Write-Host "   Querying Modrinth..." -ForegroundColor DarkGray
$modrinthMap = Get-ModrinthBulk -Hashes ([string[]]@($jarHashes.Values | Select-Object -Unique))
$bulkOk = ($null -ne $modrinthMap)
if (-not $bulkOk) {
    Write-Host "   Bulk lookup failed, falling back to per-file lookups (slower)..." -ForegroundColor DarkYellow
}

$idx = 0
$modrinthWhitelistedSlugs = @("viafabricplus", "viafabricversion")

foreach ($jar in $jarFiles) {
    $idx++
    $spinner = $spinnerFrames[$idx % $spinnerFrames.Length]
    Write-Host "`r[$spinner] Verifying: $idx/$totalFiles - $($jar.Name)" -ForegroundColor Yellow -NoNewline

    $hash = $jarHashes[$jar.FullName]

    if ($hash) {
        $info = $null
        if ($bulkOk) {
            if ($modrinthMap.ContainsKey($hash)) { $info = $modrinthMap[$hash] }
        } else {
            $q = Query-Modrinth -Hash $hash
            if ($q.Slug) { $info = $q }
        }

        if ($info -and $info.Slug) {
            $isModrinthWhitelisted = $modrinthWhitelistedSlugs -contains $info.Slug.ToLower()

            $verifiedMods += [PSCustomObject]@{
                ModName             = $info.Name
                Slug                = $info.Slug
                Downloads           = $info.Downloads
                FileName            = $jar.Name
                FilePath            = $jar.FullName
                ModrinthWhitelisted = $isModrinthWhitelisted
            }
            continue
        }

        $megabaseData = Query-Megabase -Hash $hash
        if ($megabaseData.name) {
            $verifiedMods += [PSCustomObject]@{
                ModName             = $megabaseData.Name
                Slug                = $null
                Downloads           = $null
                FileName            = $jar.Name
                FilePath            = $jar.FullName
                ModrinthWhitelisted = $false
            }
            continue
        }
    }

    $src = Get-DownloadSource $jar.FullName
    $unknownMods += [PSCustomObject]@{ FileName = $jar.Name; FilePath = $jar.FullName; DownloadSource = $src }
}

Write-Host "`r$(' ' * 110)`r" -NoNewline

# ---------------- Pass 2: deep scan (patterns + bypass + obfuscation), parallel ----------------
$modWord = if ($totalFiles -eq 1) { "mod" } else { "mods" }
$threads = [Math]::Max(2, [Math]::Min([Environment]::ProcessorCount, 8))
Write-Host "🔬 Pass 2 — Deep scan (detections + bypass + obfuscation) on $totalFiles $modWord [$threads threads]..." -ForegroundColor Cyan

$whiteNames = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($v in $verifiedMods) { if ($v.ModrinthWhitelisted -eq $true) { [void]$whiteNames.Add($v.FileName) } }

$pool = [runspacefactory]::CreateRunspacePool(1, $threads)
$pool.Open()
$scriptText = $deepScanScript.ToString()

$jobs = @()
foreach ($jar in $jarFiles) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($scriptText).AddArgument($jar.FullName).AddArgument($scanCtx).AddArgument([bool]$whiteNames.Contains($jar.Name))
    $jobs += [PSCustomObject]@{ Jar = $jar; PS = $ps; Handle = $ps.BeginInvoke() }
}

$frame = 0
while ($true) {
    $done = @($jobs | Where-Object { $_.Handle.IsCompleted }).Count
    $spinner = $spinnerFrames[$frame % $spinnerFrames.Length]; $frame++
    Write-Host "`r[$spinner] Scanning: $done/$totalFiles" -ForegroundColor Yellow -NoNewline
    if ($done -ge $totalFiles) { break }
    Start-Sleep -Milliseconds 120
}
Write-Host "`r$(' ' * 110)`r" -NoNewline

foreach ($j in $jobs) {
    $jar = $j.Jar
    $r = $null
    try {
        $out = $j.PS.EndInvoke($j.Handle)
        if ($out -and $out.Count -gt 0) { $r = $out[0] }
    } catch { }
    try { $j.PS.Dispose() } catch { }
    if (-not $r) { continue }

    $isWhite = $whiteNames.Contains($jar.Name)

    if (-not $isWhite) {
        if (@($r.Patterns).Count -gt 0 -or @($r.Strings).Count -gt 0 -or @($r.Fullwidth).Count -gt 0) {
            $suspiciousMods += [PSCustomObject]@{
                FileName  = $jar.Name
                Patterns  = @($r.Patterns)
                Strings   = @($r.Strings)
                Fullwidth = @($r.Fullwidth)
            }
            $verifiedMods = @($verifiedMods | Where-Object { $_.FileName -ne $jar.Name })
        }

        if (@($r.BypassFlags).Count -gt 0) {
            $bypassMods += [PSCustomObject]@{
                FileName = $jar.Name
                Flags    = @($r.BypassFlags)
            }
            $verifiedMods = @($verifiedMods | Where-Object { $_.FileName -ne $jar.Name })
            $unknownMods  = @($unknownMods  | Where-Object { $_.FileName -ne $jar.Name })
        }
    }

    if (@($r.ObfFlags).Count -gt 0) {
        $alreadyFlagged = (@($suspiciousMods | Where-Object { $_.FileName -eq $jar.Name }).Count -gt 0) -or
                          (@($bypassMods     | Where-Object { $_.FileName -eq $jar.Name }).Count -gt 0)
        if (-not $alreadyFlagged) {
            $obfuscatedMods += [PSCustomObject]@{
                FileName = $jar.Name
                Flags    = @($r.ObfFlags)
            }
            $verifiedMods = @($verifiedMods | Where-Object { $_.FileName -ne $jar.Name })
        }
    }
}

try { $pool.Close(); $pool.Dispose() } catch { }

# ---------------- Modrinth-method detection (low download count) ----------------
$lowDlMods     = @($verifiedMods | Where-Object { $null -ne $_.Downloads -and $_.Downloads -le $lowDownloadThreshold })
$verifiedMods  = @($verifiedMods | Where-Object { -not ($null -ne $_.Downloads -and $_.Downloads -le $lowDownloadThreshold) })

# ---------------- Pass 3: JVM inspector ----------------
Write-Host "⚡ Pass 3 — JVM Inspector (agents, addMods, library paths)..." -ForegroundColor DarkYellow
$jvmInspection = @(Get-JvmInspection)
$jvmFlagCount  = 0
foreach ($jp in $jvmInspection) { $jvmFlagCount += @($jp.Flags).Count }
if ($jvmFlagCount -gt 0) {
    Write-Host "   ⚠️  $jvmFlagCount relevant JVM flag(s) found" -ForegroundColor Yellow
} elseif ($jvmInspection.Count -gt 0) {
    Write-Host "   ✓  JVM looks clean" -ForegroundColor DarkGray
} else {
    Write-Host "   -  No javaw.exe / java.exe process running" -ForegroundColor DarkGray
}
Write-Host ""

# ---------------- Results ----------------
if ($verifiedMods.Count -gt 0) {
    Write-SectionHeader -Title "VERIFIED MODS" -Count $verifiedMods.Count -DotColor Green -CountColor Green
    Write-Rule "-" 76 DarkGray
    foreach ($mod in $verifiedMods) {
        Write-Host "  ✓ " -ForegroundColor Green -NoNewline
        Write-Host "$($mod.ModName)" -ForegroundColor White -NoNewline
        Write-Host " → " -ForegroundColor Gray -NoNewline
        Write-Host "$($mod.FileName)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

if ($lowDlMods.Count -gt 0) {
    Write-SectionHeader -Title "LOW-DOWNLOAD MODRINTH MODS (possible 'Modrinth method')" -Count $lowDlMods.Count -DotColor Cyan -CountColor Cyan
    Write-Rule "-" 76 DarkGray
    Write-Host "  These mods are verified by hash on Modrinth but have $lowDownloadThreshold downloads or fewer." -ForegroundColor Gray
    Write-Host "  Bypassers upload/reuse a Modrinth-listed file so analyzers mark it as safe." -ForegroundColor Gray
    Write-Host "  A low download count is NOT proof of cheating: decompile the jar" -ForegroundColor Yellow
    Write-Host "  (Recaf / JD-GUI / Bytecode Viewer) for a safer check." -ForegroundColor Yellow
    Write-Host ""
    foreach ($mod in ($lowDlMods | Sort-Object Downloads)) {
        Write-LowDownloadCard -Mod $mod
    }
}

if ($unknownMods.Count -gt 0) {
    Write-SectionHeader -Title "UNKNOWN MODS" -Count $unknownMods.Count -DotColor Yellow -CountColor Yellow
    Write-Rule "-" 76 DarkGray
    Write-Host ""
    foreach ($mod in $unknownMods) {
        $sourceText = if ($mod.DownloadSource) { $mod.DownloadSource } else { "?" }
        Write-Host "  " -NoNewline
        Write-Host " UNKNOWN " -ForegroundColor Black -BackgroundColor Yellow -NoNewline
        Write-Host "  $($mod.FileName)" -ForegroundColor Yellow
        Write-Host "      Source: " -ForegroundColor DarkGray -NoNewline
        Write-Host $sourceText -ForegroundColor Gray
        Write-Host ""
    }
}

if ($suspiciousMods.Count -gt 0) {
    Write-SectionHeader -Title "SUSPICIOUS MODS" -Count $suspiciousMods.Count -DotColor Red -CountColor Red
    Write-Rule "-" 76 DarkGray
    Write-Host ""
    foreach ($mod in $suspiciousMods) {
        Write-SuspiciousCard -Mod $mod
    }
}

if ($bypassMods.Count -gt 0) {
    Write-SectionHeader -Title "BYPASS / INJECTION DETECTED" -Count $bypassMods.Count -DotColor Magenta -CountColor Magenta
    Write-Rule "-" 76 DarkGray
    Write-Host ""
    foreach ($mod in $bypassMods) {
        Write-InjectionCard -Mod $mod
    }
}

if ($obfuscatedMods.Count -gt 0) {
    Write-SectionHeader -Title "OBFUSCATED MODS" -Count $obfuscatedMods.Count -DotColor DarkYellow -CountColor Yellow
    Write-Rule "-" 76 DarkGray
    Write-Host ""
    foreach ($mod in $obfuscatedMods) {
        Write-ObfuscationCard -Mod $mod
    }
}

if ($jvmInspection.Count -gt 0) {
    Write-SectionHeader -Title "JVM INSPECTOR" -Count $jvmFlagCount -DotColor Yellow -CountColor Yellow
    Write-Rule "-" 76 DarkGray
    Write-Host "  By Tonynoh - discord.gg/meowtools" -ForegroundColor DarkCyan
    Write-Host ""
    $procLabel = if ($jvmInspection.Count -eq 1) { "process" } else { "processes" }
    Write-Host "  Found $($jvmInspection.Count) running Java $procLabel." -ForegroundColor Gray
    Write-Host ""

    foreach ($jp in $jvmInspection) {
        Write-Host "  PID $($jp.ProcessId) ($($jp.Name))" -ForegroundColor DarkGray
        if (-not $jp.Accessible) {
            Write-Host "    CommandLine not accessible (run PowerShell as admin)." -ForegroundColor DarkYellow
        }
        elseif (@($jp.Flags).Count -gt 0) {
            if ($jp.ViaPerf) {
                Write-Host "    (read from hsperfdata)" -ForegroundColor DarkGray
            }
            foreach ($f in $jp.Flags) {
                Write-Host "    $($f.Text)" -ForegroundColor $f.Color
            }
        }
        else {
            Write-Host "    No relevant arguments found." -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    $flagLabel = if ($jvmFlagCount -eq 1) { "flag" } else { "flags" }
    Write-Host "  Scan completed, $jvmFlagCount relevant $flagLabel found" -ForegroundColor Cyan
    Write-Host ""
}

Write-Host "📊 SUMMARY" -ForegroundColor Cyan
Write-Rule "=" 76 Blue
Write-Host "  Total files scanned:   " -ForegroundColor Gray -NoNewline; Write-Host "$totalFiles"                   -ForegroundColor White
Write-Host "  Verified mods:         " -ForegroundColor Gray -NoNewline; Write-Host "$($verifiedMods.Count)"        -ForegroundColor Green
Write-Host "  Low-download (Modr.):  " -ForegroundColor Gray -NoNewline; Write-Host "$($lowDlMods.Count)"          -ForegroundColor Cyan
Write-Host "  Unknown mods:          " -ForegroundColor Gray -NoNewline; Write-Host "$($unknownMods.Count)"         -ForegroundColor Yellow
Write-Host "  Suspicious mods:       " -ForegroundColor Gray -NoNewline; Write-Host "$($suspiciousMods.Count)"      -ForegroundColor Red
Write-Host "  Bypass/Injected:       " -ForegroundColor Gray -NoNewline; Write-Host "$($bypassMods.Count)"          -ForegroundColor Magenta
Write-Host "  Obfuscated mods:       " -ForegroundColor Gray -NoNewline; Write-Host "$($obfuscatedMods.Count)"      -ForegroundColor Yellow
Write-Host "  JVM flags:             " -ForegroundColor Gray -NoNewline; Write-Host "$jvmFlagCount"                 -ForegroundColor Yellow
Write-Host
Write-Rule "=" 76 Blue
Write-Host ""
Write-Host "  ✨ Analysis complete! Thanks for using Meow Mod Analyzer 🐱" -ForegroundColor Cyan
Write-Host ""
Write-Host "  👤 Created by: " -ForegroundColor White -NoNewline
Write-Host "🌟 " -ForegroundColor Cyan -NoNewline
Write-Host "Tonynoh" -ForegroundColor Cyan
Write-Host "  📱 My Socials: " -ForegroundColor White -NoNewline
Write-Host "💬 " -ForegroundColor Blue -NoNewline
Write-Host "Discord  : " -ForegroundColor Blue -NoNewline
Write-Host "tonyboy90_" -ForegroundColor Blue
Write-Host "                 " -NoNewline
Write-Host "🔗 " -ForegroundColor DarkGray -NoNewline
Write-Host "GitHub   : " -ForegroundColor DarkGray -NoNewline
Write-Host "https://github.com/MeowTonynoh" -ForegroundColor DarkGray
Write-Host "                 " -NoNewline
Write-Host "🎥 " -ForegroundColor Red -NoNewline
Write-Host "YouTube  : " -ForegroundColor Red -NoNewline
Write-Host "tonynoh-07" -ForegroundColor Red
Write-Host ""
Write-Rule "=" 76 Blue
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
