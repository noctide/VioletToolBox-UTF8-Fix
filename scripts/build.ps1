<#
.SYNOPSIS
    克隆上游 VioletToolBox、应用 UTF-8 修复补丁并构建

.DESCRIPTION
    1. 克隆 Smart-Paocai/VioletToolBox
    2. 切换到补丁对应的上游 commit
    3. 应用 patch/0001-fix-utf8-adb-output.patch
    4. dotnet publish 生成单文件版本

.NOTES
    需要 .NET 8 SDK（或更高版本 SDK）
    需要 git
#>
[CmdletBinding()]
param(
    [string]$WorkDir = "$PSScriptRoot\..\build",
    [string]$UpstreamUrl = "https://github.com/Smart-Paocai/VioletToolBox.git",
    [string]$UpstreamCommit = "153a0d13a0ae855c3e682bf281940e691ef22f21",
    [string]$PatchFile = "$PSScriptRoot\..\patch\0001-fix-utf8-adb-output.patch",
    [string]$OutDir = "$PSScriptRoot\..\out"
)

$ErrorActionPreference = 'Stop'
function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

# 检查工具
foreach ($tool in @('git','dotnet')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "缺少依赖：$tool"
    }
}

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$srcDir = Join-Path $WorkDir 'VioletToolBox'

Step "克隆上游"
if (Test-Path (Join-Path $srcDir '.git')) {
    Push-Location $srcDir
    try { & git fetch --all --tags; & git checkout $UpstreamCommit } finally { Pop-Location }
} else {
    & git clone $UpstreamUrl $srcDir
    Push-Location $srcDir
    try { & git checkout $UpstreamCommit } finally { Pop-Location }
}

Step "应用补丁"
Push-Location $srcDir
try {
    $check = & git apply --check $PatchFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "补丁可能已应用或冲突，尝试反向检查..." -ForegroundColor Yellow
        & git apply --reverse --check $PatchFile 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "补丁已应用，跳过" -ForegroundColor Green
        } else {
            throw "补丁应用失败：$check"
        }
    } else {
        & git apply $PatchFile
        Write-Host "补丁应用成功" -ForegroundColor Green
    }
} finally { Pop-Location }

Step "校验修复代码"
$cs = Join-Path $srcDir 'VioletToolBox\MainWindow.xaml.cs'
if (-not (Select-String -Path $cs -Pattern 'StandardOutputEncoding = new UTF8Encoding\(false\)' -Quiet)) {
    throw "源码中未找到修复代码，补丁可能未正确应用"
}
Write-Host "修复代码已确认存在" -ForegroundColor Green

Step "构建"
Push-Location $srcDir
try {
    & dotnet build "VioletToolBox\SmartTool.csproj" -c Release
    if ($LASTEXITCODE -ne 0) { throw "编译失败" }
} finally { Pop-Location }

Step "发布单文件"
Push-Location $srcDir
try {
    & dotnet publish "VioletToolBox\SmartTool.csproj" -c Release -r win-x64 `
        --self-contained false -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true -o $OutDir
    if ($LASTEXITCODE -ne 0) { throw "发布失败" }
} finally { Pop-Location }

$exe = Join-Path $OutDir 'VioletToolBox.exe'
if (Test-Path $exe) {
    Write-Host "`n构建成功: $exe" -ForegroundColor Green
    Write-Host ("大小  : {0:N1} MB" -f ((Get-Item $exe).Length/1MB))
    Write-Host ("SHA256: {0}" -f (Get-FileHash $exe -Algorithm SHA256).Hash)
} else {
    throw "未找到产物 VioletToolBox.exe"
}
