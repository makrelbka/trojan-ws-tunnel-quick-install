# trojan-ws-tunnel-quick-install

Быстрая установка trojan-go с WebSocket туннелированием через Cloudflare.

## Установка

<div align="center" style="background-color: #fff3cd; border: 2px solid #ffc107; padding: 15px; border-radius: 5px; margin: 20px 0;">

⚠️ **ВАЖНО: Установка должна выполняться от root!**

</div>

### Интерактивная установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/makrelbka/trojan-ws-tunnel-quick-install/main/install.sh)
```

### С указанием домена

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/makrelbka/trojan-ws-tunnel-quick-install/main/install.sh) makrelbka.online
```

## Требования

- Ubuntu/Debian сервер
- Домен с DNS записями, указывающими на IP сервера
- Root доступ

## Использование

После установки используйте скрипт trojan-client для управления клиентами:

```bash
# Добавить клиента
trojan-client add mypassword123

# Удалить клиента
trojan-client remove mypassword123

# Список всех клиентов с ссылками
trojan-client list
```

## Удаление

Для полного удаления trojan-go:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/makrelbka/trojan-ws-tunnel-quick-install/main/install.sh) uninstall
```

## Покупка домена (личная рекомендация)

https://timeweb.com/ru/services/domains/

Покупать домае лучше с TLD ".online"

## Особенности

- Автоматическая установка trojan-go
- Настройка nginx с WebSocket проксированием
- Получение SSL сертификата через Let's Encrypt
- Автоматическая проверка DNS записей
- Управление клиентами через удобный скрипт
- Поддержка Cloudflare для маскировки трафика


## P.S.:

```bash
      "tls": {
        "enabled": true,
        "server_name": "makrelbka.online"
      },
```
win client:
https://github.com/hiddify/hiddify-app/
https://github.com/hiddify/hiddify-app/releases/
