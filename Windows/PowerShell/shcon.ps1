<#
.SYNOPSIS
    Shadow Connect RDP Tool - Утилита для удаленного управления и наблюдения за сессиями пользователей через теневое копирование (Shadow RDP).

.DESCRIPTION
    Скрипт предоставляет графический интерфейс для:
    1. Получения списка активных и отключенных сессий на удаленном компьютере (через qwinsta).
    2. Подключения к выбранной сессии в режиме "Полный контроль" (с возможностью управления) или "Просмотр" (только наблюдение).
    3. Автоматического обхода подтверждения на стороне пользователя (/noConsentPrompt), если это позволяют групповые политики.

.USAGE
    1. Введите имя компьютера или IP-адрес.
    2. Нажмите Enter или кнопку 'Refresh'.
    3. Выберите пользователя из списка для инициации подключения.
    4. Нажмите Esc для закрытия окна.

.NOTES
    Требуются права администратора на удаленной машине.
#>

chcp 65001 > $null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Функция для логирования в консоль ---
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch($Level) {
        "Error"   { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        default   { "Gray" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

Write-Log "Запуск Shadow Connect RDP..." "Info"

# Создаем форму
$form = New-Object System.Windows.Forms.Form
$form.Text = "Shadow Connect RDP (Esc - Close)"
$form.Width = 400
$form.Height = 350
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.StartPosition = "CenterScreen"
$form.KeyPreview = $true

# Глобальная переменная для хранения найденных сессий
$global:SessionMatches = $null

# --- Элементы управления ---
$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(10, 5)
$label.Size = New-Object System.Drawing.Size(70, 15)
$label.Text = "Name or IP:"
$form.Controls.Add($label)

$textbox = New-Object System.Windows.Forms.TextBox
$textbox.Location = New-Object System.Drawing.Point(10, 25)
$textbox.Size = New-Object System.Drawing.Size(150, 20)
$form.Controls.Add($textbox)

$radioButton = New-Object System.Windows.Forms.RadioButton
$radioButton.Location = New-Object System.Drawing.Point(180, 10)
$radioButton.Size = New-Object System.Drawing.Size(120, 20)
$radioButton.Text = "Полный контроль"
$radioButton.Checked = $true
$form.Controls.Add($radioButton)

$radioButton1 = New-Object System.Windows.Forms.RadioButton
$radioButton1.Location = New-Object System.Drawing.Point(180, 30)
$radioButton1.Text = "Просмотр"
$form.Controls.Add($radioButton1)

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(10, 85)
$listBox.Size = New-Object System.Drawing.Size(360, 200)
$listBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($listBox)

# Заголовки колонок
$headerLabel = New-Object System.Windows.Forms.Label
$headerLabel.Location = New-Object System.Drawing.Point(10, 65)
$headerLabel.Size = New-Object System.Drawing.Size(360, 20)
$headerLabel.Font = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
$headerLabel.Text = "User           Status  ID      Type"
$form.Controls.Add($headerLabel)

# --- Логика работы ---

function Get-RemoteSessions {
    $hostname = $textbox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        Write-Log "Введите имя компьютера!" "Warning"
        return
    }

    Write-Log "Проверка связи с $hostname..." "Info"
    $listBox.Items.Clear()
    $listBox.Items.Add("Поиск сессий...")
    
    if (Test-Connection -ComputerName $hostname -Count 1 -Quiet) {
        Write-Log "Связь установлена. Получение списка сессий..." "Info"
        try {
            $Orig = qwinsta.exe /server:$hostname 2>$null
            $OrigSessions = $Orig -join "`n"
            
            # Регулярное выражение для парсинга вывода qwinsta
            $regular = "(?m)^[\s{1}\>?]?(?<sessionname>((rdp-tcp#*\d*)|(\s)|(console)))\s+(?<nameuser>(\w*\.*\w+))\s+(?<id>\d+)\s+(?<status>((Active)|(Disc)|(Conn)))"
            $global:SessionMatches = [regex]::Matches($OrigSessions, $regular)
            
            $listBox.Items.Clear()
            if ($global:SessionMatches.Count -eq 0) {
                Write-Log "Сессии не найдены или доступ запрещен." "Warning"
                $listBox.Items.Add("Сессии не найдены")
            } else {
                foreach ($match in $global:SessionMatches) {
                    $u = $match.Groups['nameuser'].Value.PadRight(15)
                    $s = $match.Groups['status'].Value.PadRight(8)
                    $i = $match.Groups['id'].Value.PadRight(8)
                    $t = $match.Groups['sessionname'].Value
                    $listBox.Items.Add("$u$s$i$t")
                }
                Write-Log "Найдено сессий: $($global:SessionMatches.Count)" "Success"
            }
        } catch {
            Write-Log "Ошибка при выполнении qwinsta: $($_.Exception.Message)" "Error"
            $listBox.Items.Clear()
            $listBox.Items.Add("Ошибка выполнения")
        }
    } else {
        Write-Log "Хост $hostname недоступен (Ping failed)." "Error"
        $listBox.Items.Clear()
        $listBox.Items.Add("Хост недоступен")
    }
}

# Обработчик выбора в списке
$listBox.Add_SelectedIndexChanged({
    if ($listBox.SelectedIndex -lt 0) { return }
    $selectedText = $listBox.SelectedItem.ToString()
    if ($selectedText -match "Сессии не найдены" -or $selectedText -match "Поиск") { return }

    $userName = $selectedText.Substring(0, 15).Trim()
    $hostname = $textbox.Text.Trim()

    foreach ($m in $global:SessionMatches) {
        if ($m.Groups['nameuser'].Value -eq $userName) {
            $sessionId = $m.Groups['id'].Value
            $mode = if ($radioButton.Checked) { "/control" } else { "" }
            $modeText = if ($radioButton.Checked) { "УПРАВЛЕНИЕ" } else { "ПРОСМОТР" }

            Write-Log "Подключение к $userName (ID: $sessionId) на $hostname [$modeText]..." "Success"
            
            $args = "/shadow:$sessionId /v:$hostname /noConsentPrompt $mode"
            Start-Process "mstsc.exe" -ArgumentList $args
            break
        }
    }
})

$button = New-Object System.Windows.Forms.Button
$button.Text = "Refresh"
$button.Location = New-Object System.Drawing.Point(310, 15)
$button.Size = New-Object System.Drawing.Size(70, 35)
$button.Add_Click({ Get-RemoteSessions })
$form.Controls.Add($button)

$textbox.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        Get-RemoteSessions
    }
})

$form.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $form.Close()
    }
})

$form.Add_Shown({$form.Activate()})
Write-Log "Готов к работе." "Info"
[System.Windows.Forms.Application]::Run($form)