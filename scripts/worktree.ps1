<#
.SYNOPSIS
    Manages git worktrees across multiple repositories.

.DESCRIPTION
    Creates or removes git worktrees for a given branch across multiple repositories.
    Worktrees are placed at <OutputPath>\<Branch>\<RepoFolderName>.

.PARAMETER Action
    The action to perform: 'add' to create worktrees, 'remove' to delete them.

.PARAMETER Branch
    The branch name to create/checkout in each worktree.

.PARAMETER Repos
    Array of paths to git repositories. Required for 'add'; optional for 'remove' (will auto-discover from worktrees).

.PARAMETER OutputPath
    Base directory where worktrees will be placed.

.EXAMPLE
    .\worktree.ps1 -Action add -Branch feature/my-work -Repos C:\src\repo1,C:\src\repo2 -OutputPath C:\worktrees

.EXAMPLE
    .\worktree.ps1 -Action remove -Branch feature/my-work -Repos C:\src\repo1,C:\src\repo2 -OutputPath C:\worktrees

.EXAMPLE
    .\worktree.ps1 -Action remove -Branch feature/my-work -OutputPath C:\worktrees
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('add', 'remove')]
    [string] $Action,

    [Parameter(Mandatory)]
    [Alias('b')]
    [string] $Branch,

    [Parameter()]
    [Alias('r')]
    [string[]] $Repos,

    [Parameter(Mandatory)]
    [Alias('o')]
    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Validate mandatory params
if ($Action -eq 'add' -and -not $Repos) {
    throw "'-Repos' is required for 'add' action."
}

# Counters for summary
$created = 0
$removed = 0
$skipped = 0
$failed  = 0

function Test-GitRepo([string] $Path) {
    return (Test-Path (Join-Path $Path '.git'))
}

function Get-RepoName([string] $Path) {
    return (Get-Item $Path).Name
}

function Get-MainRepoFromWorktree([string] $WorktreePath) {
    $gitFile = Join-Path $WorktreePath '.git'
    if (-not (Test-Path $gitFile)) {
        return $null
    }

    $content = Get-Content $gitFile -Raw
    if ($content -match 'gitdir:\s*(.+)') {
        $gitdirPath = $matches[1].Trim()
        # gitdir is typically: /path/to/mainrepo/.git/worktrees/worktreename
        # We need: /path/to/mainrepo
        $resolved = Resolve-Path $gitdirPath -ErrorAction SilentlyContinue
        if ($resolved) {
            # Go up to .git, then up one more level to the repo root
            $gitDir = Split-Path $resolved -Parent  # Remove /worktrees/name
            $gitDir = Split-Path $gitDir -Parent    # Remove /worktrees
            $repoRoot = Split-Path $gitDir -Parent  # Remove /.git
            return $repoRoot
        }
    }
    return $null
}

# Auto-discover repos if remove action and no repos specified
if ($Action -eq 'remove' -and -not $Repos) {
    $branchPath = Join-Path $OutputPath $Branch
    if (Test-Path $branchPath) {
        $worktrees = @(Get-ChildItem $branchPath -Directory -ErrorAction SilentlyContinue)
        if ($worktrees.Count -gt 0) {
            $discoveredRepos = @()
            foreach ($wt in $worktrees) {
                $mainRepo = Get-MainRepoFromWorktree $wt.FullName
                if ($mainRepo) {
                    $discoveredRepos += $mainRepo
                }
            }
            if ($discoveredRepos.Count -gt 0) {
                $Repos = @($discoveredRepos | Select-Object -Unique)
                Write-Verbose "Auto-discovered repos: $($Repos -join ', ')"
            }
        }
    }
}

# If still no repos after discovery, error
if (-not $Repos) {
    if ($Action -eq 'remove') {
        throw "No worktrees found at $(Join-Path $OutputPath $Branch) to remove."
    } else {
        throw "No repositories specified and none could be discovered."
    }
}

# Ensure output path exists when adding
if ($Action -eq 'add' -and -not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
    Write-Verbose "Created output directory: $OutputPath"
}

foreach ($repoPath in $Repos) {
    $repoPath = $repoPath.TrimEnd('\', '/')
    $repoName = ''

    # Validate repo
    if (-not (Test-Path $repoPath)) {
        Write-Warning "Path does not exist, skipping: $repoPath"
        $skipped++
        continue
    }
    if (-not (Test-GitRepo $repoPath)) {
        Write-Warning "Not a git repository, skipping: $repoPath"
        $skipped++
        continue
    }

    $repoName = Get-RepoName $repoPath
    $worktreeDest = Join-Path $OutputPath $Branch $repoName

    try {
        Push-Location $repoPath

        if ($Action -eq 'add') {
            if (Test-Path $worktreeDest) {
                Write-Warning "[$repoName] Worktree destination already exists, skipping: $worktreeDest"
                $skipped++
                continue
            }

            # -B creates or resets the branch; --force bypasses the "already checked out" prompt
            if ($PSCmdlet.ShouldProcess("$repoName", "git worktree add --force -B '$Branch' '$worktreeDest'")) {
                git worktree add --force -B $Branch $worktreeDest 2>&1 | Write-Verbose
                if ($LASTEXITCODE -ne 0) {
                    throw "git worktree add failed (exit code $LASTEXITCODE)"
                }
                Write-Host "[$repoName] Worktree created at: $worktreeDest" -ForegroundColor Green
                $created++
            }
        }
        elseif ($Action -eq 'remove') {
            if (-not (Test-Path $worktreeDest)) {
                Write-Warning "[$repoName] Worktree folder not found, skipping: $worktreeDest"
                $skipped++
                continue
            }

            if ($PSCmdlet.ShouldProcess("$repoName", "git worktree remove '$worktreeDest'")) {
                git worktree remove $worktreeDest --force 2>&1 | Write-Verbose
                if ($LASTEXITCODE -ne 0) {
                    throw "git worktree remove failed (exit code $LASTEXITCODE)"
                }
                Write-Host "[$repoName] Worktree removed: $worktreeDest" -ForegroundColor Green
                $removed++
            }
        }
    }
    catch {
        Write-Warning "[$repoName] Error: $_"
        $failed++
    }
    finally {
        Pop-Location
    }
}

# Clean up empty directories after removal
if ($Action -eq 'remove' -and $removed -gt 0) {
    $branchPathNormalized = Join-Path $OutputPath ($Branch -replace '/', '\')
    
    # Remove branch directory if empty
    if ((Test-Path $branchPathNormalized) -and @(Get-ChildItem $branchPathNormalized -Force).Count -eq 0) {
        Remove-Item $branchPathNormalized -Force
        Write-Host "Removed empty directory: $branchPathNormalized" -ForegroundColor Green
    }
    
    # Remove parent directory if empty
    $parentPath = Split-Path $branchPathNormalized -Parent
    if ((Test-Path $parentPath) -and @(Get-ChildItem $parentPath -Force).Count -eq 0) {
        Remove-Item $parentPath -Force
        Write-Host "Removed empty directory: $parentPath" -ForegroundColor Green
    }
}

# Summary
Write-Host ''
Write-Host '--- Summary ---' -ForegroundColor Cyan
if ($Action -eq 'add') {
    Write-Host "  Created : $created" -ForegroundColor Green
} else {
    Write-Host "  Removed : $removed" -ForegroundColor Green
}
Write-Host "  Skipped : $skipped" -ForegroundColor Yellow
Write-Host "  Failed  : $failed"  -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Gray' })
