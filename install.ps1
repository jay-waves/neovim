# Compatible with Windows PowerShell 5.1 and PowerShell 7; requires git.
& {
    $ErrorActionPreference = 'Stop'
    $null = Get-Command git -CommandType Application -ErrorAction Stop
    $appName = if ($env:NVIM_APPNAME) { $env:NVIM_APPNAME } else { 'nvim' }
    if ($appName -in '.', '..' -or $appName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $appName -match '[/\\]') {
        throw 'NVIM_APPNAME must be a directory name.'
    }
    $configRoot = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { $env:LOCALAPPDATA }
    if (-not $configRoot) { throw 'LOCALAPPDATA or XDG_CONFIG_HOME must be set.' }
    $target = [IO.Path]::GetFullPath((Join-Path $configRoot $appName))
    $parent = Split-Path -Parent $target
    $null = [IO.Directory]::CreateDirectory($parent)
    $stage = Join-Path $parent ('.nvim-install.' + [guid]::NewGuid().ToString('N'))
    $checkout = Join-Path $stage 'config'
    $backup = $null
    $installed = $false
    try {
        $null = [IO.Directory]::CreateDirectory($stage)
        & git clone --depth 1 --single-branch --branch main https://github.com/jay-waves/neovim.git $checkout
        if ($LASTEXITCODE -ne 0) { throw "git clone failed ($LASTEXITCODE)." }
        if (-not (Test-Path -LiteralPath (Join-Path $checkout 'init.lua') -PathType Leaf)) {
            throw 'Downloaded configuration is missing init.lua.'
        }
        if (Test-Path -LiteralPath $target) {
            $backup = $target + '.backup.' + (Get-Date -Format 'yyyyMMddHHmmss') + '.' + [guid]::NewGuid().ToString('N')
            [IO.Directory]::Move($target, $backup)
            Write-Host "Backup: $backup"
        }
        [IO.Directory]::Move($checkout, $target)
        $installed = $true
        Write-Host "Installed main: $target"
    }
    finally {
        if (-not $installed -and $backup -and -not (Test-Path -LiteralPath $target)) {
            [IO.Directory]::Move($backup, $target)
        }
        if (Test-Path -LiteralPath $stage) {
            # stage is an absolute, uniquely generated child of the config parent.
            Remove-Item -LiteralPath $stage -Recurse -Force
        }
    }
}
