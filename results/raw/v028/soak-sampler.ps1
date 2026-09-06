# soak-sampler.ps1 — the adapter-memory counters every 10 s for the overnight soak (2026-09-06).
# Same line shape as spill-counters-continuous.txt so counters_window.py can read it:
#   HH:MM:SS | <luid4>_phys_0 ded=<MiB> shr=<MiB> com=<MiB> | ... || <nvidia-smi index, used MiB; ...>
param([int]$Hours = 9, [string]$Out = "<workspace>\projects\flightbench\results\raw\v028\spill-counters-soak.txt")
$end = (Get-Date).AddHours($Hours)
Add-Content -Path $Out -Value ("# soak sampler started {0}Z for {1} h" -f (Get-Date).ToUniversalTime().ToString("HH:mm:ss"), $Hours)
while ((Get-Date) -lt $end) {
  try {
    $ded = Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop
    $shr = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop
    $com = Get-Counter '\GPU Adapter Memory(*)\Total Committed' -ErrorAction Stop
    $byInst = @{}
    foreach ($s in $ded.CounterSamples) { $byInst[$s.InstanceName] = @{ ded = $s.CookedValue } }
    foreach ($s in $shr.CounterSamples) { if ($byInst[$s.InstanceName]) { $byInst[$s.InstanceName].shr = $s.CookedValue } }
    foreach ($s in $com.CounterSamples) { if ($byInst[$s.InstanceName]) { $byInst[$s.InstanceName].com = $s.CookedValue } }
    $parts = @()
    foreach ($k in ($byInst.Keys | Sort-Object)) {
      $v = $byInst[$k]
      if ($v.ded -le 0 -and $v.com -le 0) { continue }
      $luid = if ($k -match 'luid_0x[0-9A-Fa-f]+_0x([0-9A-Fa-f]+)_phys_(\d+)') { $matches[1].Substring([Math]::Max(0, $matches[1].Length - 4)) + "_phys_" + $matches[2] } else { $k }
      $parts += ("{0} ded={1} shr={2} com={3}" -f $luid, [int]($v.ded / 1MB), [int]($v.shr / 1MB), [int]($v.com / 1MB))
    }
    $smi = (& nvidia-smi --query-gpu=index,memory.used --format=csv,noheader) -join '; '
    $line = ("{0} | {1} || {2}" -f (Get-Date).ToUniversalTime().ToString("HH:mm:ss"), ($parts -join ' | '), $smi)
    Add-Content -Path $Out -Value $line
  } catch {
    Add-Content -Path $Out -Value ("{0} | sampler error {1}" -f (Get-Date).ToUniversalTime().ToString("HH:mm:ss"), $_.Exception.Message)
  }
  Start-Sleep -Seconds 10
}
Add-Content -Path $Out -Value ("# soak sampler ended {0}Z" -f (Get-Date).ToUniversalTime().ToString("HH:mm:ss"))
