#!/bin/bash
## https://www.ibm.com/docs/en/content-cortex/26.0.0?topic=ccpeda-creating-content-platform-engine-database-user-db2-linux-unix-windows
set -euo pipefail

# ============================================================
# ICCx / FileNet Db2 database object initialization
#
# Usage:
#   ./create_iccx_db_objects.sh <database> <environment> [--user <name>] [--dry-run]
#
# Examples:
#   ./create_iccx_db_objects.sh AVAMDMSDB ftst --dry-run
#   ./create_iccx_db_objects.sh AVAMDMSDB ftst --user myldapuser
#   ./create_iccx_db_objects.sh AVAMDMSDB ftst
#
# Options:
#   --user     Connects with CONNECT TO <db> USER <name>. Db2 prompts for
#              the password on the terminal; it is never passed as an
#              argument. Needs an interactive terminal. Without --user the
#              script connects as the logged-in OS user.
#   --password-file <path>
#              Reads the password of --user from a file instead of
#              prompting, e.g. a mounted Kubernetes secret such as
#              /secrets/db2instancepwd/password. The file must contain the
#              plain password (mounted secrets are already decoded). The
#              password is never passed as a process argument.
#   --dry-run  Connects, runs read-only feasibility checks, lists every
#              statement that would be executed and prints a report
#              (objects to create / already existing, grants, checks).
#              Nothing is changed. Exit code 1 if a check failed.
#
# Resulting schema example:
#   SVCFNDB2PERSONFTST
#
# Resulting tablespace example (identical on all environments):
#   TS_PERSON_DAT
#
# Important:
#   Db2 users must already exist in the operating system,
#   LDAP or the configured Db2 authentication provider.
# ============================================================


# ------------------------------------------------------------
# Logging and error handling
# ------------------------------------------------------------

log()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}


error()
{
    echo "ERROR: $1" >&2
    exit 1
}


# Important: all db2 calls must run in the main shell, never inside $(...).
# The CLP shares one connection only between db2 calls with the same parent
# process. A db2 call inside $(function) has another parent and fails with
# SQL1024N. Query results are therefore returned in the variable DB2_RESULT.
#
# Runs a Db2 CLP command. Db2 CLP return codes:
#   0 = success, 1 = no rows found, 2 = warning  -> accepted
#   4 = Db2/SQL error, 8 = CLP system error      -> abort
db2_exec()
{
    local rc=0

    db2 "$@" || rc=$?

    if [ "${rc}" -ge 4 ]; then
        error "Db2 command failed with return code ${rc}"
    fi
}


run_db2()
{
    local statement="$1"

    if [ "${DRY_RUN}" = "yes" ]; then
        echo "[DRY-RUN] Would execute: ${statement}"
        if [[ "${statement}" == GRANT* ]]; then
            GRANT_COUNT=$((GRANT_COUNT + 1))
        fi
        return 0
    fi

    echo "Executing: ${statement}"
    db2_exec -v "${statement}"
}


# ------------------------------------------------------------
# Input parameters
# ------------------------------------------------------------

DRY_RUN="no"
CONNECT_USER=""
PASSWORD_FILE=""
GRANT_COUNT=0
POSITIONAL=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN="yes" ;;
        --user)
            [ "$#" -ge 2 ] || error "Option --user requires a user name."
            CONNECT_USER="$2"
            shift
            ;;
        --password-file)
            [ "$#" -ge 2 ] || error "Option --password-file requires a file path."
            PASSWORD_FILE="$2"
            shift
            ;;
        -*)        error "Unknown option '$1'. Supported: --user, --password-file, --dry-run." ;;
        *)         POSITIONAL+=("$1") ;;
    esac
    shift
done

if [ "${#POSITIONAL[@]}" -gt 2 ]; then
    error "Too many arguments. Usage: $0 <database> <environment> [--user <name>] [--dry-run]"
fi

DB_NAME="${POSITIONAL[0]:-}"
ENV_SUFFIX="${POSITIONAL[1]:-}"

if [ -z "${DB_NAME}" ] || [ -z "${ENV_SUFFIX}" ]; then
    echo "Usage: $0 <database> <environment> [--user <name>] [--dry-run]"
    echo "Example: $0 AVAMDMSDB ftst --user myldapuser --dry-run"
    exit 1
fi

if [ -n "${CONNECT_USER}" ]; then
    [[ "${CONNECT_USER}" =~ ^[A-Za-z0-9_.@-]+$ ]] ||
        error "Invalid user name for --user. Allowed: letters, digits, underscore, dot, at sign, hyphen."
fi

if [ -n "${PASSWORD_FILE}" ]; then
    [ -n "${CONNECT_USER}" ] || error "Option --password-file requires --user."

    [[ "${PASSWORD_FILE}" =~ ^/[A-Za-z0-9._/-]+$ ]] ||
        error "Invalid path for --password-file. Use an absolute path (letters, digits, . _ / -)."
fi

# Allowlist validation: values are used in SQL statements and identifiers
[[ "${DB_NAME}" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] ||
    error "Invalid database name. Allowed: letters, digits, underscore; must start with a letter."

[[ "${ENV_SUFFIX}" =~ ^[A-Za-z0-9]+$ ]] ||
    error "Invalid environment. Allowed: letters and digits only."


# ------------------------------------------------------------
# Normalize environment suffix
# ------------------------------------------------------------

ENV_LOWER="$(echo "${ENV_SUFFIX}" | tr '[:upper:]' '[:lower:]')"
ENV_UPPER="$(echo "${ENV_SUFFIX}" | tr '[:lower:]' '[:upper:]')"


# ------------------------------------------------------------
# General Db2 configuration
# ------------------------------------------------------------

# Tablespace names are identical on all environments (no environment suffix)
BUFFERPOOL="AVAMDMSDBP32KB"
TEMP_TABLESPACE="ICCX_TEMP"
SYSTEM_TEMP_TABLESPACE="ICCX_SYSTEMP"

PAGE_SIZE="32K"
PAGE_SIZE_BYTES="32768"


# ------------------------------------------------------------
# ICCx users and schemas
# ------------------------------------------------------------

ICN_USER="svcfndb2icn${ENV_LOWER}"
GCD_USER="svcfndb2gcd${ENV_LOWER}"
LOGI_USER="svcfndb2logistik${ENV_LOWER}"
PERSON_USER="svcfndb2person${ENV_LOWER}"
UNTER_USER="svcfndb2unternehmen${ENV_LOWER}"

ICN_SCHEMA="${ICN_USER}"
GCD_SCHEMA="${GCD_USER}"
LOGI_SCHEMA="${LOGI_USER}"
PERSON_SCHEMA="${PERSON_USER}"
UNTER_SCHEMA="${UNTER_USER}"

ALL_USERS=(
    "${ICN_USER}"
    "${GCD_USER}"
    "${LOGI_USER}"
    "${PERSON_USER}"
    "${UNTER_USER}"
)


# ------------------------------------------------------------
# Check connection
# ------------------------------------------------------------

# Reads the password from PASSWORD_FILE into DB_PASSWORD. The value is never
# printed and never passed to db2 as an argument. Trailing newlines are
# removed by the command substitution.
read_password_file()
{
    [ -f "${PASSWORD_FILE}" ] ||
        error "Password file '${PASSWORD_FILE}' does not exist or is not a regular file."

    [ -r "${PASSWORD_FILE}" ] ||
        error "Password file '${PASSWORD_FILE}' is not readable."

    DB_PASSWORD="$(cat "${PASSWORD_FILE}")"

    [[ -n "${DB_PASSWORD}" && "${DB_PASSWORD}" != *[[:space:]]* ]] ||
        error "The password in '${PASSWORD_FILE}' is empty or contains whitespace."
}


# Temporary file for query results (mode 0600), removed on exit
DB2_TMP="$(mktemp)"
DB2_RESULT=""

# Always release the connection and remove the temp file, also if the
# script aborts
trap 'db2 "CONNECT RESET" >/dev/null 2>&1 || true; rm -f "${DB2_TMP}"' EXIT

log "Connecting to database ${DB_NAME}"

# Runs in the main shell (not in $(...)), so that all later db2 calls of
# this shell share the connection.
connect_rc=0

if [ -n "${CONNECT_USER}" ] && [ -n "${PASSWORD_FILE}" ]; then
    read_password_file

    # The password goes through a 0600 file, never through process
    # arguments (visible in ps). The file is emptied right after the connect.
    printf 'CONNECT TO %s USER %s USING %s\n' \
        "${DB_NAME}" "${CONNECT_USER}" "${DB_PASSWORD}" > "${DB2_TMP}"
    DB_PASSWORD=""
    db2 -f "${DB2_TMP}" || connect_rc=$?
    : > "${DB2_TMP}"
elif [ -n "${CONNECT_USER}" ]; then
    # Without USING, the CLP prompts for the password on the terminal
    [ -t 0 ] || error "Option --user prompts for the password and needs an interactive terminal."
    db2 "CONNECT TO ${DB_NAME} USER ${CONNECT_USER}" || connect_rc=$?
else
    db2 "CONNECT TO ${DB_NAME}" || connect_rc=$?
fi

if [ "${connect_rc}" -ge 4 ]; then
    error "Could not connect to database ${DB_NAME}"
fi


# ------------------------------------------------------------
# Dry-run report and checks
# Read-only queries that predict typical failures of the real run.
# ------------------------------------------------------------

DRY_RUN_PROBLEMS=0
DRY_RUN_WARNINGS=0
REPORT_LINES=()

check_ok()
{
    echo "[CHECK OK]   $1"
}


check_warn()
{
    echo "[CHECK WARN] $1"
    DRY_RUN_WARNINGS=$((DRY_RUN_WARNINGS + 1))
}


check_fail()
{
    echo "[CHECK FAIL] $1"
    DRY_RUN_PROBLEMS=$((DRY_RUN_PROBLEMS + 1))
}


# Records one object for the dry-run report: type, name, action
report_add()
{
    REPORT_LINES+=("$1|$2|$3")
}


# Single-value query. Sets DB2_RESULT to the value, or to an empty string if
# the query cannot be executed (missing view, missing privilege, no rows).
try_value()
{
    local rc=0

    DB2_RESULT=""
    db2 -x "$1" > "${DB2_TMP}" 2>&1 || rc=$?

    if [ "${rc}" -lt 4 ]; then
        DB2_RESULT="$(tr -d ' \n' < "${DB2_TMP}")"
    fi
}


# Single-value query. Sets DB2_RESULT. Unlike try_value, a failure aborts
# and shows the Db2 message. Return codes 1 (no rows) and 2 (warning) are
# accepted, as in db2_exec.
db2_value()
{
    local rc=0

    DB2_RESULT=""
    db2 -x "$1" > "${DB2_TMP}" 2>&1 || rc=$?

    if [ "${rc}" -ge 4 ]; then
        cat "${DB2_TMP}" >&2
        error "Query failed with return code ${rc}: $1"
    fi

    DB2_RESULT="$(tr -d ' \n' < "${DB2_TMP}")"
}


# Counts the given authorities (SQL list) held by the connected user,
# directly or via group, role or PUBLIC. Sets DB2_RESULT.
count_session_authorities()
{
    try_value \
        "SELECT COUNT(*)
           FROM TABLE(SYSPROC.AUTH_LIST_AUTHORITIES_FOR_AUTHID(SESSION_USER, 'U')) AS T
          WHERE AUTHORITY IN ($1)
            AND 'Y' IN (D_USER, D_GROUP, D_PUBLIC, ROLE_USER, ROLE_GROUP, ROLE_PUBLIC)"
}


run_dry_run_checks()
{
    local session_user
    local count
    local user
    local bp_page_size
    local resolvable=0

    log "Dry-run feasibility checks"

    db2_value "VALUES SESSION_USER"
    session_user="${DB2_RESULT}"

    [ -n "${session_user}" ] || error "Could not determine the connected user"

    # 1. Authority to create bufferpool, tablespaces and schemas
    count_session_authorities "'DBADM','SYSADM'"
    count="${DB2_RESULT}"
    if [ -z "${count}" ]; then
        check_warn "Could not determine the authorities of ${session_user}."
    elif [ "${count}" -gt 0 ]; then
        check_ok "${session_user} holds DBADM or SYSADM (create bufferpool, tablespaces, schemas)."
    else
        check_fail "${session_user} holds neither DBADM nor SYSADM. CREATE BUFFERPOOL, CREATE TABLESPACE and CREATE SCHEMA would fail."
    fi

    # 2. Authority to grant privileges
    count_session_authorities "'ACCESSCTRL','SECADM'"
    count="${DB2_RESULT}"
    if [ -z "${count}" ]; then
        check_warn "Could not determine the authorities of ${session_user}."
    elif [ "${count}" -gt 0 ]; then
        check_ok "${session_user} holds ACCESSCTRL or SECADM (GRANT)."
    else
        check_fail "${session_user} holds neither ACCESSCTRL nor SECADM. The GRANT statements would fail."
    fi

    # 3. Automatic storage: a default storage group is required
    try_value \
        "SELECT COUNT(*)
           FROM SYSCAT.STOGROUPS
          WHERE DEFAULTSG = 'Y'
          WITH UR"
    count="${DB2_RESULT}"
    if [ -z "${count}" ]; then
        check_warn "Could not check the default storage group."
    elif [ "${count}" -gt 0 ]; then
        check_ok "A default storage group exists (MANAGED BY AUTOMATIC STORAGE)."
    else
        check_fail "No default storage group. Tablespaces MANAGED BY AUTOMATIC STORAGE cannot be created."
    fi

    # 4. An existing bufferpool must have the expected page size
    if bufferpool_exists "${BUFFERPOOL}"; then
        try_value \
            "SELECT PAGESIZE
               FROM SYSCAT.BUFFERPOOLS
              WHERE BPNAME = UPPER('${BUFFERPOOL}')
              WITH UR"
        bp_page_size="${DB2_RESULT}"
        if [ "${bp_page_size}" = "${PAGE_SIZE_BYTES}" ]; then
            check_ok "Existing bufferpool ${BUFFERPOOL} has page size ${PAGE_SIZE}."
        else
            check_fail "Existing bufferpool ${BUFFERPOOL} has page size '${bp_page_size}', expected ${PAGE_SIZE_BYTES}. Tablespaces cannot use it."
        fi
    fi

    # 5. Users must exist outside Db2 (OS / LDAP). Only checkable via the host.
    if command -v getent >/dev/null 2>&1; then
        for user in "${ALL_USERS[@]}"; do
            if getent passwd "${user}" >/dev/null 2>&1; then
                resolvable=$((resolvable + 1))
            else
                check_warn "User ${user} is not resolvable on this host (getent passwd). It must exist in OS/LDAP before FileNet connects."
            fi
        done
        if [ "${resolvable}" -eq "${#ALL_USERS[@]}" ]; then
            check_ok "All ${resolvable} service users are resolvable on this host."
        fi
    else
        check_warn "getent not available. Existence of the service users in OS/LDAP was not checked."
    fi
}


print_dry_run_report()
{
    local line
    local type
    local name
    local action
    local to_create=0
    local existing=0

    log "DRY-RUN REPORT: ${DB_NAME} / ${ENV_UPPER}"

    printf '%-24s %-26s %s\n' "TYPE" "NAME" "ACTION"
    printf '%-24s %-26s %s\n' "------------------------" "--------------------------" "------------------------"

    for line in "${REPORT_LINES[@]}"; do
        IFS='|' read -r type name action <<< "${line}"
        printf '%-24s %-26s %s\n' "${type}" "${name}" "${action}"

        if [ "${action}" = "CREATE" ]; then
            to_create=$((to_create + 1))
        else
            existing=$((existing + 1))
        fi
    done

    echo
    echo "Objects to create     : ${to_create}"
    echo "Objects already there : ${existing}"
    echo "GRANT statements      : ${GRANT_COUNT} (idempotent, always executed)"
    echo "Failed checks         : ${DRY_RUN_PROBLEMS}"
    echo "Warnings              : ${DRY_RUN_WARNINGS}"
    echo
    echo "Users and schemas:"
    printf '  %s\n' "${ALL_USERS[@]}"
    echo
    echo "No changes were made."

    if [ "${DRY_RUN_PROBLEMS}" -gt 0 ]; then
        error "Dry run found ${DRY_RUN_PROBLEMS} problem(s). The real run would likely fail."
    fi
}


# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

# The existence checks abort with the Db2 message if the query fails,
# instead of treating an error as "object does not exist".
bufferpool_exists()
{
    local bufferpool_name="$1"

    db2_value \
        "SELECT COUNT(*)
           FROM SYSCAT.BUFFERPOOLS
          WHERE BPNAME = UPPER('${bufferpool_name}')
          WITH UR"
    [ "${DB2_RESULT}" = "1" ]
}


tablespace_exists()
{
    local tablespace_name="$1"

    db2_value \
        "SELECT COUNT(*)
           FROM SYSCAT.TABLESPACES
          WHERE TBSPACE = UPPER('${tablespace_name}')
          WITH UR"
    [ "${DB2_RESULT}" = "1" ]
}


system_temp_tablespace_exists()
{
    # Db2 needs one system temporary tablespace per page size in use
    db2_value \
        "SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
           FROM SYSCAT.TABLESPACES
          WHERE DATATYPE = 'T'
            AND PAGESIZE = ${PAGE_SIZE_BYTES}
          WITH UR"
    [ "${DB2_RESULT}" = "1" ]
}


schema_exists()
{
    local schema_name="$1"

    db2_value \
        "SELECT COUNT(*)
           FROM SYSCAT.SCHEMATA
          WHERE SCHEMANAME = UPPER('${schema_name}')
          WITH UR"
    [ "${DB2_RESULT}" = "1" ]
}


create_bufferpool()
{
    local bufferpool_name="$1"

    if bufferpool_exists "${bufferpool_name}"; then
        echo "Bufferpool ${bufferpool_name} already exists. Skipping."
        report_add "BUFFERPOOL" "${bufferpool_name}" "EXISTS"
    else
        report_add "BUFFERPOOL" "${bufferpool_name}" "CREATE"
        run_db2 \
            "CREATE BUFFERPOOL ${bufferpool_name}
             SIZE AUTOMATIC
             PAGESIZE ${PAGE_SIZE}"
    fi
}


create_regular_tablespace()
{
    local tablespace_name="$1"
    local caching_option="$2"
    local existing_page_size

    if tablespace_exists "${tablespace_name}"; then
        echo "Tablespace ${tablespace_name} already exists. Skipping."
        report_add "TABLESPACE" "${tablespace_name}" "EXISTS"

        if [ "${DRY_RUN}" = "yes" ]; then
            try_value \
                "SELECT PAGESIZE
                   FROM SYSCAT.TABLESPACES
                  WHERE TBSPACE = UPPER('${tablespace_name}')
                  WITH UR"
            existing_page_size="${DB2_RESULT}"
            if [ "${existing_page_size}" != "${PAGE_SIZE_BYTES}" ]; then
                check_fail "Existing tablespace ${tablespace_name} has page size '${existing_page_size}', expected ${PAGE_SIZE_BYTES}."
            fi
        fi
    else
        report_add "TABLESPACE" "${tablespace_name}" "CREATE"
        run_db2 \
            "CREATE LARGE TABLESPACE ${tablespace_name}
             PAGESIZE ${PAGE_SIZE}
             MANAGED BY AUTOMATIC STORAGE
             AUTORESIZE YES
             BUFFERPOOL ${BUFFERPOOL}
             ${caching_option}"
    fi
}


# Creates TS_<group>_DAT, TS_<group>_IND, TS_<group>_LOB
create_tablespace_set()
{
    local group="$1"

    create_regular_tablespace \
        "TS_${group}_DAT" \
        "NO FILE SYSTEM CACHING"

    create_regular_tablespace \
        "TS_${group}_IND" \
        "NO FILE SYSTEM CACHING"

    create_regular_tablespace \
        "TS_${group}_LOB" \
        "FILE SYSTEM CACHING"
}


create_temporary_tablespace()
{
    local tablespace_name="$1"

    if tablespace_exists "${tablespace_name}"; then
        echo "Temporary tablespace ${tablespace_name} already exists. Skipping."
        report_add "USER TEMP TABLESPACE" "${tablespace_name}" "EXISTS"
    else
        report_add "USER TEMP TABLESPACE" "${tablespace_name}" "CREATE"
        run_db2 \
            "CREATE USER TEMPORARY TABLESPACE ${tablespace_name}
             PAGESIZE ${PAGE_SIZE}
             MANAGED BY AUTOMATIC STORAGE
             BUFFERPOOL ${BUFFERPOOL}"
    fi
}


create_system_temporary_tablespace()
{
    local tablespace_name="$1"

    if system_temp_tablespace_exists; then
        echo "A system temporary tablespace with page size ${PAGE_SIZE} already exists. Skipping."
        report_add "SYSTEM TEMP TABLESPACE" "(existing ${PAGE_SIZE})" "EXISTS"
    else
        report_add "SYSTEM TEMP TABLESPACE" "${tablespace_name}" "CREATE"
        run_db2 \
            "CREATE SYSTEM TEMPORARY TABLESPACE ${tablespace_name}
             PAGESIZE ${PAGE_SIZE}
             MANAGED BY AUTOMATIC STORAGE
             BUFFERPOOL ${BUFFERPOOL}"
    fi
}


create_schema()
{
    local schema_name="$1"
    local authorization_user="$2"

    local current_owner

    if schema_exists "${schema_name}"; then
        echo "Schema ${schema_name} already exists. Skipping."
        report_add "SCHEMA" "$(echo "${schema_name}" | tr '[:lower:]' '[:upper:]')" "EXISTS"

        if [ "${DRY_RUN}" = "yes" ]; then
            try_value \
                "SELECT OWNER
                   FROM SYSCAT.SCHEMATA
                  WHERE SCHEMANAME = UPPER('${schema_name}')
                  WITH UR"
            current_owner="${DB2_RESULT}"
            if [ "${current_owner}" != "$(echo "${authorization_user}" | tr '[:lower:]' '[:upper:]')" ]; then
                check_warn "Schema ${schema_name} is owned by '${current_owner}', not by ${authorization_user}."
            fi
        fi
    else
        report_add "SCHEMA" "$(echo "${schema_name}" | tr '[:lower:]' '[:upper:]')" "CREATE"
        run_db2 \
            "CREATE SCHEMA ${schema_name}
             AUTHORIZATION ${authorization_user}"
    fi
}


grant_base_permissions()
{
    local db_user="$1"

    log "Granting base permissions to ${db_user}"

    run_db2 "GRANT CONNECT ON DATABASE TO USER ${db_user}"
    run_db2 "GRANT CREATETAB ON DATABASE TO USER ${db_user}"
    run_db2 "GRANT IMPLICIT_SCHEMA ON DATABASE TO USER ${db_user}"

    run_db2 \
        "GRANT SELECT ON TABLE SYSIBM.SYSVERSIONS
         TO USER ${db_user}"

    run_db2 \
        "GRANT SELECT ON TABLE SYSCAT.DATATYPES
         TO USER ${db_user}"

    run_db2 \
        "GRANT SELECT ON TABLE SYSCAT.INDEXES
         TO USER ${db_user}"

    run_db2 \
        "GRANT SELECT ON TABLE SYSIBM.SYSDUMMY1
         TO USER ${db_user}"

    run_db2 \
        "GRANT USAGE ON WORKLOAD SYSDEFAULTUSERWORKLOAD
         TO USER ${db_user}"

    run_db2 \
        "GRANT USE OF TABLESPACE ${TEMP_TABLESPACE}
         TO USER ${db_user}"
}


grant_tablespace_use()
{
    local db_user="$1"
    shift

    local tablespace_name

    log "Granting tablespace permissions to ${db_user}"

    for tablespace_name in "$@"; do
        run_db2 \
            "GRANT USE OF TABLESPACE ${tablespace_name}
             TO USER ${db_user}"
    done
}


# Grants USE on the DAT, IND and LOB tablespaces of the given groups
grant_tablespace_sets()
{
    local db_user="$1"
    shift

    local group
    local tablespaces=()

    for group in "$@"; do
        tablespaces+=(
            "TS_${group}_DAT"
            "TS_${group}_IND"
            "TS_${group}_LOB"
        )
    done

    grant_tablespace_use "${db_user}" "${tablespaces[@]}"
}


# ============================================================
# Step 1: Create 32 KB bufferpool
# ============================================================

log "Creating or checking 32 KB bufferpool"

create_bufferpool "${BUFFERPOOL}"


# ============================================================
# Step 2: Create temporary tablespaces
# ============================================================

log "Creating or checking system temporary tablespace"

create_system_temporary_tablespace "${SYSTEM_TEMP_TABLESPACE}"

log "Creating or checking user temporary tablespace"

create_temporary_tablespace "${TEMP_TABLESPACE}"


# ============================================================
# Step 3: Create tablespaces
#   ICN, GCD:             DAT only
#   Object stores (OS):   DAT, IND, LOB per group
# ============================================================

log "Creating ICN tablespace"
create_regular_tablespace "TS_ICN_DAT" "NO FILE SYSTEM CACHING"

log "Creating GCD tablespace"
create_regular_tablespace "TS_GCD_DAT" "NO FILE SYSTEM CACHING"

log "Creating PERSON tablespaces"
create_tablespace_set "PERSON"

log "Creating PERSONVW tablespaces"
create_tablespace_set "PERSONVW"

log "Creating LOGISTIK tablespaces"
create_tablespace_set "LOGI"

log "Creating UNTERNEHMEN tablespaces"
create_tablespace_set "UNTER"


# ============================================================
# Step 4: Create schemas
# ============================================================

log "Creating ICCx schemas"

create_schema "${ICN_SCHEMA}" "${ICN_USER}"
create_schema "${GCD_SCHEMA}" "${GCD_USER}"
create_schema "${LOGI_SCHEMA}" "${LOGI_USER}"
create_schema "${PERSON_SCHEMA}" "${PERSON_USER}"
create_schema "${UNTER_SCHEMA}" "${UNTER_USER}"


# ============================================================
# Step 5: Grant basic FileNet/ICCx permissions
# ============================================================

for DB_USER in "${ALL_USERS[@]}"; do
    grant_base_permissions "${DB_USER}"
done


# ============================================================
# Step 6: Grant tablespace permissions
# ============================================================

grant_tablespace_use  "${ICN_USER}"    "TS_ICN_DAT"
grant_tablespace_use  "${GCD_USER}"    "TS_GCD_DAT"
grant_tablespace_sets "${PERSON_USER}" "PERSON" "PERSONVW"
grant_tablespace_sets "${LOGI_USER}"   "LOGI"
grant_tablespace_sets "${UNTER_USER}"  "UNTER"


# ============================================================
# Step 7: Optional security hardening
# ============================================================

# Only enable this after confirming that no other application
# relies on the PUBLIC CONNECT privilege.
#
# run_db2 "REVOKE CONNECT ON DATABASE FROM PUBLIC"


# ============================================================
# Dry run: feasibility checks and report instead of validation
# ============================================================

if [ "${DRY_RUN}" = "yes" ]; then
    run_dry_run_checks
    print_dry_run_report
    exit 0
fi



# ============================================================
# Step 8: Validation
# ============================================================

log "Created schemas"

db2_exec \
    "SELECT SCHEMANAME,
            OWNER
       FROM SYSCAT.SCHEMATA
      WHERE SCHEMANAME IN (
            UPPER('${ICN_SCHEMA}'),
            UPPER('${GCD_SCHEMA}'),
            UPPER('${LOGI_SCHEMA}'),
            UPPER('${PERSON_SCHEMA}'),
            UPPER('${UNTER_SCHEMA}')
      )
      ORDER BY SCHEMANAME"


log "Created tablespaces"

db2_exec \
    "SELECT TBSPACE,
            TBSPACETYPE,
            PAGESIZE,
            BUFFERPOOLID
       FROM SYSCAT.TABLESPACES
      WHERE TBSPACE LIKE 'TS!_%' ESCAPE '!'
         OR TBSPACE LIKE 'ICCX!_%' ESCAPE '!'
      ORDER BY TBSPACE"


log "Database privileges"

db2_exec \
    "SELECT GRANTEE,
            CONNECTAUTH,
            CREATETABAUTH,
            IMPLSCHEMAAUTH
       FROM SYSCAT.DBAUTH
      WHERE GRANTEE IN (
            UPPER('${ICN_USER}'),
            UPPER('${GCD_USER}'),
            UPPER('${LOGI_USER}'),
            UPPER('${PERSON_USER}'),
            UPPER('${UNTER_USER}')
      )
      ORDER BY GRANTEE"


# ============================================================
# Done (connection is released by the EXIT trap)
# ============================================================

log "ICCx database initialization completed successfully"

echo "Database          : ${DB_NAME}"
echo "Environment       : ${ENV_UPPER}"
echo "Bufferpool        : ${BUFFERPOOL}"
echo "Temporary TS      : ${TEMP_TABLESPACE}"
echo "System temp TS    : ${SYSTEM_TEMP_TABLESPACE}"
echo
echo "Users and schemas:"
printf '  %s\n' "${ALL_USERS[@]}"
