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
            throw 'Для клонирования укажите -DestinationPath.'
        }

        $destination = [System.IO.Path]::GetFullPath($DestinationPath)
        if (Test-Path -LiteralPath $destination) {
            if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                throw "Путь назначения не является папкой: $destination"
            }
            $existing = @(Get-ChildItem -LiteralPath $destination -Force)
            if ($existing.Count -gt 0) {
                throw "Папка назначения уже существует и не пуста: $destination"
            }
        }
        else {
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                throw "Родительская папка не существует: $parent"
            }
        }

        Write-Host "Клонирование $Repository в $destination"
        Invoke-Git -Arguments @('clone', '--', $Repository, $destination)
        Write-Host "Клон создан: $destination"
        exit 0
    }

    if (-not (Test-Path -LiteralPath $Repository -PathType Container)) {
        throw "Локальная папка не найдена: $Repository"
    }

    $repoRoot = & git -C $Repository rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
        throw 'Указанная папка не находится внутри Git-репозитория.'
    }
    $repoRoot = [System.IO.Path]::GetFullPath($repoRoot.Trim())
    $requestedPath = [System.IO.Path]::GetFullPath($Repository)
    if ($repoRoot.TrimEnd('\') -ne $requestedPath.TrimEnd('\')) {
        throw "Укажите корень репозитория, а не вложенную папку. Корень: $repoRoot"
    }

    $origin = & git -C $repoRoot remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) {
        throw 'У репозитория не настроен remote origin.'
    }

    $branch = & git -C $repoRoot branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $branch) {
        throw 'Не удалось определить текущую ветку. Возможно, репозиторий находится в detached HEAD.'
    }
    $branch = $branch.Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw 'Не удалось определить текущую ветку. Возможно, репозиторий находится в detached HEAD.'
    }

    $changes = @(& git -C $repoRoot status --porcelain --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) {
        throw 'Не удалось проверить состояние рабочей копии.'
    }
    if ($changes.Count -gt 0) {
        Write-Host 'Обновление остановлено: в рабочей копии есть локальные изменения.'
        $changes | ForEach-Object { Write-Host "  $_" }
        throw 'Сохраните изменения самостоятельно и повторите запрос.'
    }

    Write-Host "Обновление $repoRoot, ветка $branch, remote origin: $($origin.Trim())"
    Invoke-Git -Arguments @('-C', $repoRoot, 'pull', '--ff-only', 'origin', $branch)
    Write-Host "Репозиторий обновлён: $repoRoot ($branch)"
}
catch {
    Write-Error -ErrorRecord $_
    exit 1
}
