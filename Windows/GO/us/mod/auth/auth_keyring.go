package auth

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/zalando/go-keyring"
	"golang.org/x/term"
)

type CredentialType struct {
	serviceName string
	userName    string
}

// Создание сервиса
func (a *CredentialType) New(serviceName string) {
	a.serviceName = serviceName
}

// Запрос логина и пароля с дальнейшей регистрацией в системе
func (a *CredentialType) Register(stdin *os.File, serviceName string, confirm bool) error {

	login, err := requestLogin(stdin)
	if err != nil {
		return err
	}

	a.userName = login

	bytepass, err := requestPassword(stdin, confirm)
	if err != nil {
		return err
	}

	a.serviceName = serviceName

	err = keyring.Set(a.serviceName, login, string(bytepass))
	if err != nil {
		return err
	}

	return nil
}

// Получить пароль из хранилища
func (a *CredentialType) GetPassword() ([]byte, error) {
	pass, err := keyring.Get(a.serviceName, a.userName)

	return []byte(pass), err
}

// Получить пароль из хранилища
func GetPassword(serviceName string, userName string) ([]byte, error) {

	pass, err := keyring.Get(serviceName, userName)

	return []byte(pass), err
}

// Получить login пользователя
func (a *CredentialType) GetLogin() string {
	return a.userName
}

// Получить login пользователя
func (a *CredentialType) GetServiceName() string {
	return a.serviceName
}

// Запрос логина
func requestLogin(stdin *os.File) (string, error) {
	reader := bufio.NewReader(stdin)

	fmt.Print("Логин: ")
	login, err := reader.ReadString('\n')
	if err != nil {
		fmt.Println("Ошибка чтения из консоли")
		return "", err
	}
	login = strings.TrimSpace(login)

	return login, err
}

// Удаление даннх из хранилища
func (a *CredentialType) RemoveRegister() error {
	err := keyring.Delete(a.serviceName, a.userName)

	return err
}

// Удаление даннх из хранилища
func RemoveRegister(serviceName string, userName string) error {
	err := keyring.Delete(serviceName, userName)

	return err
}

/*
	Запрос пароля

- stdin - указатель на файл
- confirm - подтвержение пароля (false - не запрашивать)
*/
func requestPassword(stdin *os.File, confirm bool) ([]byte, error) {
	var (
		pass []byte
		err  error
	)

	for {
		fmt.Print("Пароль: ")
		pass, err = term.ReadPassword(int(stdin.Fd()))
		if err != nil {
			fmt.Println("Не удалось считать пароль, повторите.")
			continue
		}

		fmt.Println()

		if confirm {
			fmt.Print("Повторите пароль: ")
			repeatpass, err := term.ReadPassword(int(stdin.Fd()))
			if err != nil {
				break
			}

			if string(pass) == string(repeatpass) {
				return pass, nil
			} else {
				fmt.Println("Пароли не совпадают.")
				pass = nil
				repeatpass = nil
			}
		} else {
			return pass, nil
		}
	}

	return pass, nil
}
