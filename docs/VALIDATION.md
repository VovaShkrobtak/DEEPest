# Проверка 0.1.0 — 2026-11-14

Исполнитель: Linux sandbox, Godot 4.6.3.stable.official.7d41c59c4. Команда `python3 tools/run_tests.py`: **16/16 checks passed**, exit0, включая архитектурную проверку, импорт и14 standalone test scripts. Ни один SCRIPT ERROR/ERROR не подавляется. В sandbox импорту редактора требуется разрешение открыть локальный debug socket; игровая симуляция сетевой зависимости не имеет.

Проверены: finite domain inventories, heat/mass ledgers, warm-core feedback, delayed absorption, wound care, NPC paths and finite trade, observer locality, Russian grammar and quantity validation, deterministic commands, numeric save/load tolerance, invalid save rejection, backups and checksums, interruption/resume and non-transferable work progress, actual project portrait scaling, touch UI at390×844/1280×800 and200% text, autosave recovery, win/death states.

Сценарий `test_survival_scenario.gd` проходит первую ночь только публичными командами; все пять целей достигнуты примерно06:04, персонаж жив и в сознании. Около8.5 игровых часов отдыха рассчитываются примерно за0.55 секунды на этом Linux CPU. Пассивный100-дневный прогон доменов занимает примерно17.4 секунды, проверяет конечность чисел/ресурсов и границы памяти; это не утверждение о100 днях полноценной жизни NPC.

Визуальная проверка выполнена реальным OpenGL renderer (llvmpipe) на X11, включая портрет с настоящими project viewport settings. Исправлено обнаруженное несоответствие: design viewport теперь390×844 с expand, а не1280×800, чтобы на телефоне был мобильный интерфейс.

Независимый reviewer нашёл два important-дефекта: прогресс очистки дымохода переносился между зданиями; завершение удалённого горения попадало в местный журнал. Исправления покрыты `test_transactions.gd`, reviewer воспроизвёл исправленное поведение. Дополнительно усилены malformed-state проверки, исправлены терморегуляция, парсер названия питья и разделение тепла печи между комнатой и водой.

Удалённый GitHub CI не приравнивается к этому локальному прогону. Android APK, Android device profiling, clinical/reference calibration и вся матрица A–G целевого ТЗ не заявляются. Полный список фактических ограничений — `PROTOTYPE_STATUS.md`.

## Новый набор проверок после смены жанра

Последовательные коммиты в main добавили `tests/test_zombies.gd`, обновили `tests/test_survival_scenario.gd` (нет победы), `tests/test_ui.gd` (настройки и без баннера), `tests/test_project_viewport.gd` (landscape design и portrait fallback). Последний CI статус должен проверяться для конкретного SHA. См. Z01–Z20 в docs/08_ACCEPTANCE.md. Эмулятор/настоящий Android не испытаны, клиническая и акустическая калибровка не выполнена.

## Perception 2.0 — новая проверка на GitHub Actions

Добавлены `test_acoustics.gd`, `test_zombie_acoustics.gd`, `test_perception.gd`, `test_acoustic_integration.gd`, изменены тесты заражённых и UI. Команды через `tools/run_tests.py` проверяют детерминированное ослабление звука, преграды, дождь/ветер, поведение заражённых без всеведения, скрытую личность NPC ночью, наблюдение после включения света, влияние кровопотери и сериализацию шумов.

**Подтверждённый ранний CI** для `6d5bfeeab8aad73247c9a7fc49da033663a4c5d3`: [GitHub Actions #43597288298](https://github.com/VovaShkrobtak/DEEPest/actions/runs/43597288298), **23/23**, включая headless import и архитектурную проверку. Последующие коммиты проверять отдельно на их SHA. Это НЕ замеры Android, не 3D-акустика, не экспериментальная калибровка и не окончательная сквозная матрица всей игры.

## Организм 2.0 — верификация 2026-11-14

**Подтверждённый коммит с кодом:** `f06b58782770455f983eeb2fcd0a59595c39d8b6`, [GitHub Actions #43600022039](https://github.com/VovaShkrobtak/DEEPest/actions/runs/43600022039): **25/25 успешных проверок** Godot 4.6.3, включая import, architecture, `test_anatomy.gd`, `test_body_actions.gd`, `test_physiology.gd`, `test_transactions.gd`, `test_perception.gd` и прочие регрессии.

**Подтверждённый коммит со спецификациями:** `20056d13e589a0c4a272970389402e2a0b350e0d`, [GitHub Actions #43600284799](https://github.com/VovaShkrobtak/DEEPest/actions/runs/43600284799): **успешный прогон** после добавления `docs/15_BODY_PHYSIOLOGY.md` и нормализации связанной документации. Полный набор тестов запускается для каждого SHA заново, даже при изменении документации.

**Проверено:** живые ограничения при работе/перемещении (в том числе перерыв крафта и сохранение прогресса), двухсторонние органы слуха/зрения, различие адреналина/боли/структурной травмы, независимость ран, локальное лечение и расход материалов, атомарный отказ при повреждённых сохранениях, миграция старого NPC и игрока, корректная сериализация параметров `String` без `StringName`.

**Не проверено:** фактический Android APK и SM-T515; медицинские reference ranges, долгосрочная регенерация костей/нервов, настройка терапии и фармакологии, полноценная анатомия суставов и органов, калиброванная модель гормонов. Утверждать реализм на основании одних 25/25 тестов нельзя — это функциональные регрессии на выбранных допущениях.
