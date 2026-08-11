# Пакеты для переиспользования

Примеры суффиксов файлов
```shell
internal/ldap/
├── client.go          # общий интерфейс
├── client_windows.go  # //go:build windows — реализация под Windows
└── client_linux.go    # //go:build linux  — реализация под Linux
```