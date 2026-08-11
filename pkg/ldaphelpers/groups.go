package ldaphelpers

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/go-ldap/ldap/v3"
)

type GroupInfo struct {
	DN string
	CN string
}

// Возвращает список DN групп в которые входит пользователь. (Рекурсивно)
func GetUserGroupDNs(conn *ldap.Conn, baseDN, userDN string) ([]string, error) {
	entries, err := findGroupEntries(conn, baseDN, userDN)
	if err != nil {
		return nil, err
	}
	dns := make([]string, len(entries))
	for i, entry := range entries {
		dns[i] = entry.DN
	}
	return dns, nil
}

// Возвращает список имён групп в которые входит пользователь. (Рекурсивно)
func GetUserGroupNames(conn *ldap.Conn, baseDN, userDN string) ([]string, error) {
	entries, err := findGroupEntries(conn, baseDN, userDN)
	if err != nil {
		return nil, err
	}
	groups := ParseGroupEntries(entries)
	names := make([]string, len(groups))
	for i, group := range groups {
		names[i] = group.CN
	}
	return names, nil
}

func ParseGroupEntries(entries []*ldap.Entry) []GroupInfo {
	groups := make([]GroupInfo, 0, len(entries))
	for _, entry := range entries {
		groups = append(groups, GroupInfo{
			DN: entry.DN,
			CN: entry.GetAttributeValue("cn"),
		})
	}
	return groups
}

func findGroupEntries(conn *ldap.Conn, baseDN, userDN string) ([]*ldap.Entry, error) {
	userEntry, err := getUserEntry(conn, userDN)
	if err != nil {
		return nil, err
	}

	groupsByDN := make(map[string]*ldap.Entry)
	escapedUserDN := ldap.EscapeFilter(userDN)

	addEntries := func(entries []*ldap.Entry) {
		for _, entry := range entries {
			groupsByDN[entry.DN] = entry
		}
	}

	if entries, err := searchGroups(conn, baseDN, fmt.Sprintf("(&(objectClass=group)(member:1.2.840.113556.1.4.1941:=%s))", escapedUserDN)); err != nil {
		fmt.Printf("Warning: nested AD search failed: %v\n", err)
	} else {
		addEntries(entries)
	}

	for _, attr := range []string{"member", "uniqueMember"} {
		if entries, err := searchGroups(conn, baseDN, fmt.Sprintf("(&(objectClass=group)(%s=%s))", attr, escapedUserDN)); err != nil {
			fmt.Printf("Warning: direct group search by %s failed: %v\n", attr, err)
		} else {
			addEntries(entries)
		}
	}

	if primaryGroup, err := findPrimaryGroup(conn, baseDN, userEntry); err != nil {
		fmt.Printf("Warning: primary group lookup failed: %v\n", err)
	} else if primaryGroup != nil {
		groupsByDN[primaryGroup.DN] = primaryGroup
	}

	if len(groupsByDN) == 0 {
		return nil, nil
	}

	entries := make([]*ldap.Entry, 0, len(groupsByDN))
	for _, entry := range groupsByDN {
		entries = append(entries, entry)
	}
	sort.Slice(entries, func(i, j int) bool {
		return strings.ToLower(entries[i].DN) < strings.ToLower(entries[j].DN)
	})
	return entries, nil
}

func getUserEntry(conn *ldap.Conn, userDN string) (*ldap.Entry, error) {
	searchRequest := ldap.NewSearchRequest(
		userDN,
		ldap.ScopeBaseObject,
		ldap.NeverDerefAliases,
		0, 0, false,
		"(objectClass=*)",
		[]string{"memberOf", "objectSid", "primaryGroupID"},
		nil,
	)

	result, err := conn.Search(searchRequest)
	if err != nil {
		return nil, err
	}
	if len(result.Entries) != 1 {
		return nil, fmt.Errorf("user not found or multiple entries returned: %d", len(result.Entries))
	}
	return result.Entries[0], nil
}

func searchGroups(conn *ldap.Conn, baseDN, filter string) ([]*ldap.Entry, error) {
	searchRequest := ldap.NewSearchRequest(
		baseDN,
		ldap.ScopeWholeSubtree,
		ldap.NeverDerefAliases,
		0, 0, false,
		filter,
		[]string{"dn", "cn"},
		nil,
	)

	result, err := conn.Search(searchRequest)
	if err != nil {
		return nil, err
	}
	return result.Entries, nil
}

func findPrimaryGroup(conn *ldap.Conn, baseDN string, userEntry *ldap.Entry) (*ldap.Entry, error) {
	pgidStr := userEntry.GetAttributeValue("primaryGroupID")
	if pgidStr == "" {
		return nil, nil
	}

	rawSid := userEntry.GetRawAttributeValue("objectSid")
	if rawSid == nil {
		return nil, fmt.Errorf("objectSid is empty")
	}

	pgid, err := strconv.ParseUint(pgidStr, 10, 32)
	if err != nil {
		return nil, fmt.Errorf("parse primaryGroupID: %w", err)
	}

	primarySid := make([]byte, len(rawSid))
	copy(primarySid, rawSid)
	if len(primarySid) < 4 {
		return nil, fmt.Errorf("objectSid has unexpected length %d", len(primarySid))
	}
	n := len(primarySid)
	primarySid[n-4] = byte(pgid & 0xFF)
	primarySid[n-3] = byte((pgid >> 8) & 0xFF)
	primarySid[n-2] = byte((pgid >> 16) & 0xFF)
	primarySid[n-1] = byte((pgid >> 24) & 0xFF)

	esc := ""
	for _, b := range primarySid {
		esc += fmt.Sprintf("\\%02x", b)
	}

	searchRequest := ldap.NewSearchRequest(
		baseDN,
		ldap.ScopeWholeSubtree,
		ldap.NeverDerefAliases,
		0, 0, false,
		fmt.Sprintf("(objectSid=%s)", esc),
		[]string{"dn", "cn"},
		nil,
	)

	result, err := conn.Search(searchRequest)
	if err != nil {
		return nil, err
	}
	if len(result.Entries) == 0 {
		return nil, fmt.Errorf("primary group not found by objectSid")
	}
	return result.Entries[0], nil
}
