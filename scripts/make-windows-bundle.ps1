# Download embeddable CPython and install bzmap deps into dist/backend.
# Run from the repo root on Windows.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Dist = Join-Path $Root "dist"
$PyDir = Join-Path $Dist "backend\python"
$Version = "3.12.10"
$ZipName = "python-$Version-embed-amd64.zip"
$Url = "https://www.python.org/ftp/python/$Version/$ZipName"

New-Item -ItemType Directory -Force -Path $PyDir | Out-Null
$Zip = Join-Path $Dist $ZipName
if (-not (Test-Path $Zip)) {
    Write-Host "downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Zip
}
Expand-Archive -Path $Zip -DestinationPath $PyDir -Force

# Enable site-packages in the embeddable build.
Get-ChildItem $PyDir -Filter "python*._pth" | ForEach-Object {
    $text = Get-Content $_.FullName
    $text = $text | ForEach-Object { if ($_ -match '^#import site') { 'import site' } else { $_ } }
    if ($text -notcontains "Lib\site-packages") {
        $text += "Lib\site-packages"
    }
    Set-Content $_.FullName $text
}

$GetPip = Join-Path $Dist "get-pip.py"
if (-not (Test-Path $GetPip)) {
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $GetPip
}
$Python = Join-Path $PyDir "python.exe"
& $Python $GetPip
& $Python -m pip install --no-warn-script-location numpy Pillow scipy imageio

$BackendSrc = Join-Path $Root "backend"
$BackendDst = Join-Path $Dist "backend"
New-Item -ItemType Directory -Force -Path $BackendDst | Out-Null
Copy-Item -Recurse -Force (Join-Path $BackendSrc "bzmap") (Join-Path $BackendDst "bzmap")
Copy-Item -Force (Join-Path $BackendSrc "pyproject.toml") (Join-Path $BackendDst "pyproject.toml")
if (Test-Path (Join-Path $BackendSrc "reference")) {
    Copy-Item -Recurse -Force (Join-Path $BackendSrc "reference") (Join-Path $BackendDst "reference")
}

Write-Host "bundled Python is at $PyDir"
Write-Host "export the Godot project to dist/BZ98MapEditor.exe so it sits beside dist/backend/"
