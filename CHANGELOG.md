# Changelog

## 0.1.0 — 2026-11-14

First playable «Первая ночь»: seven-place settlement, connected survival models, two autonomous NPCs, material/water/crafting/repair loops, radio and cart, seasonal ecology, contextual Russian touch interface, command grammar, interruption/resume, checksummed saves and backups. Added standalone Godot tests and pinned CI.

This release implements reduced prototype models. Full target specifications remain in docs00–09; actual coverage and limitations are in docs/PROTOTYPE_STATUS.md.

## 2026-11-14 — зомби-песочница (серия коммитов main)

- Убраны сюжетная победа в 06:00, обязательные стартовые цели и спасательное радиосообщение.
- На Android default landscape; вертикальная ориентация включается и сохраняется в настройках, design viewport динамически переключается между широким и портретным.
- Персистентный доменный модуль заражённых, грубая сенсорная реакция на шум и дистанцию, контактные раны через Physiology, команды прислушивания/отступления, интеграционные регрессии и миграция старого save.
- Три большие главы ТЗ 10–12 о биологии заражённых, ощущениях и бесконечном мире. Обновлены архитектура, тестовые сценарии Z01–Z20 и документация реальной готовности.
- Полный боевой/эпидемиологический/дальний симулятор и Android APK ещё не готовы, калибровка отложена до получения достоверных reference fixtures.
