# Проверка 0.1.0 — 2026-11-14

Исполнитель: Linux sandbox, Godot 4.6.3.stable.official.7d41c59c4. Команда `python3 tools/run_tests.py`: **16/16 checks passed**, exit0, включая архитектурную проверку, импорт и14 standalone test scripts. Ни один SCRIPT ERROR/ERROR не подавляется. В sandbox импорту редактора требуется разрешение открыть локальный debug socket; игровая симуляция сетевой зависимости не имеет.

Проверены: finite domain inventories, heat/mass ledgers, warm-core feedback, delayed absorption, wound care, NPC paths and finite trade, observer locality, Russian grammar and quantity validation, deterministic commands, numeric save/load tolerance, invalid save rejection, backups and checksums, interruption/resume and non-transferable work progress, actual project portrait scaling, touch UI at390×844/1280×800 and200% text, autosave recovery, win/death states.

Сценарий `test_survival_scenario.gd` проходит первую ночь только публичными командами; все пять целей достигнуты примерно06:04, персонаж жив и в сознании. Около8.5 игровых часов отдыха рассчитываются примерно за0.55 секунды на этом Linux CPU. Пассивный100-дневный прогон доменов занимает примерно17.4 секунды, проверяет конечность чисел/ресурсов и границы памяти; это не утверждение о100 днях полноценной жизни NPC.

Визуальная проверка выполнена реальным OpenGL renderer (llvmpipe) на X11, включая портрет с настоящими project viewport settings. Исправлено обнаруженное несоответствие: design viewport теперь390×844 с expand, а не1280×800, чтобы на телефоне был мобильный интерфейс.

Независимый reviewer нашёл два important-дефекта: прогресс очистки дымохода переносился между зданиями; завершение удалённого горения попадало в местный журнал. Исправления покрыты `test_transactions.gd`, reviewer воспроизвёл исправленное поведение. Дополнительно усилены malformed-state проверки, исправлены терморегуляция, парсер названия питья и разделение тепла печи между комнатой и водой.

Удалённый GitHub CI не приравнивается к этому локальному прогону. Android APK, Android device profiling, clinical/reference calibration и вся матрица A–G целевого ТЗ не заявляются. Полный список фактических ограничений — `PROTOTYPE_STATUS.md`.

## Новый набор проверок после смены жанра

Последовательные коммиты в main добавили `tests/test_zombies.gd`, обновили `tests/test_survival_scenario.gd` (нет победы), `tests/test_ui.gd` (настройки и без баннера), `tests/test_project_viewport.gd` (landscape design и portrait fallback). Последний CI статус должен проверяться для конкретного SHA. См. Z01–Z20 в docs/08_ACCEPTANCE.md. Эмулятор/настоящий Android не испытаны, клиническая и акустическая калибровка не выполнена.
