package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"us/mod/auth"
	ljson "us/mod/json"
)

type ConfigType struct {
	// Домен
	Domain      string `json:"domain"`
	UserName    string `json:"username"`
	ServiceName string `json:"servicename"`
}

// Инициализация структуры Конфига // Запрос данных
func (p *ConfigType) New(fileName string) error {

	reader := bufio.NewReader(os.Stdin)

	// Запрос домена
	fmt.Print("Рабочий домен: ")
	domain, err := reader.ReadString('\n')
	if err != nil {
		fmt.Println("Ошибка чтения из консоли")
		return err
	}
	p.Domain = strings.TrimSpace(domain)

	// Регистрация в системном хранилище
	credentials := &auth.CredentialType{}

	err = credentials.Register(os.Stdin, serviceName, true)

	p.UserName = credentials.GetLogin()
	p.ServiceName = credentials.GetServiceName()

	err = ljson.WriteJSONInFile(p, fileName)

	return nil
}

func (p *ConfigType) RestoreFromJSON(data *ConfigType, fileName string) error {
	err := ljson.ReadJSONInFile(data, fileName)

	return err
}
