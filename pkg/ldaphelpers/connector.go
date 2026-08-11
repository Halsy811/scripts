// file ldap.go
package ldaphelpers

import (
	"fmt"
	"strings"

	"github.com/go-ldap/ldap/v3"
)

func ParseDomainToBaseDN(domain string) string {
	domainSplit := strings.Split(strings.ToUpper(domain), ".")
	var parts []string
	for _, part := range domainSplit {
		if part == "" {
			continue
		}
		parts = append(parts, "DC="+part)
	}
	return strings.Join(parts, ",")
}

func DialAndBindNTLM(domain, username, password string) (*ldap.Conn, error) {
	conn, err := ldap.DialURL(fmt.Sprintf("ldap://%s", domain))
	if err != nil {
		return nil, err
	}

	bindRequest := &ldap.NTLMBindRequest{
		Domain:   domain,
		Username: username,
		Password: password,
	}

	_, err = conn.NTLMChallengeBind(bindRequest)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("NTLM bind failed: %w", err)
	}

	return conn, nil
}
