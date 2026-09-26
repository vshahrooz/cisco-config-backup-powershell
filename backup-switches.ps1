# ============================================================
# Cisco Configuration Backup
# Nexus + Catalyst
# Plink + PuTTY Saved Session
# ============================================================

$ErrorActionPreference = "Continue"

# ============================================================
# BASE PATH
# ============================================================

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$PlinkPath = Join-Path $BaseDir "plink.exe"

# ============================================================
# HEADER
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Cisco Configuration Backup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# CHECK PLINK
# ============================================================

if (-not (Test-Path $PlinkPath)) {

    Write-Host "ERROR: plink.exe was not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected:"
    Write-Host $PlinkPath

    exit 1
}

# ============================================================
# USERNAME
# ============================================================

$username = Read-Host "Username"

# ============================================================
# PASSWORD
# ============================================================

$passwordSecure = Read-Host "Enter password" -AsSecureString

$passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
    $passwordSecure
)

$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    $passwordPtr
)

[Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
    $passwordPtr
)

# ============================================================
# SWITCH LIST PATH
# ============================================================

Write-Host ""

$switchListInput = Read-Host "Enter switch list file path (or just filename)"

if ([string]::IsNullOrWhiteSpace($switchListInput)) {

    Write-Host ""
    Write-Host "ERROR: Switch list path cannot be empty." -ForegroundColor Red
    exit 1
}

# If user entered only filename, use script directory
if ([System.IO.Path]::IsPathRooted($switchListInput)) {

    $SwitchList = $switchListInput

}
else {

    $SwitchList = Join-Path $BaseDir $switchListInput
}

# ============================================================
# CHECK SWITCH LIST
# ============================================================

if (-not (Test-Path $SwitchList)) {

    Write-Host ""
    Write-Host "ERROR: Switch list file not found:" -ForegroundColor Red
    Write-Host $SwitchList

    exit 1
}

# ============================================================
# BACKUP FOLDER
# ============================================================

Write-Host ""

$backupFolderInput = Read-Host "Enter save folder path (or just folder name)"

if ([string]::IsNullOrWhiteSpace($backupFolderInput)) {

    Write-Host ""
    Write-Host "ERROR: Backup folder cannot be empty." -ForegroundColor Red
    exit 1
}

# If user entered only folder name, use script directory
if ([System.IO.Path]::IsPathRooted($backupFolderInput)) {

    $BackupFolder = $backupFolderInput

}
else {

    $BackupFolder = Join-Path $BaseDir $backupFolderInput
}

# ============================================================
# CREATE BACKUP FOLDER
# ============================================================

if (-not (Test-Path $BackupFolder)) {

    try {

        New-Item `
            -ItemType Directory `
            -Path $BackupFolder `
            -Force | Out-Null

    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Cannot create backup folder." -ForegroundColor Red
        Write-Host $_.Exception.Message

        exit 1
    }
}

# ============================================================
# LOG FILES
# ============================================================

$ErrorLog = Join-Path $BaseDir "backup_errors.log"

$ResultLog = Join-Path $BaseDir "backup_results.log"

# Clear previous logs
"" | Out-File -FilePath $ErrorLog -Encoding UTF8

"" | Out-File -FilePath $ResultLog -Encoding UTF8

# ============================================================
# READ SWITCH LIST
# ============================================================

$switches = @(
    Get-Content $SwitchList |
    ForEach-Object {
        $_.Trim()
    } |
    Where-Object {
        $_ -ne "" -and
        -not $_.StartsWith("#")
    }
)

$total = $switches.Count

if ($total -eq 0) {

    Write-Host ""
    Write-Host "ERROR: No switches found in:" -ForegroundColor Red
    Write-Host $SwitchList

    exit 1
}

# ============================================================
# INFORMATION
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cisco Configuration Backup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Username       : $username"
Write-Host "Switch list    : $SwitchList"
Write-Host "Backup folder  : $BackupFolder"
Write-Host "Switch count   : $total"
Write-Host "Plink          : $PlinkPath"

Write-Host "========================================" -ForegroundColor Cyan

# ============================================================
# PU TTY SESSION
# ============================================================

$PuttySession = "Cisco-Legacy"

# ============================================================
# COUNTERS
# ============================================================

$success = 0

$failed = 0

$deviceNumber = 0

# ============================================================
# PROCESS SWITCHES
# ============================================================

foreach ($ip in $switches) {

    $deviceNumber++

    Write-Host ""
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    Write-Host "Device $deviceNumber of $total : $ip" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Connecting to $ip" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # --------------------------------------------------------
    # File names
    # --------------------------------------------------------

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    $backupFile = Join-Path `
        $BackupFolder `
        "${ip}_${timestamp}.cfg"

    $rawFile = Join-Path `
        $BackupFolder `
        "_raw_${ip}_${timestamp}.txt"

    # --------------------------------------------------------
    # Plink arguments
    #
    # Legacy SSH settings are taken from:
    # Cisco-Legacy saved PuTTY session
    #
    # DO NOT add:
    # -ssh-rsa
    # -1
    # -hostkey "*"
    # --------------------------------------------------------

    $plinkArgs = @(
        "-load"
        $PuttySession
        "-ssh"
        "-l"
        $username
        "-pw"
        $password
        $ip
    )

    # --------------------------------------------------------
    # Commands
    # --------------------------------------------------------

    $commands = @(
        "terminal length 0"
        "show running-config"
        "exit"
    )

    try {

        Write-Host ""
        Write-Host "Executing configuration backup..." -ForegroundColor Gray

        # ----------------------------------------------------
        # Send commands through STDIN
        #
        # Commands are intentionally separated.
        #
        # This works with both Catalyst and Nexus.
        # ----------------------------------------------------

        $output = $commands |
            & $PlinkPath @plinkArgs 2>&1

        $exitCode = $LASTEXITCODE

        # ----------------------------------------------------
        # Convert output to text
        # ----------------------------------------------------

        $text = (
            $output |
            Out-String
        )

        # ----------------------------------------------------
        # Save raw output
        # ----------------------------------------------------

        $text |
            Out-File `
            -FilePath $rawFile `
            -Encoding UTF8

        # ----------------------------------------------------
        # Show important Plink errors
        # ----------------------------------------------------

        $sshErrors = @(
            "Unable to negotiate"
            "Couldn't agree"
            "Connection refused"
            "Connection timed out"
            "Network error"
            "No route to host"
            "Access denied"
            "Authentication failed"
            "Permission denied"
            "Host does not exist"
            "Connection reset"
        )

        $connectionError = $false

        foreach ($pattern in $sshErrors) {

            if ($text -match [regex]::Escape($pattern)) {

                $connectionError = $true

                Write-Host ""
                Write-Host "SSH ERROR detected: $pattern" -ForegroundColor Red

                Add-Content `
                    -Path $ErrorLog `
                    -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Device=$ip | $pattern"

                break
            }
        }

        # ----------------------------------------------------
        # If real SSH error exists -> FAIL
        # ----------------------------------------------------

        if ($connectionError) {

            Write-Host ""
            Write-Host "FAILED | Device=$ip" -ForegroundColor Red

            Write-Host ""
            Write-Host "Raw output saved to:" -ForegroundColor Yellow
            Write-Host $rawFile

            $failed++

            continue
        }

        # ----------------------------------------------------
        # Detect command errors
        # ----------------------------------------------------

        $commandErrorPatterns = @(
            "Invalid input detected"
            "Invalid command"
            "Unknown command"
            "Incomplete command"
            "Ambiguous command"
            "Syntax error"
            "Cmd exec error"
        )

        $commandError = $false

        foreach ($pattern in $commandErrorPatterns) {

            if ($text -match [regex]::Escape($pattern)) {

                $commandError = $true

                Write-Host ""
                Write-Host "COMMAND ERROR detected: $pattern" -ForegroundColor Red

                Add-Content `
                    -Path $ErrorLog `
                    -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Device=$ip | $pattern"

                break
            }
        }

        if ($commandError) {

            Write-Host ""
            Write-Host "FAILED | Device=$ip" -ForegroundColor Red

            Write-Host ""
            Write-Host "Raw output saved to:" -ForegroundColor Yellow
            Write-Host $rawFile

            $failed++

            continue
        }

        # ----------------------------------------------------
        # Detect actual configuration
        # ----------------------------------------------------

        $configDetected = $false

        $configPatterns = @(
            "Building configuration"
            "Current configuration"
            "version "
            "hostname "
            "interface "
            "feature "
            "vrf context"
            "vlan "
            "router bgp"
            "router ospf"
            "ip route"
            "interface Ethernet"
            "interface GigabitEthernet"
            "interface TenGigabitEthernet"
        )

        foreach ($pattern in $configPatterns) {

            if ($text -match [regex]::Escape($pattern)) {

                $configDetected = $true

                break
            }
        }

        # ----------------------------------------------------
        # Configuration not detected
        # ----------------------------------------------------

        if (-not $configDetected) {

            Write-Host ""
            Write-Host "FAILED | Device=$ip | Running-config not detected" -ForegroundColor Red

            Write-Host ""
            Write-Host "Raw output saved to:" -ForegroundColor Yellow
            Write-Host $rawFile

            Add-Content `
                -Path $ErrorLog `
                -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Device=$ip | Running-config not detected | ExitCode=$exitCode"

            $failed++

            continue
        }

        # ----------------------------------------------------
        # Remove obvious Plink informational lines
        # ----------------------------------------------------

        $configLines = $text -split "`r?`n"

        $cleanLines = New-Object System.Collections.Generic.List[string]

        foreach ($line in $configLines) {

            # Skip Plink keyboard-interactive informational text
            if ($line -match "^-- Keyboard-interactive authentication prompts") {
                continue
            }

            if ($line -match "^Access granted\. Press Return to begin session") {
                continue
            }

            if ($line -match "^-- End of keyboard-interactive prompts") {
                continue
            }

            $cleanLines.Add($line)
        }

        $cleanText = $cleanLines -join [Environment]::NewLine

        # ----------------------------------------------------
        # Save configuration
        # ----------------------------------------------------

        $cleanText |
            Out-File `
            -FilePath $backupFile `
            -Encoding UTF8

        # ----------------------------------------------------
        # SUCCESS
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "SUCCESS | Device=$ip" -ForegroundColor Green

        Write-Host "Backup file:"
        Write-Host $backupFile -ForegroundColor Green

        if ($exitCode -ne 0) {

            Write-Host ""
            Write-Host "Note: Plink returned ExitCode=$exitCode, but configuration was detected and saved." -ForegroundColor DarkYellow
        }

        Add-Content `
            -Path $ResultLog `
            -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | SUCCESS | Device=$ip | File=$backupFile | ExitCode=$exitCode"

        $success++

        # ----------------------------------------------------
        # Remove raw file after successful backup
        # ----------------------------------------------------

        if (Test-Path $rawFile) {

            Remove-Item `
                $rawFile `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
    catch {

        Write-Host ""
        Write-Host "FAILED | Device=$ip" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        Add-Content `
            -Path $ErrorLog `
            -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Device=$ip | Exception=$($_.Exception.Message)"

        $failed++
    }
}

# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Backup process completed!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Total switches : $total"
Write-Host "Successful     : $success" -ForegroundColor Green
Write-Host "Failed         : $failed" -ForegroundColor Red

Write-Host ""
Write-Host "Backup folder:"
Write-Host $BackupFolder

Write-Host ""
Write-Host "Error log:"
Write-Host $ErrorLog

Write-Host ""
Write-Host "Result log:"
Write-Host $ResultLog

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan