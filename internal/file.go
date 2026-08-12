package internal

import "os"

// проверка существования файла по пути
func IsFile(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		// Файла нет или нет прав доступа
		return false
	}
	// Проверяем, что это НЕ директория
	return !info.IsDir()
}
