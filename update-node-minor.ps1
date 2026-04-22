[CmdletBinding()]
param(
    [string]$DownloadDir = "$env:TEMP"
)

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

function Get-NodeMsiArchitecture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeArch
    )

    switch ($NodeArch) {
        'x64'  { return 'x64' }
        'ia32' { return 'x86' }
        default {
            throw "Arquitetura do Node.js não suportada para MSI Windows: $NodeArch"
        }
    }
}

function Get-LatestNodeVersionForMajor {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Major,
        [Parameter(Mandatory = $true)]
        [string]$MsiArch
    )

    $requiredFileTag = "win-$MsiArch-msi"
    $allVersions = Invoke-RestMethod 'https://nodejs.org/dist/index.json'

    $candidate = $allVersions |
        Where-Object {
            $_.version -match "^v$Major\." -and
            $_.files -contains $requiredFileTag
        } |
        Select-Object -First 1

    if (-not $candidate) {
        throw "Não foi encontrada versão em https://nodejs.org/dist/latest-v$Major.x/ para arquitetura $MsiArch."
    }

    return $candidate.version
}

function Test-IsVersionGreater {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Left,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Right
    )

    if ($Left.Major -ne $Right.Major) { return $Left.Major -gt $Right.Major }
    if ($Left.Minor -ne $Right.Minor) { return $Left.Minor -gt $Right.Minor }
    return $Left.Patch -gt $Right.Patch
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCommand) {
    Write-Host 'Node.js não está instalado neste Windows.' -ForegroundColor Yellow
    exit 0
}

$currentVersionText = node --version
$currentVersion = Get-SemVer -VersionText $currentVersionText
Write-Host "Node.js instalado. Versão atual: v$($currentVersion.Text)" -ForegroundColor Green

$nodeArch = node -p "process.arch"
$msiArch = Get-NodeMsiArchitecture -NodeArch $nodeArch
Write-Host "Arquitetura detectada do Node.js: $nodeArch (MSI: $msiArch)" -ForegroundColor Green

$latestVersionTag = Get-LatestNodeVersionForMajor -Major $currentVersion.Major -MsiArch $msiArch
$latestVersion = Get-SemVer -VersionText $latestVersionTag

if (-not (Test-IsVersionGreater -Left $latestVersion -Right $currentVersion)) {
    Write-Host "Node.js já está na versão minor mais recente da major $($currentVersion.Major): v$($currentVersion.Text)." -ForegroundColor Cyan
    exit 0
}

$downloadBaseUrl = "https://nodejs.org/dist/latest-v$($currentVersion.Major).x"
$msiFileName = "node-$latestVersionTag-$msiArch.msi"
$msiUrl = "$downloadBaseUrl/$msiFileName"
$msiPath = Join-Path $DownloadDir $msiFileName

Write-Host "Baixando MSI: $msiUrl" -ForegroundColor Cyan
Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath

Write-Host "Instalando Node.js com MSI: $msiPath" -ForegroundColor Cyan
$process = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -PassThru

if ($process.ExitCode -ne 0) {
    throw "Falha na instalação MSI. ExitCode: $($process.ExitCode)"
}

Write-Host "Atualização concluída para $latestVersionTag ($msiArch)." -ForegroundColor Green
