package main

import (
	"fmt"
	"strings"

	"github.com/Ullaakut/nmap"
)

type EndpointInfo struct {
	hostname string
	ip       string
	mac      string
	os       string
}

/*
Сканирование цели на определние операционной системы:

endpoints string - хост, подсеть, списое или диапозон адресов

[EndpointInfo].os:
  - Windows
  - Linux
  - Other
*/
func NmapScanEndpointOS(endpoints string) (results []EndpointInfo, warnings []string, err error) {

	// scanner
	scanner, err := nmap.NewScanner(
		nmap.WithTargets(endpoints),
		nmap.WithOSDetection(), // -O
		//nmap.WithServiceInfo(), // -sV
	)
	if err != nil {
		return nil, nil, fmt.Errorf("ошибка создания сканера: %v\n", err)
	}

	// result содержит структурированные данные: хосты, порты, ОС, сервисы
	result, warnings, err := scanner.Run()
	if err != nil {
		return nil, warnings, fmt.Errorf("ошибка сканирования: %v\n", err)
	}

	// еребор хостов
	for _, host := range result.Hosts {
		if len(host.OS.Matches) == 0 {
			fmt.Println("совпадений с операционной системой не найдено, len(host.OS.Matches) == 0")
			continue
		}

		category := detectOSCategory(host.OS.Matches)

		results = append(results, EndpointInfo{
			hostname: host.Hostnames[0].Name,
			ip:       host.Addresses[0].Addr,
			mac:      host.Addresses[1].Addr,
			os:       category,
		})
	}

	return results, warnings, nil
}

func detectOSCategory(matches []nmap.OSMatch) string {
	// Определение по имени ОС
	for _, match := range matches {
		if strings.Contains(strings.ToLower(match.Name), "windows") {
			return "Windows"
		}
		if strings.Contains(strings.ToLower(match.Name), "linux") {
			return "Linux"
		}
	}

	// Определение по классу ОС, если не удалось определить по имени
	for _, match := range matches {
		for _, class := range match.Classes {
			family := strings.ToLower(class.Family)
			if strings.Contains(family, "windows") {
				return "Windows"
			}
			if strings.Contains(family, "linux") {
				return "Linux"
			}
		}
	}

	return "Other"
}
