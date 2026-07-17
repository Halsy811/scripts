package json

import (
	"encoding/json"
	"os"
)

// Запись структуры в JSON
func WriteJSONInFile(data any, filename string) error {

	databyte, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}

	err = os.WriteFile(filename, databyte, 0644)
	if err != nil {
		return err
	}

	return nil
}

// Чтение JSON
func ReadJSONInFile(data any, filename string) error {

	fileData, err := os.ReadFile(filename)
	if err != nil {
		return err
	}

	err = json.Unmarshal(fileData, data)
	if err != nil {
		return err
	}

	return nil
}
