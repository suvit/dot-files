# Глобальные правила

## Язык

Все сообщения пользователю (статусы, пояснения, выводы) — только по-русски.

## Время в шагах

В каждой статус-строке (шаге) в начале — метка времени: `[16.09 16:26] Проверяю тесты...`

- Метка на каждом шаге, а не только в начале хода; итоговая строка `result:` тоже с меткой.
- Время узнавать отдельной командой `date '+%d.%m %H:%M'`, не добавлять `date` к каждой команде.

## Напоминания

- 05.10.2026 проверить, появился ли публичный usage/quota API у Alibaba Model Studio (token-plan, `sk-sp-*` ключ): на 28.09.2026 нет — 404 на usage-путях `token-plan.*aliyuncs.com`/`dashscope-intl`, rate-limit заголовков в ответе `/v1/messages` нет, остатки только в консоли `modelstudio.console.alibabacloud.com`. Следить: github.com/steipete/CodexBar/issues/612, github.com/can1357/oh-my-pi/issues/8509. Если появился — добавить alibaba-ветку в `~/dotfiles/claude/statusline.sh` (сегмент плана сейчас только для provider=zai). Дубль — systemd user-таймер `alibaba-quota-reminder.timer`.
