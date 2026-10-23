# IBM Content Cortex (ICCx) - DB2 Database Setup Documentation

Dieses Dokument beschreibt Architektur, Konfiguration, Berechtigungsvergabe und Ausführung des Skripts [`create_iccx_db_objects.sh`](create_iccx_db_objects.sh) für die DB2-Datenbankobjekte von **IBM Content Cortex (ICCx)** bzw. **IBM FileNet Content Manager (FNCM / CP4BA)**.

---

## Inhaltsverzeichnis

1. [Übersicht & Architektur](#1-übersicht--architektur)
2. [Objekt-Referenz](#2-objekt-referenz)
   - [Bufferpool](#21-bufferpool)
   - [Schemas & Service-Benutzer](#22-schemas--service-benutzer)
   - [Tablespaces & Caching-Strategie](#23-tablespaces--caching-strategie)
   - [Temporary Tablespaces](#24-temporary-tablespaces)
   - [Berechtigungskonzept (Least Privilege)](#25-berechtigungskonzept-least-privilege)
3. [Parameter](#3-parameter)
4. [Voraussetzungen](#4-voraussetzungen)
5. [Ausführung](#5-ausführung)
6. [CI/CD Pipeline-Integration](#6-cicd-pipeline-integration)
7. [Verifikation & Qualitätssicherung](#7-verifikation--qualitätssicherung)
8. [Fehlerbehebung & Best Practices](#8-fehlerbehebung--best-practices)
9. [Rückbau (`drop_iccx_db_objects.sh`)](#9-rückbau-drop_iccx_db_objectssh)

---

## 1. Übersicht & Architektur

IBM Content Cortex (ICCx) nutzt die Enterprise-Content-Management-Engine von IBM FileNet Content Manager. Die Datenbankarchitektur gliedert sich in:

- **Global Configuration Database (GCD):** Zentrale Konfigurations- und Domain-Metadaten (`svcfndb2gcd<ENV>`).
- **IBM Content Navigator (ICN):** Web-Client Konfigurations- und Session-Datenbank (`svcfndb2icn<ENV>`).
- **Object Stores (OS):** Fachliche Dokumentenspeicher für Metadaten, Indexe, LOBs und Workflow-Tabellen:
  - **PERSON (`svcfndb2person<ENV>`):** Standard Object Store & Workflow / Process Engine (`PERSONVW`).
  - **LOGISTIK (`svcfndb2logistik<ENV>`):** Fachbereichs-Object-Store Logistik.
  - **UNTERNEHMEN (`svcfndb2unternehmen<ENV>`):** Fachbereichs-Object-Store Unternehmensdaten.

Jede Umgebung hat eine eigene Datenbank. Nur **Schema- und Benutzernamen** tragen den Umgebungssuffix `<ENV>`. Bufferpool und Tablespaces heißen auf allen Umgebungen gleich.

---

## 2. Objekt-Referenz

### 2.1 Bufferpool

FileNet Content Manager benötigt für Metadaten, Dokumenteigenschaften und Indizes eine Pagesize von **32 KB**.

| Name | Pagesize | Typ | Konfiguration |
| :--- | :--- | :--- | :--- |
| `AVAMDMSDBP32KB` | 32 KB (32768 Byte) | Automatisch | `SIZE AUTOMATIC PAGESIZE 32K` |

### 2.2 Schemas & Service-Benutzer

Schema und Benutzer heißen identisch. Das Schema wird mit `CREATE SCHEMA <SCHEMA> AUTHORIZATION <USER>` angelegt.

| Schema / User | Funktion / Komponente | Tablespaces |
| :--- | :--- | :--- |
| `svcfndb2icn<ENV>` | IBM Content Navigator Konfiguration | `TS_ICN_DAT` |
| `svcfndb2gcd<ENV>` | FileNet GCD (Global Configuration DB) | `TS_GCD_DAT` |
| `svcfndb2person<ENV>` | Object Store: Person & Workflow | `TS_PERSON_*`, `TS_PERSONVW_*` |
| `svcfndb2logistik<ENV>` | Object Store: Logistik | `TS_LOGI_*` |
| `svcfndb2unternehmen<ENV>` | Object Store: Unternehmen | `TS_UNTER_*` |

### 2.3 Tablespaces & Caching-Strategie

Alle Tablespaces sind `LARGE`, 32K, `MANAGED BY AUTOMATIC STORAGE` mit `AUTORESIZE YES` im Bufferpool `AVAMDMSDBP32KB`.

- **DAT & IND Tablespaces:** `NO FILE SYSTEM CACHING` (Direktzugriff über DB2 Bufferpool, Vermeidung von Double-Caching im OS).
- **LOB Tablespaces:** `FILE SYSTEM CACHING` (Vorteilhaft für große unformatierte Binärobjekte).

Die Tablespace-Namen enthalten **keinen** Umgebungssuffix und sind auf allen Umgebungen identisch.

| Gruppe | Tablespace Name | File System Caching |
| :--- | :--- | :--- |
| **ICN** | `TS_ICN_DAT` | `NO FILE SYSTEM CACHING` |
| **GCD** | `TS_GCD_DAT` | `NO FILE SYSTEM CACHING` |
| **PERSON** | `TS_PERSON_DAT` | `NO FILE SYSTEM CACHING` |
| | `TS_PERSON_IND` | `NO FILE SYSTEM CACHING` |
| | `TS_PERSON_LOB` | `FILE SYSTEM CACHING` |
| **PERSON VW** | `TS_PERSONVW_DAT` | `NO FILE SYSTEM CACHING` |
| | `TS_PERSONVW_IND` | `NO FILE SYSTEM CACHING` |
| | `TS_PERSONVW_LOB` | `FILE SYSTEM CACHING` |
| **LOGISTIK** | `TS_LOGI_DAT` | `NO FILE SYSTEM CACHING` |
| | `TS_LOGI_IND` | `NO FILE SYSTEM CACHING` |
| | `TS_LOGI_LOB` | `FILE SYSTEM CACHING` |
| **UNTERNEHMEN** | `TS_UNTER_DAT` | `NO FILE SYSTEM CACHING` |
| | `TS_UNTER_IND` | `NO FILE SYSTEM CACHING` |
| | `TS_UNTER_LOB` | `FILE SYSTEM CACHING` |

### 2.4 Temporary Tablespaces

| Name | Typ | Hinweis |
| :--- | :--- | :--- |
| `ICCX_TEMP` | User Temporary (32K) | Wird allen Service-Benutzern per `GRANT USE OF TABLESPACE` zugewiesen. |
| `ICCX_SYSTEMP` | System Temporary (32K) | Wird nur angelegt, wenn noch kein System Temporary Tablespace mit 32K existiert. Db2 benötigt ihn für Sorts und Joins auf 32K-Tabellen (sonst `SQL1585N`). |

### 2.5 Berechtigungskonzept (Least Privilege)

Das Skript vergibt die von IBM FileNet CPE und IBM Content Navigator benötigten Mindestberechtigungen an jeden der fünf Service-Benutzer:

1. **Datenbankebene:**
   - `GRANT CONNECT ON DATABASE TO USER <USER>`
   - `GRANT CREATETAB ON DATABASE TO USER <USER>`
   - `GRANT IMPLICIT_SCHEMA ON DATABASE TO USER <USER>`
2. **Katalogtabellen & Workload:**
   - `GRANT SELECT ON TABLE SYSIBM.SYSVERSIONS TO USER <USER>`
   - `GRANT SELECT ON TABLE SYSCAT.DATATYPES TO USER <USER>`
   - `GRANT SELECT ON TABLE SYSCAT.INDEXES TO USER <USER>`
   - `GRANT SELECT ON TABLE SYSIBM.SYSDUMMY1 TO USER <USER>`
   - `GRANT USAGE ON WORKLOAD SYSDEFAULTUSERWORKLOAD TO USER <USER>`
3. **Schemaebene:**
   - `CREATE SCHEMA <SCHEMA> AUTHORIZATION <USER>`
4. **Tablespaceebene:**
   - `GRANT USE OF TABLESPACE ICCX_TEMP TO USER <USER>` (für temporäre Operationen)
   - `GRANT USE OF TABLESPACE <TS_NAME> TO USER <USER>` (ICN und GCD: nur DAT; Object Stores: DAT, IND und LOB der eigenen Gruppe, `svcfndb2person<ENV>` zusätzlich `TS_PERSONVW_*`)

Optional (im Skript auskommentiert, Step 7): `REVOKE CONNECT ON DATABASE FROM PUBLIC`. Erst aktivieren, wenn keine andere Anwendung auf das `PUBLIC CONNECT`-Recht angewiesen ist.

---

## 3. Parameter

| Parameter | Beschreibung | Beispielwerte | Erlaubte Zeichen |
| :--- | :--- | :--- | :--- |
| `<database>` | Name der Ziel-DB2-Datenbank | `AVAMDMSDB` | Buchstaben, Ziffern, `_`; muss mit einem Buchstaben beginnen |
| `<environment>` | Suffix der Zielumgebung (Groß-/Kleinschreibung egal) | `int`, `ftst`, `prd` | Buchstaben und Ziffern |

---

## 4. Voraussetzungen

1. **DB2 Instanz & Datenbank:** Die DB2-Datenbank muss bereits existieren und über Automatic Storage verfügen.
2. **Betriebssystem- / LDAP-Benutzer:** DB2 LUW nutzt die Authentifizierung des Betriebssystems oder zentralen Directory-Servers (LDAP/AD). Die Benutzer `svcfndb2icn<ENV>`, `svcfndb2gcd<ENV>`, `svcfndb2logistik<ENV>`, `svcfndb2person<ENV>`, `svcfndb2unternehmen<ENV>` müssen vor der Skriptausführung angelegt worden sein.
3. **Ausführender Benutzer:** Der ausführende Administrator benötigt `DBADM` (sowie `SECADM` bzw. `ACCESSCTRL` für die `GRANT`-Befehle), um Bufferpools, Tablespaces, Schemas und Berechtigungen zu erstellen.
4. **DB2 CLP:** Der `db2`-Befehl muss in der Shell verfügbar sein (Instanzumgebung geladen, z.B. `. ~/sqllib/db2profile`).

---

## 5. Ausführung

```bash
# Ausführungsrechte setzen
chmod +x create_iccx_db_objects.sh

# Syntax: ./create_iccx_db_objects.sh <database> <environment> [--user <name>] [--dry-run]
./create_iccx_db_objects.sh AVAMDMSDB ftst

# Trockenlauf mit Report: ändert nichts
./create_iccx_db_objects.sh AVAMDMSDB ftst --dry-run

# Verbindung mit explizitem (LDAP-)Benutzer, das Passwort fragt Db2 interaktiv ab
./create_iccx_db_objects.sh AVAMDMSDB ftst --user meinldapuser --dry-run
```

**Verbindung:** Ohne `--user` verbindet sich das Skript als angemeldeter OS-Benutzer (`CONNECT TO <db>`). Mit `--user <name>` führt es `CONNECT TO <db> USER <name>` aus, und Db2 fragt das Passwort am Terminal ab. Das Passwort wird nie als Argument übergeben oder im Skript gespeichert, `--user` braucht daher ein interaktives Terminal. Der Benutzername wird per Allowlist geprüft (Buchstaben, Ziffern, `_ . @ -`). Der verbundene Benutzer braucht die Rechte aus Abschnitt 5.1.

**Passwort aus einer Datei (gemountetes Secret):** Mit `--password-file` liest das Skript das Passwort aus einer Datei statt es abzufragen. Das ist für den Betrieb im Db2-Pod gedacht, in dem das Secret als Datei gemountet ist. Es braucht weder ein Terminal noch `oc` oder `kubectl`.

```bash
./create_iccx_db_objects.sh AVAMDMSDB ftst --user db2inst1 \
    --password-file /secrets/db2instancepwd/password --dry-run
```

- **Inhalt der Datei:** Ein gemountetes Secret enthält den Wert bereits dekodiert. Es ist kein `base64 -d` nötig. Das wäre nur bei `oc get secret -o jsonpath` der Fall.
- **Voraussetzung:** Die Datei existiert, ist lesbar und enthält nur das Passwort. Ein abschließender Zeilenumbruch wird entfernt. `--password-file` erfordert `--user`.
- **Sicherheit:** Das Passwort steht in keinem Prozess-Argument (`ps`) und wird nicht ausgegeben. Das Skript schreibt den `CONNECT`-Befehl in eine temporäre Datei mit Rechten 0600, führt sie mit `db2 -f` aus und leert sie sofort danach. Beim Beenden wird die Datei gelöscht. Der Pfad muss absolut sein und wird per Allowlist geprüft (Buchstaben, Ziffern, `. _ / -`).
- **Grenzen:** Das Passwort darf keine Leerzeichen enthalten. Ist die Datei leer oder nicht lesbar, bricht das Skript mit einer klaren Meldung ab, bevor es sich verbindet.

**Was das Skript macht:**
1. Validiert die Eingabeparameter per Allowlist.
2. Verbindet sich mit der Datenbank. Eine `trap` führt am Ende, auch bei einem Abbruch, `CONNECT RESET` aus.
3. Legt Bufferpool, System- und User-Temporary-Tablespace, alle Tablespaces und die Schemas an.
4. Vergibt die Berechtigungen aus Abschnitt 2.5.
5. Gibt zur Kontrolle Schemas, Tablespaces und Datenbankrechte aus.

**Wiederholbar:** Vor jedem `CREATE` prüft das Skript, ob das Objekt existiert, und überspringt es dann. Ein erneuter Lauf ist damit gefahrlos. `GRANT`-Befehle werden bei jedem Lauf erneut ausgeführt.

**Fehlerbehandlung:** Die Db2-Return-Codes 0 bis 2 (Erfolg, keine Zeilen, Warnung) gelten als OK. Ab Return Code 4 (SQL- oder CLP-Fehler) bricht das Skript ab und gibt einen Exit-Code ungleich 0 zurück.

### 5.1 Trockenlauf (`--dry-run`)

Mit `--dry-run` verbindet sich das Skript, gibt jeden Befehl als `[DRY-RUN] Would execute: …` aus, ohne ihn auszuführen, und schreibt am Ende einen Report:

```
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
|---|---|
| Verbundener Benutzer hat `DBADM` oder `SYSADM` (Bufferpool, Tablespaces, Schemas anlegen) | `FAIL` |
| Verbundener Benutzer hat `ACCESSCTRL` oder `SECADM` (`GRANT`) | `FAIL` |
| Eine Default-Storage-Group existiert (`MANAGED BY AUTOMATIC STORAGE`) | `FAIL` |
| Ein vorhandener Bufferpool hat nicht die Seitengröße 32K | `FAIL` |
| Ein vorhandener Tablespace hat nicht die Seitengröße 32K | `FAIL` |
| Ein vorhandenes Schema gehört einem anderen Besitzer als dem Service-Benutzer | `WARN` |
| Die Service-Benutzer sind auf dem Host auflösbar (`getent passwd`) | `WARN` |

Bei mindestens einem `FAIL` endet der Trockenlauf mit Exit-Code 1. Der Trockenlauf kann nicht prüfen, ob die Benutzer in LDAP existieren, wenn der Host sie nicht über `getent` auflöst. Er sagt auch keinen Speicherplatz und keine Sperren voraus.

---

## 6. CI/CD Pipeline-Integration

Der Runner bzw. Agent benötigt einen installierten DB2-Client mit katalogisierter Datenbank sowie einen Account mit den Rechten aus Abschnitt 4. Das Skript wird direkt aufgerufen und liefert einen Exit-Code für die Pipeline.

### GitLab CI/CD

```yaml
stages:
  - deploy-db

deploy_iccx_db2_int:
  stage: deploy-db
  tags:
    - db2-runner
  variables:
    DB_NAME: "AVAMDMSDB"
    ENV_NAME: "int"
  script:
    - chmod +x ./create_iccx_db_objects.sh
    - ./create_iccx_db_objects.sh "${DB_NAME}" "${ENV_NAME}"
  only:
    - develop

deploy_iccx_db2_prd:
  stage: deploy-db
  tags:
    - db2-runner
  variables:
    DB_NAME: "AVAMDMSDB"
    ENV_NAME: "prd"
  script:
    - chmod +x ./create_iccx_db_objects.sh
    - ./create_iccx_db_objects.sh "${DB_NAME}" "${ENV_NAME}"
  when: manual
  only:
    - main
```

### GitHub Actions

```yaml
name: Deploy ICCx DB2 Objects

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Zielumgebung (int, tst, prd)'
        required: true
        default: 'int'
      dbname:
        description: 'DB2 Datenbankname'
        required: true
        default: 'AVAMDMSDB'

jobs:
  deploy:
    runs-on: [self-hosted, db2-client]
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Run DB2 Setup
        env:
          DB_NAME: ${{ github.event.inputs.dbname }}
          ENV_NAME: ${{ github.event.inputs.environment }}
        run: |
          chmod +x ./create_iccx_db_objects.sh
          ./create_iccx_db_objects.sh "${DB_NAME}" "${ENV_NAME}"
```

### Azure DevOps Pipelines

```yaml
trigger: none

parameters:
  - name: dbName
    displayName: "DB2 Database Name"
    type: string
    default: "AVAMDMSDB"
  - name: envSuffix
    displayName: "Environment Suffix"
    type: string
    default: "int"
    values:
      - dev
      - int
      - tst
      - prd

jobs:
- job: DeployDB2
  pool:
    name: 'DB2-Agent-Pool'
  steps:
  - script: |
      chmod +x ./create_iccx_db_objects.sh
      ./create_iccx_db_objects.sh "${{ parameters.dbName }}" "${{ parameters.envSuffix }}"
    displayName: 'Execute DB2 Setup Script'
```

### Jenkinsfile

```groovy
pipeline {
    agent { label 'db2-agent' }
    parameters {
        string(name: 'DB_NAME', defaultValue: 'AVAMDMSDB', description: 'DB2 Datenbankname')
        choice(name: 'ENV_SUFFIX', choices: ['int', 'tst', 'prd', 'dev'], description: 'Umgebungssuffix')
    }
    stages {
        stage('Deploy DB2 Objects') {
            steps {
                sh '''
                    chmod +x ./create_iccx_db_objects.sh
                    ./create_iccx_db_objects.sh "${DB_NAME}" "${ENV_SUFFIX}"
                '''
            }
        }
    }
}
```

---

## 7. Verifikation & Qualitätssicherung

Das Skript gibt am Ende bereits Schemas, Tablespaces und Datenbankrechte aus. Für eine ausführlichere Kontrolle nach dem Deployment:

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
WHERE TBSPACE LIKE 'TS\_%' ESCAPE '\'
   OR TBSPACE LIKE 'ICCX\_%' ESCAPE '\'
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

CONNECT RESET;
```

---

## 8. Fehlerbehebung & Best Practices

| Symptom / Fehler | Ursache | Lösung |
| :--- | :--- | :--- |
| `SQL0204N ... "AVAMDMSDBP32KB" is an undefined name` | Der Bufferpool wurde vor der Tablespace-Erstellung nicht angelegt oder ist fehlgeschlagen. | Prüfen, ob `CREATE BUFFERPOOL` erfolgreich durchlief (`SYSCAT.BUFFERPOOLS`). |
| `SQL0551N ... does not have required authorization` | Der ausführende Benutzer besitzt nicht ausreichend Rechte (z.B. fehlendes `SECADM` / `DBADM`). | Skript mit einem privilegierten DB2-Admin-Account (`db2inst1` oder administrativer CI/CD-Service-Account) ausführen. |
| `SQL1585N ... no system temporary table space with sufficient page size` | Es existiert kein System Temporary Tablespace mit 32K. | Skript erneut ausführen. Es legt `ICCX_SYSTEMP` an, falls keiner mit 32K existiert. |
| `SQL0289N Unable to allocate new pages in table space` | DB2 Automatic Storage Speicherpfad ist voll oder nicht konfiguriert. | Plattenplatz der DB2 Storage Groups prüfen (`db2pd -storagepools`). |
| `SQL0567N ... invalid authorization ID` | Der angegebene Benutzername ist im OS/LDAP unbekannt oder überschreitet die DB2-Längenbegrenzung. | Sicherstellen, dass die Service-Accounts im LDAP/OS existieren und in Klein-/Großschreibung übereinstimmen. |
| `ERROR: Invalid database name` / `Invalid environment` | Die Parameter enthalten unzulässige Zeichen. | Nur die in Abschnitt 3 erlaubten Zeichen verwenden. |

---

## 9. Rückbau (`drop_iccx_db_objects.sh`)

[`drop_iccx_db_objects.sh`](drop_iccx_db_objects.sh) entfernt alle Objekte, die `create_iccx_db_objects.sh` angelegt hat. Die Objektnamen sind in beiden Skripten identisch hinterlegt. Bei Änderungen an Namen müssen beide Skripte angepasst werden.

> **Achtung:** Der Rückbau ist destruktiv und nicht umkehrbar. Alle Tabellen und Daten in den ICCx-Schemas gehen verloren. Vorher ein Datenbank-Backup erstellen.

```bash
chmod +x drop_iccx_db_objects.sh

# Interaktiv: der Datenbankname muss zur Bestätigung eingegeben werden
./drop_iccx_db_objects.sh AVAMDMSDB ftst

# Ohne Rückfrage (Pflicht in CI/CD, ohne Terminal bricht das Skript sonst ab)
./drop_iccx_db_objects.sh AVAMDMSDB ftst --yes

# Trockenlauf: zeigt Plan und die geplanten Befehle, ändert nichts
./drop_iccx_db_objects.sh AVAMDMSDB ftst --dry-run

# Mit explizitem (LDAP-)Benutzer, das Passwort fragt Db2 interaktiv ab
./drop_iccx_db_objects.sh AVAMDMSDB ftst --user meinldapuser --dry-run
```

`--user <name>` verhält sich wie beim Anlegen-Skript (Abschnitt 5): `CONNECT TO <db> USER <name>`, Passwortabfrage durch Db2, nur mit interaktivem Terminal. Der Benutzer darf keiner der ICCx-Service-Benutzer sein. Auch `--password-file <pfad>` funktioniert hier identisch (Abschnitt 5), z. B. `--user db2inst1 --password-file /secrets/db2instancepwd/password`.

Mit `--dry-run` verbindet sich das Skript, führt die Vorabprüfungen aus und gibt jeden Befehl als `[DRY-RUN] Would execute: …` aus, ohne ihn auszuführen. Es erfolgt keine Rückfrage und keine Abschlussprüfung. `--dry-run` und `--yes` lassen sich kombinieren, `--dry-run` hat dann Vorrang.

Zusätzlich prüft der Trockenlauf mit reinen Leseabfragen, ob der echte Lauf voraussichtlich gelingt:

| Prüfung | Ergebnis bei Problem |
|---|---|
| Verbundener Benutzer ist keiner der ICCx-Benutzer (`REVOKE` vom ausführenden Benutzer wird mit SQLSTATE 42502 abgelehnt) | `FAIL` |
| Verbundener Benutzer hat `DBADM` oder `SYSADM` (Schemas, Tablespaces, Bufferpool löschen) | `FAIL` |
| Verbundener Benutzer hat `ACCESSCTRL` oder `SECADM` (`REVOKE`) | `FAIL` |
| Aktive Verbindungen der ICCx-Benutzer (Sperren können das Löschen blockieren) | `WARN` |
| `ICCX_SYSTEMP` ist der letzte System Temporary Tablespace seiner Seitengröße (`SQL0283N`) | `WARN` |

Bei mindestens einem `FAIL` endet der Trockenlauf mit Exit-Code 1. Eine Garantie ist das nicht: Der Trockenlauf kann Sperren, Platzprobleme oder Fehler in einzelnen Objekten nicht vorhersagen. Ein echter Probelauf mit Rollback ist nicht möglich, weil `DROP TABLESPACE` und `ADMIN_DROP_SCHEMA` nicht zuverlässig rückgängig zu machen sind.

**Reihenfolge:**
1. Schemas samt Inhalt (`SYSPROC.ADMIN_DROP_SCHEMA`, danach `DROP SCHEMA … RESTRICT`).
2. Berechtigungen der fünf Service-Benutzer (`REVOKE` auf Datenbank, Katalogsichten und Workload).
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
- Rechte von `PUBLIC`.
- `SYSTOOLSPACE`.

