param([ValidateSet('x64','arm64')][string]$Architecture)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$version = [IO.File]::ReadAllText((Join-Path $repoRoot 'VERSION')).Trim()
$runtime = 'win-' + $Architecture
$outputPath = Join-Path $repoRoot ('dist\FourGSwitch-' + $version + '-' + $runtime)
dotnet publish (Join-Path $repoRoot 'windows\FourGSwitch.csproj') -c Release -r $runtime --self-contained true -o $outputPath
if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }
$appPath = Join-Path $outputPath 'FourGSwitch.exe'
$resultPath = Join-Path $outputPath 'self-test-result.txt'
Start-Process -FilePath $appPath -ArgumentList @('--self-test', ('"' + $resultPath + '"')) -WindowStyle Hidden -Wait
if (-not (Test-Path -LiteralPath $resultPath) -or -not ([IO.File]::ReadAllText($resultPath).StartsWith('PASS:'))) {
    Get-ChildItem -LiteralPath $outputPath -Filter '*.error.txt' | ForEach-Object { Get-Content -LiteralPath $_.FullName }
    throw 'Native architecture self-test failed.'
}
$stream = [IO.File]::OpenRead($appPath)
try {
    $reader = [IO.BinaryReader]::new($stream)
    $stream.Position = 0x3c
    $peOffset = $reader.ReadInt32()
    $stream.Position = $peOffset + 4
    $machine = $reader.ReadUInt16()
    $expected = if ($Architecture -eq 'arm64') { 0xaa64 } else { 0x8664 }
    if ($machine -ne $expected) { throw "Wrong PE architecture: $machine" }
} finally { $stream.Dispose() }
Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination $outputPath
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $outputPath 'LICENSE-app.txt')
Copy-Item -LiteralPath (Join-Path $repoRoot 'third_party\NOTICES.md') -Destination (Join-Path $outputPath 'THIRD-PARTY-NOTICES.md')
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dotnet/runtime/v10.0.0/LICENSE.TXT' -OutFile (Join-Path $outputPath 'LICENSE-dotnet.txt')
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dotnet/runtime/v10.0.0/THIRD-PARTY-NOTICES.TXT' -OutFile (Join-Path $outputPath 'THIRD-PARTY-NOTICES-dotnet.txt')
Compress-Archive -Path (Join-Path $outputPath '*') -DestinationPath ($outputPath + '.zip') -Force
