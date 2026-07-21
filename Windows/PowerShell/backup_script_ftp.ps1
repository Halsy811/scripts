<#
.SYNOPSIS
    Version 2.1 - LLM обработка
    
    Ключевые исправления и улучшения:
    - Добавлена отправка messageMail о начале работы скрипта

    НАЗНАЧЕНИЕ:
    Скрипт для создания инкрементальных или полных резервных копий локальных данных 
    на FTP/SFTP-серверы с использованием модуля WinSCP, с гибкой фильтрацией и проверкой целостности.

    ВОЗМОЖНОСТИ:
    - Выполнение нескольких независимых задач за один запуск скрипта.
    - Поддержка протоколов FTP и SFTP.
    - Гибкая фильтрация: от полной синхронизации папки до выборочной загрузки конкретных файлов.
    - Индивидуальная отправка детализированного отчета на Email для каждой задачи с вложенным полным логом.
    - Автоматическая ротация (удаление) старых бекапов на сервере по заданному сроку (в днях).
    - Локальное сохранение полных логов выполнения в папке %TEMP%.
    - Автоматическая сверка локальных и удаленных файлов (проверка целостности).

    ФОРМАТ ЗАДАЧИ:
    [Откуда]::[Удаленный Путь (без хоста)]::[Фильтр]::[Mail 0/1]::[Дни хранения]
    
    * Если [Фильтр] пуст (две двоеточия подряд ::::), выполняется полная синхронизация.
    * В [Фильтре] можно использовать несколько путей, разделенных запятой (,) или точкой с запятой (;).

    ПРИМЕРЫ ВВОДА ЗАДАЧ (ВСЕ ВОЗМОЖНЫЕ ВАРИАНТЫ):
    $tasksListStr = @(
        # 1. ПОЛНАЯ СИНХРОНИЗАЦИЯ (Фильтр пуст)
        # Копирует ВСЁ содержимое C:\Data в /backups/data
        "C:\Data::/backups/data::::7",
        
        # 2. ОДИН КОНКРЕТНЫЙ ФАЙЛ (Относительный путь)
        # Путь считается от C:\Config
        "C:\Config::/backups/config::settings.xml::1::14",
        
        # 3. НЕСКОЛЬКО КОНКРЕТНЫХ ФАЙЛОВ (Относительные пути, разделитель запятая)
        "C:\Config::/backups/config::settings.xml,db.conf,app.ini::1::14",
        
        # 4. МАСКА В КОНКРЕТНОЙ ПАПКЕ (Относительный путь с *)
        # Заберет только .log файлы непосредственно из папки C:\Logs (без вложенных папок)
        "C:\Logs::/backups/logs::*.log::0::30",
        
        # 5. РЕКУРСИВНАЯ МАСКА (Относительный путь, заканчивающийся на \*)
        # ВНИМАНИЕ: Скрипт автоматически удалит \* и добавит -Recurse. 
        # Заберет ВСЕ файлы из папки src\components и всех её подпапок.
        "C:\Project::/backups/project::src\components\*::1::7",
        
        # 6. АБСОЛЮТНЫЙ ПУТЬ В ФИЛЬТРЕ
        # Игнорирует базовый путь "C:\BaseDir" и берет файл с другого диска/пути.
        "C:\BaseDir::/backups/mixed::D:\Important\report.docx::1::7",
        
        # 7. КОМБИНИРОВАННЫЙ ФИЛЬТР (Относительные + Абсолютные + Рекурсивные маски)
        # Самый мощный вариант: конкретный exe, файл по абсолютному пути и все файлы из папки ch6 с вложенностью.
        "C:\tmp\gobook::/tmp/backup::gopl.io/ch1/dup1/main.exe,C:\tmp\gobook\gopl.io\ch6\*::1::7"
    )

    СТРУКТУРА ДИРЕКТОРИЙ БЕКАПА НА СЕРВЕРЕ:
    [Удаленный Путь]/[ИмяПапкиИсточника]_[ХэшЗадачи]/[ГГГГ_ММ_ДД--ЧЧ-ММ]/
    
    Пример: /tmp/backup/gobook_A35AF6A8EFB29896/2026_07_16--09-42/
    
    * Хэш (16 символов) генерируется на основе исходного пути и строки фильтра. 
      Это гарантирует, что две разные задачи для одной и той же папки (но с разными 
      фильтрами) не перезапишут бекапы друг друга.

    СТРУКТУРА ОТЧЕТА (ЛОГА):
    1. Заголовок задачи и **Путь к файлу лога на диске**.
    2. Используемые фильтры.
    3. Итоги загрузки (количество файлов / количество ошибок).
    4. Проверка целостности (сверка локальных и удаленных файлов).
    5. Структура директории бекапов на сервере (список оставшихся папок после очистки).
    6. Структура нового бекапа (усеченный список в письме, полный в файле лога).
    7. Удаленные директории (список очищенных старых бекапов).
    8. Итоговый статус и Exit Code (0 - успех, 1 - есть реальные ошибки/сбои).

    ПРИМЕЧАНИЯ:
    - Одна строка в $tasksListStr = одна независимая задача с отдельным письмом и логом.
    - Для корректной работы требуется установленный модуль WinSCP: Install-Module WinSCP
    - Если в логине FTP есть обратный слеш (например, домен\пользователь), 
      ОБЯЗАТЕЛЬНО используйте одинарные кавычки: $ftpUser = 'DOMAIN\user'
#>

################### Изменяемые переменные ####################

$ScriptLabel = "FTP backup"

$ftpHost = "10.0.0.45"      # Адрес ftp/sftp сервера
$ftpPort = 21               # Порт сервера
$ftpUser = 'IT09\ftp'       # Авторизация логин # Одинарные кавычки обязательны для экранирования обратного слеша
$ftpPass = "111111"         # Авторизация пароль
$ftpProtocol = "Ftp"        # Протокол Ftp / Sftp

$tasksListStr = @(       
    # Формат: [Откуда]::[Удаленный Путь]::[Фильтр]::[Mail 0/1]::[Дни хранения]
    #"C:\tmp\gobook::/tmp/backup::::1::1"
    "C:\tmp\gobook::/tmp/backup::gopl.io/ch1/dup1/main.exe,gopl.io/ch2/boiling/main.go,C:\tmp\gobook\gopl.io\ch6\*::0::7"
)

$desiredLength = 16                    # Длина генерируемого хэша
$messageBodyLength = 40                # Макс. строк структуры в Email (в файле лога будет больше)
$mailFrom = "mail.mail.ru"      # От кого отправлять почту
$mailFromPas = "password"  # Пароль (от кого)
$mailTo = "fromMail.mail.ru"     # Кому отправлять почту
$smtpServer = "smtp.mail.ru"           # mail server
$smtpPort = 587                        # mail server port

#############################################

$tasksList = New-Object System.Collections.ArrayList
$hostname = hostname

if ($PSCommandPath) {
    $NameScript = Split-Path $PSCommandPath -Leaf
} else {
    $NameScript = "Interactive_Session.ps1"
}

function GetHash ([string]$inputString) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($inputString)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''
    return $hashString.Substring(0, [Math]::Min($desiredLength, $hashString.Length))
}

foreach ($taskStr in $tasksListStr) {
    $tmp = $taskStr -split '::'
    
    $copyed_directory = if ($tmp[0]) { $tmp[0].Trim() } else { continue }
    $remoteBasePath = if ($tmp[1]) { $tmp[1].Trim().TrimEnd('/') } else { "/" }
    $filesRaw = if ($tmp[2]) { $tmp[2].Trim() } else { "" }
    $send_message = if ($tmp[3]) { $tmp[3].Trim() } else { "0" }
    $quantity_days = if ($tmp[4]) { $tmp[4].Trim() } else { "0" }
    
    $hash = GetHash("$copyed_directory$filesRaw")
    $dirName = Split-Path $copyed_directory -Leaf
    $remoteBackupFolder = "${dirName}_${hash}"
    $localLogRoot = Join-Path $env:TEMP "FTP_Backup_Logs_${hash}"

    $tasksList.Add(
        [PSCustomObject]@{
            copyed_directory   = $copyed_directory
            remoteBasePath     = $remoteBasePath
            remoteBackupFolder = $remoteBackupFolder
            localLogRoot       = $localLogRoot
            send_message       = $send_message
            quantity_days      = [int]$quantity_days
            filesFilter        = $filesRaw
            hash               = $hash
            dirName            = $dirName
        }
    ) | Out-Null
}

# Функция для ПОДРОБНОГО лога в файл
function Write-DetailLog {
    param([string]$msg)
    if ($logFile) {
        try {
            Add-Content -Path $logFile -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {}
    }
}

# Функция для КРАТКОГО лога в Email
function Write-EmailLog {
    param([string]$msg)
    $emailBody.Add($msg) | Out-Null
}

foreach ($task in $tasksList) {
    $date = Get-Date -Format "yyyy_MM_dd--HH-mm"
    $subjectLine = "$($ScriptLabel): $($task.dirName) | Host: $hostname | Date: $date"
    
    $fullRemotePath = "$($task.remoteBasePath)/$($task.remoteBackupFolder)/$date"
    $logFile = Join-Path $task.localLogRoot "$date.txt"

    $emailBody = New-Object System.Collections.ArrayList
    $session = $null
    
    $taskErrors = New-Object System.Collections.ArrayList
    $deletedFolders = New-Object System.Collections.ArrayList
    $remainingFolders = New-Object System.Collections.ArrayList

	$header = "$($task.copyed_directory) => $($task.remoteBasePath)/$($task.remoteBackupFolder)/$date"
    
    Write-DetailLog $header
    Write-EmailLog $header

    # Путь к файлу лога в системе
    Write-EmailLog "Путь к файлу лога на диске: $logFile"
    Write-Host "Путь к файлу лога на диске: $logFile"

	# ---------------------------------------------------------
    # ОТПРАВКА ПОЧТЫ (Информирование о начале работы отдельным письмом)
    # ---------------------------------------------------------
    if ([int]$task.send_message -eq 1) {
        try {
            
            $startHeaderLine = " == START TASK == "
            
            # В письмо идет ТОЛЬКО краткая сводка $emailBody
            $emailContent = $($emailBody -join "`n") + "`n$startHeaderLine"
            
            $mes = New-Object System.Net.Mail.MailMessage
            $mes.From = $mailFrom
            $mes.To.Add($mailTo)
            $mes.Subject = $subjectLine + $startHeaderLine
            $mes.IsBodyHTML = $false
            $mes.Body = $emailContent
            
            # В прикрепленный файл идет ПОЛНЫЙ детальный лог $logFile
            # if (Test-Path $logFile) {
            #    $att = New-Object System.Net.Mail.Attachment($logFile)
            #    $mes.Attachments.Add($att)
            #}

            $smtp = New-Object Net.Mail.SmtpClient($smtpServer, $smtpPort)
            $smtp.EnableSSL = $true
            $smtp.Credentials = New-Object System.Net.NetworkCredential($mailFrom, $mailFromPas)
            $smtp.Send($mes)
            $mes.Dispose()
            $smtp.Dispose()
            Write-Host "Email sent successfully for task: $($task.dirName)"
        } catch {
            Write-Warning "Failed to send email for task: $_"
        }
    }

	#############################################

    Write-Host "Processing task: $($task.copyed_directory) -> $fullRemotePath"

    try {
        New-Item -ItemType Directory -Path $task.localLogRoot -Force | Out-Null
        New-Item -ItemType File -Path $logFile -Force | Out-Null
    } catch {
        $taskErrors.Add("Failed to create log directory: $_") | Out-Null
        continue
    }

    if (-not (Test-Path $task.copyed_directory)) {
        $taskErrors.Add("CRITICAL ERROR: Source path does not exist: $($task.copyed_directory)") | Out-Null
        continue
    }

    # Подключение к FTP
    try {
        $securePassword = ConvertTo-SecureString $ftpPass -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($ftpUser, $securePassword)
        
        $sessionOptions = New-WinSCPSessionOption -HostName $ftpHost `
            -PortNumber $ftpPort `
            -Credential $credential `
            -Protocol $ftpProtocol
        
        $session = Open-WinSCPSession -SessionOption $sessionOptions
        Write-DetailLog "Успешное подключение к FTP: $ftpHost"
    } catch {
        $taskErrors.Add("CRITICAL ERROR connecting to FTP: $_") | Out-Null
        continue
    }

    Write-EmailLog "------------------------------------------------------------------------------"

    # ---------------------------------------------------------
    # РАЗДЕЛ: ИСПОЛЬЗУЕМЫЕ ФИЛЬТРЫ
    # ---------------------------------------------------------
    Write-DetailLog "------------------------------------------------------------------------------"
    Write-DetailLog "### ИСПОЛЬЗУЕМЫЕ ФИЛЬТРЫ ###"
    Write-EmailLog "### ИСПОЛЬЗУЕМЫЕ ФИЛЬТРЫ ###"
    
    if ($task.filesFilter) {
        $filterList = $task.filesFilter -split '[,;]' | ForEach-Object { $_.Trim() }
        foreach ($f in $filterList) {
            Write-DetailLog "    [x] $f"
            Write-EmailLog "    - $f"
        }
    } else {
        Write-DetailLog "    [x] ПОЛНАЯ СИНХРОНИЗАЦИЯ (без фильтра)"
        Write-EmailLog "    - ПОЛНАЯ СИНХРОНИЗАЦИЯ (без фильтра)"
    }
    Write-EmailLog "------------------------------------------------------------------------------"

    # ---------------------------------------------------------
    # СИНХРОНИЗАЦИЯ (ЗАГРУЗКА)
    # ---------------------------------------------------------
    try {
        New-WinSCPItem -WinSCPSession $session -Path $fullRemotePath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    } catch { }

    $uploadSuccessCount = 0
    $uploadErrorCount = 0

    if ($task.filesFilter) {
        Write-DetailLog "------------------------------------------------------------------------------"
        Write-DetailLog "### ПРОЦЕСС ЗАГРУЗКИ ПО ФИЛЬТРАМ ###"
        
        foreach ($singleFilter in $filterList) {
            if (-not $singleFilter) { continue }
            
            Write-DetailLog "  Обработка правила: '$singleFilter'"
            
            if ([System.IO.Path]::IsPathRooted($singleFilter)) {
                $fullLocalSearchPath = $singleFilter
            } else {
                $fullLocalSearchPath = Join-Path $task.copyed_directory $singleFilter
            }
            
            $cleanSearchPath = $fullLocalSearchPath
            if ($cleanSearchPath.EndsWith('\*') -or $cleanSearchPath.EndsWith('/*')) {
                $cleanSearchPath = $cleanSearchPath.Substring(0, $cleanSearchPath.Length - 2)
                Write-DetailLog "    -> Распознана рекурсивная маска. Базовый путь: $cleanSearchPath"
            }
            
            if (Test-Path $cleanSearchPath -PathType Container) {
                $itemsToSend = Get-ChildItem -Path $cleanSearchPath -Recurse -File -ErrorAction SilentlyContinue
            } else {
                $itemsToSend = Get-ChildItem -Path $fullLocalSearchPath -File -ErrorAction SilentlyContinue
            }
            
            if ($itemsToSend) {
                Write-DetailLog "    -> Найдено файлов для обработки: $($itemsToSend.Count)"
                foreach ($item in $itemsToSend) {
                    try {
                        $relativePath = $item.FullName.Substring($task.copyed_directory.Length).TrimStart('\').Replace('\', '/')
                        $remoteTargetFile = "$fullRemotePath/$relativePath"
                        $remoteDirOnly = Split-Path $remoteTargetFile -Parent
                        
                        Write-DetailLog "      Файл: $($item.Name)"
                        Write-DetailLog "      Локальный путь: $($item.FullName)"
                        Write-DetailLog "      Удаленный путь: $remoteTargetFile"
                        
                        New-WinSCPItem -WinSCPSession $session -Path $remoteDirOnly -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
                        Send-WinSCPItem -WinSCPSession $session -Path $item.FullName -Destination $remoteTargetFile -ErrorAction Stop | Out-Null
                        
                        $uploadSuccessCount++
                        Write-DetailLog "      Статус: [OK]"
                    } catch {
                        $uploadErrorCount++
                        $err = "Error uploading '$($item.Name)' to '$remoteTargetFile': $_"
                        Write-DetailLog "      Статус: [ERROR] $_"
                        $taskErrors.Add($err) | Out-Null
                    }
                }
            } else {
                $warn = "WARNING: No files found locally for filter: '$singleFilter'"
                Write-DetailLog "    -> $warn"
                $taskErrors.Add($warn) | Out-Null
            }
        }
    } else {
        try {
            Write-DetailLog "------------------------------------------------------------------------------"
            Write-DetailLog "### ПРОЦЕСС ПОЛНОЙ СИНХРОНИЗАЦИИ ###"
            $result = Sync-WinSCPPath -WinSCPSession $session `
                -LocalPath $task.copyed_directory `
                -RemotePath $fullRemotePath `
                -Mode ([WinSCP.SynchronizationMode]::Remote) -ErrorAction SilentlyContinue
            
            $uploadSuccessCount = $result.Uploads.Count
            $uploadErrorCount = $result.Failures.Count
            
            Write-DetailLog "Загружено: $($result.Uploads.Count), Удалено на сервере: $($result.Removals.Count)"
            
            if ($result.Failures.Count -gt 0) {
                foreach ($f in $result.Failures) {
                    Write-DetailLog "  [ERROR] $($f.FileName) - $($f.Message)"
                    $taskErrors.Add("Upload Failure: $($f.Message)") | Out-Null
                }
            }
        } catch {
            $taskErrors.Add("CRITICAL ERROR during Sync: $_") | Out-Null
        }
    }

    # Краткий итог загрузки для Email
    Write-EmailLog "Загружено файлов: $uploadSuccessCount"
    if ($uploadErrorCount -gt 0) {
        Write-EmailLog "Ошибок при загрузке: $uploadErrorCount (подробности в прикрепленном файле лога)"
    } else {
        Write-EmailLog "Ошибок при загрузке: 0"
    }

    # ---------------------------------------------------------
    # ПРОВЕРКА ЦЕЛОСТНОСТИ
    # ---------------------------------------------------------
    Write-DetailLog "------------------------------------------------------------------------------"
    Write-DetailLog "### ПРОВЕРКА ПРОПУЩЕННЫХ ПАПОК ###"
    Write-EmailLog "------------------------------------------------------------------------------"
    Write-EmailLog "### ПРОВЕРКА ЦЕЛОСТНОСТИ ###"

    try {
        $srcItems = @()
        if ($task.filesFilter) {
            foreach ($singleFilter in $filterList) {
                if (-not $singleFilter) { continue }
                $fullLocalSearchPath = if ([System.IO.Path]::IsPathRooted($singleFilter)) { $singleFilter } else { Join-Path $task.copyed_directory $singleFilter }
                
                $cleanSearchPath = $fullLocalSearchPath
                if ($cleanSearchPath.EndsWith('\*') -or $cleanSearchPath.EndsWith('/*')) {
                    $cleanSearchPath = $cleanSearchPath.Substring(0, $cleanSearchPath.Length - 2)
                }

                $foundItems = if (Test-Path $cleanSearchPath -PathType Container) {
                    Get-ChildItem -Path $cleanSearchPath -Recurse -File -ErrorAction SilentlyContinue
                } else {
                    Get-ChildItem -Path $fullLocalSearchPath -File -ErrorAction SilentlyContinue
                }
                
                if ($foundItems) {
                    $srcItems += $foundItems | ForEach-Object { $_.FullName.Substring($task.copyed_directory.Length).TrimStart("\").Replace("\", "/") }
                }
            }
        } else {
            $srcItems = Get-ChildItem -Path $task.copyed_directory -Recurse -File -ErrorAction SilentlyContinue | 
                        Where-Object { $_.Name -ne 'desktop.ini' } |
                        ForEach-Object { $_.FullName.Substring($task.copyed_directory.Length).TrimStart("\").Replace("\", "/") }
        }
        
        $dstItems = @()
        $remoteFilesObj = Get-WinSCPChildItem -Path $fullRemotePath -WinSCPSession $session -Recurse -ErrorAction SilentlyContinue | 
                          Where-Object { -not $_.IsDirectory -and $_.Name -ne 'desktop.ini' }
        
        if ($remoteFilesObj) {
            $dstItems = $remoteFilesObj | ForEach-Object { $_.FullName.Substring($fullRemotePath.Length).TrimStart("/") }
        }

        $missing = $srcItems | Where-Object { $_ -notin $dstItems }
        
        if ($missing) {
            $taskErrors.Add("Integrity check: $($missing.Count) files missing on server") | Out-Null
            Write-DetailLog "Найдены несоответствия ($($missing.Count)):"
            $indentedMissing = $missing | ForEach-Object { "    $_" }
            Write-DetailLog ($indentedMissing -join "`n")
            
            Write-EmailLog "СТАТУС: НАЙДЕНЫ НЕСОВПАДЕНИЯ ($($missing.Count) файлов)"
            Write-EmailLog "(Полный список отсутствующих файлов см. в прикрепленном логе)"
        } else {
            Write-DetailLog "Все папки на месте (структура директорий совпадает)."
            Write-EmailLog "СТАТУС: ЦЕЛОСТНОСТЬ ПОДТВЕРЖДЕНА"
        }
    } catch {
        $taskErrors.Add("Ошибка при проверке целостности: $_") | Out-Null
    }
    
    # ---------------------------------------------------------
    # ОЧИСТКА СТАРЫХ БЕКАПОВ
    # ---------------------------------------------------------
    if ($task.quantity_days -gt 0) {
        try {
            $remoteBackupRoot = "$($task.remoteBasePath)/$($task.remoteBackupFolder)"
            $allBackups = Get-WinSCPChildItem -Path $remoteBackupRoot -WinSCPSession $session -ErrorAction SilentlyContinue | 
                          Where-Object { $_.IsDirectory -and $_.Name -match '^\d{4}_\d{2}_\d{2}' } |
                          Sort-Object Name
            
            if ($allBackups.Count -gt $task.quantity_days) {
                $toDelete = $allBackups | Select-Object -SkipLast $task.quantity_days
                foreach ($folder in $toDelete) {
                    try {
                        $folderPath = "$remoteBackupRoot/$($folder.Name)"
                        Remove-WinSCPItem -WinSCPSession $session -Path $folderPath -Recurse -ErrorAction SilentlyContinue
                        $deletedFolders.Add($folder.Name) | Out-Null
                        Write-DetailLog "Удален старый бекап: $($folder.Name)"
                    } catch {
                        $taskErrors.Add("Failed to delete $($folder.Name): $_") | Out-Null
                    }
                }
            }
            
            $currentBackups = Get-WinSCPChildItem -Path $remoteBackupRoot -WinSCPSession $session -ErrorAction SilentlyContinue | 
                              Where-Object { $_.IsDirectory -and $_.Name -match '^\d{4}_\d{2}_\d{2}' } |
                              Sort-Object Name -Descending
            foreach ($folder in $currentBackups) {
                $remainingFolders.Add($folder.Name) | Out-Null
            }
        } catch {
            $taskErrors.Add("Error during cleanup phase: $_") | Out-Null
        }
    }

    # ---------------------------------------------------------
    # ФОРМИРОВАНИЕ ОТЧЕТА ПО СТРУКТУРЕ
    # ---------------------------------------------------------
    Write-DetailLog "------------------------------------------------------------------------------"
    Write-DetailLog "### СТРУКТУРА ДИРЕКТОРИИ БЕКАПОВ (после очистки) ###"
    Write-EmailLog "------------------------------------------------------------------------------"
    Write-EmailLog "### СТРУКТУРА ДИРЕКТОРИИ БЕКАПОВ (после очистки) ###"
    
    if ($remainingFolders.Count -gt 0) {
        $indentedRemaining = $remainingFolders | ForEach-Object { "    $_" }
        Write-DetailLog ($indentedRemaining -join "`n")
        Write-EmailLog ($indentedRemaining -join "`n")
    } else {
        Write-DetailLog "    Нет доступных папок"
        Write-EmailLog "    Нет доступных папок"
    }

    Write-DetailLog "------------------------------------------------------------------------------"
    Write-DetailLog "### СТРУКТУРА НОВОГО БЕКАПА ###"
    Write-EmailLog "------------------------------------------------------------------------------"
    Write-EmailLog "### СТРУКТУРА НОВОГО БЕКАПА ###"
    
    try {
        Start-Sleep -Milliseconds 500
        $structureNewObj = Get-WinSCPChildItem -Path $fullRemotePath -WinSCPSession $session -Recurse -File -ErrorAction SilentlyContinue
        
        if ($structureNewObj) {
            $validObjects = $structureNewObj | Where-Object { $_ }
            if ($validObjects) {
                $relativePaths = @($validObjects | ForEach-Object { 
                    $p = $_.FullName.Substring($fullRemotePath.Length).TrimStart("/")
                    "\" + ($p -replace "/", "\")
                })
                
                # === ИСПРАВЛЕНИЕ: Безопасное усечение без использования .Add() на фиксированных массивах ===
                
                # Для Email: жесткое ограничение длины
                if ($relativePaths.Count -gt $messageBodyLength) {
                    $emailPaths = $relativePaths | Select-Object -First $messageBodyLength
                    $emailPaths += "    ... (усечено, полный список в файле лога)"
                } else {
                    $emailPaths = $relativePaths
                }
                $indentedEmailPaths = $emailPaths | ForEach-Object { "    $_" }
                Write-EmailLog ($indentedEmailPaths -join "`n")

                # Для Файла лога: выводим всё (или очень большой лимит, например 500)
                if ($relativePaths.Count -gt 500) {
                    $detailPaths = $relativePaths | Select-Object -First 500
                    $detailPaths += "    ... (лог усечен после 500 файлов)"
                } else {
                    $detailPaths = $relativePaths
                }
                $indentedDetailPaths = $detailPaths | ForEach-Object { "    $_" }
                Write-DetailLog ($indentedDetailPaths -join "`n")
            }
        } else {
            Write-DetailLog "    Бекап пуст."
            Write-EmailLog "    Бекап пуст."
        }
    } catch {
        $taskErrors.Add("Structure retrieval failed: $_") | Out-Null
    }

    Write-DetailLog "------------------------------------------------------------------------------"
    Write-DetailLog "### УДАЛЕННЫЕ ДИРЕКТОРИИ ###"
    Write-EmailLog "------------------------------------------------------------------------------"
    Write-EmailLog "### УДАЛЕННЫЕ ДИРЕКТОРИИ ###"
    
    if ($deletedFolders.Count -gt 0) {
        $indentedDeleted = $deletedFolders | ForEach-Object { "    $_" }
        Write-DetailLog ($indentedDeleted -join "`n")
        Write-EmailLog ($indentedDeleted -join "`n")
    } else {
        Write-DetailLog "Нет удаленных папок"
        Write-EmailLog "Нет удаленных папок"
    }

    # ---------------------------------------------------------
    # ИТОГОВЫЙ СТАТУС И EXIT CODE
    # ---------------------------------------------------------
    Write-DetailLog "------------------------------------------------------------------------------"
    Write-DetailLog "### ИТОГОВЫЙ СТАТУС ###"
    Write-EmailLog "------------------------------------------------------------------------------"
    Write-EmailLog "### ИТОГОВЫЙ СТАТУС ###"
    
    $exitCode = if ($taskErrors.Count -gt 0) { 1 } else { 0 }
    
    Write-DetailLog "Exit Code: $exitCode"
    Write-EmailLog "Exit Code: $exitCode"
    
    if ($exitCode -eq 0) {
        Write-DetailLog "0) Успешно. Ошибок не обнаружено."
        Write-EmailLog "0) Успешно. Ошибок не обнаружено."
    } else {
        Write-DetailLog "1) Выполнено с ошибками или предупреждениями."
        Write-EmailLog "1) Выполнено с ошибками или предупреждениями."
        
        Write-DetailLog "Детали ошибок:"
        Write-EmailLog "Детали ошибок:"
        $indentedErrors = $taskErrors | ForEach-Object { "    $_" }
        Write-DetailLog ($indentedErrors -join "`n")
        Write-EmailLog ($indentedErrors -join "`n")
    }

    # Закрытие сессии
    if ($session) { 
        try { Remove-WinSCPSession -WinSCPSession $session } catch {}
    }

    # ---------------------------------------------------------
    # ОТПРАВКА ПОЧТЫ
    # ---------------------------------------------------------
    if ([int]$task.send_message -eq 1) {
        try {
            # В письмо идет ТОЛЬКО краткая сводка $emailBody
            $emailContent = $emailBody -join "`n"
            
            $mes = New-Object System.Net.Mail.MailMessage
            $mes.From = $mailFrom
            $mes.To.Add($mailTo)
            $mes.Subject = $subjectLine
            $mes.IsBodyHTML = $false
            $mes.Body = $emailContent
            
            # А в прикрепленный файл идет ПОЛНЫЙ детальный лог $logFile
            if (Test-Path $logFile) {
                $att = New-Object System.Net.Mail.Attachment($logFile)
                $mes.Attachments.Add($att)
            }

            $smtp = New-Object Net.Mail.SmtpClient($smtpServer, $smtpPort)
            $smtp.EnableSSL = $true
            $smtp.Credentials = New-Object System.Net.NetworkCredential($mailFrom, $mailFromPas)
            $smtp.Send($mes)
            $mes.Dispose()
            $smtp.Dispose()
            Write-Host "Email sent successfully for task: $($task.dirName)"
        } catch {
            Write-Warning "Failed to send email for task: $_"
        }
    }
    
    $global:Error.Clear()
}