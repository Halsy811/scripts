function Get-SoftwareFromRegistry {
    param (
        [string]$RegistryPath,
        [string]$Source
    )
    
    if (Test-Path $RegistryPath) {
        $keys = Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            $prop = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
            if ($prop.DisplayName) {
                [PSCustomObject]@{
                    Name            = $prop.DisplayName
                    Version         = $prop.DisplayVersion
                    Publisher       = $prop.Publisher
                    InstallDate     = $prop.InstallDate
                    UninstallString = $prop.UninstallString
                    Source          = $Source
                }
            }
        }
    }
}

# 1. Собираем системное ПО (64-бит и 32-бит)
$computerSoft = @()
$computerSoft += Get-SoftwareFromRegistry -RegistryPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -Source "HKLM-64"
$computerSoft += Get-SoftwareFromRegistry -RegistryPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -Source "HKLM-32"

# 2. Собираем пользовательское ПО (проходим по всем загруженным профилям в HKEY_USERS)
$usersSoft = @()

# Получаем список SID в HKEY_USERS, исключая системные записи (.DEFAULT, S-1-5-18 и т.д.)
$userSIDs = Get-ChildItem -Path Registry::HKEY_USERS | Where-Object { $_.Name -match 'S-1-5-21-[\d\-]+$' }

foreach ($sid in $userSIDs) {
    $sidName = $sid.PSChildName
    # Пытаемся получить имя пользователя по SID
    try {
        $objSID = New-Object System.Security.Principal.SecurityIdentifier($sidName)
        $userName = $objSID.Translate([System.Security.Principal.NTAccount]).Value
    } catch {
        $userName = $sidName
    }

    $userPath = "Registry::HKEY_USERS\$sidName\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    $foundSoft = Get-SoftwareFromRegistry -RegistryPath $userPath -Source "HKU-$userName"
    
    if ($foundSoft) {
        foreach ($item in $foundSoft) {
            $item | Add-Member -MemberType NoteProperty -Name "User" -Value $userName
            $usersSoft += $item
        }
    }
}

# Формируем итоговый объект согласно требуемому формату
$result = @(
    [PSCustomObject]@{
        Soft = [PSCustomObject]@{
            Users    = $usersSoft
            Computer = $computerSoft
        }
    }
)

# Вывод в JSON
$result | ConvertTo-Json -Depth 10