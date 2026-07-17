package ldap

import (
	"fmt"
	"strings"

	"github.com/go-ldap/ldap/v3"
)

// Type: SearcherType
type SearcherType struct {
	// Атрибуты по которым будет производиться поиск
	attribFilter map[string]string
	// result     *ldap.SearchResult
}

// Инициализация
func (s *SearcherType) New() {
	s.attribFilter = make(map[string]string)
}

/*
	Добавить/Обновить атрибут Фильтра

- key: атрибут в котором искать строку value
*/
func (s *SearcherType) AddAttribToFilter(key string, value string) {
	s.attribFilter[key] = value
}

/*
	Поиск по атрибутам

- ldapConnector: текущее подключение
- demoListAttrib: список атрибутов, которые предоставлены в выводе для обьекта
*/
func (s *SearcherType) SearchByAttrib(ldapConnector *LDAPConnectorType, demoListAttrib []string, objCategory string) []*ldap.Entry {

	filter := s.parseAttribInLDAPFilter(objCategory)

	searchRequest := ldap.NewSearchRequest(
		ldapConnector.BaseDN,
		ldap.ScopeWholeSubtree,
		ldap.NeverDerefAliases,
		0,
		0,
		false,
		filter,
		demoListAttrib,
		nil,
	)

	var err error

	result, err := ldapConnector.LDAPConn.Search(searchRequest)
	if err != nil {
		fmt.Println("Search ldap err: ", err)
	}

	if len(result.Entries) == 0 {
		fmt.Println("Возвращена пустота")
	}
	return result.Entries
}

// #######################################################################
// Локальные функции
// #######################################################################

/*
	Перерабатывает map с атрибутами в filter для поиска по LDAP

- objCategory: категория поиска (Например:User/Computer)
*/
func (s *SearcherType) parseAttribInLDAPFilter(objCategory string) string {
	var filterParts []string

	// Базовое условие: только пользователи
	filterParts = append(filterParts, "(objectCategory="+objCategory+")")

	for key, value := range s.attribFilter {
		// Пропускаем пустые значения
		if value == "" {
			continue
		}

		// Экранируем значение и добавляем в фильтр
		filterParts = append(filterParts, fmt.Sprintf("(%s=*%s*)", key, ldap.EscapeFilter(value)))
	}

	return "(&" + strings.Join(filterParts, "") + ")"
}
