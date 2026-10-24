# Secret-Mount im Pod prüfen (OpenShift / Kubernetes)

Diese Anleitung zeigt, wie man prüft, ob ein Secret als **Datei (Volume)** in einem Pod eingebunden ist und ob die erwarteten Dateien im Container vorhanden sind.

## Voraussetzungen

- Zugriff auf den Cluster über `oc` (oder `kubectl`)
- Berechtigung für `get pod`, `get secret` und `exec` im Ziel-Namespace
- Optional: `jq` für eine lesbare JSON-Ausgabe

## Platzhalter

| Platzhalter    | Bedeutung                                   |
|----------------|---------------------------------------------|
| `<pod>`        | Name des Pods                               |
| `<namespace>`  | Namespace des Pods                          |
| `<container>`  | Container-Name (bei Multi-Container-Pods)   |
| `<secret>`     | Name des Secrets                            |
| `<mountPath>`  | Mount-Pfad des Secrets im Container         |
| `<key>`        | Key im Secret, entspricht dem Dateinamen    |

---

## 1. In der Pod-Definition prüfen

Zuerst wird geprüft, ob das Secret als Volume definiert ist und unter welchem Pfad es gemountet wird.

```bash
# Volumes und VolumeMounts anzeigen
oc get pod <pod> -n <namespace> -o yaml | grep -A5 -E "secret:|volumeMounts:"

# Als Volume eingebundene Secrets (Volume-Name -> Secret-Name)
oc get pod <pod> -n <namespace> -o jsonpath='{range .spec.volumes[*]}{.name}{" -> "}{.secret.secretName}{"\n"}{end}'

# Mount-Pfade pro Container
oc get pod <pod> -n <namespace> -o jsonpath='{range .spec.containers[*]}{.name}{":\n"}{range .volumeMounts[*]}{"  "}{.name}{" -> "}{.mountPath}{"\n"}{end}{end}'
```

**Alternative mit übersichtlicher Ausgabe:**

```bash
oc describe pod <pod> -n <namespace>
```

- Im Abschnitt **Volumes** steht `Type: Secret (...)` mit dem `SecretName`.
- Im Abschnitt **Mounts** steht beim jeweiligen Container der Mount-Pfad.

---

## 2. Im laufenden Container prüfen

Danach wird geprüft, ob die Dateien im Container tatsächlich vorhanden sind.

```bash
# Dateien im Mount-Pfad auflisten
oc exec <pod> -n <namespace> -c <container> -- ls -la <mountPath>

# Inhalt eines Keys anzeigen (Achtung: sensible Daten!)
oc exec <pod> -n <namespace> -c <container> -- cat <mountPath>/<key>

# Alle tmpfs-Mounts im Container anzeigen (Secret-Volumes sind tmpfs)
oc exec <pod> -n <namespace> -- sh -c 'mount | grep -i tmpfs'
```

### Hinweise

- Secret-Volumes werden als **tmpfs** gemountet und liegen daher nur im Arbeitsspeicher.
- Für **jeden Key** im Secret gibt es eine **eigene Datei**.
- Die Dateien sind Symlinks auf `..data/`. Ändert sich das Secret, werden sie automatisch aktualisiert.
- **Ausnahme:** Bei Mounts mit `subPath` werden die Dateien **nicht** automatisch aktualisiert.

---

## 3. Mit dem Secret abgleichen

Zum Schluss werden die Keys und Werte mit dem Inhalt im Container verglichen.

```bash
# Keys im Secret auflisten
oc get secret <secret> -n <namespace> -o jsonpath='{.data}' | jq 'keys'

# Wert eines Keys dekodiert anzeigen
oc get secret <secret> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d
```

---

## Wichtig: Einbindung als Umgebungsvariable

Wird das Secret nur über `env` oder `envFrom` eingebunden, gibt es **keine Datei** im Container. Prüfen lässt sich das so:

```bash
oc exec <pod> -n <namespace> -- env | grep -i <name>
```

---

## Kurzübersicht

| Ziel                                | Befehl                                                        |
|-------------------------------------|---------------------------------------------------------------|
| Secret-Volumes im Pod               | `oc describe pod <pod> -n <namespace>`                        |
| Dateien im Container                | `oc exec <pod> -n <namespace> -- ls -la <mountPath>`          |
| Keys im Secret                      | `oc get secret <secret> -n <namespace> -o jsonpath='{.data}'` |
| Secret als Umgebungsvariable        | `oc exec <pod> -n <namespace> -- env \| grep -i <name>`       |
