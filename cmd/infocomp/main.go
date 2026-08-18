package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/Halsy811/go-litelibs/formatter"
	"github.com/spf13/pflag"
)

//go:embed winrm-ps/info_basic.ps1
var ps1_info_basic string

//go:embed winrm-ps/info_gpo.ps1
var ps1_info_gpo string

//go:embed winrm-ps/info_hardware.ps1
var ps1_info_hardware string

//go:embed winrm-ps/info_network.ps1
var ps1_info_network string

//go:embed winrm-ps/info_realtime.ps1
var ps1_info_realtime string

//go:embed winrm-ps/info_system.ps1
var ps1_info_system string

// HELP
//
//go:embed winrm-ps/info_help.help
var helpText string

var (
	scriptList = map[string]string{
		"basic":    ps1_info_basic,
		"gpo":      ps1_info_gpo,
		"hardware": ps1_info_hardware,
		"net":      ps1_info_network,
		"net2":     ps1_info_system,
		"realtime": ps1_info_realtime,
		"system":   ps1_info_system,
	}
)

type resultScr struct {
	stdout   string
	stderr   string
	exitCode int
	err      error
}

func main() {
	fUser := pflag.StringP("user", "u", "", "Имя пользователя для подключения к WinRM")
	fPass := pflag.StringP("pass", "p", "", "Пароль пользователя для подключения к WinRM")
	fEndpoint := pflag.StringP("endpoint", "e", "", "Цель для сканирования (IP-адрес, имя хоста, подсеть, диапазон адресов)")
	fFilter := pflag.StringP("filter", "f", "", "Фильтр для выбора скриптов. Больше информации --manual")
	fHelp := pflag.Bool("manual", false, "Показать полную справку")
	fjson := pflag.Bool("json", false, "Вывод в виде json")

	pflag.Parse()

	// Вывод справки, если указана опция -h или --help
	if *fHelp {
		fmt.Print(helpText)
		return
	}

	selectedScripts := make(map[string]string)
	if *fFilter == "" || strings.ToLower(*fFilter) == "all" { // Если фильтр пустой или равен "all", выполняем все скрипты
		selectedScripts = scriptList
	} else { // Если указан фильтр, выполняем только скрипты, соответствующие фильтру
		filters := strings.Split(strings.ToLower(*fFilter), ",")
		for _, f := range filters {
			f = strings.TrimSpace(f)
			if f == "" {
				continue
			}
			for name, script := range scriptList {
				if strings.HasPrefix(name, f) {
					selectedScripts[name] = script
				}
			}
		}
	}

	// Пример использования отфильтрованных скриптов
	// if len(selectedScripts) == 0 {
	// 	fmt.Println("Скрипты не найдены по указанному фильтру.")
	// 	return
	// }

	// for name := range selectedScripts {
	// 	fmt.Printf("Выбран скрипт: %s\n", name)
	// }

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	// Перехват системных сигналов. Содержит сам факт что сигнал пришел
	sigChan := make(chan os.Signal, 1)                      // канал для значений os.Signal с буфером 1
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM) // Когда ОС доставляет процессу SIGINT или SIGTERM, runtime перехватывает его. Runtime создаёт значение os.Signal и отправляет его в sigChan (неблокирующая отправка! если буфер полон — сигнал дропается, поэтому буфер ≥ 1 обязателен)

	dataChan := make(chan resultScr, len(selectedScripts))
	if len(selectedScripts) == 0 {
		fmt.Println("Скрипты не найдены по указанному фильтру.")
		return
	}

	var wg sync.WaitGroup

	// Важно: каждый goroutine должен работать со своим экземпляром клиента WinRM.
	// В библиотеке masterzen/winrm NTLM-состояние и HTTP-сессия не являются потокобезопасными,
	// поэтому общий client на несколько параллельных вызовов даёт нестабильный 401.
	// Запуск скриптов
	for _, script := range selectedScripts {
		wg.Add(1)
		go scriptExecuterWorker(ctx, dataChan, &wg, *fEndpoint, *fUser, *fPass, script)
	}

	go func() {
		wg.Wait()
		close(dataChan)
	}()

	var jsons []string

Loop:
	for {
		select {
		case <-ctx.Done():
			fmt.Println("Завершение по таймауту или сигналу.")

		case <-sigChan:
			cancel()
			fmt.Println("Получен SIGINT/SIGTERM, завершение работы.")

		case result, ok := <-dataChan:
			if !ok {
				fmt.Println("Все скрипты завершены")
				break Loop
			}

			if result.err != nil {
				fmt.Printf("Ошибка выполнения: %v\n", result.err)
			} else {
				jsons = append(jsons, result.stdout)
			}
		}
	}

	margeJSON, err := mergeJSON(jsons...)
	if err != nil {
		fmt.Printf("Ошибка обьединения json: %v", err)
	}

	if !*fjson {
		var res map[string]any
		err = json.Unmarshal(margeJSON, &res)

		formatter.FormatAnyAsNestedList(res)
	} else {
		fmt.Println(string(margeJSON))
	}
}

func scriptExecuterWorker(ctx context.Context, dataChanOut chan<- resultScr, wg *sync.WaitGroup, endpoint string, user string, pass string, script string) {
	defer wg.Done()

	cli, err := NewClient(endpoint, 5985, user, pass)
	if err != nil {
		dataChanOut <- resultScr{
			err: fmt.Errorf("Ошибка создания клиента WinRM: %w", err),
		}
		return
	}

	stdout, stderr, exitCode, err := ExecutePSScript(ctx, cli, script)

	dataChanOut <- resultScr{
		stdout:   stdout,
		stderr:   stderr,
		exitCode: exitCode,
		err:      err,
	}
}

func mergeJSON(jsons ...string) ([]byte, error) {
	result := make(map[string]any)

	for _, j := range jsons {
		var m map[string]any
		if err := json.Unmarshal([]byte(j), &m); err != nil {
			return nil, fmt.Errorf("invalid JSON: %w", err)
		}
		for k, v := range m {
			result[k] = v
		}
	}

	return json.MarshalIndent(result, "", "    ")
}
