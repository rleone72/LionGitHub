# IBM Content Cortex (ICCx) - DB2 Database Setup Documentation

Dieses Dokument beschreibt Architektur, Konfiguration, Berechtigungsvergabe und Ausführung des Skripts [create_iccx_db_objects.sh](create_iccx_db_objects.sh) für die DB2-Datenbankobjekte von **IBM Content Cortex (ICCx)** bzw. **IBM FileNet Content Manager (FNCM / CP4BA)**.

## Inhaltsverzeichnis

1. [Übersicht & Architektur](#1-übersicht--architektur)
2. [Objekt-Referenz](#2-objekt-referenz)
   - [2.1 Bufferpool](#21-bufferpool)
   - [2.2 Schemas & Service-Benutzer](#22-schemas--service-benutzer)
   - [2.3 Tablespaces & Caching-Strategie](#23-tablespaces--caching-strategie)
   - [2.4 Temporary Tablespaces](#24-temporary-tablespaces)
   - [2.5 Berechtigungskonzept (Least Privilege)](#25-berechtigungskonzept-least-privilege)
3. [Parameter](#3-parameter)
4. [Voraussetzungen](#4-voraussetzungen)
5. [Ausführung](#5-ausführung)
6. [Verifikation & Qualitätssicherung](#6-verifikation--qualitätssicherung)
7. [Fehlerbehebung & Best Practices](#7-fehlerbehebung--best-practices)
8. [Rückbau (drop_iccx_db_objects.sh)](#8-rückbau-drop_iccx_db_objectssh)

---

## 1. Übersicht & Architektur

IBM Content Cortex (ICCx) nutzt die Enterprise-Content-Management-Engine von IBM FileNet Content Manager. Die Datenbankarchitektur gliedert sich in:

- **Global Configuration Database (GCD):** Zentrale Konfigurations- und Domain-Metadaten (`svcfndb2gcd<ENV>`).
- **IBM Content Navigator (ICN):** Web-Client-Konfigurations- und Session-Datenbank (`svcfndb2icn<ENV>`).
- **Object Stores (OS):** Fachliche Dokumentenspeicher für Metadaten, Indexe, LOBs und Workflow-Tabellen:
  - **PERSON** (`svcfndb2person<ENV>`): Standard Object Store & Workflow / Process Engine (PERSONVW).
  - **LOGISTIK** (`svcfndb2logistik<ENV>`): Fachbereichs-Object-Store Logistik.
  - **UNTERNEHMEN** (`svcfndb2unternehmen<ENV>`): Fachbereichs-Object-Store Unternehmensdaten.

Jede Umgebung hat eine eigene Datenbank. Nur **Schema- und Benutzernamen** tragen den Umgebungssuffix `<ENV>`. Bufferpool und Tablespaces heißen auf allen Umgebungen gleich.

---

## 2. Objekt-Referenz

### 2.1 Bufferpool

FileNet Content Manager benötigt für Metadaten, Dokumenteigenschaften und Indizes eine Pagesize von **32 KB**.

| Name | Pagesize | Typ | Konfiguration |
|------|----------|-----|---------------|
| `AVAMDMSDBP32KB` | 32 KB (32768 Byte) | Automatisch | `SIZE AUTOMATIC PAGESIZE 32K` |

### 2.2 Schemas & Service-Benutzer

Schema und Benutzer heißen identisch. Das Schema wird mit `CREATE SCHEMA <SCHEMA> AUTHORIZATION <USER>` angelegt.

| Schema / User | Funktion / Komponente | Tablespaces |
|---------------|-----------------------|-------------|
| `svcfndb2icn<ENV>` | IBM Content Navigator Konfiguration | `TS_ICN_DAT` |
| `svcfndb2gcd<ENV>` | FileNet GCD (Global Configuration DB) | `TS_GCD_DAT` |
| `svcfndb2person<ENV>` | Object Store: Person & Workflow | `TS_PERSON_*`, `TS_PERSONVW_*` |
| `svcfndb2logistik<ENV>` | Object Store: Logistik | `TS_LOGI_*` |
| `svcfndb2unternehmen<ENV>` | Object Store: Unternehmen | `TS_UNTER_*` |

### 2.3 Tablespaces & Caching-Strategie

Alle Tablespaces sind `LARGE`, 32K, `MANAGED BY AUTOMATIC STORAGE` mit `AUTORESIZE YES` im Bufferpool `AVAMDMSDBP32KB`.

- **DAT & IND Tablespaces:** `NO FILE SYSTEM CACHING` (Direktzugriff über den DB2-Bufferpool, Vermeidung von Double-Caching im OS).
- **LOB Tablespaces:** `FILE SYSTEM CACHING` (vorteilhaft für große unformatierte Binärobjekte).

Die Tablespace-Namen enthalten **keinen** Umgebungssuffix und sind auf allen Umgebungen identisch.

| Gruppe | Tablespace Name | File System Caching |
|--------|-----------------|---------------------|
| **ICN** | `TS_ICN_DAT` | NO FILE SYSTEM CACHING |
| **GCD** | `TS_GCD_DAT` | NO FILE SYSTEM CACHING |
| **PERSON** | `TS_PERSON_DAT` | NO FILE SYSTEM CACHING |
| | `TS_PERSON_IND` | NO FILE SYSTEM CACHING |
| | `TS_PERSON_LOB` | FILE SYSTEM CACHING |
| **PERSON VW** | `TS_PERSONVW_DAT` | NO FILE SYSTEM CACHING |
| | `TS_PERSONVW_IND` | NO FILE SYSTEM CACHING |
| | `TS_PERSONVW_LOB` | FILE SYSTEM CACHING |
| **LOGISTIK** | `TS_LOGI_DAT` | NO FILE SYSTEM CACHING |
| | `TS_LOGI_IND` | NO FILE SYSTEM CACHING |
| | `TS_LOGI_LOB` | FILE SYSTEM CACHING |
| **UNTERNEHMEN** | `TS_UNTER_DAT` | NO FILE SYSTEM CACHING |
| | `TS_UNTER_IND` | NO FILE SYSTEM CACHING |
| | `TS_UNTER_LOB` | FILE SYSTEM CACHING |

### 2.4 Temporary Tablespaces

| Name | Typ | Hinweis |
|------|-----|---------|
| `ICCX_TEMP` | User Temporary (32K) | Wird allen Service-Benutzern per `GRANT USE OF TABLESPACE` zugewiesen. |
| `ICCX_SYSTEMP` | System Temporary (32K) | Wird nur angelegt, wenn noch kein System Temporary Tablespace mit 32K existiert. Db2 benötigt ihn für Sorts und Joins auf 32K-Tabellen (sonst `SQL1585N`). |

### 2.5 Berechtigungskonzept (Least Privilege)

Das Skript vergibt die von IBM FileNet CPE und IBM Content Navigator benötigten Mindestberechtigungen an jeden der fünf Service-Benutzer.

**Datenbankebene:**

```sql
GRANT CONNECT ON DATABASE TO USER <USER>;
GRANT CREATETAB ON DATABASE TO USER <USER>;
GRANT IMPLICIT_SCHEMA ON DATABASE TO USER <USER>;
```

**Katalogtabellen & Workload:**

```sql
GRANT SELECT ON TABLE SYSIBM.SYSVERSIONS TO USER <USER>;
GRANT SELECT ON TABLE SYSCAT.DATATYPES TO USER <USER>;
GRANT SELECT ON TABLE SYSCAT.INDEXES TO USER <USER>;
GRANT SELECT ON TABLE SYSIBM.SYSDUMMY1 TO USER <USER>;
GRANT USAGE ON WORKLOAD SYSDEFAULTUSERWORKLOAD TO USER <USER>;
```

**Schemaebene:**

```sql
CREATE SCHEMA <SCHEMA> AUTHORIZATION <USER>;
```

**Tablespaceebene:**

```sql
-- Fuer temporaere Operationen
GRANT USE OF TABLESPACE ICCX_TEMP TO USER <USER>;
-- ICN und GCD: nur DAT; Object Stores: DAT, IND und LOB der eigenen Gruppe;
-- svcfndb2person<ENV> zusaetzlich TS_PERSONVW_*
GRANT USE OF TABLESPACE <TS_NAME> TO USER <USER>;
```

> **Optional** (im Skript auskommentiert, Step 7): `REVOKE CONNECT ON DATABASE FROM PUBLIC`. Erst aktivieren, wenn keine andere Anwendung auf das PUBLIC-CONNECT-Recht angewiesen ist.

---

## 3. Parameter

| Parameter | Beschreibung | Beispielwerte | Erlaubte Zeichen |
|-----------|--------------|---------------|------------------|
| `<database>` | Name der Ziel-DB2-Datenbank | `AVAMDMSDB` | Buchstaben, Ziffern, `_`; muss mit einem Buchstaben beginnen |
| `<environment>` | Suffix der Zielumgebung (Groß-/Kleinschreibung egal) | `int`, `ftst`, `prd` | Buchstaben und Ziffern |
| `--user <name>` | Ausführender DB2-Admin-Benutzer | `db2inst1` | – |
| `--password-file <pfad>` | Datei mit dem Passwort des Admin-Benutzers | `/secrets/db2instancepwd/password` | – |
| `--dry-run` | Trockenlauf, ändert nichts | – | – |

---

## 4. Voraussetzungen

- **DB2-Instanz & Datenbank:** Die DB2-Datenbank muss bereits existieren und über Automatic Storage verfügen.
- **Betriebssystem- / LDAP-Benutzer:** DB2 LUW nutzt die Authentifizierung des Betriebssystems oder des zentralen Directory-Servers (LDAP/AD). Die Benutzer `svcfndb2icn<ENV>`, `svcfndb2gcd<ENV>`, `svcfndb2logistik<ENV>`, `svcfndb2person<ENV>` und `svcfndb2unternehmen<ENV>` müssen vor der Skriptausführung angelegt worden sein.
- **Ausführender Benutzer:** Der ausführende Administrator benötigt `DBADM` (sowie `SECADM` bzw. `ACCESSCTRL` für die GRANT-Befehle), um Bufferpools, Tablespaces, Schemas und Berechtigungen zu erstellen.
- **DB2 CLP:** Der `db2`-Befehl muss in der Shell verfügbar sein (Instanzumgebung geladen, z. B. `. ~/sqllib/db2profile`).

---

## 5. Ausführung

```bash
# Ausführungsrechte setzen
chmod +x create_iccx_db_objects.sh

# Syntax
./create_iccx_db_objects.sh <database> <environment> --user <user> --password-file <pfad> [--dry-run]

# Ausführung
./create_iccx_db_objects.sh <database> <environment> \
  --user db2inst1 \
  --password-file /secrets/db2instancepwd/password \
  2>&1 | tee create_iccx_db_objects.log

# Trockenlauf mit Report: ändert nichts
./create_iccx_db_objects.sh <database> <environment> \
  --user db2inst1 \
  --password-file /secrets/db2instancepwd/password \
  --dry-run 2>&1 | tee create_iccx_db_objects_dryrun.log
```

**Was das Skript macht:**

1. Validiert die Eingabeparameter per Allowlist.
2. Verbindet sich mit der Datenbank. Ein `trap` führt am Ende, auch bei einem Abbruch, `CONNECT RESET` aus.
3. Legt Bufferpool, System- und User-Temporary-Tablespace, alle Tablespaces und die Schemas an.
4. Vergibt die Berechtigungen aus Abschnitt [2.5](#25-berechtigungskonzept-least-privilege).
5. Gibt zur Kontrolle Schemas, Tablespaces und Datenbankrechte aus.

**Wiederholbar:** Vor jedem `CREATE` prüft das Skript, ob das Objekt existiert, und überspringt es dann. Ein erneuter Lauf ist damit gefahrlos. GRANT-Befehle werden bei jedem Lauf erneut ausgeführt.

**Fehlerbehandlung:** Die Db2-Return-Codes 0 bis 2 (Erfolg, keine Zeilen, Warnung) gelten als OK. Ab Return Code 4 (SQL- oder CLP-Fehler) bricht das Skript ab und gibt einen Exit-Code ungleich 0 zurück.

### 5.1 Trockenlauf (`--dry-run`)

Mit `--dry-run` verbindet sich das Skript, gibt jeden Befehl als `[DRY-RUN] Would execute: …` aus, ohne ihn auszuführen, und schreibt am Ende einen Report:

```text
TYPE                     NAME                       ACTION
------------------------ -------------------------- ------------------------
BUFFERPOOL               AVAMDMSDBP32KB             CREATE
TABLESPACE               TS_ICN_DAT                 EXISTS
SCHEMA                   SVCFNDB2ICNFTST            CREATE
...
Objects to create     : 12
Objects already there : 20
GRANT statements      : 105 (idempotent, always executed)
Failed checks         : 0
Warnings              : 1
```

Der Report listet pro Objekt, ob es angelegt würde (`CREATE`) oder schon existiert (`EXISTS`). Zusätzlich laufen reine Leseprüfungen:

| Prüfung | Ergebnis bei Problem |
|---------|----------------------|
| Verbundener Benutzer hat `DBADM` oder `SYSADM` (Bufferpool, Tablespaces, Schemas anlegen) | FAIL |
| Verbundener Benutzer hat `ACCESSCTRL` oder `SECADM` (GRANT) | FAIL |
| Eine Default-Storage-Group existiert (`MANAGED BY AUTOMATIC STORAGE`) | FAIL |
| Ein vorhandener Bufferpool hat nicht die Seitengröße 32K | FAIL |
| Ein vorhandener Tablespace hat nicht die Seitengröße 32K | FAIL |
| Ein vorhandenes Schema gehört einem anderen Besitzer als dem Service-Benutzer | WARN |
| Die Service-Benutzer sind auf dem Host auflösbar (`getent passwd`) | WARN |

Bei mindestens einem FAIL endet der Trockenlauf mit Exit-Code 1. Der Trockenlauf kann nicht prüfen, ob die Benutzer in LDAP existieren, wenn der Host sie nicht über `getent` auflöst. Er sagt auch keinen Speicherplatz und keine Sperren voraus.

---

## 6. Verifikation & Qualitätssicherung

Das Skript gibt am Ende bereits Schemas, Tablespaces und Datenbankrechte aus. Für eine ausführlichere Kontrolle nach dem Deployment stehen die folgenden Abfragen zur Verfügung.

> **Ausführung:** Abfragen in eine Datei (z. B. `check_iccx_db_objects.sql`) kopieren, `<DBNAME>` ersetzen und mit `db2 -tvf check_iccx_db_objects.sql` ausführen.

### 6.1 Datenbankobjekte und Berechtigungen

```sql
CONNECT TO <DBNAME>;

-- 1. Bufferpool pruefen (PAGESIZE muss 32768 sein)
SELECT SUBSTR(BPNAME,1,20) AS BPNAME, PAGESIZE, NPAGES
FROM SYSCAT.BUFFERPOOLS
WHERE BPNAME = 'AVAMDMSDBP32KB';

-- 2. Schemas pruefen
SELECT SCHEMANAME, OWNER, DEFINER
FROM SYSCAT.SCHEMATA
WHERE SCHEMANAME LIKE 'SVCFNDB2%';

-- 3. Tablespaces und Caching pruefen
SELECT SUBSTR(TBSPACE,1,28) AS TBSPACE, TBSPACETYPE, DATATYPE, PAGESIZE, FSCACHING, BUFFERPOOLID
FROM SYSCAT.TABLESPACES
WHERE TBSPACE LIKE 'TS!_%' ESCAPE '!'
   OR TBSPACE LIKE 'ICCX!_%' ESCAPE '!'
ORDER BY TBSPACE;

-- 4. Datenbank-Basisberechtigungen pruefen
SELECT GRANTEE, DBADMAUTH, CREATETABAUTH, IMPLSCHEMAAUTH, CONNECTAUTH
FROM SYSCAT.DBAUTH
WHERE GRANTEE LIKE 'SVCFNDB2%';

-- 5. Tablespace-Nutzungsrechte pruefen
SELECT SUBSTR(TBSPACE,1,28) AS TBSPACE, GRANTEE, USEAUTH
FROM SYSCAT.TBSPACEAUTH
WHERE GRANTEE LIKE 'SVCFNDB2%'
ORDER BY GRANTEE, TBSPACE;
```

> **Hinweis Escape-Zeichen:** Der Unterstrich `_` ist in `LIKE` ein Platzhalter. Als Escape-Zeichen wird `!` statt `\` verwendet, weil der Backslash in Shell-Aufrufen (`db2 "..."`) und in Markdown Probleme verursacht.

### 6.2 Tabellen und Tablespace-Zuordnung

Nachdem FileNet (GCD, ICN, Object Stores) initialisiert wurde, wird geprüft, dass:

- alle Tabellen den vorgesehenen `TS_*`-Tablespaces zugeordnet sind,
- keine Tabellen außerhalb der definierten Tablespace-Struktur angelegt wurden,
- die Anzahl der Tabellen pro Schema und Tablespace nachvollzogen werden kann.

#### 6.2.1 Tabellen pro Schema und Tablespace

```bash
db2 "SELECT TABSCHEMA, TBSPACE, COUNT(*) AS TABELLEN
       FROM SYSCAT.TABLES
      WHERE TABSCHEMA LIKE 'SVCFNDB2%'
        AND TYPE = 'T'
      GROUP BY TABSCHEMA, TBSPACE
      ORDER BY TABSCHEMA, TBSPACE"
```

**Ergebnis (Umgebung EG1):**

| Schema | Tablespace | Tabellen |
|--------|------------|---------:|
| `SVCFNDB2GCDEG1` | `TS_GCD_DAT` | 3 |
| `SVCFNDB2ICNEG1` | `TS_ICN_DAT` | 17 |
| `SVCFNDB2LOGISTIKEG1` | `TS_LOGI_DAT` | 83 |
| `SVCFNDB2PERSONEG1` | `TS_PERSONVW_DAT` | 2 |
| `SVCFNDB2PERSONEG1` | `TS_PERSON_DAT` | 83 |
| `SVCFNDB2UNTERNEHMENEG1` | `TS_UNTER_DAT` | 83 |

Insgesamt wurden Tabellen in **6 Schema-/Tablespace-Kombinationen** gefunden.

#### 6.2.2 Tabellen außerhalb der vorgesehenen Tablespaces

Prüft, ob Tabellen existieren, deren Tablespace nicht dem Namensschema `TS_*` entspricht. Erwartetes Ergebnis: **keine Zeilen**.

```bash
db2 "SELECT TABSCHEMA, TABNAME, TBSPACE
       FROM SYSCAT.TABLES
      WHERE TABSCHEMA LIKE 'SVCFNDB2%'
        AND TYPE = 'T'
        AND TBSPACE NOT LIKE 'TS!_%' ESCAPE '!'"
```

**Ergebnis:**

```text
0 record(s) selected.
```

✅ **Validierung erfolgreich:** Es wurden keine Tabellen gefunden, die außerhalb der vorgesehenen `TS_*`-Tablespaces liegen.

Verbindung beenden:

```bash
db2 "CONNECT RESET"
```

#### 6.2.3 Zusammenfassung

Die aktuelle DB2-Struktur entspricht dem definierten Konzept: Alle FileNet-Tabellen liegen in den vorgesehenen `TS_*`-Tablespaces, und es wurden keine Tabellen außerhalb dieser Struktur angelegt.

---

## 7. Fehlerbehebung & Best Practices

| Symptom / Fehler | Ursache | Lösung |
|------------------|---------|--------|
| `SQL0204N ... "AVAMDMSDBP32KB" is an undefined name` | Der Bufferpool wurde vor der Tablespace-Erstellung nicht angelegt oder ist fehlgeschlagen. | Prüfen, ob `CREATE BUFFERPOOL` erfolgreich durchlief (`SYSCAT.BUFFERPOOLS`). |
| `SQL0551N ... does not have required authorization` | Der ausführende Benutzer besitzt nicht ausreichend Rechte (z. B. fehlendes `SECADM` / `DBADM`). | Skript mit einem privilegierten DB2-Admin-Account (`db2inst1` oder administrativer CI/CD-Service-Account) ausführen. |
| `SQL1585N ... no system temporary table space with sufficient page size` | Es existiert kein System Temporary Tablespace mit 32K. | Skript erneut ausführen. Es legt `ICCX_SYSTEMP` an, falls keiner mit 32K existiert. |
| `SQL0289N Unable to allocate new pages in table space` | DB2-Automatic-Storage-Speicherpfad ist voll oder nicht konfiguriert. | Plattenplatz der DB2 Storage Groups prüfen (`db2pd -storagepools`). |
| `SQL0567N ... invalid authorization ID` | Der angegebene Benutzername ist im OS/LDAP unbekannt oder überschreitet die DB2-Längenbegrenzung. | Sicherstellen, dass die Service-Accounts im LDAP/OS existieren und in Groß-/Kleinschreibung übereinstimmen. |
| `ERROR: Invalid database name / Invalid environment` | Die Parameter enthalten unzulässige Zeichen. | Nur die in Abschnitt [3](#3-parameter) erlaubten Zeichen verwenden. |

---

## 8. Rückbau (drop_iccx_db_objects.sh)

[drop_iccx_db_objects.sh](drop_iccx_db_objects.sh) entfernt alle Objekte, die `create_iccx_db_objects.sh` angelegt hat. Die Objektnamen sind in beiden Skripten identisch hinterlegt. Bei Änderungen an Namen müssen beide Skripte angepasst werden.

> ⚠️ **Achtung:** Der Rückbau ist destruktiv und nicht umkehrbar. Alle Tabellen und Daten in den ICCx-Schemas gehen verloren. Vorher ein Datenbank-Backup erstellen.

```bash
chmod +x drop_iccx_db_objects.sh

# Interaktiv: der Datenbankname muss zur Bestätigung eingegeben werden
./drop_iccx_db_objects.sh <database> <environment> \
  --user db2inst1 \
  --password-file /secrets/db2instancepwd/password \
  2>&1 | tee drop_iccx_db_objects.log

# Ohne Rückfrage (Pflicht in CI/CD, ohne Terminal bricht das Skript sonst ab)
./drop_iccx_db_objects.sh <database> <environment> \
  --user db2inst1 \
  --password-file /secrets/db2instancepwd/password \
  --yes 2>&1 | tee drop_iccx_db_objects.log

# Trockenlauf: zeigt Plan und die geplanten Befehle, ändert nichts
./drop_iccx_db_objects.sh <database> <environment> \
  --user db2inst1 \
  --password-file /secrets/db2instancepwd/password \
  --dry-run 2>&1 | tee drop_iccx_db_objects_dryrun.log
```

`--user <name>` verhält sich wie beim Anlegen-Skript (Abschnitt [5](#5-ausführung)): `CONNECT TO <db> USER <name>`. Der Benutzer darf keiner der ICCx-Service-Benutzer sein.

Mit `--dry-run` verbindet sich das Skript, führt die Vorabprüfungen aus und gibt jeden Befehl als `[DRY-RUN] Would execute: …` aus, ohne ihn auszuführen. Es erfolgt keine Rückfrage und keine Abschlussprüfung. `--dry-run` und `--yes` lassen sich kombinieren, `--dry-run` hat dann Vorrang.

Zusätzlich prüft der Trockenlauf mit reinen Leseabfragen, ob der echte Lauf voraussichtlich gelingt:

| Prüfung | Ergebnis bei Problem |
|---------|----------------------|
| Verbundener Benutzer ist keiner der ICCx-Benutzer (REVOKE vom ausführenden Benutzer wird mit SQLSTATE 42502 abgelehnt) | FAIL |
| Verbundener Benutzer hat `DBADM` oder `SYSADM` (Schemas, Tablespaces, Bufferpool löschen) | FAIL |
| Verbundener Benutzer hat `ACCESSCTRL` oder `SECADM` (REVOKE) | FAIL |
| Aktive Verbindungen der ICCx-Benutzer (Sperren können das Löschen blockieren) | WARN |
| `ICCX_SYSTEMP` ist der letzte System Temporary Tablespace seiner Seitengröße (`SQL0283N`) | WARN |

Bei mindestens einem FAIL endet der Trockenlauf mit Exit-Code 1. Eine Garantie ist das nicht: Der Trockenlauf kann Sperren, Platzprobleme oder Fehler in einzelnen Objekten nicht vorhersagen. Ein echter Probelauf mit Rollback ist nicht möglich, weil `DROP TABLESPACE` und `ADMIN_DROP_SCHEMA` nicht zuverlässig rückgängig zu machen sind.

**Reihenfolge:**

1. Schemas samt Inhalt (`SYSPROC.ADMIN_DROP_SCHEMA`, danach `DROP SCHEMA … RESTRICT`).
2. Berechtigungen der fünf Service-Benutzer (REVOKE auf Datenbank, Katalogsichten und Workload).
3. Tablespaces. Die `USE OF TABLESPACE`-Rechte entfallen mit ihnen.
4. Temporary Tablespaces `ICCX_TEMP` und `ICCX_SYSTEMP`.
5. Bufferpool `AVAMDMSDBP32KB`, aber nur, wenn ihn kein anderer Tablespace mehr nutzt.

**Schutzmechanismen:**

- **Vorabprüfung:** Liegen Tabellen außerhalb der ICCx-Schemas in den ICCx-Tablespaces, bricht das Skript ab, bevor etwas geändert wird. `DROP TABLESPACE` würde diese Tabellen sonst mit löschen.
- **Bestätigung:** Ohne `--yes` muss der Datenbankname eingegeben werden.
- **Wiederholbar:** Nicht vorhandene Objekte werden übersprungen. Nicht gehaltene Rechte (`SQL0556N`) werden toleriert.
- **System Temporary Tablespace:** Ist `ICCX_SYSTEMP` der letzte seiner Seitengröße, kann Db2 ihn nicht löschen (`SQL0283N`). Das Skript meldet das und läuft weiter.

**Voraussetzungen:**

- `DBADM` (Drop-Recht auf alle Objekte in den ICCx-Schemas).
- Der Tablespace `SYSTOOLSPACE` muss existieren, weil `ADMIN_DROP_SCHEMA` darin seine Fehlertabelle anlegt. Fehlt er, bricht die Vorabprüfung ab, bevor etwas geändert wurde.

**Nicht enthalten:**

- Die Benutzer selbst (liegen im OS bzw. LDAP).
- Rechte von PUBLIC.
- `SYSTOOLSPACE`.
