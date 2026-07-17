package file

import "os"

func IsFile(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		// Файла нет или нет прав доступа
		return false
	}
	// Проверяем, что это НЕ директория
	return !info.IsDir()
}
