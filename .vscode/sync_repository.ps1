param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [string]$DestinationPath = ''
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed with exit code $LASTEXITCODE."
    }
}

function Test-RemoteAddress {
    param([string]$Value)
    return $Value -match '^(https?://|git@|ssh://|git://)'
}

try {
    if (Test-RemoteAddress $Repository) {
        if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
            throw 'Specify -DestinationPath to clone a repository.'
        }

        $destination = [System.IO.Path]::GetFullPath($DestinationPath)
        if (Test-Path -LiteralPath $destination) {
            if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                throw "Destination is not a directory: $destination"
            }
            $existing = @(Get-ChildItem -LiteralPath $destination -Force)
            if ($existing.Count -gt 0) {
                throw "Destination directory is not empty: $destination"
            }
        }
        else {
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                throw "Parent directory does not exist: $parent"
            }
        }

        Write-Host "Cloning $Repository into $destination"
        Invoke-Git -Arguments @('clone', '--', $Repository, $destination)
        Write-Host "Clone created: $destination"
        exit 0
    }

    if (-not (Test-Path -LiteralPath $Repository -PathType Container)) {
        throw "Local directory not found: $Repository"
    }

    $repoRoot = & git -C $Repository rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
        throw 'Specified directory is not inside a Git repository.'
    }
    $repoRoot = [System.IO.Path]::GetFullPath($repoRoot.Trim())
    $requestedPath = [System.IO.Path]::GetFullPath($Repository)
    if ($repoRoot.TrimEnd('\') -ne $requestedPath.TrimEnd('\')) {
        throw "Specify the repository root, not a subdirectory. Root: $repoRoot"
    }

    $origin = & git -C $repoRoot remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) {
        throw 'Git remote origin is not configured.'
    }

    $branch = & git -C $repoRoot branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $branch) {
        throw 'Cannot determine current branch (possibly detached HEAD).'
    }
    $branch = $branch.Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw 'Cannot determine current branch (possibly detached HEAD).'
    }

    $changes = @(& git -C $repoRoot status --porcelain --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot check working tree status.'
    }
    if ($changes.Count -gt 0) {
        Write-Host 'Update stopped: working tree has local changes.'
        $changes | ForEach-Object { Write-Host "  $_" }
        throw 'Commit or stash local changes and try again.'
    }

    Write-Host "Updating $repoRoot, branch $branch, remote origin: $($origin.Trim())"
    Invoke-Git -Arguments @('-C', $repoRoot, 'pull', '--ff-only', 'origin', $branch)
    Write-Host "Repository updated: $repoRoot ($branch)"
}
catch {
    Write-Error -ErrorRecord $_
    exit 1
}
