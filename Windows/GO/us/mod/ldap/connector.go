// file ldap.go
package ldap

import (
	"fmt"
	"log"
	"strings"

	"github.com/go-ldap/ldap/v3"
)

// Type: LDAPConnectorType
type LDAPConnectorType struct {
	// Домен
	Domain string
	// Домен в виде BaseDN
	BaseDN string
	// Пользователь использующий подключение
	UserName string
	// Текущее подключение
	LDAPConn *ldap.Conn
}

// Создание подключения
func (l *LDAPConnectorType) New(domain string, username string, password string) {
	l.Domain = domain
	l.BaseDN = l.parseDomainInDN(l.Domain)

	l.UserName = username

	ldapConn, err := ldap.DialURL(fmt.Sprintf("ldap://%s", l.Domain))
	if err != nil {
		log.Fatal(err)
	}

	ntlmReq := &ldap.NTLMBindRequest{
		Domain:   l.Domain,
		Username: l.UserName,
		Password: password,
	}

	_, err = ldapConn.NTLMChallengeBind(ntlmReq)
	if err != nil {
		log.Fatalf("NTLM авторизация не удалясь: %v", err)
	}

	l.LDAPConn = ldapConn
}

// Закрытие подключения
func (l *LDAPConnectorType) Close() {
	l.LDAPConn.Close()
}

// #######################################################################
// Локальные функции
// #######################################################################

// Перерабатывает Domain в BaseDN
func (l *LDAPConnectorType) parseDomainInDN(domain string) string {
	domainSplit := strings.Split(strings.ToUpper(domain), ".")

	var parts []string
	for _, part := range domainSplit {
		parts = append(parts, "DC="+part)
	}

	// Соединяем через запятую: DC=TEST,DC=ENV,DC=XYZ
	return strings.Join(parts, ",")
}
