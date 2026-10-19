# 🚀 IBM MQ to Kafka Streaming Pipeline via Confluent for Kubernetes (CFK)

Dieses Repository enthält die deklarative Konfiguration (GitOps-ready) zur Einrichtung einer Event-Streaming-Pipeline von **IBM MQ** nach **Apache Kafka** unter Verwendung von **Confluent for Kubernetes (CFK)** auf **Minikube**. Zwei Stacks (`source` und `destination`) werden per **Helmfile** deployt und über einen **Cluster Link** verbunden.

---

## 📋 Voraussetzungen

* **Minikube** (mit aktivierter Container-Runtime)
* **kubectl**
* **Docker Desktop**
* **Helm** und **Helmfile** (der CFK Operator wird von Helmfile mitinstalliert)

---

## 🛠️ 1. Docker Image bauen & bereitstellen

Da der IBM MQ Source Connector proprietäre Treiberelemente benötigt (`com.ibm.mq.allclient.jar` und `javax.jms-api.jar`), nutzen wir ein Custom Docker Image basierend auf `Dockerfile.connect`.

### Schritt 1.1: Docker CLI auf Minikube-Engine umstellen

Damit das gebaute Image direkt im Minikube-Cluster verfügbar ist, verbinden wir die lokale Shell mit der Docker-Engine von Minikube:

```bash
eval $(minikube docker-env)
```

### Schritt 1.2: Custom Connect Image bauen

Baue das Image unter Verwendung von `Dockerfile.connect`:

```bash
DOCKER_BUILDKIT=0 docker build -f Dockerfile.connect -t custom-connect-ibmmq:7.6.0 .
```

---

## 📦 2. Kubernetes Ressourcen deployen

Alle Ressourcen werden über `helmfile.yaml` deployt:

| Release | Namespace | Inhalt |
|---|---|---|
| `confluent-operator-source` | `source` | CFK Operator |
| `confluent-operator-destination` | `destination` | CFK Operator |
| `source-stack` | `source` | KRaft, Kafka, Schema Registry, Control Center, Connect, IBM MQ, MQ Source Connector, Topic |
| `destination-stack` | `destination` | wie oben, aber ohne IBM MQ/Connector, dafür mit Cluster Link von `source` |

Der gemeinsame Chart liegt unter `charts/ibm-kafka-stack`, Einstellungen in dessen `values.yaml`.

### Schritt 2.1: Confluent Helm Repository hinzufügen

```bash
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
```

### Schritt 2.2: Alles deployen

```bash
helmfile apply
```

Vorschau ohne Änderungen am Cluster: `helmfile diff` bzw. `helmfile template`.

---

### Alternative: Deployment mit Argo CD

Statt Helmfile kann alles per Argo CD (App-of-Apps) deployt werden. Der Chart `charts/confluent-apps` erzeugt im Namespace `argocd` vier `Application`s:

| Application | Namespace | Sync-Wave |
|---|---|---|
| `confluent-operator-source` | `source` | 0 (installiert die CFK CRDs) |
| `confluent-operator-destination` | `destination` | 0 (`skipCrds`) |
| `source-stack` | `source` | 1 |
| `destination-stack` | `destination` | 1 |

Die Namespaces werden von Argo CD angelegt (`CreateNamespace=true`). Namespaces und Stack-Werte lassen sich in `charts/confluent-apps/values.yaml` anpassen.

**Voraussetzungen:** Argo CD läuft im Namespace `argocd`, und dieses Repository liegt in einem Git-Remote, auf das Argo CD zugreifen kann.

1. In `argocd/root-app.yaml` `repoURL` (beide Stellen) zeigt auf `https://github.com/BigDatalex/confluent-platform.git`; Änderungen pushen.
2. Root-Application anlegen:

   ```bash
   kubectl apply -n argocd -f argocd/root-app.yaml
   ```

> **Hinweis:** Argo CD wartet zwischen Sync-Waves von Child-Applications nur, wenn der Health-Check für `argoproj.io/Application` in `argocd-cm` aktiviert ist ([Doku](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)). Ohne ihn konvergiert das Setup trotzdem: Die Stacks nutzen `SkipDryRunOnMissingResource` und Retries, bis die CRDs des Operators existieren.

> **Hinweis:** Das Image `custom-connect-ibmmq:7.6.0` muss weiterhin wie in Abschnitt 1 lokal in Minikube gebaut werden.

Helmfile und Argo CD nicht parallel auf denselben Cluster anwenden.

---

## ✉️ 3. Test-Nachricht an IBM MQ senden

Verwende das in IBM MQ enthaltene Test-Tool `amqsput`, um Nachrichten in die Queue `DEV.QUEUE.1` zu schreiben.

**Interaktiven Writer im IBM MQ Pod starten:**

```bash
kubectl exec -it deployment/ibmmq -n source -- /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 QM1
```

**Test-JSON eingeben und mit Enter bestätigen:**

```json
{"event_id": 1001, "message": "Hallo aus IBM MQ via CFK Connector!", "timestamp": "2026-10-05"}
```

**Beenden:** Drücke zweimal Enter (leere Zeile), um den Stream zu schließen.

### Queue-Inhalt prüfen (optional)

Prüfe mit `amqsbcg`, ob die Nachricht in MQ bereitsteht oder bereits vom Connector abgeholt wurde:

```bash
kubectl exec -it deployment/ibmmq -n source -- /opt/mqm/samp/bin/amqsbcg DEV.QUEUE.1 QM1
```

> Zeigt `No more messages` an, sobald der Connector die Nachricht verarbeitet hat.

---

## 🖥️ 4. Nachrichten im Confluent Control Center ansehen

### Schritt 4.1: Port-Forwarding zum Control Center starten

Öffne ein Terminal und leite den Port des Control Centers weiter:

```bash
kubectl port-forward svc/controlcenter 9021:9021 -n source
```

### Schritt 4.2: Control Center im Browser öffnen

Rufe folgende URL im Browser auf:
👉 <http://localhost:9021>

### Schritt 4.3: Nachrichten & Connector verifizieren

1. **Cluster auswählen:** Klicke auf deinen Control-Center-Cluster (z. B. `controlcenter`).
2. **Connector-Status prüfen:**
   * Navigiere im linken Menü auf **Connect**.
   * Wähle `connect-cluster`.
   * Der Connector `ibm-mq-source` sollte den Status **RUNNING** haben (sowohl Connector als auch Task 0).
3. **Nachrichten im Topic ansehen:**
   * Navigiere im linken Menü auf **Topics**.
   * Wähle das Topic `ibmmq-messages`.
   * Wechsle auf den Tab **Messages**.
   * Klicke auf **Offset / Jump to offset** (z. B. Offset `0` / *From beginning*).

Hier siehst du die aus IBM MQ gestreamten JSON-Nachrichten inklusive JMS-Metadaten und Nutzlast!

---

## 🔍 Troubleshooting Commands

**Connector Task-Status via REST API prüfen:**

```bash
kubectl exec -it connect-cluster-0 -n source -- curl -s http://localhost:8083/connectors/ibm-mq-source/tasks/0/status
```

**Connect Cluster Logs einsehen:**

```bash
kubectl logs statefulset/connect-cluster -n source --tail=100
```

**Connect Pod neu starten (Rollout Restart):**

```bash
kubectl rollout restart statefulset/connect-cluster -n source
```

# Argo CD
```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d | pbcopy