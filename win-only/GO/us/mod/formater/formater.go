package formater

import (
	"fmt"
	"sort"
	"strings"
)

/*
Форматирование в виде листа (2 уровня вложенности)
Пример:

	key1: value1
		value2
		value3
	key2: value1
		value2
*/
func FormatList1(data *map[string][]string) {

}

// Форматированный вывод коллекции в виде list
func FormatAsNestedList(data map[string][]string) {
	fmt.Println("---")

	keys := make([]string, 0, len(data))
	for k := range data {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	// 1. Находим самую длинную строку среди ключей для выравнивания
	maxKeyLen := 0
	for _, key := range keys {
		if len(key) > maxKeyLen {
			maxKeyLen = len(key)
		}
	}

	var sb strings.Builder

	for _, key := range keys {
		values := data[key]
		if len(values) == 0 {
			sb.WriteString(fmt.Sprintf("%-*s: <empty>\n", maxKeyLen, key))
			continue
		}

		// Разбиваем первое значение по переносам строк
		lines := strings.Split(values[0], "\n")
		for j, line := range lines {
			line = strings.ReplaceAll(line, "\r", "")
			if j == 0 {
				// Первая строка: Ключ + Значение с выравниванием
				sb.WriteString(fmt.Sprintf("%-*s: %s\n", maxKeyLen, key, line))
			} else {
				// Остальные строки многострочного значения с отступом под значение
				// Отступ = длина самого длинного ключа + 2 символа (ключ + ": ")
				sb.WriteString(fmt.Sprintf("%*s%s\n", maxKeyLen+2, "", line))
			}
		}

		// Остальные значения массива (если их несколько)
		for i := 1; i < len(values); i++ {
			lines := strings.Split(values[i], "\n")
			for _, line := range lines {
				line = strings.ReplaceAll(line, "\r", "")
				// Тот же отступ
				sb.WriteString(fmt.Sprintf("%*s%s\n", maxKeyLen+2, "", line))
			}
		}
	}

	fmt.Print(sb.String())
}
