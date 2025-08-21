# Function to output JSON
function Write-JsonLine {
    param (
        [hashtable]$Data
    )
    $Data | ConvertTo-Json -Compress
}

# Function to safely get value or default
function Safe-Value {
    param (
        $Value,
        $Default = 0
    )
    if ($Value -ne $null) {
        return $Value
    } else {
        return $Default
    }
}

$node = $env:COMPUTERNAME

# CPU
Get-WmiObject -Class Win32_Processor | ForEach-Object {
    $load = Safe-Value $_.LoadPercentage
    Write-JsonLine @{
        "hyper-v.metric" = "CPU usage"
        "hyper-v.host" = $node
        "hyper-v.used_percent" = $load
        "hyper-v.free_percent" = 100 - $load
    }
}

# Memory
$mem = Get-WmiObject -Class Win32_OperatingSystem
$total = [math]::Round((Safe-Value $mem.TotalVisibleMemorySize) / 1MB, 2)
$free = [math]::Round((Safe-Value $mem.FreePhysicalMemory) / 1MB, 2)
$used = [math]::Round($total - $free, 2)
$percent = if ($total -ne 0) { [math]::Round(($used / $total) * 100, 2) } else { 0 }
Write-JsonLine @{
    "hyper-v.metric" = "Memory usage"
    "hyper-v.host" = $node
    "hyper-v.used_gb" = $used
    "hyper-v.free_gb" = $free
    "hyper-v.used_percent" = $percent
}

# Disks
Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $total = [math]::Round((Safe-Value $_.Size) / 1GB, 2)
    $free = [math]::Round((Safe-Value $_.FreeSpace) / 1GB, 2)
    $used = [math]::Round($total - $free, 2)
    $percent = if ($total -ne 0) { [math]::Round(($used / $total) * 100, 2) } else { 0 }
    Write-JsonLine @{
        "hyper-v.metric" = "Disk usage"
        "hyper-v.host" = $node
        "hyper-v.drive" = $_.DeviceID
        "hyper-v.used_gb" = $used
        "hyper-v.free_gb" = $free
        "hyper-v.used_percent" = $percent
    }
}

# VMs
Get-VM | ForEach-Object {
    Write-JsonLine @{
        "hyper-v.metric" = "VM state"
        "hyper-v.host" = $node
        "hyper-v.vm_name" = $_.Name
        "hyper-v.state" = $_.State.ToString()
    }
}
