# patch-check.ps1
# Reads the security patch level of an OTA package and, optionally, compares it
# with a recovery image. Works in Windows PowerShell 5.1+ and PowerShell 7.
#
# Recovery images:
#   - recovery.img / boot.img (header "ANDROID!", e.g. tucana): Android version and
#     patch level are read from the image header.
#   - vendor_boot.img (header "VNDRBOOT", e.g. bramble): Android version and patch
#     level are read from prop.default in the ramdisk. The kernel modules in the
#     ramdisk are also compared with the ROM kernel, because vendor_boot is used for
#     the normal Android boot as well.
#
# Supported inputs:
#   - A-only OTA zip with boot.img at its root (tucana, most retrofit devices)
#   - A/B OTA zip with payload.bin (needs payload-dumper-go)
#   - A bare payload.bin
#   - A boot.img you extracted yourself (e.g. with Multi Image Kitchen) via -BootImg
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File patch-check.ps1 -Zip <ota.zip> [-RecoveryImg <recovery.img>]
#   powershell -ExecutionPolicy Bypass -File patch-check.ps1 -BootImg <boot.img> [-RecoveryImg <recovery.img>]
# Optional: -PayloadTool <path to a payload tool .exe>
#           -GoDumper <path to payload-dumper-go.exe>
#           -MikDir <path to your Multi Image Kitchen folder>
#           -WorkDir <folder for temporary files>. Only used for A/B (payload.bin) zips;
#           if omitted there, the script shows the space needed and asks.
#           Without -PayloadTool, -GoDumper or -MikDir, the script looks for a payload tool
#           next to itself and in PATH.
# Supported payload tools: payload-dumper-go (fast, extracts only boot)
#                          payload_dumper by vm03 (bundled with MIK, extracts all, stopped after boot)

param(
  [string]$Zip,
  [string]$BootImg,
  [string]$RecoveryImg,
  [string]$PayloadTool,
  [string]$GoDumper,   # <path to payload-dumper-go.exe>
  [string]$MikDir,     # <path to your Multi Image Kitchen folder>
  [string]$WorkDir = $env:TEMP
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not ([System.Management.Automation.PSTypeName]'FoxUnpack').Type) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;
public static class FoxUnpack {
  static void Grow(ref byte[] b, int need) {
    if (need <= b.Length) return;
    int n = b.Length * 2; while (n < need) n *= 2;
    Array.Resize(ref b, n);
  }
  static int Block(byte[] src, int ip, int end, ref byte[] dst, int op) {
    while (ip < end) {
      int token = src[ip++];
      int lit = token >> 4;
      if (lit == 15) { int b; do { b = src[ip++]; lit += b; } while (b == 255); }
      Grow(ref dst, op + lit);
      Buffer.BlockCopy(src, ip, dst, op, lit); ip += lit; op += lit;
      if (ip >= end) break;
      int off = src[ip] | (src[ip + 1] << 8); ip += 2;
      int ml = token & 15;
      if (ml == 15) { int b; do { b = src[ip++]; ml += b; } while (b == 255); }
      ml += 4;
      Grow(ref dst, op + ml);
      int m = op - off;
      if (off >= ml) { Buffer.BlockCopy(dst, m, dst, op, ml); op += ml; }
      else { for (int i = 0; i < ml; i++) dst[op++] = dst[m + i]; }
    }
    return op;
  }
  // LZ4 legacy, LZ4 frame, gzip or uncompressed data.
  public static byte[] Decompress(byte[] src, int start, int len) {
    int end = start + len;
    if (len >= 4 && src[start] == 0x02 && src[start + 1] == 0x21 && src[start + 2] == 0x4C && src[start + 3] == 0x18) {
      byte[] dst = new byte[Math.Max(len * 3, 1 << 20)]; int op = 0; int ip = start + 4;
      while (ip + 4 <= end) {
        uint n = BitConverter.ToUInt32(src, ip);
        if (n == 0x184C2102) { ip += 4; continue; }
        if (n == 0 || ip + 4 + n > end) break;
        op = Block(src, ip + 4, ip + 4 + (int)n, ref dst, op);
        ip += 4 + (int)n;
      }
      Array.Resize(ref dst, op); return dst;
    }
    if (len >= 4 && src[start] == 0x04 && src[start + 1] == 0x22 && src[start + 2] == 0x4D && src[start + 3] == 0x18) {
      int ip = start + 4; int flg = src[ip]; ip += 2;
      if ((flg & 0x08) != 0) ip += 8;
      if ((flg & 0x01) != 0) ip += 4;
      ip += 1;
      bool bsum = (flg & 0x10) != 0;
      byte[] dst = new byte[Math.Max(len * 3, 1 << 20)]; int op = 0;
      while (ip + 4 <= end) {
        uint n = BitConverter.ToUInt32(src, ip); ip += 4;
        if (n == 0) break;
        int sz = (int)(n & 0x7FFFFFFF);
        if ((n & 0x80000000u) != 0) { Grow(ref dst, op + sz); Buffer.BlockCopy(src, ip, dst, op, sz); op += sz; }
        else op = Block(src, ip, ip + sz, ref dst, op);
        ip += sz; if (bsum) ip += 4;
      }
      Array.Resize(ref dst, op); return dst;
    }
    if (len >= 2 && src[start] == 0x1F && src[start + 1] == 0x8B) {
      using (var ms = new MemoryStream(src, start, len))
      using (var gz = new GZipStream(ms, CompressionMode.Decompress))
      using (var o = new MemoryStream()) { gz.CopyTo(o); return o.ToArray(); }
    }
    byte[] r = new byte[len]; Buffer.BlockCopy(src, start, r, 0, len); return r;
  }
  // Returns the release from the kernel banner ("Linux version <release> (").
  public static string KernelRelease(byte[] k) {
    byte[] pat = System.Text.Encoding.ASCII.GetBytes("Linux version ");
    for (int i = 0; i + pat.Length + 2 < k.Length; i++) {
      int j = 0; while (j < pat.Length && k[i + j] == pat[j]) j++;
      if (j < pat.Length) continue;
      int s = i + pat.Length;
      if (k[s] < (byte)'0' || k[s] > (byte)'9') continue;
      int e = s; while (e < k.Length && k[e] != (byte)' ' && k[e] != 0) e++;
      if (e + 1 < k.Length && k[e] == (byte)' ' && k[e + 1] == (byte)'(')
        return System.Text.Encoding.ASCII.GetString(k, s, e - s);
    }
    return null;
  }
  public static bool Contains(byte[] data, int start, int len, byte[] pat) {
    int last = start + len - pat.Length;
    for (int i = start; i <= last; i++) {
      int j = 0; while (j < pat.Length && data[i + j] == pat[j]) j++;
      if (j == pat.Length) return true;
    }
    return false;
  }
}
'@
}

$workDirGiven = $PSBoundParameters.ContainsKey('WorkDir')

if (-not $Zip -and -not $BootImg) { throw 'Give -Zip <ota.zip | payload.bin> or -BootImg <boot.img>' }

function Read-Head([IO.Stream]$s, [int]$n) {
  $buf = New-Object byte[] $n
  $read = 0
  while ($read -lt $n) {
    $k = $s.Read($buf, $read, $n - $read)
    if ($k -le 0) { break }
    $read += $k
  }
  return ,$buf
}

function Read-OsVersion([byte[]]$h) {
  $magic = [Text.Encoding]::ASCII.GetString($h, 0, 8)
  if ($magic -ne 'ANDROID!') { throw "Not an Android boot image (magic: $magic)" }
  $hv  = [BitConverter]::ToUInt32($h, 40)
  $off = if ($hv -ge 3) { 16 } else { 44 }
  $v   = [BitConverter]::ToUInt32($h, $off)
  $lvl = $v -band 0x7FF
  $y   = ($lvl -shr 4) + 2000
  $m   = $lvl -band 0xF
  $a   = ($v -shr 25) -band 0x7F
  $b   = ($v -shr 18) -band 0x7F
  $c   = ($v -shr 11) -band 0x7F
  [pscustomobject]@{
    HeaderVersion = $hv
    OsVersion     = "$a.$b.$c"
    PatchLevel    = ('{0:D4}-{1:D2}' -f $y, $m)
  }
}

function Get-BootKernelRelease([byte[]]$d) {
  $hv = [BitConverter]::ToUInt32($d, 40)
  $kSize = [BitConverter]::ToUInt32($d, 8)
  $page = if ($hv -ge 3) { 4096 } else { [BitConverter]::ToUInt32($d, 36) }
  if ($kSize -eq 0 -or $page + $kSize -gt $d.Length) { return $null }
  try { return [FoxUnpack]::KernelRelease([FoxUnpack]::Decompress($d, [int]$page, [int]$kSize)) } catch { return $null }
}

function Read-VendorBoot([byte[]]$d) {
  $hv = [BitConverter]::ToUInt32($d, 8)
  if ($hv -ne 3) { throw "vendor_boot header v$hv is not supported (v3 expected)" }
  $page = [BitConverter]::ToUInt32($d, 12)
  $rSize = [BitConverter]::ToUInt32($d, 24)
  $hSize = [BitConverter]::ToUInt32($d, 2096)
  $rOff = [int]([math]::Ceiling($hSize / $page) * $page)
  $raw = [FoxUnpack]::Decompress($d, $rOff, [int]$rSize)
  $prop = $null; $vermagic = $null
  $p = 0
  while ($p -lt $raw.Length -and ($null -eq $prop -or $null -eq $vermagic)) {
    $hdr = [Text.Encoding]::ASCII.GetString($raw, $p, 110)
    if (-not $hdr.StartsWith('07070')) { break }
    $fsize = [Convert]::ToInt32($hdr.Substring(54, 8), 16)
    $nsize = [Convert]::ToInt32($hdr.Substring(94, 8), 16)
    $p += 110
    $name = [Text.Encoding]::ASCII.GetString($raw, $p, $nsize - 1).TrimStart('/')
    $p = ($p + $nsize + 3) -band -bnot 3
    if ($name -eq 'TRAILER!!!') { break }
    if ($name -eq 'prop.default') { $prop = [Text.Encoding]::ASCII.GetString($raw, $p, $fsize) }
    elseif ($null -eq $vermagic -and $name -like 'lib/modules/*.ko') {
      $m = [regex]::Match([Text.Encoding]::ASCII.GetString($raw, $p, $fsize), 'vermagic=([^\x00 ]+)')
      if ($m.Success) { $vermagic = $m.Groups[1].Value }
    }
    $p = ($p + $fsize + 3) -band -bnot 3
  }
  if (-not $prop) { throw 'prop.default not found in the vendor_boot ramdisk' }
  $rel = ([regex]::Match($prop, '(?m)^ro\.build\.version\.release=(.*)$')).Groups[1].Value.Trim()
  $spl = ([regex]::Match($prop, '(?m)^ro\.build\.version\.security_patch=(.*)$')).Groups[1].Value.Trim()
  $parts = @($rel.Split('.')) + @('0', '0')
  [pscustomobject]@{
    Kind          = 'vendor_boot'
    HeaderVersion = $hv
    OsVersion     = '{0}.{1}.{2}' -f $parts[0], $parts[1], $parts[2]
    PatchLevel    = if ($spl.Length -ge 7) { $spl.Substring(0, 7) } else { $spl }
    PatchDate     = $spl
    Vermagic      = $vermagic
  }
}

function Read-ImgBytes([byte[]]$d) {
  $magic = [Text.Encoding]::ASCII.GetString($d, 0, 8)
  if ($magic -eq 'VNDRBOOT') { return Read-VendorBoot $d }
  $info = Read-OsVersion $d
  $info | Add-Member -NotePropertyName Kind -NotePropertyValue 'boot'
  $info | Add-Member -NotePropertyName KernelRelease -NotePropertyValue (Get-BootKernelRelease $d)
  return $info
}

function Read-ImgFile([string]$path) {
  return Read-ImgBytes ([IO.File]::ReadAllBytes($path))
}

function Find-PayloadTool {
  if ($PayloadTool) {
    if (Test-Path $PayloadTool) { return (Resolve-Path $PayloadTool).Path }
    throw "PayloadTool not found: $PayloadTool"
  }
  if ($GoDumper -and (Test-Path $GoDumper)) { return (Resolve-Path $GoDumper).Path }
  foreach ($name in 'payload-dumper-go.exe', 'payload_dumper.exe') {
    $local = Join-Path $PSScriptRoot $name
    if (Test-Path $local) { return $local }
  }
  $cmd = Get-Command 'payload-dumper-go' -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  if ($MikDir -and (Test-Path $MikDir)) {
    $all = Get-ChildItem $MikDir -Recurse -Include 'payload-dumper*.exe', 'payload_dumper*.exe' -ErrorAction SilentlyContinue
    $go = $all | Where-Object { $_.Name -like 'payload-dumper-go*' } | Select-Object -First 1
    if ($go) { return $go.FullName }
    $any = $all | Select-Object -First 1
    if ($any) { return $any.FullName }
  }
  return $null
}

function Select-WorkDir([long]$needBytes) {
  $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 0 }
  $tempDrive = (Split-Path -Qualifier $env:TEMP).TrimEnd(':')
  $tempFree = ($drives | Where-Object { $_.Name -eq $tempDrive } | Select-Object -First 1).Free
  Write-Host ('This is an A/B package: payload.bin needs about {0:N1} GB of temporary space.' -f ($needBytes / 1GB))
  foreach ($d in $drives) { Write-Host ('  {0}: {1:N1} GB free' -f $d.Name, ($d.Free / 1GB)) }
  $default = $env:TEMP
  if (-not $tempFree -or $tempFree -lt $needBytes) {
    $best = $drives | Sort-Object Free -Descending | Select-Object -First 1
    $default = Join-Path $best.Root 'tmp'
    Write-Host "Not enough space on ${tempDrive}:, suggesting $default"
  }
  $ans = Read-Host "Temporary folder (Enter = $default)"
  if ([string]::IsNullOrWhiteSpace($ans)) { $ans = $default }
  return $ans.Trim('"')
}

function Get-PayloadFile([string]$zipPath, [string]$tmp) {
  Write-Host 'Extracting payload.bin from the zip (this can take a while)...'
  $pl = Join-Path $tmp 'payload.bin'
  $zf = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try { [IO.Compression.ZipFileExtensions]::ExtractToFile($zf.GetEntry('payload.bin'), $pl) }
  finally { $zf.Dispose() }
  return $pl
}

function Invoke-GoDumper([string]$tool, [string]$inputPath, [string]$zipPath, [string]$out, [string]$tmp) {
  & $tool -p boot -o $out $inputPath | Out-Host
  $img = Get-ChildItem $out -Recurse -Filter 'boot.img' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $img -and $zipPath) {
    $pl = Get-PayloadFile $zipPath $tmp
    & $tool -p boot -o $out $pl | Out-Host
    $img = Get-ChildItem $out -Recurse -Filter 'boot.img' -ErrorAction SilentlyContinue | Select-Object -First 1
  }
  return $img
}

function Invoke-Vm03Dumper([string]$tool, [string]$payloadPath, [string]$out) {
  Write-Host 'This tool extracts every partition in order; it will be stopped as soon as boot.img is complete.'
  $argList = @('--out', ('"' + $out + '"'), ('"' + $payloadPath + '"'))
  $p = Start-Process -FilePath $tool -ArgumentList $argList -WorkingDirectory (Split-Path $out) -NoNewWindow -PassThru
  $boot = Join-Path $out 'boot.img'
  while (-not $p.HasExited) {
    if (Test-Path $boot) {
      $bootTime = (Get-Item $boot).LastWriteTime
      $next = Get-ChildItem $out -Filter '*.img' -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -ne 'boot.img' -and $_.CreationTime -ge $bootTime }
      if ($next) {
        Write-Host 'boot.img complete, stopping the payload tool.'
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        break
      }
    }
    Start-Sleep -Milliseconds 500
  }
  $p.WaitForExit()
  if (Test-Path $boot) { return Get-Item $boot }
  return $null
}

function Get-BootFromPayload([string]$inputPath, [string]$zipPath) {
  $tool = Find-PayloadTool
  if (-not $tool) {
    throw "payload.bin found but no payload tool was found. Use -PayloadTool or -MikDir, or extract boot.img with Multi Image Kitchen and pass it with -BootImg."
  }
  Write-Host "Using payload tool: $tool"
  $tmp = Join-Path $WorkDir ('patchcheck_' + [guid]::NewGuid().ToString('N'))
  $out = Join-Path $tmp 'out'
  New-Item -ItemType Directory -Path $out -Force | Out-Null
  $oldTmp = $env:TMP; $oldTemp = $env:TEMP
  $env:TMP = $tmp; $env:TEMP = $tmp
  try {
    if ((Split-Path $tool -Leaf) -like 'payload-dumper-go*') {
      $img = Invoke-GoDumper $tool $inputPath $zipPath $out $tmp
    }
    else {
      $pl = if ($zipPath) { Get-PayloadFile $zipPath $tmp } else { $inputPath }
      $img = Invoke-Vm03Dumper $tool $pl $out
    }
    if (-not $img) { throw 'payload tool ran but no boot.img was produced. Extract it with Multi Image Kitchen and use -BootImg.' }
    return Read-ImgFile $img.FullName
  }
  finally {
    $env:TMP = $oldTmp; $env:TEMP = $oldTemp
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$metaPatch = $null
$metaDevice = $null
$boot = $null

if ($BootImg) {
  $boot = Read-ImgFile (Resolve-Path $BootImg).Path
}
else {
  $zipFull = (Resolve-Path $Zip).Path
  if ([IO.Path]::GetFileName($zipFull) -ieq 'payload.bin') {
    $boot = Get-BootFromPayload $zipFull $null
  }
  else {
    $zf = [IO.Compression.ZipFile]::OpenRead($zipFull)
    $hasPayload = $false
    try {
      $meta = $zf.GetEntry('META-INF/com/android/metadata')
      if ($meta) {
        $sr = New-Object IO.StreamReader($meta.Open())
        $text = $sr.ReadToEnd()
        $sr.Close()
        $line = ($text -split "`r?`n") | Where-Object { $_ -like 'post-security-patch-level=*' } | Select-Object -First 1
        if ($line) { $metaPatch = $line.Split('=')[1].Trim() }
        $dline = ($text -split "`r?`n") | Where-Object { $_ -like 'pre-device=*' } | Select-Object -First 1
        if ($dline) { $metaDevice = $dline.Split('=')[1].Split(',')[0].Trim() }
      }
      $bootEntry = $zf.GetEntry('boot.img')
      if ($bootEntry) {
        $ms = New-Object IO.MemoryStream
        $s = $bootEntry.Open()
        try { $s.CopyTo($ms) } finally { $s.Close() }
        $boot = Read-ImgBytes $ms.ToArray()
      }
      elseif ($zf.GetEntry('payload.bin')) {
        $hasPayload = $true
        $payloadSize = $zf.GetEntry('payload.bin').Length
      }
      else { throw 'Neither boot.img nor payload.bin found in the zip' }
    }
    finally { $zf.Dispose() }
    if ($hasPayload) {
      if (-not $workDirGiven) { $WorkDir = Select-WorkDir ([long]($payloadSize * 1.05) + 200MB) }
      $boot = Get-BootFromPayload $zipFull $zipFull
    }
  }
}

if ($metaDevice) { Write-Host "OTA device     : $metaDevice" }
if ($metaPatch) { Write-Host "OTA metadata   : security patch $metaPatch" }
Write-Host "Boot header    : Android $($boot.OsVersion), patch $($boot.PatchLevel) (header v$($boot.HeaderVersion))"
if ($boot.KernelRelease) { Write-Host "Boot kernel    : $($boot.KernelRelease)" }

if ($RecoveryImg) {
  $rec = Read-ImgFile (Resolve-Path $RecoveryImg).Path
  $kernelProblem = $null
  if ($rec.Kind -eq 'vendor_boot') {
    Write-Host "Recovery props : Android $($rec.OsVersion), patch $($rec.PatchDate) (vendor_boot v$($rec.HeaderVersion))"
    Write-Host "Recovery kmods : $(if ($rec.Vermagic) { $rec.Vermagic } else { '(no modules found)' })"
    if (-not $boot.KernelRelease) {
      $kernelProblem = 'the ROM kernel release could not be read from boot.img; compare the module version by hand'
    }
    elseif ($rec.Vermagic -and $rec.Vermagic -ne $boot.KernelRelease) {
      $kernelProblem = "the kernel modules in this vendor_boot were built for $($rec.Vermagic), the ROM kernel is $($boot.KernelRelease). vendor_boot is also used for the normal Android boot, so flashing it can stop Android from booting"
    }
  }
  else {
    Write-Host "Recovery header: Android $($rec.OsVersion), patch $($rec.PatchLevel)"
  }
  $recName = Split-Path $RecoveryImg -Leaf
  $deviceMismatch = $metaDevice -and ($recName -notmatch [regex]::Escape($metaDevice))
  $patchMatch = ($rec.OsVersion -eq $boot.OsVersion -and $rec.PatchLevel -eq $boot.PatchLevel)
  $target = if ($metaPatch) { $metaPatch } else { "$($boot.PatchLevel)-01 (check the exact day)" }
  if ($deviceMismatch) {
    Write-Host "WARNING: the recovery file name does not mention '$metaDevice'." -ForegroundColor Red
    if ($patchMatch) {
      Write-Host "RESULT: patch levels match, but the files appear to belong to different devices. Do not flash this recovery for $metaDevice." -ForegroundColor Red
    }
    else {
      Write-Host "RESULT: patch levels differ and the files appear to belong to different devices. A $metaDevice recovery needs PLATFORM_SECURITY_PATCH := $target" -ForegroundColor Red
    }
  }
  elseif ($kernelProblem -and $boot.KernelRelease) {
    Write-Host "RESULT: do not flash: $kernelProblem." -ForegroundColor Red
    if (-not $patchMatch) { Write-Host "The patch level also differs; a rebuild needs PLATFORM_SECURITY_PATCH := $target" -ForegroundColor Red }
  }
  elseif ($patchMatch) {
    if ($kernelProblem) {
      Write-Host "RESULT: patch levels match, but $kernelProblem." -ForegroundColor Yellow
    } else {
      Write-Host 'RESULT: match, no rebuild needed' -ForegroundColor Green
    }
  }
  else {
    Write-Host "RESULT: mismatch, rebuild with PLATFORM_SECURITY_PATCH := $target" -ForegroundColor Yellow
  }
}
