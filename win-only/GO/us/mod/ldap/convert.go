package ldap

import (
	"encoding/binary"
	"fmt"
	"strings"

	"github.com/go-ldap/ldap/v3"
)

// Конвертация элемента ldap.Entry в map
func ConvertEntryToMap(entry *ldap.Entry) map[string][]string {
	result := make(map[string][]string, len(entry.Attributes))

	for _, attr := range entry.Attributes {
		vals := make([]string, len(attr.Values))

		// Если это SID, пробуем декодировать
		if strings.EqualFold(attr.Name, "objectSid") {
			for i, byteVal := range attr.ByteValues { // Используем ByteValues для сырых данных
				sidStr, err := DecodeSID(byteVal)
				if err != nil {
					// Если ошибка, оставляем как есть или пишем ошибку
					sidStr = fmt.Sprintf("ERR:%v", err)
				}
				vals[i] = sidStr
			}
		} else {
			// Для остальных атрибутов просто копируем строки
			copy(vals, attr.Values)
		}

		result[attr.Name] = vals
	}
	return result
}

// DecodeSID преобразует бинарный SID в строку S-1-5-21-...
func DecodeSID(sidBytes []byte) (string, error) {
	if len(sidBytes) < 8 {
		return "", fmt.Errorf("invalid SID length")
	}

	revision := sidBytes[0]
	subAuthorityCount := sidBytes[1]

	// Первые 6 байт после заголовка - это Identifier Authority (48 бит)
	var identifierAuthority uint64
	for i := 0; i < 6; i++ {
		identifierAuthority = identifierAuthority<<8 + uint64(sidBytes[2+i])
	}

	result := fmt.Sprintf("S-%d-%d", revision, identifierAuthority)

	// Остальные байты - это Sub Authorities (по 4 байта каждая, Little Endian)
	offset := 8
	for i := 0; i < int(subAuthorityCount); i++ {
		if offset+4 > len(sidBytes) {
			return "", fmt.Errorf("invalid SID structure")
		}
		subAuth := binary.LittleEndian.Uint32(sidBytes[offset : offset+4])
		result += fmt.Sprintf("-%d", subAuth)
		offset += 4
	}

	return result, nil
}
