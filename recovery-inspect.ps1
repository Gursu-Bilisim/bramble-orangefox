# recovery-inspect.ps1
# Lists what a bramble (Pixel 4a 5G) OrangeFox vendor_boot image contains for
# FBE v2 + metadata encryption with Titan M (Weaver) on LineageOS 23.2, without
# flashing it. Works in Windows PowerShell 5.1+ and PowerShell 7 (Windows, Linux).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File recovery-inspect.ps1 -Img <vendor_boot.img>
#   powershell -ExecutionPolicy Bypass -File recovery-inspect.ps1 -Img <OrangeFox zip>
#
# Each check prints OK or MISSING. The image decrypts /data only if every item in
# the "Decryption" and "Titan M" groups is OK and patch-check.ps1 reports a match
# for the ROM build you run (patch level and kernel modules).

param(
  [Parameter(Mandatory = $true)][string]$Img
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

function Get-ImageBytes([string]$path) {
  $full = (Resolve-Path $path).Path
  if ([IO.Path]::GetExtension($full) -ieq '.zip') {
    $zf = [IO.Compression.ZipFile]::OpenRead($full)
    try {
      $e = $zf.GetEntry('recovery.img')
      if (-not $e) { throw 'recovery.img not found in the zip' }
      $ms = New-Object IO.MemoryStream
      $s = $e.Open(); $s.CopyTo($ms); $s.Close()
      return ,$ms.ToArray()
    } finally { $zf.Dispose() }
  }
  return ,[IO.File]::ReadAllBytes($full)
}

function Read-VendorBootHeader([byte[]]$d) {
  if ([Text.Encoding]::ASCII.GetString($d, 0, 8) -ne 'VNDRBOOT') { throw 'Not a vendor_boot image (bramble OrangeFox is installed to vendor_boot)' }
  $hv = [BitConverter]::ToUInt32($d, 8)
  if ($hv -ne 3) { throw "vendor_boot header v$hv is not supported by this script (bramble uses v3)" }
  $page = [BitConverter]::ToUInt32($d, 12)
  $rSize = [BitConverter]::ToUInt32($d, 24)
  $hSize = [BitConverter]::ToUInt32($d, 2096)
  $dtbSize = [BitConverter]::ToUInt32($d, 2100)
  $rOff = [math]::Ceiling($hSize / $page) * $page
  $tail = [Text.Encoding]::ASCII.GetString($d, $d.Length - 64, 4)
  [pscustomobject]@{
    HeaderVersion = $hv
    PageSize      = $page
    Cmdline       = [Text.Encoding]::ASCII.GetString($d, 28, 2048).TrimEnd([char]0)
    RamdiskOffset = [int]$rOff
    RamdiskSize   = [int]$rSize
    DtbSize       = $dtbSize
    AvbFooter     = ($tail -eq 'AVBf')
  }
}

function Read-Ramdisk([byte[]]$d, $h) {
  $raw = [FoxUnpack]::Decompress($d, $h.RamdiskOffset, $h.RamdiskSize)
  $magic = [Text.Encoding]::ASCII.GetString($raw, 0, 6)
  if ($magic -ne '070701' -and $magic -ne '070702') { throw 'Ramdisk is not a newc cpio archive after decompression' }
  $files = @{}
  $p = 0
  while ($p -lt $raw.Length) {
    $hdr = [Text.Encoding]::ASCII.GetString($raw, $p, 110)
    $mode  = [Convert]::ToInt32($hdr.Substring(14, 8), 16)
    $fsize = [Convert]::ToInt32($hdr.Substring(54, 8), 16)
    $nsize = [Convert]::ToInt32($hdr.Substring(94, 8), 16)
    $p += 110
    $name = [Text.Encoding]::ASCII.GetString($raw, $p, $nsize - 1)
    $p = ($p + $nsize + 3) -band -bnot 3
    if ($name -eq 'TRAILER!!!') { break }
    if (($mode -band 0xF000) -eq 0x8000) { $files[$name.TrimStart('/')] = @($p, $fsize) }
    $p = ($p + $fsize + 3) -band -bnot 3
  }
  return @{ Data = $raw; Files = $files }
}

function Get-Text($rd, [string]$name) {
  $f = $rd.Files[$name]
  if (-not $f) { return $null }
  return [Text.Encoding]::ASCII.GetString($rd.Data, $f[0], $f[1])
}

function Test-Bytes($rd, [string]$name, [byte[]]$pattern) {
  $f = $rd.Files[$name]
  if (-not $f) { return $false }
  return [FoxUnpack]::Contains($rd.Data, $f[0], $f[1], $pattern)
}

function Find-File($rd, [string[]]$names) {
  foreach ($n in $names) { if ($rd.Files.ContainsKey($n)) { return $n } }
  return $null
}

function Get-Missing($rd, [string]$dir, [string[]]$names) {
  return @($names | Where-Object { -not $rd.Files.ContainsKey("$dir/$_") })
}

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$group, [string]$check, [bool]$ok, [string]$detail) {
  $results.Add([pscustomobject]@{ Group = $group; Check = $check; Result = $(if ($ok) { 'OK' } else { 'MISSING' }); Detail = $detail })
}

$bytes = Get-ImageBytes $Img
$h = Read-VendorBootHeader $bytes
$rd = Read-Ramdisk $bytes $h

$props = Get-Text $rd 'prop.default'
function Get-Prop([string]$key) {
  if (-not $props) { return '' }
  return ([regex]::Match($props, "(?m)^$([regex]::Escape($key))=(.*)$")).Groups[1].Value.Trim()
}
$kos = @($rd.Files.Keys | Where-Object { $_ -like 'lib/modules/*.ko' })
$vermagic = ''
if ($kos.Count -gt 0) {
  $vermagic = ([regex]::Match((Get-Text $rd $kos[0]), 'vermagic=([^\x00]+)')).Groups[1].Value
}

Write-Host "Image          : $(Split-Path $Img -Leaf)"
Write-Host "Header         : vendor_boot v$($h.HeaderVersion), page $($h.PageSize), DTB $($h.DtbSize) bytes, AVB footer $(if ($h.AvbFooter) { 'yes' } else { 'no' })"
Write-Host "Android        : $(Get-Prop 'ro.build.version.release'), security patch $(Get-Prop 'ro.build.version.security_patch'), vendor patch $(Get-Prop 'ro.vendor.build.security_patch')"
Write-Host "Modules        : $($kos.Count), vermagic $vermagic"
Write-Host ''

# Header and first stage (shared with normal Android boot)
Add-Result 'Boot' 'boot device on cmdline' ($h.Cmdline -match 'androidboot\.boot_devices=soc/1d84000\.ufshc') 'androidboot.boot_devices=soc/1d84000.ufshc'
Add-Result 'Boot' 'DTB present' ($h.DtbSize -gt 0) "$($h.DtbSize) bytes"
Add-Result 'Boot' 'first stage fstab' ($rd.Files.ContainsKey('first_stage_ramdisk/fstab.sm7250')) 'first_stage_ramdisk/fstab.sm7250'
$load = Get-Text $rd 'lib/modules/modules.load'
$listed = @()
if ($load) { $listed = @($load -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { (Split-Path $_ -Leaf) -replace '\.ko$', '' }) }
$absent = @($listed | Where-Object {
  -not ($rd.Files.ContainsKey("lib/modules/$_.ko") -or $rd.Files.ContainsKey("lib/modules/$($_ -replace '-', '_').ko") -or $rd.Files.ContainsKey("lib/modules/$($_ -replace '_', '-').ko"))
})
Add-Result 'Boot' 'every module in modules.load present' ([bool]$load -and $listed.Count -gt 0 -and $absent.Count -eq 0) $(if (-not $load) { 'lib/modules/modules.load not found' } elseif ($absent) { 'missing: ' + ($absent[0..4] -join ', ') } else { "$($listed.Count) modules" })

# Decryption chain (QTI)
$rcText = ($rd.Files.Keys | Where-Object { $_ -like '*.rc' } | ForEach-Object { Get-Text $rd $_ }) -join "`n"
Add-Result 'Decryption' '/dev/block/bootdevice link created by init' ($rcText -match '(?m)symlink\s+\S+\s+/dev/block/bootdevice\s*$') ''
Add-Result 'Decryption' 'modem firmware mount (slot suffix)' ($rcText -match 'modem\$\{ro\.boot\.slot_suffix\}\s+/vendor/firmware_mnt') '/vendor/firmware_mnt'
Add-Result 'Decryption' 'qcom decrypt init (twrp-common)' ($rd.Files.ContainsKey('init.recovery.qcom_decrypt.rc')) 'init.recovery.qcom_decrypt.rc'
$n = Find-File $rd @('system/bin/prepdecrypt.sh', 'vendor/bin/prepdecrypt.sh')
Add-Result 'Decryption' 'prepdecrypt script' ([bool]$n) $n
$n = Find-File $rd @('system/bin/qseecomd', 'vendor/bin/qseecomd')
Add-Result 'Decryption' 'qseecomd' ([bool]$n) $n
$n = Find-File $rd @('vendor/lib64/libQSEEComAPI.so', 'system/lib64/libQSEEComAPI.so')
Add-Result 'Decryption' 'QSEECom library' ([bool]$n) $n
$missing = Get-Missing $rd 'vendor/lib64' @('librpmb.so', 'libssd.so', 'libops.so', 'libGPreqcancel.so', 'libGPreqcancel_svc.so', 'libdrmtime.so', 'libtime_genoff.so', 'libqisl.so', 'libsecureui.so')
Add-Result 'Decryption' 'qseecomd listener libraries' ($missing.Count -eq 0) $(if ($missing) { 'missing: ' + ($missing -join ', ') } else { '9 listeners' })
$n = Find-File $rd @('system/bin/android.hardware.keymaster@4.0-service-qti', 'vendor/bin/hw/android.hardware.keymaster@4.0-service-qti')
Add-Result 'Decryption' 'QTI keymaster 4.0 service' ([bool]$n) $n
$n = Find-File $rd @('system/bin/android.hardware.gatekeeper@1.0-service-qti', 'vendor/bin/hw/android.hardware.gatekeeper@1.0-service-qti')
Add-Result 'Decryption' 'QTI gatekeeper 1.0 service' ([bool]$n) $n
Add-Result 'Decryption' 'QTI gatekeeper implementation' ($rd.Files.ContainsKey('vendor/lib64/hw/android.hardware.gatekeeper@1.0-impl-qti.so')) 'vendor/lib64/hw'
$man = Get-Text $rd 'vendor/etc/vintf/manifest.xml'
$manVer = if ($man) { ([regex]::Match($man, 'manifest\s+version="([^"]+)"')).Groups[1].Value } else { '' }
Add-Result 'Decryption' 'device VINTF manifest readable by recovery' ([bool]$man -and $manVer -and [double]$manVer -le 4) $(if ($man) { "manifest version $manVer" } else { 'vendor/etc/vintf/manifest.xml not found' })
Add-Result 'Decryption' 'manifest declares keymaster' ([bool]$man -and $man -match 'android\.hardware\.keymaster') ''
Add-Result 'Decryption' 'manifest declares keystore2 (AIDL)' ([bool]$man -and $man -match 'android\.system\.keystore2') ''
$fman = Get-Text $rd 'system/etc/vintf/manifest.xml'
Add-Result 'Decryption' 'framework manifest declares hidl manager' ([bool]$fman -and $fman -match 'android\.hidl\.manager') 'needed by keystore2'

# Titan M (Weaver)
Add-Result 'Titan M' 'Titan M init' ($rd.Files.ContainsKey('init.recovery.titan.rc')) 'init.recovery.titan.rc'
$missing = Get-Missing $rd 'system/bin' @('vndservicemanager', 'citadeld', 'android.hardware.weaver@1.0-service.citadel', 'linker64_a16')
Add-Result 'Titan M' 'services and Android 16 linker' ($missing.Count -eq 0) $(if ($missing) { 'missing: ' + ($missing -join ', ') } else { 'vndservicemanager, citadeld, weaver, linker64_a16' })
$missing = Get-Missing $rd 'system/lib64/a16' @('ld-android.so', 'libc.so', 'libdl.so', 'liblog.so', 'libm.so', 'libbinder_ndk.so', 'libselinux.so', 'libvndksupport.so', 'libpcre2.so', 'libpackagelistparser.so', 'libdl_android.so')
Add-Result 'Titan M' 'Android 16 runtime libraries' ($missing.Count -eq 0) $(if ($missing) { 'missing: ' + ($missing -join ', ') } else { 'system/lib64/a16 (11)' })
Add-Result 'Titan M' 'libapexsupport' ($rd.Files.ContainsKey('vendor/lib64/libapexsupport.so')) 'vendor/lib64'
Add-Result 'Titan M' 'manifest declares weaver' ([bool]$man -and $man -match 'android\.hardware\.weaver') ''
Add-Result 'Titan M' 'manifest declares authsecret' ([bool]$man -and $man -match 'android\.hardware\.authsecret') 'weaver aborts without it'

# Boot control
$bootImpl = 'system/lib64/hw/android.hardware.boot@1.0-impl-1.2-qti.so'
Add-Result 'Boot control' 'QTI boot control 1.2 implementation' ($rd.Files.ContainsKey($bootImpl)) $bootImpl
Add-Result 'Boot control' 'boot HAL service without vendor library path' ($rcText -match '(?m)^service\s+boot-hal-1-2\s+/system/bin/android\.hardware\.boot@1\.2-service') 'init.recovery.bramble.rc'
Add-Result 'Boot control' 'slot count ignores the boot link' (Test-Bytes $rd $bootImpl ([Text.Encoding]::ASCII.GetBytes("`0boot_`0"))) 'BOOT_IMG_PTN_NAME "boot_"'

# Recovery binary
Add-Result 'Recovery' 'battery read from sysfs' (Test-Bytes $rd 'system/bin/recovery' ([Text.Encoding]::ASCII.GetBytes('/sys/class/power_supply/battery/capacity'))) 'TW_USE_LEGACY_BATTERY_SERVICES'
Add-Result 'Recovery' 'bootdevice paths rewritten in ROM fstab' (Test-Bytes $rd 'system/bin/recovery' ([Text.Encoding]::ASCII.GetBytes('Rewrote bootdevice paths'))) 'recovery binary'
Add-Result 'Recovery' 'touch event debug logging off' (-not (Test-Bytes $rd 'system/bin/recovery' ([Text.Encoding]::ASCII.GetBytes('TOUCH_START:')))) 'gui.cpp _EVENT_LOGGING'

# USB
$usb = Get-Text $rd 'init.recovery.usb.rc'
Add-Result 'USB' 'configfs USB gadget' ([bool]$usb -and $usb -match '/config/usb_gadget') ''
Add-Result 'USB' 'MTP function linked in mtp,adb mode' ([bool]$usb -and $usb -match 'functions/mtp\.gs0\s+\S+/configs/b\.1/f') ''

$results | Format-Table -AutoSize Group, Check, Result, Detail | Out-String -Width 200 | Write-Host
$miss = @($results | Where-Object { ($_.Group -eq 'Decryption' -or $_.Group -eq 'Titan M') -and $_.Result -ne 'OK' }).Count
$other = @($results | Where-Object { $_.Group -ne 'Decryption' -and $_.Group -ne 'Titan M' -and $_.Result -ne 'OK' }).Count
if ($miss -eq 0) {
  Write-Host 'RESULT: all decryption and Titan M components present. Check the ROM build with patch-check.ps1 before flashing.' -ForegroundColor Green
} else {
  Write-Host "RESULT: $miss decryption or Titan M component(s) missing; this image is not expected to decrypt /data." -ForegroundColor Yellow
}
if ($other -gt 0) { Write-Host "NOTE: $other other check(s) not OK; see the table above." -ForegroundColor Yellow }
