# 🚀 IBM MQ to Kafka Streaming Pipeline via Confluent for Kubernetes (CFK)

Dieses Repository enthält die deklarative Konfiguration (GitOps-ready) zur Einrichtung einer Event-Streaming-Pipeline von **IBM MQ** nach **Apache Kafka** unter Verwendung von **Confluent for Kubernetes (CFK)** auf **Minikube**.

---

## 📋 Voraussetzungen

* **Minikube** (mit aktivierter Container-Runtime)
* **kubectl**
* **Docker Desktop**
* **Confluent for Kubernetes Operator (CFK)** im Cluster installiert

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

Deploye die Infrastrukturkomponenten und Custom Resources in der vorgegebenen Reihenfolge.

### Schritt 2.1: Confluent Platform deployen (KRaft, Kafka, Schema Registry, Control Center, Connect)

Deploye die zentrale Confluent Platform-Infrastruktur inklusive KRaft Controller, Kafka Broker, Schema Registry, Control Center und Connect Cluster:

```bash
kubectl apply -f kafka_kraft.yaml -n default
```

### Schritt 2.2: IBM MQ Broker deployen

Deploye den IBM MQ Test-Container (Queue Manager: `QM1`, Queue: `DEV.QUEUE.1`, Channel: `DEV.APP.SVRCONN`):

```bash
kubectl apply -f ibm-mq.yaml -n default
```

### Schritt 2.3: Kafka Rest Class & Kafka Topics anlegen

Erstelle das Ziel-Topic `ibmmq-messages` sowie die benötigte `KafkaRestClass`:

```bash
kubectl apply -f kafka-rest-class.yaml -n default
kubectl apply -f kafka-topic.yaml -n default
```

### Schritt 2.4: IBM MQ Source Connector deployen

Deploye den Connector zur Anbindung der MQ-Queue `DEV.QUEUE.1`:

```bash
kubectl apply -f ibm-mq-sc.yaml -n default
```

---

## ✉️ 3. Test-Nachricht an IBM MQ senden

Verwende das in IBM MQ enthaltene Test-Tool `amqsput`, um Nachrichten in die Queue `DEV.QUEUE.1` zu schreiben.

**Interaktiven Writer im IBM MQ Pod starten:**

```bash
kubectl exec -it deployment/ibmmq -n default -- /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 QM1
```

**Test-JSON eingeben und mit Enter bestätigen:**

```json
{"event_id": 1001, "message": "Hallo aus IBM MQ via CFK Connector!", "timestamp": "2026-10-05"}
```

**Beenden:** Drücke zweimal Enter (leere Zeile), um den Stream zu schließen.

### Queue-Inhalt prüfen (optional)

Prüfe mit `amqsbcg`, ob die Nachricht in MQ bereitsteht oder bereits vom Connector abgeholt wurde:

```bash
kubectl exec -it deployment/ibmmq -n default -- /opt/mqm/samp/bin/amqsbcg DEV.QUEUE.1 QM1
```

> Zeigt `No more messages` an, sobald der Connector die Nachricht verarbeitet hat.

---

## 🖥️ 4. Nachrichten im Confluent Control Center ansehen

### Schritt 4.1: Port-Forwarding zum Control Center starten

Öffne ein Terminal und leite den Port des Control Centers weiter:

```bash
kubectl port-forward svc/controlcenter 9021:9021 -n default
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
kubectl exec -it connect-cluster-0 -n default -- curl -s http://localhost:8083/connectors/ibm-mq-source/tasks/0/status
```

**Connect Cluster Logs einsehen:**

```bash
kubectl logs statefulset/connect-cluster -n default --tail=100
```

**Connect Pod neu starten (Rollout Restart):**

```bash
kubectl rollout restart statefulset/connect-cluster -n default
```
