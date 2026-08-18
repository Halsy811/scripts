package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"
	"time"
	"unicode/utf16"

	"github.com/masterzen/winrm"
)

// NewClient создает нового клиента WinRM для подключения к удаленному хосту
func NewClient(host string, port int, user string, password string) (*winrm.Client, error) {
	endpoint := winrm.NewEndpoint(
		host,
		port,  // 5985
		false, // HTTP
		true,  // InsecureSkipVerify
		nil, nil, nil,
		30*time.Second,
	)
	params := winrm.DefaultParameters
	params.Timeout = "PT120S"
	// КЛЮЧЕВОЕ: используем встроенный NTLM-транспорт библиотеки
	// НЕ нужен go-ntlmssp вообще
	params.TransportDecorator = func() winrm.Transporter {
		return &winrm.ClientNTLM{}
	}

	client, err := winrm.NewClientWithParameters(endpoint, user, password, params)
	if err != nil {
		err = fmt.Errorf("Ошибка создания клиента: %v\n", err)
		return nil, err
	}

	return client, err
}

func ExecutePSScript(ctx context.Context, client *winrm.Client, script string) (stdoutStr string, stderrStr string, exitCode int, err error) {

	// Команда PowerShell для чтения скрипта из stdin
	// -Command - означает "читать команду из stdin"
	cmd := "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command -"

	// Создаем буферы для сбора вывода
	var stdout, stderr strings.Builder

	// Потоковый вывод через io.Writer
	exitCode, err = client.RunWithContextWithInput(
		ctx,
		cmd,
		&stdout,
		&stderr,
		strings.NewReader(winrm.Powershell(script)),
	)

	if err != nil {
		err = fmt.Errorf("Ошибка выполения WinRM: %v", err)
		return "", "", exitCode, err
	}

	stdoutStr = stdout.String()
	stderrStr = stderr.String()

	return stdoutStr, stderrStr, exitCode, nil
}

// ==============================================
// ================== internal ==================
// ==============================================

// кодирует скрипт encodePSCommandв UTF-16LE Base64 для -EncodedCommand
func encodePSCommand(script string) string {
	runes := utf16.Encode([]rune(script))
	bytes := make([]byte, len(runes)*2)
	for i, r := range runes {
		bytes[i*2] = byte(r)
		bytes[i*2+1] = byte(r >> 8)
	}
	return base64.StdEncoding.EncodeToString(bytes)
}
