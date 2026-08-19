package main

import (
	"bufio"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/Halsy811/go-litelibs/auth"
	"github.com/Halsy811/go-litelibs/formatter"
	"github.com/Halsy811/go-litelibs/logger"
	"github.com/spf13/pflag"
	"go.uber.org/zap"
	"golang.org/x/term"
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

//go:embed winrm-ps/info_soft.ps1
var ps1_info_soft string

//go:embed winrm-ps/info_printer.ps1
var ps1_info_printer string

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
		"realtime": ps1_info_realtime,
		"soft":     ps1_info_soft,
		"system":   ps1_info_system,
		"printer":  ps1_info_printer,
	}
)

type resultScr struct {
	stdout   string
	stderr   string
	exitCode int
	err      error
}

const credentialServiceName = "Script_infocomp"

// credentialStorePath хранит имя последнего успешно использованного пользователя
// в профиле текущего пользователя, чтобы не запрашивать его заново при каждом запуске.
func credentialStorePath() string {
	home, err := os.UserConfigDir()
	if err != nil {
		home = "."
	}
	return filepath.Join(home, "infocomp", "last-user.txt")
}

// saveCredentialUser сохраняет логин в локальный файл кеша для повторного использования.
func saveCredentialUser(username string) error {
	path := credentialStorePath()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(strings.TrimSpace(username)), 0o600)
}

// loadCredentialUser пытается восстановить последний логин из локального кеша.
func loadCredentialUser() string {
	content, err := os.ReadFile(credentialStorePath())
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(content))
}

func main() {
	fUser := pflag.StringP("user", "u", "", "Имя пользователя для подключения к WinRM")
	fPass := pflag.StringP("pass", "p", "", "Пароль пользователя для подключения к WinRM")
	fEndpoint := pflag.StringP("endpoint", "e", "", "Цель для сканирования (IP-адрес, имя хоста, подсеть, диапазон адресов)")
	fFilter := pflag.StringP("filter", "f", "", "Фильтр для выбора скриптов. Больше информации --manual")
	fHelp := pflag.Bool("manual", false, "Показать дополнительную справку")
	fjson := pflag.Bool("json", false, "Вывод в виде json")
	fKB := pflag.BoolP("kilobyte", "k", false, "Еденицы измерения KB")
	fMB := pflag.BoolP("megabyte", "m", false, "Еденицы измерения MB")
	fGB := pflag.BoolP("gigabyte", "g", false, "Еденицы измерения GB")
	fconf := pflag.Bool("conf", false, "Зарегистрировать учетные данные утилиты в системном хранилище")
	frmconf := pflag.Bool("rmconf", false, "Удалить учетные данные утилиты из системного хранилища")
	flog := pflag.BoolP("log", "l", false, "Вывод подробного лога при выполнении")

	pflag.Parse()

	// Вывод справки, если указана опция -h или --help
	if *fHelp {
		fmt.Println(helpText)

		fmt.Println("-f ([print,net,sys]|[printer]) - Набор выполняемых скриптов")
		fmt.Println("Если указанный патерн является частью нескольких скриптов, то они все будут выполнены.")
		fmt.Println("Допустимые значения:")
		for name := range scriptList {
			fmt.Printf("\t%s\n", name)
		}
		return
	}

	logs, err := logger.CreateLoggerConsole(true, logger.DisableLog)
	if err != nil {
		fmt.Println("Внетренняя ошибка при выделении места под logger")
	}

	// Лог
	if *flog {
		logs.SetLevel(logger.DebugLevel)
	} else {
		logs.Disable()
	}

	// Конфиг
	if *fconf {
		credentials := &auth.CredentialType{}
		if err := credentials.Register(os.Stdin, credentialServiceName, true); err != nil {
			logs.Error("Ошибка регистрации в системном хранилище: %v\n", zap.Error(err))
			return
		}
		if err := saveCredentialUser(credentials.GetLogin()); err != nil {
			logs.Warn("Предупреждение: не удалось сохранить логин по умолчанию: %v\n", zap.Error(err))
		}
		logs.Info("Процесс внесения учетных данных в системное хранилище паролей завершено\n", zap.String("Service name", credentialServiceName))
		return
	}

	// Удалить конфиг
	if *frmconf {
		if *fUser == "" {
			fmt.Println("Для удаления учетных данных укажите параметр -u/--user")
			return
		}
		if err := auth.RemoveRegister(credentialServiceName, *fUser); err != nil {
			logs.Error("Ошибка удаления учетных данных из системного хранилища", zap.Error(err))
			return
		}
		fmt.Printf("Учетные данные удалены из системного хранилища (%s)\n", credentialServiceName)
		return
	}

	if err := resolveCredentials(fUser, fPass); err != nil {
		logs.Error("Ошибка аутентификации", zap.Error(err))
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
	for name, script := range selectedScripts {
		wg.Add(1)
		go scriptExecuterWorker(ctx, dataChan, &wg, *fEndpoint, *fUser, *fPass, script)
		logs.Info("Запущен скрипт", zap.String("Скрипт", name))
	}

	go func() {
		wg.Wait()

		ids := make([]string, 0, len(selectedScripts))
		for id := range selectedScripts {
			ids = append(ids, id)
		}

		logs.Info("Все процессы завершены", zap.Any("Скрипты:", ids))
		close(dataChan)
	}()

	var jsons []string

Loop:
	for {
		select {
		case <-ctx.Done():
			fmt.Println("Завершение по таймауту или сигналу")
			return
		case <-sigChan:
			cancel()
			fmt.Println("Получен SIGINT/SIGTERM, завершение работы")

		case result, ok := <-dataChan:
			if !ok {
				break Loop
			}

			if result.err != nil {
				logs.Error("Ошибка выполнения", zap.Error(result.err))
			} else {
				jsons = append(jsons, result.stdout)
			}
		}
	}

	margeJSON, err := mergeJSON(jsons...)
	if err != nil {
		logs.Error("Ошибка обьединения json", zap.Error(err))
	}

	if !*fjson { // Человекочитаемый формат
		var res map[string]any
		err = json.Unmarshal(margeJSON, &res)
		if err != nil {
			logs.Error("Ошибка разбора JSON", zap.Error(err))
			return
		}

		formatter.FormatAnyAsNestedList(ConvertBytesByUnit(res, resolveByteUnit(*fKB, *fMB, *fGB)))
	} else { // JSON формат вывода
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

//
//
//

// resolveCredentials определяет, откуда брать логин и пароль:
// 1) из аргументов CLI,
// 2) из кеша последнего логина + системного хранилища Windows,
// 3) из интерактивного ввода в консоль.
func resolveCredentials(user, pass *string) error {
	if *user != "" && *pass != "" {
		return nil
	}

	if *user == "" {
		storedUser := loadCredentialUser()
		if storedUser != "" {
			*user = storedUser
		}
	}

	if *user != "" {
		storedPass, err := auth.GetPassword(credentialServiceName, *user)
		if err == nil && len(storedPass) > 0 {
			*pass = string(storedPass)
			return nil
		}
	}

	if *user == "" {
		fmt.Print("Логин: ")
		reader := bufio.NewReader(os.Stdin)
		login, err := reader.ReadString('\n')
		if err != nil {
			return fmt.Errorf("не удалось прочитать логин: %w", err)
		}
		*user = strings.TrimSpace(login)
		if *user == "" {
			return fmt.Errorf("логин не может быть пустым")
		}
		if err := saveCredentialUser(*user); err != nil {
			fmt.Printf("Предупреждение: не удалось сохранить логин по умолчанию: %v\n", err)
		}
	}

	if *pass == "" {
		storedPass, err := auth.GetPassword(credentialServiceName, *user)
		if err == nil && len(storedPass) > 0 {
			*pass = string(storedPass)
			return nil
		}

		fmt.Print("Пароль: ")
		bytePass, err := term.ReadPassword(int(os.Stdin.Fd()))
		if err != nil {
			return fmt.Errorf("не удалось прочитать пароль: %w", err)
		}
		fmt.Println()
		*pass = string(bytePass)
	}

	return nil
}

// resolveByteUnit выбирает итоговую единицу измерения для всех полей с "Bytes".
// При отсутствии флагов конвертация не выполняется.
func resolveByteUnit(kb, mb, gb bool) string {
	switch {
	case gb:
		return "GB"
	case mb:
		return "MB"
	case kb:
		return "KB"
	default:
		return ""
	}
}

// ConvertBytesByUnit рекурсивно проходит по структуре JSON и конвертирует
// все значения в ключах с "Bytes" в заданную единицу измерения.
func ConvertBytesByUnit(data map[string]any, unit string) map[string]any {
	result := make(map[string]any)

	for key, value := range data {
		switch v := value.(type) {
		case map[string]any:
			result[key] = ConvertBytesByUnit(v, unit)
		case []any:
			result[key] = convertArrayBytesByUnit(v, unit)
		default:
			if strings.Contains(strings.ToLower(key), "bytes") && unit != "" {
				result[key] = convertToUnit(v, unit)
			} else {
				result[key] = value
			}
		}
	}

	return result
}

// convertArrayBytesByUnit обрабатывает массивы и применяет ту же конвертацию
// к вложенным объектам и элементам массива, если они содержат поля с "Bytes".
func convertArrayBytesByUnit(arr []any, unit string) []any {
	result := make([]any, len(arr))

	for i, item := range arr {
		switch v := item.(type) {
		case map[string]any:
			result[i] = ConvertBytesByUnit(v, unit)
		case []any:
			result[i] = convertArrayBytesByUnit(v, unit)
		default:
			result[i] = v
		}
	}

	return result
}

// convertToUnit переводит число из байтов в KB/MB/GB с округлением до сотых.
func convertToUnit(value any, unit string) any {
	factor := 1.0
	switch strings.ToUpper(unit) {
	case "KB":
		factor = 1024
	case "MB":
		factor = 1024 * 1024
	case "GB":
		factor = 1024 * 1024 * 1024
	default:
		factor = 1
	}

	converted := func(v float64) float64 {
		return math.Round(v/factor*100) / 100
	}

	switch v := value.(type) {
	case float64:
		return converted(v)
	case float32:
		return converted(float64(v))
	case int:
		return converted(float64(v))
	case int8:
		return converted(float64(v))
	case int16:
		return converted(float64(v))
	case int32:
		return converted(float64(v))
	case int64:
		return converted(float64(v))
	case uint:
		return converted(float64(v))
	case uint8:
		return converted(float64(v))
	case uint16:
		return converted(float64(v))
	case uint32:
		return converted(float64(v))
	case uint64:
		return converted(float64(v))
	default:
		return value
	}
}
