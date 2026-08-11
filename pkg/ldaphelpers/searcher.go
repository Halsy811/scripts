package ldaphelpers

import (
	"fmt"
	"strings"

	"github.com/go-ldap/ldap/v3"
)

type Searcher struct {
	attribFilter   map[string]string
	objectCategory string
}

func NewSearcher(objectCategory string) *Searcher {
	if objectCategory == "" {
		objectCategory = "user"
	}

	return &Searcher{
		attribFilter:   make(map[string]string),
		objectCategory: objectCategory,
	}
}

func (s *Searcher) AddAttribToFilter(key, value string) {
	if key == "" || value == "" {
		return
	}
	if s.attribFilter == nil {
		s.attribFilter = make(map[string]string)
	}
	s.attribFilter[key] = value
}

func (s *Searcher) Search(conn *ldap.Conn, baseDN string, attributes []string) ([]*ldap.Entry, error) {
	if conn == nil {
		return nil, fmt.Errorf("ldap connection is nil")
	}
	if baseDN == "" {
		return nil, fmt.Errorf("baseDN is empty")
	}

	searchRequest := ldap.NewSearchRequest(
		baseDN,
		ldap.ScopeWholeSubtree,
		ldap.NeverDerefAliases,
		0,
		0,
		false,
		s.buildFilter(),
		attributes,
		nil,
	)

	result, err := conn.Search(searchRequest)
	if err != nil {
		return nil, err
	}
	return result.Entries, nil
}

func (s *Searcher) Filter() string {
	return s.buildFilter()
}

func (s *Searcher) buildFilter() string {
	filterParts := []string{fmt.Sprintf("(objectCategory=%s)", ldap.EscapeFilter(s.objectCategory))}

	for key, value := range s.attribFilter {
		if value == "" {
			continue
		}
		filterParts = append(filterParts, fmt.Sprintf("(%s=*%s*)", key, ldap.EscapeFilter(value)))
	}

	return "(&" + strings.Join(filterParts, "") + ")"
}
