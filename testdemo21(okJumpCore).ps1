$Logfile = "C:\activity(testdemo21).log"
Clear-Content -Path $LogFile -ErrorAction SilentlyContinue
	function WriteLog {
		Param ([string]$LogString)
		$Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
		$LogMessage = "$Stamp $LogString"
		Add-content $LogFile -value $LogMessage 
}
#CONTROL ON EACH CORE

#For each process, the script checks if it is exceeding 80% usage on any core.
#If it is, it attempts to assign an additional available core to distribute the load.


# get the CPU usage of each oracle.exe process
function Get-OracleCPUUsage {
    $cpuUsages = @{}
    $oracleProcesses = Get-Process oracle -ErrorAction SilentlyContinue
    foreach ($process in $oracleProcesses) {
        $startCPU = $process.TotalProcessorTime
        Start-Sleep -Milliseconds 500
        $endCPU = $process.TotalProcessorTime
        $cpuUsage = (($endCPU - $startCPU).TotalMilliseconds / 500) * 100 / $env:NUMBER_OF_PROCESSORS
        $cpuUsages[$process.Id] = $cpuUsage
    }
    return $cpuUsages
}

# set CPU affinity for oracle.exe processes
function Set-CPUAffinity {
    param (
        [int]$processId,
        [int]$coreIndex
    )

    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process) {
        $affinityMask = [math]::Pow(2, $coreIndex)
        $process.ProcessorAffinity = [convert]::ToInt32($affinityMask)
        Write-Host "Set CPU affinity for process $($process.Id) to core $coreIndex."
        WriteLog "Set CPU affinity for process $($process.Id) to core $coreIndex."
    } else {
        Write-Host "Process with ID $processId not found."
        WriteLog "Process with ID $processId not found."
    }
}

#convert integer affinity mask to binary string
function ConvertTo-BinaryString {
    param (
        [int]$number,
        [int]$length
    )
    return [System.Convert]::ToString($number, 2).PadLeft($length, '0')
}

# get the current affinity mask of a process
function Get-CPUAffinity {
    param (
        [int]$processId
    )

    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process) {
        $affinity = ConvertTo-BinaryString -number $process.ProcessorAffinity -length $env:NUMBER_OF_PROCESSORS
        return $affinity
    } else {
        return "Process with ID $processId not found."
    }
}

# get the next available core index
function Get-NextAvailableCore {
    param (
        [array]$usedCores,
        [int]$totalCores
    )

    for ($i = 0; $i -lt $totalCores; $i++) {
        if ($usedCores -notcontains $i) {
            return $i
        }
    }
    return $null
}
#main
while ($true) {
    $cpuUsages = Get-OracleCPUUsage
    $usedCores = @()

    foreach ($processId in $cpuUsages.Keys) {
        $cpuUsage = $cpuUsages[$processId]
        $currentAffinity = Get-CPUAffinity -processId $processId
        Write-Host "Process $processId is using $cpuUsage% CPU, current affinity mask: $currentAffinity"
        WriteLog "Process $processId is using $cpuUsage% CPU, current affinity mask: $currentAffinity"

        if ($cpuUsage -gt 15) {
            Write-Host "Process $processId is using $cpuUsage% CPU, setting affinity to limit CPU usage."
            WriteLog "Process $processId is using $cpuUsage% CPU, setting affinity to limit CPU usage."
            # Get the next available core index
            $coreIndex = Get-NextAvailableCore -usedCores $usedCores -totalCores $env:NUMBER_OF_PROCESSORS
            if ($coreIndex -ne $null) {
                Set-CPUAffinity -processId $processId -coreIndex $coreIndex
                $usedCores += $coreIndex
            } else {
                Write-Host "No available cores to assign."
            }
        } else {
            $currentCore = [convert]::ToInt32($currentAffinity, 2)
            for ($i = 0; $i -lt $env:NUMBER_OF_PROCESSORS; $i++) {
                if (($currentCore -band [math]::Pow(2, $i)) -ne 0) {
                    $usedCores += $i
                }
            }
        }
    }

    # Check if any process is exceeding 80% of the core and adjust if necessary
    foreach ($processId in $cpuUsages.Keys) {
        $cpuUsage = $cpuUsages[$processId]
        $currentAffinity = Get-CPUAffinity -processId $processId
        $currentCore = [convert]::ToInt32($currentAffinity, 2)
        for ($i = 0; $i -lt $env:NUMBER_OF_PROCESSORS; $i++) {
            if (($currentCore -band [math]::Pow(2, $i)) -ne 0) {
                $coreUsage = ($cpuUsage / [math]::Pow(2, $i)) * 100
                if ($coreUsage -gt 80) {
                    Write-Host "Process $processId is exceeding 80% on core $i, adjusting affinity."    #(!!!) check if works --doesnt--
                    WriteLog "Process $processId is exceeding 80% on core $i, adjusting affinity."
                    $coreIndex = Get-NextAvailableCore -usedCores $usedCores -totalCores $env:NUMBER_OF_PROCESSORS
                    if ($coreIndex -ne $null) {
                        Set-CPUAffinity -processId $processId -coreIndex $coreIndex
                        $usedCores += $coreIndex
                    } else {
                        Write-Host "No available cores to assign."
                        WriteLog "No available cores to assign."
                    }
                }
            }
        }
    }

   
    Start-Sleep -Seconds 3
}
