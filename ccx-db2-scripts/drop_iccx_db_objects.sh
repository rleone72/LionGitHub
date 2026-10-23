#!/bin/bash
set -euo pipefail

# ============================================================
# ICCx / FileNet Db2 database object removal
#
# Reverts everything that create_iccx_db_objects.sh created.
#
# WARNING: DESTRUCTIVE AND IRREVERSIBLE.
#   All objects inside the ICCx schemas (all FileNet tables and
#   their data) are dropped. Create a database backup first.
#
# Usage:
#   ./drop_iccx_db_objects.sh <database> <environment> [--user <name>] [--yes] [--dry-run]
#
# Examples:
#   ./drop_iccx_db_objects.sh AVAMDMSDB ftst --dry-run
#   ./drop_iccx_db_objects.sh AVAMDMSDB ftst --user myldapuser --dry-run
#   ./drop_iccx_db_objects.sh AVAMDMSDB ftst
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
#   --dry-run  Connects, runs the pre-flight checks and lists every
#              statement that would be executed. Additionally checks
#              whether the removal is likely to succeed (authorities,
#              active connections, last system temporary tablespace).
#              Nothing is changed and no confirmation is asked. Exit
#              code 1 if a check failed.
#   --yes      Skips the confirmation prompt.
#
# Without --yes the script asks you to type the database name.
# In non-interactive shells (CI/CD) --yes is mandatory.
#
# Order of removal (reverse of creation):
#   1. Schemas incl. all contained objects
#   2. Granted privileges (database, catalog views, workload)
#   3. Tablespaces (their tablespace privileges are removed with them)
#   4. Temporary tablespaces
#   5. Bufferpool (only if no other tablespace still uses it)
#
# Requirements:
#   - DBADM (drop authority on all objects in the ICCx schemas)
#   - Tablespace SYSTOOLSPACE must exist (used by ADMIN_DROP_SCHEMA
#     for its error table)
#
# Not touched:
#   - The users themselves (OS / LDAP)
#   - PUBLIC privileges
#   - SYSTOOLSPACE
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
        return 0
    fi

    echo "Executing: ${statement}"
    db2_exec -v "${statement}"
}


# Like run_db2, but a failure containing the given SQL code is
# reported as a skip instead of aborting the script.
run_db2_tolerant()
{
    local ignore_code="$1"
    local statement="$2"
    local rc=0

    if [ "${DRY_RUN}" = "yes" ]; then
        echo "[DRY-RUN] Would execute: ${statement}"
        return 0
    fi

    echo "Executing: ${statement}"
    db2 -v "${statement}" > "${DB2_TMP}" 2>&1 || rc=$?
    cat "${DB2_TMP}"

    if [ "${rc}" -ge 4 ]; then
        if grep -q "${ignore_code}" "${DB2_TMP}"; then
            echo "Skipping (${ignore_code})."
        else
            error "Db2 command failed with return code ${rc}"
        fi
    fi
}


# ------------------------------------------------------------
# Input parameters
# ------------------------------------------------------------

CONFIRMED="no"
DRY_RUN="no"
CONNECT_USER=""
PASSWORD_FILE=""
POSITIONAL=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes)     CONFIRMED="yes" ;;
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
        -*)        error "Unknown option '$1'. Supported: --user, --password-file, --yes, --dry-run." ;;
        *)         POSITIONAL+=("$1") ;;
    esac
    shift
done

if [ "${#POSITIONAL[@]}" -gt 2 ]; then
    error "Too many arguments. Usage: $0 <database> <environment> [--user <name>] [--yes] [--dry-run]"
fi

DB_NAME="${POSITIONAL[0]:-}"
ENV_SUFFIX="${POSITIONAL[1]:-}"

if [ -z "${DB_NAME}" ] || [ -z "${ENV_SUFFIX}" ]; then
    echo "Usage: $0 <database> <environment> [--user <name>] [--yes] [--dry-run]"
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


# ------------------------------------------------------------
# Object names (must match create_iccx_db_objects.sh)
# ------------------------------------------------------------

BUFFERPOOL="AVAMDMSDBP32KB"
TEMP_TABLESPACE="ICCX_TEMP"
SYSTEM_TEMP_TABLESPACE="ICCX_SYSTEMP"

ICN_USER="svcfndb2icn${ENV_LOWER}"
GCD_USER="svcfndb2gcd${ENV_LOWER}"
LOGI_USER="svcfndb2logistik${ENV_LOWER}"
PERSON_USER="svcfndb2person${ENV_LOWER}"
UNTER_USER="svcfndb2unternehmen${ENV_LOWER}"

ALL_USERS=(
    "${ICN_USER}"
    "${GCD_USER}"
    "${LOGI_USER}"
    "${PERSON_USER}"
    "${UNTER_USER}"
)

# Schema name equals user name; Db2 stores it in upper case
ALL_SCHEMAS=()
for user in "${ALL_USERS[@]}"; do
    ALL_SCHEMAS+=("$(echo "${user}" | tr '[:lower:]' '[:upper:]')")
done

# ICN and GCD: DAT only. Object stores: DAT, IND, LOB.
TABLESPACES=("TS_ICN_DAT" "TS_GCD_DAT")
for group in PERSON PERSONVW LOGI UNTER; do
    for suffix in DAT IND LOB; do
        TABLESPACES+=("TS_${group}_${suffix}")
    done
done

# Name and schema for the error table of ADMIN_DROP_SCHEMA
ERROR_TABLE="ICCX_DROP_ERR"


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
# Helper functions
# ------------------------------------------------------------

# 'A','B','C' list for SQL IN (...) clauses (names are constants / validated)
sql_in_list()
{
    local item
    local result=""

    for item in "$@"; do
        result+="'${item}',"
    done

    echo "${result%,}"
}


# Single-value query. Sets DB2_RESULT. A failure aborts and shows the
# Db2 message. Return codes 1 (no rows) and 2 (warning) are accepted.
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


# Numeric single-value query (COUNT(*)). Sets DB2_RESULT.
db2_count()
{
    db2_value "$1"

    [[ "${DB2_RESULT}" =~ ^[0-9]+$ ]] ||
        error "Query did not return a number: $1"
}


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


table_exists()
{
    local table_schema="$1"
    local table_name="$2"

    db2_value \
        "SELECT COUNT(*)
           FROM SYSCAT.TABLES
          WHERE TABSCHEMA = UPPER('${table_schema}')
            AND TABNAME   = UPPER('${table_name}')
          WITH UR"
    [ "${DB2_RESULT}" = "1" ]
}


drop_schema_with_objects()
{
    local schema_name="$1"
    local schema_upper
    schema_upper="$(echo "${schema_name}" | tr '[:lower:]' '[:upper:]')"

    if ! schema_exists "${schema_upper}"; then
        echo "Schema ${schema_upper} does not exist. Skipping."
        return 0
    fi

    if [ "${DRY_RUN}" = "yes" ]; then
        local object_count
        db2_count \
            "SELECT COUNT(*)
               FROM SYSCAT.TABLES
              WHERE TABSCHEMA = '${schema_upper}'
              WITH UR"
        object_count="${DB2_RESULT}"
        echo "Schema ${schema_upper} exists and contains ${object_count} table-like object(s) (tables, views, aliases)."
    fi

    # DROP SCHEMA ... RESTRICT fails for non-empty schemas, so the
    # schema is emptied with ADMIN_DROP_SCHEMA. The error table must
    # not exist before the call.
    if table_exists "${ERROR_SCHEMA}" "${ERROR_TABLE}"; then
        run_db2 "DROP TABLE ${ERROR_SCHEMA}.${ERROR_TABLE}"
    fi

    # ERRORTABSCHEMA and ERRORTAB are INOUT parameters. Constants are rejected
    # with SQL0469N, so the call goes through an anonymous block with variables.
    run_db2 \
        "BEGIN
             DECLARE v_error_schema VARCHAR(128) DEFAULT '${ERROR_SCHEMA}';
             DECLARE v_error_table  VARCHAR(128) DEFAULT '${ERROR_TABLE}';
             CALL SYSPROC.ADMIN_DROP_SCHEMA(
                 '${schema_upper}', NULL,
                 v_error_schema, v_error_table);
         END"

    # Nothing was executed in a dry run, so there is nothing to check
    if [ "${DRY_RUN}" = "yes" ]; then
        return 0
    fi

    # The procedure creates the error table only if objects could not be dropped
    if table_exists "${ERROR_SCHEMA}" "${ERROR_TABLE}"; then
        db2_exec \
            "SELECT OBJECT_SCHEMA,
                    OBJECT_NAME,
                    OBJECT_TYPE,
                    SQLCODE,
                    SUBSTR(DIAGTEXT, 1, 200) AS DIAGTEXT
               FROM ${ERROR_SCHEMA}.${ERROR_TABLE}"
        error "Objects in schema ${schema_upper} could not be dropped. See error table ${ERROR_SCHEMA}.${ERROR_TABLE}."
    fi

    # The schema itself remains after ADMIN_DROP_SCHEMA only if the
    # procedure did not remove it; drop it if it is still there.
    if schema_exists "${schema_upper}"; then
        run_db2 "DROP SCHEMA ${schema_upper} RESTRICT"
    fi
}


revoke_base_permissions()
{
    local db_user="$1"

    log "Revoking base permissions from ${db_user}"

    # SQL0556N: the user does not hold the privilege (e.g. repeated run)
    run_db2_tolerant "SQL0556N" \
        "REVOKE CONNECT, CREATETAB, IMPLICIT_SCHEMA ON DATABASE FROM USER ${db_user}"

    run_db2_tolerant "SQL0556N" \
        "REVOKE SELECT ON TABLE SYSIBM.SYSVERSIONS FROM USER ${db_user}"

    run_db2_tolerant "SQL0556N" \
        "REVOKE SELECT ON TABLE SYSCAT.DATATYPES FROM USER ${db_user}"

    run_db2_tolerant "SQL0556N" \
        "REVOKE SELECT ON TABLE SYSCAT.INDEXES FROM USER ${db_user}"

    run_db2_tolerant "SQL0556N" \
        "REVOKE SELECT ON TABLE SYSIBM.SYSDUMMY1 FROM USER ${db_user}"

    run_db2_tolerant "SQL0556N" \
        "REVOKE USAGE ON WORKLOAD SYSDEFAULTUSERWORKLOAD FROM USER ${db_user}"
}


drop_tablespace()
{
    local tablespace_name="$1"

    if tablespace_exists "${tablespace_name}"; then
        run_db2 "DROP TABLESPACE ${tablespace_name}"
    else
        echo "Tablespace ${tablespace_name} does not exist. Skipping."
    fi
}


drop_system_temporary_tablespace()
{
    local tablespace_name="$1"

    if tablespace_exists "${tablespace_name}"; then
        # SQL0283N: last system temporary tablespace of the catalog page size
        run_db2_tolerant "SQL0283N" "DROP TABLESPACE ${tablespace_name}"
    else
        echo "Tablespace ${tablespace_name} does not exist. Skipping."
    fi
}


drop_bufferpool()
{
    local bufferpool_name="$1"
    local in_use
    local exclude_clause=""

    if ! bufferpool_exists "${bufferpool_name}"; then
        echo "Bufferpool ${bufferpool_name} does not exist. Skipping."
        return 0
    fi

    # In a dry run the ICCx tablespaces still exist; ignore them, because
    # a real run has dropped them at this point.
    if [ "${DRY_RUN}" = "yes" ]; then
        exclude_clause="AND T.TBSPACE NOT IN (${TABLESPACE_LIST},
                                              '${TEMP_TABLESPACE}',
                                              '${SYSTEM_TEMP_TABLESPACE}')"
    fi

    db2_count \
        "SELECT COUNT(*)
           FROM SYSCAT.TABLESPACES T
           JOIN SYSCAT.BUFFERPOOLS B
             ON T.BUFFERPOOLID = B.BUFFERPOOLID
          WHERE B.BPNAME = UPPER('${bufferpool_name}')
            ${exclude_clause}
          WITH UR"
    in_use="${DB2_RESULT}"

    if [ "${in_use}" -gt 0 ]; then
        echo "WARNING: Bufferpool ${bufferpool_name} is still used by ${in_use} tablespace(s). Not dropped."
        db2_exec \
            "SELECT T.TBSPACE
               FROM SYSCAT.TABLESPACES T
               JOIN SYSCAT.BUFFERPOOLS B
                 ON T.BUFFERPOOLID = B.BUFFERPOOLID
              WHERE B.BPNAME = UPPER('${bufferpool_name}')
                ${exclude_clause}
              ORDER BY T.TBSPACE"
    else
        run_db2 "DROP BUFFERPOOL ${bufferpool_name}"
    fi
}


# ------------------------------------------------------------
# Dry-run feasibility checks
# Read-only queries that predict typical failures of the real run.
# A real execution with rollback is not possible: ADMIN_DROP_SCHEMA
# and DROP TABLESPACE cannot be reliably undone.
# ------------------------------------------------------------

DRY_RUN_PROBLEMS=0
DRY_RUN_WARNINGS=0

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


# Like db2_count, but sets DB2_RESULT to an empty string instead of
# aborting if the query cannot be executed (missing view or privilege).
try_count()
{
    local rc=0

    DB2_RESULT=""
    db2 -x "$1" > "${DB2_TMP}" 2>&1 || rc=$?

    if [ "${rc}" -lt 4 ]; then
        DB2_RESULT="$(tr -d ' \n' < "${DB2_TMP}")"
    fi

    [[ "${DB2_RESULT}" =~ ^[0-9]+$ ]] || DB2_RESULT=""
}


# Counts the given authorities (SQL list) held by the connected user,
# directly or via group, role or PUBLIC. Sets DB2_RESULT.
count_session_authorities()
{
    try_count \
        "SELECT COUNT(*)
           FROM TABLE(SYSPROC.AUTH_LIST_AUTHORITIES_FOR_AUTHID(SESSION_USER, 'U')) AS T
          WHERE AUTHORITY IN ($1)
            AND 'Y' IN (D_USER, D_GROUP, D_PUBLIC, ROLE_USER, ROLE_GROUP, ROLE_PUBLIC)"
}


run_dry_run_checks()
{
    local session_user
    local schema
    local count
    local page_size

    log "Dry-run feasibility checks"

    # 1. The issuing user cannot revoke privileges from itself (SQLSTATE 42502)
    db2_value "VALUES SESSION_USER"
    session_user="${DB2_RESULT}"

    [ -n "${session_user}" ] || error "Could not determine the connected user"

    for schema in "${ALL_SCHEMAS[@]}"; do
        if [ "${session_user}" = "${schema}" ]; then
            check_fail "Connected as ${session_user}. REVOKE from the issuing user is rejected (SQLSTATE 42502). Run the script as an administrator."
        fi
    done
    check_ok "Connected user ${session_user} is not one of the ICCx users."

    # 2. Authority to drop schemas, tablespaces and bufferpool
    count_session_authorities "'DBADM','SYSADM'"
    count="${DB2_RESULT}"
    if [ -z "${count}" ]; then
        check_warn "Could not determine the authorities of ${session_user}."
    elif [ "${count}" -gt 0 ]; then
        check_ok "${session_user} holds DBADM or SYSADM (drop of schemas, tablespaces, bufferpool)."
    else
        check_fail "${session_user} holds neither DBADM nor SYSADM. DROP TABLESPACE, DROP BUFFERPOOL and ADMIN_DROP_SCHEMA would fail."
    fi

    # 3. Authority to revoke privileges
    count_session_authorities "'ACCESSCTRL','SECADM'"
    count="${DB2_RESULT}"
    if [ -z "${count}" ]; then
        check_warn "Could not determine the authorities of ${session_user}."
    elif [ "${count}" -gt 0 ]; then
        check_ok "${session_user} holds ACCESSCTRL or SECADM (REVOKE)."
    else
        check_fail "${session_user} holds neither ACCESSCTRL nor SECADM. The REVOKE statements would fail."
    fi

    # 4. Active connections of the ICCx users (locks block the schema drop)
    try_count \
        "SELECT COUNT(*)
           FROM SYSIBMADM.APPLICATIONS
          WHERE DB_NAME = UPPER('${DB_NAME}')
            AND AUTHID IN (${SCHEMA_LIST})"
    count="${DB2_RESULT}"
    if [ -z "${count}" ]; then
        check_warn "Could not check active connections (SYSIBMADM.APPLICATIONS not readable)."
    elif [ "${count}" -gt 0 ]; then
        check_warn "${count} active connection(s) of ICCx users. Stop the FileNet applications first, otherwise locks can make the removal fail."
    else
        check_ok "No active connections of ICCx users."
    fi

    # 5. Last system temporary tablespace of its page size (SQL0283N)
    if tablespace_exists "${SYSTEM_TEMP_TABLESPACE}"; then
        try_count \
            "SELECT PAGESIZE
               FROM SYSCAT.TABLESPACES
              WHERE TBSPACE = '${SYSTEM_TEMP_TABLESPACE}'"
        page_size="${DB2_RESULT}"

        if [ -z "${page_size}" ]; then
            check_warn "Could not read the page size of ${SYSTEM_TEMP_TABLESPACE}."
        else
            try_count \
                "SELECT COUNT(*)
                   FROM SYSCAT.TABLESPACES
                  WHERE DATATYPE = 'T'
                    AND PAGESIZE = ${page_size}
                    AND TBSPACE <> '${SYSTEM_TEMP_TABLESPACE}'"
            count="${DB2_RESULT}"

            if [ -z "${count}" ]; then
                check_warn "Could not check other system temporary tablespaces."
            elif [ "${count}" -gt 0 ]; then
                check_ok "Another system temporary tablespace with page size ${page_size} exists."
            else
                check_warn "${SYSTEM_TEMP_TABLESPACE} is the only system temporary tablespace with page size ${page_size}. Db2 refuses to drop it (SQL0283N); the script skips it."
            fi
        fi
    fi
}


# ------------------------------------------------------------
# Pre-flight check
# ------------------------------------------------------------

log "Pre-flight check"

# ADMIN_DROP_SCHEMA stores its error table in SYSTOOLSPACE
tablespace_exists "SYSTOOLSPACE" ||
    error "Tablespace SYSTOOLSPACE does not exist, ADMIN_DROP_SCHEMA cannot be used. Nothing was changed."

db2_value "VALUES CURRENT SCHEMA"
ERROR_SCHEMA="${DB2_RESULT}"

[ -n "${ERROR_SCHEMA}" ] || error "Could not determine the current schema"

SCHEMA_LIST="$(sql_in_list "${ALL_SCHEMAS[@]}")"
TABLESPACE_LIST="$(sql_in_list "${TABLESPACES[@]}")"

# DROP TABLESPACE also destroys tables of other schemas stored in it.
# Abort if anything outside the ICCx schemas lives in these tablespaces.
FOREIGN_TABLES_QUERY="FROM SYSCAT.TABLES
          WHERE TYPE = 'T'
            AND TABSCHEMA NOT IN (${SCHEMA_LIST})
            AND (   TBSPACE       IN (${TABLESPACE_LIST})
                 OR INDEX_TBSPACE IN (${TABLESPACE_LIST})
                 OR LONG_TBSPACE  IN (${TABLESPACE_LIST}))"

db2_count "SELECT COUNT(*) ${FOREIGN_TABLES_QUERY} WITH UR"
foreign_tables="${DB2_RESULT}"

if [ "${foreign_tables}" -gt 0 ]; then
    db2_exec "SELECT TABSCHEMA, TABNAME, TBSPACE ${FOREIGN_TABLES_QUERY} WITH UR"
    error "${foreign_tables} table(s) outside the ICCx schemas use ICCx tablespaces. Dropping the tablespaces would destroy them. Aborting; nothing was changed."
fi

echo "OK: no foreign tables in ICCx tablespaces."


# ------------------------------------------------------------
# Plan and confirmation
# ------------------------------------------------------------

if [ "${DRY_RUN}" = "yes" ]; then
    log "DRY RUN: the following objects WOULD be dropped from database ${DB_NAME}"
else
    log "The following objects will be DROPPED from database ${DB_NAME}"
fi

echo "Schemas incl. ALL contained objects and data:"
printf '  %s\n' "${ALL_SCHEMAS[@]}"
echo
echo "Privileges revoked from users:"
printf '  %s\n' "${ALL_USERS[@]}"
echo
echo "Tablespaces:"
printf '  %s\n' "${TABLESPACES[@]}" "${TEMP_TABLESPACE}" "${SYSTEM_TEMP_TABLESPACE}"
echo
echo "Bufferpool (only if no other tablespace uses it):"
echo "  ${BUFFERPOOL}"
echo

if [ "${DRY_RUN}" = "yes" ]; then
    echo "DRY RUN: no changes are made. Statements are only listed."
    run_dry_run_checks
elif [ "${CONFIRMED}" != "yes" ]; then
    if [ ! -t 0 ]; then
        error "Non-interactive shell: pass --yes to confirm the removal."
    fi

    read -r -p "This cannot be undone. Type the database name (${DB_NAME}) to confirm: " answer

    [ "${answer}" = "${DB_NAME}" ] || error "Confirmation failed. Nothing was changed."
fi


# ============================================================
# Step 1: Drop schemas including all contained objects
# ============================================================

log "Dropping ICCx schemas"

for schema in "${ALL_SCHEMAS[@]}"; do
    drop_schema_with_objects "${schema}"
done


# ============================================================
# Step 2: Revoke granted privileges
# ============================================================

for DB_USER in "${ALL_USERS[@]}"; do
    revoke_base_permissions "${DB_USER}"
done


# ============================================================
# Step 3: Drop tablespaces
# (USE OF TABLESPACE privileges are removed together with them)
# ============================================================

log "Dropping tablespaces"

for tablespace in "${TABLESPACES[@]}"; do
    drop_tablespace "${tablespace}"
done


# ============================================================
# Step 4: Drop temporary tablespaces
# ============================================================

log "Dropping temporary tablespaces"

drop_tablespace "${TEMP_TABLESPACE}"
drop_system_temporary_tablespace "${SYSTEM_TEMP_TABLESPACE}"


# ============================================================
# Step 5: Drop bufferpool
# ============================================================

log "Dropping bufferpool"

drop_bufferpool "${BUFFERPOOL}"


# ============================================================
# Step 6: Validation (all queries should return no rows)
# Skipped in a dry run, nothing was removed.
# ============================================================

show_remaining_objects()
{
    local user_list_upper

    log "Remaining ICCx schemas"

    db2_exec \
        "SELECT SCHEMANAME
           FROM SYSCAT.SCHEMATA
          WHERE SCHEMANAME IN (${SCHEMA_LIST})
          ORDER BY SCHEMANAME"


    log "Remaining ICCx tablespaces"

    db2_exec \
        "SELECT TBSPACE
           FROM SYSCAT.TABLESPACES
          WHERE TBSPACE IN (${TABLESPACE_LIST},
                            '${TEMP_TABLESPACE}',
                            '${SYSTEM_TEMP_TABLESPACE}')
          ORDER BY TBSPACE"


    log "Remaining database privileges of ICCx users"

    user_list_upper="$(sql_in_list "${ALL_SCHEMAS[@]}")"

    db2_exec \
        "SELECT GRANTEE,
                CONNECTAUTH,
                CREATETABAUTH,
                IMPLSCHEMAAUTH
           FROM SYSCAT.DBAUTH
          WHERE GRANTEE IN (${user_list_upper})
            AND (   CONNECTAUTH    = 'Y'
                 OR CREATETABAUTH  = 'Y'
                 OR IMPLSCHEMAAUTH = 'Y')
          ORDER BY GRANTEE"
}

if [ "${DRY_RUN}" != "yes" ]; then
    show_remaining_objects
fi


# ============================================================
# Done (connection is released by the EXIT trap)
# ============================================================

if [ "${DRY_RUN}" = "yes" ]; then
    log "DRY RUN completed. No changes were made."
    echo "Failed checks     : ${DRY_RUN_PROBLEMS}"
    echo "Warnings          : ${DRY_RUN_WARNINGS}"

    if [ "${DRY_RUN_PROBLEMS}" -gt 0 ]; then
        error "Dry run found ${DRY_RUN_PROBLEMS} problem(s). The real run would likely fail."
    fi
else
    log "ICCx database objects removed"
fi

echo "Database          : ${DB_NAME}"
echo "Environment       : ${ENV_SUFFIX}"
