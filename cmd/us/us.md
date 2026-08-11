# Предназначение
Вывод информации о пользователях из Active Directory.

Поиск осуществляется на основе атрибутов, которые можно задать через параметры.

- Параметры подключения сохраняются в json файл.
- Данные авторизации записываются в системное хранилище паролей.

```shell
  --help                  Доступные ключи

  -c, --computer string   Поиск по компьютеру
      --config            Настройка файла конфигурации us.json
  -m, --mail string       Поиск по mail
  -n, --name string       Поиск по имени
  -s, --sam string        Поиск по sAMAccountName
  -t, --tel string        Поиск по телефону
      --unreg             Удалить данные из хранилища
```
Пример:
```shell
cn               : t.test
department       : Отдел
displayName      : Тестовый пользователь
distinguishedName: CN=t.test,OU=testgp,DC=domain,DC=ru
groups           : Domain Users
objectSid        : S-1-5-21-1346215...
sAMAccountName   : t.test
title            : Должность
userPrincipalName: test@mail.ru
```