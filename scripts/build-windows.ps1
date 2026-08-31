param(
    [ValidatePattern('^[0-9]+(\.[0-9]+){0,2}$')]
    [string]$Version = '0.2.0'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'windows/CodexQuota.Windows/CodexQuota.Windows.csproj'
$dist = Join-Path $root 'dist'
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-quota-windows-" + [guid]::NewGuid().ToString('N'))

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'Required tool not found: dotnet'
}
if (-not (Test-Path $project -PathType Leaf)) {
    throw "Missing Windows project: $project"
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null
New-Item -ItemType Directory -Force -Path $stage | Out-Null

try {
    foreach ($architecture in @('x64', 'arm64')) {
        $runtime = "win-$architecture"
        $output = Join-Path $stage $runtime
        dotnet publish $project `
            --configuration Release `
            --runtime $runtime `
            --self-contained true `
            -p:PublishSingleFile=true `
            -p:IncludeNativeLibrariesForSelfExtract=true `
            -p:DebugType=None `
            -p:DebugSymbols=false `
            -p:Version=$Version `
            --output $output

        $executable = Join-Path $output 'CodexQuota.exe'
        if (-not (Test-Path $executable -PathType Leaf)) {
            throw "Windows executable was not produced for $runtime"
        }

        $archiveName = "Codex-Quota-v$Version-Windows-$architecture.zip"
        $archive = Join-Path $dist $archiveName
        $checksum = "$archive.sha256"
        Remove-Item -Force -ErrorAction SilentlyContinue $archive, $checksum
        Compress-Archive -Path (Join-Path $output '*') -DestinationPath $archive
        $hash = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
        Set-Content -Encoding ascii -NoNewline -Path $checksum -Value "$hash  $archiveName`n"
        Write-Output $archive
    }
}
finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $stage
}
