function Get-PublicIp { Invoke-RestMethod -Uri 'https://api.ipify.org' }

function Reset-Explorer {
    Stop-Process -Name 'explorer' -Force
}

function Start-EdgeRestore {
    & "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --restore-last-session
}

Set-Alias er Start-EdgeRestore

# -----------------------------------------------
# Schneider Electric Proxy Settings
# -----------------------------------------------

function Set-SeProxy-Office{
    write-host "Setting office..."
    $proxyUrl = 'http://gateway.schneider.zscaler.net:9480'
    Set-SeProxy($proxyUrl)
}

function Set-SeProxy-Home {
    write-host "Setting home..."
    $proxyUrl = 'http://127.0.0.1:9000'
    Set-SeProxy($proxyUrl)
}

function Set-SeProxy {
    param(
    [Parameter(Mandatory = $true)]
    [string]$proxyUrl)

    # # no_proxy needed for e.g. Selenium to start the ChromeDriver when proxy is set
    $noProxy = 'localhost,127.0.0.0/8,::1,.schneider-electric.com,10.0.0.0/8' 
    setx NO_PROXY $noProxy

    # http_proxy needed for Cypress to run correctly, for some reason it's not picking up https_proxy
    setx HTTP_PROXY $proxyUrl

    # https_proxy set just for the sake of it, see http_proxy for Cypress specifics
    setx HTTPS_PROXY $proxyUrl

    $zscalerCertPath = "$env:userprofile\zscaler.cer"
    if (!(test-path -path $zscalerCertPath)) {
        Write-Host -ForegroundColor Red "Warning, the '$zscalerCertPath' file does not exist." `
            "Search for the file name on the wiki to find out how to get a hold of it." 
      }
    # I've tried to get this to work with both yarn's config for caFilePath and httpsCertFilePath but no luck
    # Leaving like this for now, it works :)
    # Looks to be an issue on yarn: https://github.com/yarnpkg/berry/issues/2250
    setx NODE_EXTRA_CA_CERTS $zscalerCertPath

    # Git picks up from environment variables, but smoother to not have to restart all applications -> setting explicitly too
    git config --global https.proxy $proxyUrl
    git config --global http.proxy $proxyUrl

    Reset-Explorer

    write-host "Done!"
    write-host "Remember that some applications (eg the terminal) need a restart to use the updated environment variables."
}

# Helper function to 'clear all possible settings'
function Clear-SeProxy {
    # # global environment variable (user)
    REG delete HKCU\Environment /F /V HTTPS_PROXY
    REG delete HKCU\Environment /F /V HTTP_PROXY
    REG delete HKCU\Environment /F /V NO_PROXY
    REG delete HKCU\Environment /F /V NODE_EXTRA_CA_CERTS

    git config --global --unset https.proxy
    git config --global --unset http.proxy
    git config --global --unset http.sslBackend

    Reset-Explorer
    write-host "Done!"
    write-host "Remember that some applications (eg the Terminal) need a full application restart to use the updated environment variables."
}

# Helper function to 'show all possible settings'
function Get-SeProxyConfig {
    Write-Output '*** Registry'
    (get-itemproperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').AutoConfigURL
    Write-Output ''
    Write-Output '*** git'
    (git config --list --global | select-string 'http').Line
    Write-Output ''
    Write-Output '*** Env (process)'
    [Environment]::GetEnvironmentVariables("process").GetEnumerator() | Where-Object {$_.Name -match 'proxy'}
    Write-Output ''
    Write-Output '*** Env (user)'
    [Environment]::GetEnvironmentVariables("user").GetEnumerator() | Where-Object {$_.Name -match 'proxy'}
    Write-Output ''
    Write-Output '*** Env (machine)'
    [Environment]::GetEnvironmentVariables("machine").GetEnumerator() | Where-Object {$_.Name -match 'proxy'}
    Write-Output ''
    Write-Output '*** Netsh'
    netsh winhttp show proxy
    Write-Output ''
}

# -----------------------------------------------

function worktree { & "C:\Repo\scripts\worktree.ps1" @args }

Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows

oh-my-posh init pwsh --config "https://raw.githubusercontent.com/JohanO/dotfiles/main/oh-my-posh/johan.omp.json" | Invoke-Expression
