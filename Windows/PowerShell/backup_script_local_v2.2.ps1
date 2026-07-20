<#
.SYNOPSIS
    Version 2.2 - LLM обработка
    
    Ключевые исправления и улучшения:
    - Исправлено удаление старых лог-файлов

    НАЗНАЧЕНИЕ:
    Скрипт для создания инкрементальных или полных резервных копий локальных и сетевых данных 
    с использованием Robocopy, с гибкой фильтрацией, проверкой целостности и автоматической ротацией.

    ВОЗМОЖНОСТИ:
    - Выполнение нескольких независимых задач за один запуск скрипта.
    - Поддержка локальных дисков и сетевых путей (UNC, например \\server\share).
    - Гибкая фильтрация: от полной синхронизации папки до выборочной загрузки конкретных файлов или масок.
    - Индивидуальная отправка детализированного отчета на Email для каждой задачи с вложенным полным логом.
    - Автоматическая ротация (удаление) старых бекапов и файлов логов на сервере по заданному сроку (в днях).
    - Локальное сохранение полных логов выполнения в корневой папке бекапа.
    - Автоматическая сверка локальных и скопированных файлов (проверка целостности).

    ФОРМАТ ЗАДАЧИ:
    [Откуда]::[Куда]::[Фильтр]::[Mail 0/1]::[Дни хранения]::[Ключи Robocopy]
    
    * Если [Фильтр] пуст, выполняется полная синхронизация директории.
    * В [Фильтре] можно использовать несколько путей/масок, разделенных запятой (,) или точкой с запятой (;).
    * Если [Ключи Robocopy] пусты, применяются безопасные значения по умолчанию: /E /B /R:3 /W:1 /MT:16

    ПРИМЕРЫ ВВОДА ЗАДАЧ (ВСЕ ВОЗМОЖНЫЕ ВАРИАНТЫ):
    $tasksListStr = @(
        # 1. ПОЛНАЯ СИНХРОНИЗАЦИЯ (Фильтр пуст, ключи по умолчанию)
        # Копирует ВСЁ содержимое C:\Data в сетевую папку
        "C:\Data::\\server\backups\data::::1::7::",
        
        # 2. ОДИН КОНКРЕТНЫЙ ФАЙЛ (Относительный путь)
        "C:\Config::\\server\backups\config::settings.xml::1::14::",
        
        # 3. НЕСКОЛЬКО КОНКРЕТНЫХ ФАЙЛОВ (Относительные пути, разделитель запятая)
        "C:\Config::\\server\backups\config::settings.xml,db.conf,app.ini::1::14::",
        
        # 4. МАСКА В КОНКРЕТНОЙ ПАПКЕ (Относительный путь с *)
        # Заберет только .log файлы непосредственно из папки C:\Logs (без вложенных папок)
        "C:\Logs::\\server\backups\logs::*.log::0::30::",
        
        # 5. РЕКУРСИВНАЯ МАСКА (Относительный путь, заканчивающийся на \*)
        # ВНИМАНИЕ: Скрипт автоматически удалит \* и применит рекурсию. 
        # Заберет ВСЕ файлы из папки src\components и всех её подпапок.
        "C:\Project::\\server\backups\project::src\components\*::1::7::",
        
        # 6. АБСОЛЮТНЫЙ ПУТЬ В ФИЛЬТРЕ
        # Игнорирует базовый путь "C:\BaseDir" и берет файл с другого диска/пути.
        "C:\BaseDir::\\server\backups\mixed::D:\Important\report.docx::1::7::",
        
        # 7. КОМБИНИРОВАННЫЙ ФИЛЬТР (Относительные + Абсолютные + Рекурсивные маски)
        # Самый мощный вариант: конкретный exe, файл по абсолютному пути и все файлы из папки ch6 с вложенностью.
        "C:\tmp\gobook::C:\tmp\backup::gopl.io/ch1/dup1/main.exe,C:\tmp\gobook\gopl.io\ch6\*::1::7::"
    )

    СТРУКТУРА ДИРЕКТОРИЙ БЕКАПА:
    [Куда]/[ИмяПапкиИсточника]_[ХэшЗадачи]/[ГГГГ_ММ_ДД--ЧЧ-ММ]/
    
    Пример: C:\tmp\backup\gobook_A35AF6A8EFB29896\2026_07_16--12-35\
    
    * Хэш (16 символов) генерируется на основе исходного пути и строки фильтра. 
      Это гарантирует, что две разные задачи для одной и той же папки (но с разными 
      фильтрами) не перезапишут бекапы друг друга.

    СТРУКТУРА ОТЧЕТА (ЛОГА):
    1. Заголовок задачи и **Путь к файлу лога на диске**.
    2. Используемые фильтры.
    3. Итоги копирования (количество обработанных правил / количество ошибок).
    4. Проверка целостности (сверка локальных и скопированных файлов).
    5. Структура директории бекапов после очистки (список оставшихся папок).
    6. Структура нового бекапа (усеченный список в письме, полный в файле лога).
    7. Удаленные директории (список очищенных старых бекапов).
    8. Итоговый статус и Exit Code (0 - успех, 1 - есть реальные ошибки/сбои).

    ПРИМЕЧАНИЯ:
    - Одна строка в $tasksListStr = одна независимая задача с отдельным письмом и логом.
    - Для корректной работы ключа /B (режим резервного копирования) скрипт рекомендуется 
      запускать с правами Администратора.
    - Скрипт полностью совместим с Windows PowerShell 5.1 и PowerShell 7+.
#>

################### Изменяемые переменные ####################

$ScriptLabel = "Robocopy backup - URPcalendar"

$tasksListStr = @(       
    # Формат: [Откуда]::[Куда]::[Фильтр]::[Mail 0/1]::[Дни хранения]::[Ключи Robocopy]
    "F:\Cale::F:\Backup::dogov.ics::1::3::/s /b /r:6 /MT:128 /LEV:1"
)

$desiredLength = 16						# Длина генерируемого хэша
$messageBodyLength = 40     			# Макс. строк структуры в Email (в файле лога будет больше)
$mailFrom = "mail.mail.ru"		# От кого отправлять почту
$mailFromPas = "password"	# Пароль (от кого)
$mailTo = "fromMail.mail.ru"		# Кому отправлять почту
$smtpServer = "smtp.mail.ru"			# Сервер Mail
$smtpPort = 587							# Порта сервера Mail                        

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

function Get-RobocopyExitMessage {
    param([int]$exitCode)
    $messages = @{
        0 = "0) Успешно. Файлы не копировались (уже актуальны)."
        1 = "1) Успешно. Все файлы скопированы."
        2 = "2) Успешно. Обнаружены лишние файлы в назначении."
        3 = "3) Успешно. Файлы скопированы, обнаружены лишние файлы."
        4 = "4) Успешно. Обнаружены несовпадения, но копирование не требовалось."
        5 = "5) Успешно. Файлы скопированы, обнаружены несовпадения."
        6 = "6) Успешно. Лишние файлы и несовпадения."
        7 = "7) Успешно. Файлы скопированы, лишние файлы и несовпадения."
        8 = "8) ОШИБКА: Некоторые файлы/папки не скопированы."
        16 = "16) КРИТИЧЕСКАЯ ОШИБКА: Серьезная ошибка (синтаксис, права, диск недоступен)."
    }
    if ($exitCode -ge 8) { return "$exitCode) ОШИБКА ROBOCOPY. Проверьте детали в файле лога." }
    return $messages[$exitCode]
}

foreach ($taskStr in $tasksListStr) {
    $tmp = $taskStr -split '::'
    
    $copyed_directory = if ($tmp[0]) { $tmp[0].Trim() } else { continue }
    $backupRootBase = if ($tmp[1]) { $tmp[1].Trim().TrimEnd('\') } else { continue }
    $filesRaw = if ($tmp[2]) { $tmp[2].Trim() } else { "" }
    $send_message = if ($tmp[3]) { $tmp[3].Trim() } else { "0" }
    $quantity_days = if ($tmp[4]) { $tmp[4].Trim() } else { "0" }
    $keys_robocopy_raw = if ($tmp[5]) { $tmp[5].Trim() } else { "" }
    
    $hash = GetHash("$copyed_directory$filesRaw")
    $dirName = Split-Path $copyed_directory -Leaf
    $root_backup = Join-Path $backupRootBase "${dirName}_${hash}"
    $target_directory = Join-Path $root_backup (Get-Date -Format "yyyy_MM_dd--HH-mm")
    $logFile = Join-Path $root_backup "$(Get-Date -Format 'yyyy_MM_dd--HH-mm').txt"
    $robocopyLogFile = Join-Path $root_backup "$(Get-Date -Format 'yyyy_MM_dd--HH-mm')_robocopy.log"

    if (-not $keys_robocopy_raw) {
        $keys_robocopy = "/E /B /R:3 /W:1 /MT:16"
    } else {
        $keys_robocopy = $keys_robocopy_raw
    }

    $tasksList.Add(
        [PSCustomObject]@{
            copyed_directory  = $copyed_directory
            target_directory  = $target_directory
            filesFilter       = $filesRaw
            root_backup       = $root_backup
            logFile           = $logFile
            robocopyLogFile   = $robocopyLogFile
            send_message      = $send_message
            quantity_days     = [int]$quantity_days
            keys_robocopy     = $keys_robocopy
            dirName           = $dirName
        }
    ) | Out-Null
}

function Write-DetailLog {
    param([string]$msg)
    if ($logFile) {
        try { Add-Content -Path $logFile -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    }
}

function Write-EmailLog {
    param([string]$msg)
    $emailBody.Add($msg) | Out-Null
}

foreach ($task in $tasksList) {
    $dateStr = Get-Date -Format "yyyy_MM_dd--HH-mm"
    $subjectLine = "$($ScriptLabel): $($task.dirName) | Host: $hostname | Date: $dateStr"
    
    $emailBody = New-Object System.Collections.ArrayList
    $taskErrors = New-Object System.Collections.ArrayList
    $deletedFolders = New-Object System.Collections.ArrayList
    $remainingFolders = New-Object System.Collections.ArrayList
    $filterList = @()
    
    if ($task.filesFilter) {
        $filterList = $task.filesFilter -split '[,;]' | ForEach-Object { $_.Trim() }
    }

    Write-Host "Processing task: $($task.copyed_directory) -> $($task.target_directory)"

    try {
        New-Item -ItemType Directory -Path $task.root_backup -Force | Out-Null
        New-Item -ItemType Directory -Path $task.target_directory -Force | Out-Null
        New-Item -ItemType File -Path $logFile -Force | Out-Null
        if (Test-Path $task.robocopyLogFile) { Remove-Item $task.robocopyLogFile -Force }
    } catch {
        $taskErrors.Add("Failed to create directories: $_") | Out-Null
        continue
    }

    if (-not (Test-Path $task.copyed_directory)) {
        $taskErrors.Add("CRITICAL ERROR: Source path does not exist: $($task.copyed_directory)") | Out-Null
        continue
    }

    $header = "$($task.copyed_directory) => $($task.target_directory)"
    Write-DetailLog $header
    Write-EmailLog $header
    Write-EmailLog "Путь к файлу лога на диске: $logFile"
    Write-EmailLog "------------------------------------------------------------------------------"

    Write-DetailLog "------------------------------------------------------------------------------"
    Write-DetailLog "### ИСПОЛЬЗУЕМЫЕ ФИЛЬТРЫ ###"
    Write-EmailLog "### ИСПОЛЬЗУЕМЫЕ ФИЛЬТРЫ ###"
    
    if ($task.filesFilter) {
        foreach ($f in $filterList) {
            Write-DetailLog "    [x] $f"
            Write-EmailLog "    - $f"
        }
    } else {
        Write-DetailLog "    [x] ПОЛНАЯ СИНХРОНИЗАЦИЯ (без фильтра)"
        Write-EmailLog "    - ПОЛНАЯ СИНХРОНИЗАЦИЯ (без фильтра)"
    }
    Write-EmailLog "------------------------------------------------------------------------------"

    Write-DetailLog "------------------------------------------------------------------------------"
    Write-DetailLog "### ПРОЦЕСС КОПИРОВАНИЯ (ROBOCOPY) ###"
    
    $rulesSuccessCount = 0
    $rulesErrorCount = 0

    # Удаляем возможные конфликты /LOG из пользовательских ключей, чтобы не было дублирования
    $cleanKeys = $task.keys_robocopy -split '\s+' | Where-Object { $_ -notmatch '(?i)^/LOG(\+)?(:.*)?$' }

    if ($task.filesFilter) {
        foreach ($singleFilter in $filterList) {
            if (-not $singleFilter) { continue }
            
            Write-DetailLog "  Обработка правила: '$singleFilter'"
            
            $fullPath = if ([System.IO.Path]::IsPathRooted($singleFilter)) {
                $singleFilter
            } else {
                Join-Path $task.copyed_directory $singleFilter
            }
            
            $isDirectoryFilter = $fullPath.EndsWith('\') -or $fullPath.EndsWith('/*') -or $fullPath.EndsWith('\*')
            
            if ($isDirectoryFilter) {
                if ($fullPath.EndsWith('\*')) { $cleanPath = $fullPath.Substring(0, $fullPath.Length - 2) }
                elseif ($fullPath.EndsWith('/*')) { $cleanPath = $fullPath.Substring(0, $fullPath.Length - 2) }
                else { $cleanPath = $fullPath.TrimEnd('\') }
                
                $sourceDir = $cleanPath
                $fileMask = "*"
            } else {
                $sourceDir = Split-Path $fullPath -Parent
                $fileMask = Split-Path $fullPath -Leaf
            }
            
            $relativeSourceDir = $sourceDir.Substring($task.copyed_directory.Length).TrimStart('\')
            $destDir = Join-Path $task.target_directory $relativeSourceDir
            
            Write-DetailLog "    -> Источник: $sourceDir"
            Write-DetailLog "    -> Маска: $fileMask"
            Write-DetailLog "    -> Назначение: $destDir"
            
            # --- ИСПРАВЛЕНИЕ: Использование массива аргументов ---
            $roboArgsArray = @(
                $sourceDir
                $destDir
                $fileMask
            ) + $cleanKeys + @(
                "/LOG+:`"$($task.robocopyLogFile)`""
            )

            Write-DetailLog "    -> Команда: Robocopy.exe $($roboArgsArray -join ' ')"
            
            try {
                # Запускаем процесс с перенаправлением вывода
                $ProcessRobo = Start-Process -FilePath "Robocopy.exe" -ArgumentList $roboArgsArray -PassThru -Wait -NoNewWindow -RedirectStandardOutput "$($task.root_backup)\temp_stdout.txt" -RedirectStandardError "$($task.root_backup)\temp_stderr.txt" -ErrorAction Stop
                
                $exitCode = $ProcessRobo.ExitCode
                
                # Читаем вывод Robocopy и добавляем в наш главный лог для избыточности
                if (Test-Path "$($task.root_backup)\temp_stdout.txt") {
                    $stdOutContent = Get-Content "$($task.root_backup)\temp_stdout.txt" -Raw -Encoding Default
                    Write-DetailLog "    --- Robocopy Console Output Start ---"
                    Write-DetailLog $stdOutContent
                    Write-DetailLog "    --- Robocopy Console Output End ---"
                    Remove-Item "$($task.root_backup)\temp_stdout.txt" -Force -ErrorAction SilentlyContinue
                }
                
                if ($exitCode -ge 8) {
                    $rulesErrorCount++
                    $taskErrors.Add("Robocopy failed for '$singleFilter' (Exit Code: $exitCode)") | Out-Null
                    Write-DetailLog "    -> Статус: [ERROR] Exit Code $exitCode"
                } else {
                    $rulesSuccessCount++
                    Write-DetailLog "    -> Статус: [OK] Exit Code $exitCode"
                }
            } catch {
                $rulesErrorCount++
                $taskErrors.Add("CRITICAL ERROR starting Robocopy for '$singleFilter': $_") | Out-Null
                Write-DetailLog "    -> Статус: [CRITICAL ERROR] $_"
            }
        }
    } else {
        Write-DetailLog "  Запуск полной синхронизации..."
        
        $roboArgsArray = @(
            $task.copyed_directory
            $task.target_directory
        ) + $cleanKeys + @(
            "/LOG+:`"$($task.robocopyLogFile)`""
        )

        try {
            $ProcessRobo = Start-Process -FilePath "Robocopy.exe" -ArgumentList $roboArgsArray -PassThru -Wait -NoNewWindow -RedirectStandardOutput "$($task.root_backup)\temp_stdout.txt" -RedirectStandardError "$($task.root_backup)\temp_stderr.txt" -ErrorAction Stop
            
            $exitCode = $ProcessRobo.ExitCode
            $rulesSuccessCount = 1
            
            if (Test-Path "$($task.root_backup)\temp_stdout.txt") {
                $stdOutContent = Get-Content "$($task.root_backup)\temp_stdout.txt" -Raw -Encoding Default
                Write-DetailLog "    --- Robocopy Console Output Start ---"
                Write-DetailLog $stdOutContent
                Write-DetailLog "    --- Robocopy Console Output End ---"
                Remove-Item "$($task.root_backup)\temp_stdout.txt" -Force -ErrorAction SilentlyContinue
            }

            if ($exitCode -ge 8) {
                $taskErrors.Add("Robocopy failed (Exit Code: $exitCode)") | Out-Null
            }
        } catch {
            $taskErrors.Add("CRITICAL ERROR starting Robocopy: $_") | Out-Null
        }
    }

    $ruleCount = if ($task.filesFilter) { $filterList.Count } else { 1 }
    
    Write-EmailLog "Обработано правил фильтрации: $ruleCount"
    if ($rulesErrorCount -gt 0) {
        Write-EmailLog "Ошибок при копировании: $rulesErrorCount (подробности в файле лога)"
    } else {
        Write-EmailLog "Ошибок при копировании: 0"
    }

    # ---------------------------------------------------------
    # ПРОВЕРКА ЦЕЛОСТНОСТИ
    # ---------------------------------------------------------
    Write-DetailLog "------------------------------------------------------------------------------"
    Write-DetailLog "### ПРОВЕРКА ЦЕЛОСТНОСТИ ###"
    Write-EmailLog "------------------------------------------------------------------------------"
    Write-EmailLog "### ПРОВЕРКА ЦЕЛОСТНОСТИ ###"

    try {
        $srcItems = @()
        if ($task.filesFilter) {
            foreach ($singleFilter in $filterList) {
                if (-not $singleFilter) { continue }
                
                $fullLocalSearchPath = if ([System.IO.Path]::IsPathRooted($singleFilter)) { 
                    $singleFilter 
                } else { 
                    Join-Path $task.copyed_directory $singleFilter 
                }
                
                $cleanSearchPath = $fullLocalSearchPath
                if ($cleanSearchPath.EndsWith('\*')) { $cleanSearchPath = $cleanSearchPath.Substring(0, $cleanSearchPath.Length - 2) }
                elseif ($cleanSearchPath.EndsWith('/*')) { $cleanSearchPath = $cleanSearchPath.Substring(0, $cleanSearchPath.Length - 2) }
                elseif ($cleanSearchPath.EndsWith('\')) { $cleanSearchPath = $cleanSearchPath.TrimEnd('\') }

                $foundItems = if (Test-Path $cleanSearchPath -PathType Container) {
                    Get-ChildItem -Path $cleanSearchPath -Recurse -File -ErrorAction SilentlyContinue
                } else {
                    Get-ChildItem -Path $fullLocalSearchPath -File -ErrorAction SilentlyContinue
                }
                
                if ($foundItems) {
                    $srcItems += $foundItems | ForEach-Object { 
                        $_.FullName.Substring($task.copyed_directory.Length).TrimStart("\").Replace("\", "/") 
                    }
                }
            }
        } else {
            $srcItems = Get-ChildItem -Path $task.copyed_directory -Recurse -File -ErrorAction SilentlyContinue | 
                        Where-Object { $_.Name -ne 'desktop.ini' } |
                        ForEach-Object { 
                            $_.FullName.Substring($task.copyed_directory.Length).TrimStart("\").Replace("\", "/") 
                        }
        }
        
        $dstItems = @()
        $destFilesObj = Get-ChildItem -Path $task.target_directory -Recurse -File -ErrorAction SilentlyContinue | 
                        Where-Object { $_.Name -ne 'desktop.ini' }
        
        if ($destFilesObj) {
            $dstItems = $destFilesObj | ForEach-Object { 
                $_.FullName.Substring($task.target_directory.Length).TrimStart("\").Replace("\", "/") 
            }
        }

        $missing = $srcItems | Where-Object { $_ -notin $dstItems }
        
        if ($missing) {
            $taskErrors.Add("Integrity check: $($missing.Count) files missing in destination") | Out-Null
            Write-DetailLog "Найдены несоответствия ($($missing.Count)):"
            $indentedMissing = $missing | ForEach-Object { "    $_" }
            Write-DetailLog ($indentedMissing -join "`n")
            
            Write-EmailLog "СТАТУС: НАЙДЕНЫ НЕСОВПАДЕНИЯ ($($missing.Count) файлов)"
            Write-EmailLog "(Полный список отсутствующих файлов см. в прикрепленном логе)"
        } else {
            Write-DetailLog "Все файлы на месте (структура директорий совпадает)."
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
            $cutoffDate = (Get-Date).AddDays(-$task.quantity_days)
            
            # Удаляем старые директории бекапов по дате создания
            $oldBackups = Get-ChildItem -Path $task.root_backup -Directory | 
                          Where-Object { $_.CreationTime -lt $cutoffDate } |
                          Sort-Object CreationTime
            
            foreach ($folder in $oldBackups) {
                try {
                    Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
                    $deletedFolders.Add($folder.Name) | Out-Null
                    Write-DetailLog "Удален старый бекап: $($folder.Name) (создан: $($folder.CreationTime))"
                } catch {
                    $taskErrors.Add("Failed to delete $($folder.Name): $_") | Out-Null
                }
            }
            
            # Удаляем старые .log файлы по дате создания (только в корневой директории)
            Get-ChildItem -Path $task.root_backup -Filter "*.log" -File | 
                Where-Object { $_.CreationTime -lt $cutoffDate } | 
                Remove-Item -Force -ErrorAction SilentlyContinue
            
            # Удаляем старые .txt файлы по дате создания (только в корневой директории), исключая текущий лог
            $currentLogFile = Split-Path $logFile -Leaf
            Get-ChildItem -Path $task.root_backup -Filter "*.txt" -File | 
                Where-Object { $_.CreationTime -lt $cutoffDate -and $_.Name -ne $currentLogFile } | 
                Remove-Item -Force -ErrorAction SilentlyContinue
            
            # Получаем список оставшихся директорий бекапов
            $remainingBackups = Get-ChildItem -Path $task.root_backup -Directory | 
                                Where-Object { $_.Name -match '^\d{4}_\d{2}_\d{2}' } |
                                Sort-Object Name -Descending
            foreach ($folder in $remainingBackups) {
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
        $structureNewObj = Get-ChildItem -Path $task.target_directory -Recurse -File -ErrorAction SilentlyContinue
        
        if ($structureNewObj) {
            $validObjects = $structureNewObj | Where-Object { $_ }
            if ($validObjects) {
                $relativePaths = @($validObjects | ForEach-Object { 
                    $p = $_.FullName.Substring($task.target_directory.Length).TrimStart("\")
                    "\" + $p
                })
                
                if ($relativePaths.Count -gt $messageBodyLength) {
                    $emailPaths = $relativePaths | Select-Object -First $messageBodyLength
                    $emailPaths += "    ... (усечено, полный список в файле лога)"
                } else {
                    $emailPaths = $relativePaths
                }
                $indentedEmailPaths = $emailPaths | ForEach-Object { "    $_" }
                Write-EmailLog ($indentedEmailPaths -join "`n")

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
    
    $exitCodeFinal = if ($taskErrors.Count -gt 0) { 1 } else { 0 }
    
    Write-DetailLog "Exit Code: $exitCodeFinal"
    Write-EmailLog "Exit Code: $exitCodeFinal"
    
    if ($exitCodeFinal -eq 0) {
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

    # ---------------------------------------------------------
    # ОТПРАВКА ПОЧТЫ
    # ---------------------------------------------------------
    if ([int]$task.send_message -eq 1) {
        try {
            $emailContent = $emailBody -join "`n"
            
            $mes = New-Object System.Net.Mail.MailMessage
            $mes.From = $mailFrom
            $mes.To.Add($mailTo)
            $mes.Subject = $subjectLine
            $mes.IsBodyHTML = $false
            $mes.Body = $emailContent
            
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