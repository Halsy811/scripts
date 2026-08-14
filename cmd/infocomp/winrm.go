package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"time"
	"unicode/utf16"

	"github.com/masterzen/winrm"
)

// newClient создает нового клиента WinRM для подключения к удаленному хосту
func New(host string, port int, user string, password string) (*winrm.Client, error) {
	endpoint := winrm.NewEndpoint(host, port, false, true, nil, nil, nil, 30*time.Second)
	return winrm.NewClientWithParameters(endpoint, user, password, winrm.DefaultParameters)
}

// encodePSCommand кодирует скрипт в UTF-16LE Base64 для -EncodedCommand
func encodePSCommand(script string) string {
	runes := utf16.Encode([]rune(script))
	bytes := make([]byte, len(runes)*2)
	for i, r := range runes {
		bytes[i*2] = byte(r)
		bytes[i*2+1] = byte(r >> 8)
	}
	return base64.StdEncoding.EncodeToString(bytes)
}

func ExecutePSCommand(ctx context.Context, client *winrm.Client, script string) (stdout string, stderr string, exitCode int, err error) {

	encoded := encodePSCommand(script)
	cmd := fmt.Sprintf("powershell -NoProfile -EncodedCommand %s", encoded)

	return client.RunPSWithContext(ctx, cmd)
}
