[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-SemVer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionText
    )

    $cleanVersion = $VersionText.TrimStart('v').Trim()
    $match = [regex]::Match($cleanVersion, '^(\d+)\.(\d+)\.(\d+)')

    if (-not $match.Success) {
        throw "Não foi possível interpretar a versão semântica: $VersionText"
    }

    return [PSCustomObject]@{
        Major = [int]$match.Groups[1].Value
        Minor = [int]$match.Groups[2].Value
        Patch = [int]$match.Groups[3].Value
        Text  = "$($match.Groups[1].Value).$($match.Groups[2].Value).$($match.Groups[3].Value)"
    }
}

function Get-HighestMinorForMajor {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Major
    )

    $versions = choco search nodejs --exact --all-versions --limit-output 2>$null |
        ForEach-Object {
            $parts = $_ -split '\|'
            if ($parts.Length -ge 2 -and $parts[0] -eq 'nodejs') {
                try {
                    Get-SemVer -VersionText $parts[1]
                }
                catch {
                    $null
                }
            }
        } |
        Where-Object { $_ -and $_.Major -eq $Major }

    if (-not $versions) {
        return $null
    }

    return $versions |
        Sort-Object Major, Minor, Patch |
        Select-Object -Last 1
}

function Install-Chocolatey {
    Write-Host 'Chocolatey não encontrado. Tentando instalar...' -ForegroundColor Yellow

    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    $installScript = Invoke-WebRequest 'https://community.chocolatey.org/install.ps1' -UseBasicParsing
    Invoke-Expression $installScript.Content

    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')

    $installedChoco = Get-Command choco -ErrorAction SilentlyContinue
    if (-not $installedChoco) {
        throw 'Falha ao instalar o Chocolatey. Execute o script como Administrador e tente novamente.'
    }

    Write-Host 'Chocolatey instalado com sucesso.' -ForegroundColor Green
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCommand) {
    Write-Host 'Node.js não está instalado neste Windows.' -ForegroundColor Yellow
    exit 0
}

$currentVersionText = node --version
$currentVersion = Get-SemVer -VersionText $currentVersionText
Write-Host "Node.js instalado. Versão atual: v$($currentVersion.Text)" -ForegroundColor Green

$chocoCommand = Get-Command choco -ErrorAction SilentlyContinue
if (-not $chocoCommand) {
    Install-Chocolatey
}

$targetVersion = Get-HighestMinorForMajor -Major $currentVersion.Major
if (-not $targetVersion) {
    throw "Não foi possível descobrir a última versão minor para a major $($currentVersion.Major) via Chocolatey."
}

if ($targetVersion.Minor -eq $currentVersion.Minor -and $targetVersion.Patch -le $currentVersion.Patch) {
    Write-Host "Node.js já está na versão minor mais recente da major $($currentVersion.Major): v$($currentVersion.Text)." -ForegroundColor Cyan
    exit 0
}

Write-Host "Atualizando Node.js para a última minor disponível da major $($currentVersion.Major): v$($targetVersion.Text)" -ForegroundColor Cyan

choco upgrade nodejs --version $targetVersion.Text -y

Write-Host 'Atualização finalizada.' -ForegroundColor Green
