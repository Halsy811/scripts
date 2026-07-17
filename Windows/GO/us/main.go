/*
Вывод информации о пользовтелях AD

	--config - настройка файла конфигурации us.json
		> domain:
		> login:
		> password

	--unreg - удаление данных из хранилища

	--name -n 		- поиск по имени
	-sam	- поиск по sAMAccountName
	-с -i	- поиск по компьютеру
	-t 		- поиск по телефону
	-m		- поиск по mail
*/
// file main.go
package main

import (
	"fmt"

	flag "github.com/spf13/pflag"

	"us/mod/auth"
	"us/mod/file"
	"us/mod/formater"
	"us/mod/ldap"
)

const (
	fileName    = "config.json"
	serviceName = "Script_us"
)

func main() {
	fconfig := flag.Bool("config", false, "Настройка файла конфигурации us.json")
	funreg := flag.Bool("unreg", false, "Удалить данные из хранилища")
	fname := flag.StringP("name", "n", "", "Поиск по имени")
	fsam := flag.StringP("sam", "s", "", "Поиск по sAMAccountName")
	fcomputerName := flag.StringP("computer", "c", "", "Поиск по компьютеру")
	ftel := flag.StringP("tel", "t", "", "Поиск по телефону")
	fmail := flag.StringP("mail", "m", "", "Поиск по mail")

	flag.Parse()

	config := &ConfigType{}

	if file.IsFile(fileName) {
		err := config.RestoreFromJSON(config, fileName)

		if err != nil {
			// err
			fmt.Println("Не удалось восстановить параметры из файла конфигурации\nИспользуйте --config для создания файла")
			return
		}
	}

	// Хранит ключи по которым нужно искать
	searcher := &ldap.SearcherType{}
	searcher.New()

	switch {
	case *fconfig:
		err := config.New(fileName)
		if err != nil {
			// err
			fmt.Println("Ошибка при создании файла конфигурации")
			return
		}
		return
	case *funreg:
		auth.RemoveRegister(config.ServiceName, config.UserName)
		return
	case *fname != "":
		searcher.AddAttribToFilter("cn", *fname)
		fallthrough
	case *fsam != "":
		searcher.AddAttribToFilter("sAMAccountName", *fsam)
		fallthrough
	case *fcomputerName != "":
		searcher.AddAttribToFilter("info", *fcomputerName)
		fallthrough
	case *ftel != "":
		searcher.AddAttribToFilter("ipPhone", *ftel)
		fallthrough
	case *fmail != "":
		searcher.AddAttribToFilter("mail", *fmail)
	default:
		fmt.Println("Не указаны ключи.\nhelp: -h --help")
		return
	}

	pass, err := auth.GetPassword(config.ServiceName, config.UserName)
	if err != nil {
		fmt.Printf("Ошибка получения пароля из хранилища: %s\n", err)
		return
	}

	connector := &ldap.LDAPConnectorType{}

	connector.New(config.Domain, config.UserName, string(pass))
	defer connector.Close()

	var demoListAttr = []string{
		"cn",
		"displayName",
		"mail",
		"ipPhone",
		"info",

		"userPrincipalName",
		"sAMAccountName",
		"title",
		"department",

		"distinguishedName",
		"objectSid",
	}

	entries := searcher.SearchByAttrib(connector, demoListAttr, "user")

	for _, entry := range entries {
		formater.FormatAsNestedList(ldap.ConvertEntryToMap(entry))
	}

}
