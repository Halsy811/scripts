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
                    Name    = $prop.DisplayName
                    Version = $prop.DisplayVersion
                    User    = $Source
                }
            }
        }
    }
}

# 1. Собираем системное ПО (64-бит и 32-бит)
$computerSoft = @()
$computerSoft += Get-SoftwareFromRegistry -RegistryPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -Source "Computer"
$computerSoft += Get-SoftwareFromRegistry -RegistryPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -Source "Computer"

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
        # Убираем домен если есть
        if ($userName -match '\\') {
            $userName = $userName -replace '^.+\\',''
        }
    } catch {
        $userName = $sidName
    }

    $userPath = "Registry::HKEY_USERS\$sidName\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    $foundSoft = Get-SoftwareFromRegistry -RegistryPath $userPath -Source $userName
    
    if ($foundSoft) {
        $usersSoft += $foundSoft
    }
}

# Группируем ПО по компьютеру и пользователям
$computerGroup = @{}
if ($computerSoft) {
    $computerGroup[$(hostname)] = @($computerSoft | Select-Object Name, Version)
}

$usersGroup = @{}
if ($usersSoft) {
    # Группируем по пользователю
    $groupedByUser = $usersSoft | Group-Object -Property User
    foreach ($group in $groupedByUser) {
        $usersGroup[$group.Name] = @($group.Group | Select-Object Name, Version)
    }
}

# Формируем итоговый объект согласно требуемому формату
$result = [PSCustomObject]@{
    Soft = [PSCustomObject]@{
        Computer = $computerGroup
        Users    = $usersGroup
    }
}

# Вывод в JSON
$result | ConvertTo-Json -Depth 10