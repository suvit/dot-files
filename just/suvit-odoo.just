# Общие just-рецепты для odoo-11 проектов (gitlab.suvit.ru, CI на maintainer-quality-tools).
# Проект ОБЯЗАН определить эти переменные до импорта (just не умеет дефолты
# и запрещает повторное определение):
#
#   TEST_DB      := "taxn-test"   # база по умолчанию для create/drop/recreate и test-рецептов
#   WT_TEMPLATE  := "taxn-test"   # база-шаблон для копий в wt-create
#   PROTECTED_DB := "taxn-test"   # список рабочих баз через пробел (dump-load их не трогает)
#   PROD_HOST    := "prod.example.ru"  # боевой сервер (prod-log-grep, prod-sql)
#   PROD_DB      := "prod_db"          # боевая база для prod-sql
#   PROD_LOG     := "/home/prod/log/odoo.log"  # лог боя для prod-log-grep
#   import '~/.config/just/suvit-odoo.just'
#
# Оригинал лежит в ~/dotfiles/just/, в ~/.config/just/ — симлинк на него.

# ---------------------------------------------------------------------------
# Вспомогательное

# Параметры подключения к БД из local.conf (env DB_* имеют приоритет).
# Используется внутри other-рецептов: just --quiet db-env
[private]
[positional-arguments]
db-env *_:
    #!/usr/bin/env bash
    conf_val() { grep -E "^[[:space:]]*$1 = " local.conf | head -1 | cut -d'=' -f2 | xargs; }
    echo "DB_HOST=${DB_HOST:-$(conf_val db_host)}"
    echo "DB_PORT=${DB_PORT:-$(conf_val db_port)}"
    echo "DB_USER=${DB_USER:-$(conf_val db_user)}"
    echo "DB_PASSWORD=${DB_PASSWORD:-$(conf_val db_password)}"

# ---------------------------------------------------------------------------
# Базы данных

# Создать тестовую базу (параметры из local.conf)
[positional-arguments]
create-test-db db="":
    #!/usr/bin/env bash
    set -e
    DB="{{db}}"; [ -z "$DB" ] && DB="{{TEST_DB}}"
    eval "$(just --quiet db-env)"
    export PGPASSWORD="$DB_PASSWORD"
    createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB" 2>/dev/null \
        || echo "База уже существует: $DB"

# Удалить базу с принудительным отключением подключений
[positional-arguments]
drop-test-db db="":
    #!/usr/bin/env bash
    set -e
    DB="{{db}}"; [ -z "$DB" ] && DB="{{TEST_DB}}"
    eval "$(just --quiet db-env)"
    export PGPASSWORD="$DB_PASSWORD"
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname = '$DB'" | grep -q 1; then
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c \
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB' AND pid <> pg_backend_pid()" > /dev/null
        dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB"
        echo "База удалена: $DB"
    else
        echo "Базы нет: $DB"
    fi

# Пересоздать тестовую базу (имя — TEST_DB проекта)
recreate-test-db:
    #!/usr/bin/env bash
    set -e
    DB="{{TEST_DB}}"
    eval "$(just --quiet db-env)"
    export PGPASSWORD="$DB_PASSWORD"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB' AND pid <> pg_backend_pid()" > /dev/null 2>&1 || true
    dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB" 2>/dev/null || true
    createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB"
    echo "База пересоздана: $DB"

# Клон живой базы: в отличие от createdb -T <шаблон> не требует свободности источника
# (wt-create с базой отключает подключения к шаблону — тут наоборот, источник не трогаем).
# pg-инструменты берём из контейнера postgresdb16: хостовый pg_dump старее серверного PG16
# и в пайпе абортится молча — pipefail обязателен.
#   just db-clone 11_mrp 11_mrp_scratch
[positional-arguments]
db-clone src dst:
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(just --quiet db-env)"
    createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "{{dst}}"
    docker exec -e DB_USER="$DB_USER" -e PGPASSWORD="$DB_PASSWORD" postgresdb16 \
        sh -c 'pg_dump -U "$DB_USER" -d "$1" -Fc | pg_restore -U "$DB_USER" -d "$2" --no-owner' _ "{{src}}" "{{dst}}"
    echo "Склонировано: {{src}} -> {{dst}}"

# Раскатать дамп базы (plain SQL, голый или .gz, в т.ч. снятый с pg_dump -C)
# в ЛОКАЛЬНУЮ postgres (параметры из local.conf).
# Имя базы по умолчанию — из имени файла: 11_mrp_dev_2026-10-02.gz -> 11_mrp_dev_2026-10-02
# Примеры:
#   just dump-load ~/Downloads/dump.gz          # новая база с именем из файла
#   just dump-load ~/Downloads/dump.gz my_base  # в базу my_base
#   FRESH=1 just dump-load dump.gz my_base      # пересоздать my_base и залить заново
#   FORCE=1 just dump-load dump.gz base11       # в рабочую базу (по умолчанию запрещено)
# Повторный раскат в существующую базу даёт ДУБЛИКАТЫ (PK/констрейнты дампом создаются
# только в конце) — поэтому занятую базу рецепт не трогает: FRESH=1 или другое имя.
# Ловушка дампов -C: внутри CREATE DATABASE и \connect "<имя>" без подмены имени psql
# переключается на базу из дампа и пишет в неё. Рецепт подменяет.
# Идёт под nice 19 + best-effort 7 (idle-класс IO): машина не встаёт колом.
# Перед раскатом в базу, на которой крутится odoo, odoo лучше остановить.
[positional-arguments]
dump-load file db="":
    #!/usr/bin/env bash
    set -u
    FILE="$1"
    [ -f "$FILE" ] || { echo "Нет файла: $FILE"; exit 1; }
    eval "$(just --quiet db-env)"

    BASE_NAME="$(basename "$FILE")"
    DEFAULT_DB="${BASE_NAME%.gz}"
    DEFAULT_DB="${DEFAULT_DB%.sql}"
    DEFAULT_DB="${DEFAULT_DB%.dump}"
    DB="${2:-$DEFAULT_DB}"
    case "$DB" in *[!A-Za-z0-9_.-]*) echo "Некорректное имя базы: $DB"; exit 1;; esac

    # защита рабочих баз: активный db_name из local.conf и список PROTECTED_DB — только с FORCE=1
    ACTIVE_DB="$(grep -E '^[[:space:]]*db_name[[:space:]]*=' local.conf | head -1 | cut -d'=' -f2 | xargs || true)"
    for P in {{PROTECTED_DB}} "$ACTIVE_DB"; do
        if [ -z "${FORCE:-}" ] && [ "$DB" = "$P" ]; then
            echo "База $DB — рабочая. Перезалив только по команде: FORCE=1 just dump-load ..."
            exit 1
        fi
    done

    head_dump() { case "$FILE" in *.gz) gunzip -c "$FILE" 2>/dev/null;; *) head -c 400000 "$FILE";; esac | head -c 400000; }
    SRC_DB="$(head_dump | sed -n 's/^CREATE DATABASE "\([^"]*\)".*/\1/p' | head -1)"
    if [ -n "$SRC_DB" ]; then
        echo "Дамп с -C (встроенное имя базы: $SRC_DB) — переименовываю в $DB"
    else
        echo "Дамп без CREATE DATABASE — грузу прямо в $DB"
    fi

    export PGPASSWORD="$DB_PASSWORD"
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -At \
         -c "select 1 from pg_database where datname = '$DB'" | grep -q '^1$'; then
        if [ -n "${FRESH:-}" ]; then
            echo "FRESH=1 — пересоздаю $DB, данные заменяются дампом"
            dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB"
        else
            echo "База $DB уже существует. Второй раскат в неё удвоит строки (PK создаются"
            echo "только в конце дампа, незащищённые COPY допишут дубли)."
            echo "Заново: FRESH=1 just dump-load $FILE $DB; или укажи другое имя."
            exit 1
        fi
    fi
    createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB"

    LOG="/tmp/dump_load_${DB}_$(date +%Y%m%d_%H%M%S).log"
    if [ -n "$SRC_DB" ]; then
        { case "$FILE" in *.gz) gunzip -c "$FILE";; *) cat "$FILE";; esac \
          | awk -v src="$SRC_DB" -v db="$DB" '
              $0 == "CREATE DATABASE \"" src "\"" { print "CREATE DATABASE \"" db "\""; next }
              $0 == "\\connect \"" src "\""       { print "\\connect \"" db "\""; next }
              { print }'; } \
        | nice -n 19 ionice -c2 -n7 psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
            -d "$DB" -q -v ON_ERROR_STOP=0 \
            -c "SET synchronous_commit = off; SET maintenance_work_mem = '256MB'; SET work_mem = '64MB'" \
            -f /dev/stdin > "$LOG" 2>&1
    else
        { case "$FILE" in *.gz) gunzip -c "$FILE";; *) cat "$FILE";; esac; } \
        | nice -n 19 ionice -c2 -n7 psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
            -d "$DB" -q -v ON_ERROR_STOP=0 \
            -c "SET synchronous_commit = off; SET maintenance_work_mem = '256MB'; SET work_mem = '64MB'" \
            -f /dev/stdin > "$LOG" 2>&1
    fi

    ERR_N=$(grep -c "ERROR" "$LOG" 2>/dev/null || true)
    TABLES=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB" -At -c "select count(*) from pg_class where relkind='r'" 2>/dev/null)
    SIZE=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -At -c "select pg_size_pretty(pg_database_size('$DB'))" 2>/dev/null)
    echo "Готово: база $DB, таблиц: ${TABLES:-?}, размер ${SIZE:-?}, ошибок в логе: ${ERR_N:-?} (см. $LOG)"
    echo "Проверь полноту count(*) на поздних по порядку таблицах."
    echo "Если раскат оборвался — не повторяй в ту же базу: FRESH=1 just dump-load $FILE $DB"

# ---------------------------------------------------------------------------
# Worktree

# Создать worktree + копию local.conf с путями до worktree.
# Если <имя> — существующая ветка (локальная или origin), worktree подключится
# к ней: удобно проверять задачи сотрудников (база — по второму аргументу).
# База: только если указана — копия из шаблона WT_TEMPLATE (env WT_TEMPLATE
# перекрывает проект), имя пишется в флаг .wt-db (для wt-remove).
# Примеры:
#   just wt-create my_wt              # только worktree, без базы
#   just wt-create my_wt my_base      # worktree + база my_base (копия шаблона)
#   just wt-create ivan_fix review_ivan   # worktree на ветке коллеги + база
#   WT_TEMPLATE=other_db just wt-create my_wt my_base   # другой шаблон базы
[positional-arguments]
wt-create name db="":
    #!/usr/bin/env bash
    set -e
    NAME="$1"
    DB="$2"
    WT_DIR=".claude/worktrees/$NAME"
    WT_DIR_ABS="$PWD/$WT_DIR"
    TEMPLATE="{{env_var_or_default('WT_TEMPLATE', WT_TEMPLATE)}}"

    if [ -e "$WT_DIR" ]; then
        echo "Worktree уже существует: $WT_DIR"
        exit 1
    fi
    [ -f local.conf ] || { echo "Нет local.conf в основной папке — нечего копировать"; exit 1; }

    # 1. Worktree + ветка: локальная; если её нет — с сервера (ревью); только если
    #    нет нигде — новая
    if git show-ref --verify --quiet "refs/heads/$NAME"; then
        echo "Ветка $NAME существует локально — подключаю worktree к ней"
        git worktree add "$WT_DIR" "$NAME"
    else
        git fetch origin "$NAME" 2>/dev/null || true
        if git show-ref --verify --quiet "refs/remotes/origin/$NAME"; then
            echo "Ветки $NAME локально нет — беру с сервера (origin/$NAME)"
            git branch --track "$NAME" "origin/$NAME"
            git worktree add "$WT_DIR" "$NAME"
        else
            git worktree add -b "$NAME" "$WT_DIR"
        fi
    fi

    # 2. local.conf: копия; путь worktree первым в addons_path, чтобы модули
    #    брались из worktree, а не из основной папки/симлинка; и имя базы
    cp local.conf "$WT_DIR/local.conf"
    REPO_REAL="$(readlink -f .)"
    sed -i "s|$REPO_REAL|$WT_DIR_ABS|g" "$WT_DIR/local.conf"
    sed -i "s|^addons_path = |addons_path = $WT_DIR_ABS,\n    |" "$WT_DIR/local.conf"

    # 3. Копия базы из шаблона (шаблон должен быть свободен от подключений)
    if [ -n "$DB" ]; then
        sed -i -E "s|^#? ?db_name = .*|db_name = $DB|" "$WT_DIR/local.conf"
        echo "$DB" > "$WT_DIR/.wt-db"

        eval "$(just --quiet db-env)"
        export PGPASSWORD="$DB_PASSWORD"
        PSQL=(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER")

        if ! "${PSQL[@]}" -tAc "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE'" | grep -q 1; then
            echo "Шаблон базы не найден: $TEMPLATE"
            exit 1
        fi
        if "${PSQL[@]}" -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB'" | grep -q 1; then
            echo "База уже существует, пропускаю создание: $DB"
        else
            echo "Отключаю подключения к шаблону $TEMPLATE (запущенный на нём odoo отвалится)"
            "${PSQL[@]}" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$TEMPLATE' AND pid <> pg_backend_pid()" >/dev/null
            sleep 1
            createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -T "$TEMPLATE" "$DB"
            echo "База $DB создана из шаблона $TEMPLATE"
        fi
    fi

    echo ""
    echo "Worktree готов: $WT_DIR"
    echo "Дальше — команды just запускать из папки worktree:"
    echo "  cd $WT_DIR"
    echo "  just run-odoo              # из worktree возьмёт venv основной папки, конфиг — местный"

# Удалить worktree (+ копию базы, если она создавалась через wt-create).
# Имя базы берётся из файла-флага .wt-db внутри worktree; второй аргумент задаёт базу явно
# Примеры:
#   just wt-remove my_wt          # worktree + база из флага .wt-db (если была)
#   just wt-remove my_wt my_base  # worktree + база my_base (даже если флага нет)
[positional-arguments]
wt-remove name db="":
    #!/usr/bin/env bash
    set -e
    NAME="$1"
    DB="$2"
    WT_DIR=".claude/worktrees/$NAME"

    # 1. Имя базы: из аргумента или из файла-флага
    if [ -z "$DB" ] && [ -f "$WT_DIR/.wt-db" ]; then
        DB="$(cat "$WT_DIR/.wt-db" | xargs)"
        echo "Найден флаг базы: $DB"
    fi

    # 2. Защита: коммиты, которых нет на сервере — стоп
    if [ -d "$WT_DIR" ]; then
        HEAD_SHA="$(git -C "$WT_DIR" rev-parse HEAD)"
        if ! git branch -r --contains "$HEAD_SHA" | grep -q .; then
            echo "В $NAME есть коммиты, которых нет на сервере. Сначала git push."
            exit 1
        fi
    else
        git worktree prune
    fi

    # 3. Worktree (--force из-за копий local.conf/.wt-db, они не в git)
    if [ -d "$WT_DIR" ]; then
        git worktree remove --force "$WT_DIR"
        echo "Worktree удалён: $WT_DIR"
    fi

    # 4. Локальная ветка
    if git branch -D "$NAME" 2>/dev/null; then
        echo "Ветка удалена: $NAME"
    fi

    # 5. Копия базы
    if [ -n "$DB" ]; then
        if [ ! -f local.conf ]; then
            echo "Не найден local.conf — параметры БД неизвестны, базу $DB не трогаю"
            exit 0
        fi
        eval "$(just --quiet db-env)"
        export PGPASSWORD="$DB_PASSWORD"
        PSQL=(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER")

        if "${PSQL[@]}" -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB'" | grep -q 1; then
            "${PSQL[@]}" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB' AND pid <> pg_backend_pid()" >/dev/null
            sleep 1
            dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB"
            echo "База удалена: $DB"
        else
            echo "База не существует: $DB"
        fi
    fi

# ---------------------------------------------------------------------------
# CI

# Проверить .gitlab-ci.yml без пуша: YAML валиден, каждый script-блок проходит
# bash -n, apt-вызовы только под which-guard (buster в CI-образе EOL).
check-ci:
    #!/usr/bin/env bash
    set -e
    python3 - <<'PYEOF'
    import sys, yaml, subprocess, tempfile, os
    d = yaml.safe_load(open('.gitlab-ci.yml'))
    jobs = [k for k, v in d.items() if isinstance(v, dict) and 'script' in v]
    if not jobs:
        sys.exit('нет джоб со script в .gitlab-ci.yml')
    for job in jobs:
        joined = '\n'.join(d[job]['script'])
        f = tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False)
        f.write(joined); f.close()
        r = subprocess.run(['bash', '-n', f.name], capture_output=True, text=True)
        os.unlink(f.name)
        if r.returncode != 0:
            sys.exit(f'{job}: bash -n: {r.stderr.strip()}')
        print(f'{job}: OK')
    apt_lines = [l for l in open('.gitlab-ci.yml') if 'apt-get' in l and 'which' not in l]
    print('apt-get вне which-guard строк:', len(apt_lines))
    if apt_lines:
        sys.exit(1)
    PYEOF

# Grep лога боя (PROD_LOG проекта) без «Запрос:»-простыней.
# Время в логе — UTC. Пример: just prod-log-grep 'cannot follow twice'
prod-log-grep pattern:
    #!/usr/bin/env bash
    ssh root@{{PROD_HOST}} "grep -in -- '{{pattern}}' {{PROD_LOG}} | grep -v Запрос | cut -c1-300 | tail -50"

# Read-only SQL в боевую базу PROD_DB на хосте PROD_HOST: запрос выполняется
# в READ ONLY транзакции — любой DML/DDL упадёт на стороне PG.
# Данные для тикетов, которые закрыты ACL бота.
# Пример: just prod-sql "SELECT id, name FROM res_partner WHERE id = 1"
prod-sql *sql:
    #!/usr/bin/env bash
    query="BEGIN TRANSACTION READ ONLY; {{sql}}; ROLLBACK"
    ssh root@{{PROD_HOST}} "sudo -u postgres psql {{PROD_DB}} -At -F' | ' -c \"${query}\""
