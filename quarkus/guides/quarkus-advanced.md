# Quarkus — Référence avancée

## Build-time vs Runtime

Quarkus fait le maximum au **build time** (CDI, Hibernate metadata, config resolution). Conséquences :
- Certaines properties sont **fixées au build** (db-kind, jdbc.driver en 2.16)
- `@IfBuildProfile` et `@UnlessBuildProfile` pour conditionner les beans
- `quarkus.package.type=fast-jar` (défaut), `uber-jar`, `native`, `native-sources`

## Extensions essentielles

| Extension | Artefact Maven | Usage |
|-----------|---------------|-------|
| RESTEasy Reactive | `quarkus-rest` (3.9+) ou `quarkus-resteasy-reactive` | REST APIs non-bloquantes |
| Hibernate ORM + Panache | `quarkus-hibernate-orm-panache` | Active Record ou Repository JPA |
| SmallRye Reactive Messaging | `quarkus-messaging-kafka` | Kafka consumers/producers |
| SmallRye Health | `quarkus-smallrye-health` | /q/health (liveness, readiness) |
| SmallRye OpenAPI | `quarkus-smallrye-openapi` | /q/openapi, Swagger UI |
| Micrometer Prometheus | `quarkus-micrometer-registry-prometheus` | /q/metrics |
| REST Client | `quarkus-rest-client-reactive` | Appels HTTP déclaratifs |
| Cache | `quarkus-cache` | @CacheResult, @CacheInvalidate |
| Scheduler | `quarkus-scheduler` | @Scheduled |
| Flyway | `quarkus-flyway` | Migrations BDD |

## Dev Services (TestContainers automatiques)

Quarkus démarre automatiquement les services nécessaires en `%dev` et `%test` :

```properties
# Pas besoin de configurer, Quarkus détecte et démarre automatiquement :
# - PostgreSQL/MySQL/Oracle via testcontainers
# - Kafka via Redpanda
# - RabbitMQ, Redis, MongoDB, etc.
# Désactiver si Docker incompatible :
quarkus.devservices.enabled=false
```

## Reactive vs Imperative

```java
// Imperative (thread bloquant)
@GET
@Path("/{id}")
public MyEntity get(@PathParam("id") Long id) {
    return MyEntity.findById(id);
}

// Reactive (non-bloquant, Mutiny)
@GET
@Path("/{id}")
public Uni<MyEntity> getReactive(@PathParam("id") Long id) {
    return MyEntity.findById(id);
}
```

Utiliser `@Blocking` sur un endpoint reactive pour le forcer en thread pool worker.

## Kafka SmallRye Reactive Messaging

### Consumer

```java
@ApplicationScoped
public class MyConsumer {

    @Incoming("my-channel")
    @Acknowledgment(Acknowledgment.Strategy.POST_PROCESSING) // at-least-once
    @Blocking  // si traitement synchrone
    public CompletionStage<Void> consume(Message<String> msg) {
        try {
            process(msg.getPayload());
            return msg.ack();
        } catch (Exception e) {
            return msg.nack(e);  // → DLQ si configuré
        }
    }
}
```

### Configuration Kafka

```properties
# Canal entrant
mp.messaging.incoming.my-channel.connector=smallrye-kafka
mp.messaging.incoming.my-channel.topic=my-topic
mp.messaging.incoming.my-channel.group.id=my-group
mp.messaging.incoming.my-channel.auto.offset.reset=earliest
mp.messaging.incoming.my-channel.failure-strategy=dead-letter-queue
mp.messaging.incoming.my-channel.dead-letter-queue.topic=my-topic-dlq

# Désactiver en test
%test.mp.messaging.incoming.my-channel.enabled=false

# Throttling en dev
%dev.mp.messaging.incoming.my-channel.pause-if-no-requests=false
```

### Acknowledgment strategies

| Stratégie | Quand l'offset est committé | Sémantique |
|-----------|---------------------------|------------|
| `PRE_PROCESSING` | Avant le traitement | At-most-once |
| `POST_PROCESSING` | Après le traitement | At-least-once |
| `MANUAL` | Quand msg.ack() est appelé | Contrôle total |

## Panache — Active Record vs Repository

```java
// Active Record (recommandé pour les cas simples)
@Entity
public class Person extends PanacheEntity {
    public String name;
    
    public static List<Person> findByName(String name) {
        return find("name", name).list();
    }
}

// Repository (pour inversion of control, testabilité)
@ApplicationScoped
public class PersonRepository implements PanacheRepository<Person> {
    public List<Person> findByName(String name) {
        return find("name", name).list();
    }
}
```

## Configuration multi-profils

```properties
# Défaut (production)
quarkus.datasource.db-kind=oracle
quarkus.datasource.jdbc.url=jdbc:oracle:thin:@prod:1521/ORCL

# Dev (Docker local)
%dev.quarkus.datasource.db-kind=oracle
%dev.quarkus.datasource.jdbc.url=jdbc:oracle:thin:@localhost:1521/XEPDB1

# Test (H2 in-memory)
%test.quarkus.datasource.db-kind=h2
%test.quarkus.datasource.jdbc.url=jdbc:h2:mem:testdb

# CI (mêmes valeurs que test mais avec couverture)
%ci.quarkus.datasource.db-kind=h2
```

## Tests

```java
@QuarkusTest
@Tag("integration")
class MyResourceTest {

    @Test
    @DisplayName("GET /api/persons retourne 200")
    void testGetPersons() {
        given()
            .when().get("/api/persons")
            .then()
            .statusCode(200)
            .body("size()", greaterThan(0));
    }
}

// Test natif (compile et exécute en natif)
@QuarkusIntegrationTest
class MyResourceIT extends MyResourceTest {}
```

## Health checks

```java
@Liveness
@ApplicationScoped
public class MyLivenessCheck implements HealthCheck {
    @Override
    public HealthCheckResponse call() {
        return HealthCheckResponse.up("alive");
    }
}

@Readiness
@ApplicationScoped
public class MyReadinessCheck implements HealthCheck {
    @Override
    public HealthCheckResponse call() {
        // Vérifier les dépendances externes
        return HealthCheckResponse.named("database")
            .status(isDatabaseReachable())
            .withData("driver", "oracle")
            .build();
    }
}
```

## Pitfalls Quarkus

1. **@Transactional sur méthode privée** : silencieux en 2.x, ERROR en 3.x
2. **CDI beans scope** : `@ApplicationScoped` (proxy, lazy) vs `@Singleton` (pas de proxy, eager)
3. **build-time properties** (2.16) : `db-kind`, `jdbc.driver` fixés au build — pas modifiable au runtime
4. **Kafka désactivé en test** : sans `enabled=false`, Quarkus tente de se connecter au broker
5. **Hibernate lazy loading** : toujours dans une transaction, sinon `LazyInitializationException`
6. **REST client timeout** : configurer explicitement, le défaut est illimité
7. **SmallRye Reactive Messaging — canaux avec tirets et env vars** : les env vars `MP_MESSAGING_INCOMING_MY_CHANNEL_*` ne peuvent pas représenter sans ambiguïté un canal nommé `my-channel`. MicroProfile Config convertit `_` → `.` (simple), donc `MP_MESSAGING_INCOMING_MY_CHANNEL_CONNECTOR` devient `mp.messaging.incoming.my.channel.connector`, ce qui crée un canal parasite `my` au lieu de configurer `my-channel`. Symptôme : `SRMSG00071: connector attribute must be set for channel 'my'`. **Solution** : monter un fichier `application.properties` via ConfigMap dans `/deployments/config/` (Quarkus le charge automatiquement avec priorité haute). Toujours utiliser la notation `.properties` pour les canaux dont le nom contient des tirets.

```yaml
# Kubernetes ConfigMap monté dans /deployments/config/application.properties
mp.messaging.incoming.my-channel.connector=smallrye-kafka
mp.messaging.incoming.my-channel.bootstrap.servers=kafka:9092
mp.messaging.incoming.my-channel.topic=my-topic
```

8. **SmallRye Kafka — profil par défaut** : le profil par défaut utilise souvent `smallrye-in-memory` comme connecteur. En K8s (profil `prod`), sans surcharge explicite du connecteur, l'application ne consomme pas le vrai Kafka. Ne jamais oublier de configurer explicitement `connector=smallrye-kafka` pour les envs K8s.
