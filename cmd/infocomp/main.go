package main

import (
	_ "embed"
	"fmt"
	"strings"

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

//go:embed winrm-ps/info_help.help
var helpText string

var (
	scriptList = map[string]string{
		"basic":    ps1_info_basic,
		"gpo":      ps1_info_gpo,
		"hardware": ps1_info_hardware,
		"net":      ps1_info_network,
		"net2":     ps1_info_network,
		"realtime": ps1_info_realtime,
		"system":   ps1_info_system,
	}
)

func main() {
	fUser := pflag.StringP("user", "u", "", "Имя пользователя для подключения к WinRM")
	fPass := pflag.StringP("pass", "p", "", "Пароль пользователя для подключения к WinRM")
	fEndpoint := pflag.StringP("endpoint", "e", "", "Цель для сканирования (IP-адрес, имя хоста, подсеть, диапазон адресов)")
	fFilter := pflag.StringP("filter", "f", "", "Фильтр для выбора скриптов. Больше информации --manual")
	fHelp := pflag.Bool("manual", false, "Показать полную справку")

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

}
