# Spring Boot 4.x / Spring Framework 7.x — Java 21+

GA : 20 novembre 2025 | Dernière version : 4.0.5 (mars 2026)

---

## Versions de l'écosystème

| Composant | Version |
|---|---|
| Spring Framework | **7.0** |
| Spring Boot | **4.0.5** (4.1.0-M4 en cours) |
| Spring Security | **7.0** |
| Spring Data | **2025.1** |
| Hibernate ORM | **7.1/7.2** (JPA 3.2) |
| Jackson | **3.0** (group ID: `tools.jackson`) |
| Jakarta EE | **11** (Servlet 6.1, Bean Validation 3.1) |
| Tomcat | **11.0** |
| Jetty | **12.1** |
| Micrometer | **1.16** |
| JUnit | **6** |
| Kotlin | **2.2** |
| TestContainers | **2.0** |

**Java** : minimum 17, recommandé **25** (LTS). Java 21 pour virtual threads.

---

## Changements majeurs vs 3.x

### Modularisation (changement structurel principal)

L'auto-configuration est découpée en **modules focalisés** au lieu de jars monolithiques. Résultat : startup plus rapide, moins de mémoire, native-image plus rapide.

Renommages de starters :
```xml
<!-- 3.x -->                              <!-- 4.x -->
spring-boot-starter-web          →  spring-boot-starter-webmvc
spring-boot-starter-aop          →  spring-boot-starter-aspectj
spring-boot-starter-oauth2-*     →  spring-boot-starter-security-oauth2-*
```

Transition : `spring-boot-starter-classic` pour une migration progressive.

### Jakarta EE 11

- **Servlet 6.1** (Tomcat 11.0, Jetty 12.1)
- **JPA 3.2** (Hibernate 7.1)
- **Bean Validation 3.1**
- **Undertow SUPPRIMÉ** (pas de support Servlet 6.1)

### Jackson 3.0 (remplace Jackson 2.x)

```xml
<!-- 4.x : Jackson 3 par défaut -->
<dependency>
    <groupId>tools.jackson</groupId>              <!-- était com.fasterxml.jackson -->
    <artifactId>jackson-databind</artifactId>
</dependency>

<!-- Fallback Jackson 2 (déprécié) -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-jackson2</artifactId>
</dependency>
```

### Null safety avec JSpecify

```java
// Toutes les APIs Spring sont maintenant annotées
import org.jspecify.annotations.NullMarked;
import org.jspecify.annotations.Nullable;

@NullMarked
public class MyService {
    public @Nullable User findById(Long id) { ... }
}
```

### API versioning natif

```yaml
spring:
  mvc:
    apiversion:
      type: path-prefix  # ou header, query-parameter, media-type
      prefix: /api/v
```

```java
@RestController
@RequestMapping("/users")
public class UserController {
    @GetMapping(version = "1")
    public List<UserV1> listV1() { ... }
    
    @GetMapping(version = "2")
    public List<UserV2> listV2() { ... }
}
```

### HTTP Service Clients (déclaratif)

```java
@HttpExchange("/api/users")
public interface UserClient {
    @GetExchange
    List<User> findAll();
    
    @PostExchange
    User create(@RequestBody User user);
}

// Auto-configuré avec @ImportHttpServices
```

### Résilience intégrée dans spring-core

```java
@Retryable(maxAttempts = 3, backoff = @Backoff(delay = 1000))
public String callExternalService() { ... }

@ConcurrencyLimit(10)
public void processBatch() { ... }
```

---

## Virtual Threads (Java 21+)

```yaml
spring.threads.virtual.enabled: true
```

- **PAS activé par défaut** mais intégration profonde
- HTTP clients, task executors, schedulers sont virtual-thread-aware
- Recommandé pour les workloads I/O-bound (REST calls, DB, messaging)
- **Éviter** pour les workloads CPU-bound (compression, crypto)

---

## GraalVM Native Image

- **GraalVM 25** requis (nouveau format metadata)
- Pipeline AOT redesigné : beans conditionnels et profils gérés automatiquement
- RuntimeHints automatiques pour beans Spring, entités JPA, contrôleurs
- Proxies interface (JDK) préférés aux proxies CGLIB
- Log4j2 supporté en natif (depuis 4.0.1)
- **Startup < 100ms** réalisable en production

---

## Observabilité

```xml
<!-- UN seul starter pour tout -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-opentelemetry</artifactId>
</dependency>
```

```yaml
management:
  otlp:
    tracing:
      endpoint: http://otel-collector:4318/v1/traces
    metrics:
      endpoint: http://otel-collector:4318/v1/metrics
```

```java
@Observed(name = "order.process", contextualName = "process-order")
public Order processOrder(OrderRequest request) { ... }
// Crée automatiquement métriques Micrometer + spans OpenTelemetry
```

---

## Spring Security 7.0

### MFA natif

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/**").authenticated()
                .anyRequest().permitAll()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .csrf(csrf -> csrf.spa())  // SPA-friendly CSRF
            .build();
    }
}
```

- `PathPatternRequestMatcher` remplace `MvcRequestMatcher` et `AntPathRequestMatcher`
- Spring Authorization Server fusionné dans Spring Security
- **PKCE activé par défaut**
- Password4j : Argon2, BCrypt, SCrypt, PBKDF2

---

## Spring Data JPA / Hibernate 7

```java
// Derived queries génèrent maintenant du JPQL (3.5x plus rapide)
public interface UserRepository extends JpaRepository<User, Long> {
    List<User> findByNameContaining(String name);
    Optional<User> findByEmail(String email);
}
```

- `getSingleResultOrNull()` remplace la gestion de `NoResultException`
- Nouvelles fonctions SQL : `union`, `intersect`, `except`, `cast`
- `hibernate-jpamodelgen` renommé en `hibernate-processor`
- Spring Batch : mode in-memory par défaut (ajouter `spring-boot-starter-batch-jdbc` pour DB)

---

## Tests

### Changements CRITIQUES

```java
// 3.x (SUPPRIMÉ en 4.x)
@MockBean UserService userService;
@SpyBean AuditService auditService;

// 4.x (obligatoire)
@MockitoBean UserService userService;
@MockitoSpyBean AuditService auditService;
```

```java
// 3.x : MockMvc auto-configuré dans @SpringBootTest
@SpringBootTest
class MyTest {
    @Autowired MockMvc mvc;  // marchait en 3.x
}

// 4.x : DOIT ajouter @AutoConfigureMockMvc explicitement
@SpringBootTest
@AutoConfigureMockMvc
class MyTest {
    @Autowired MockMvc mvc;
}
```

### Nouveau RestTestClient

```java
// Alternative non-réactive à WebTestClient
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@AutoConfigureRestTestClient
class MyApiTest {
    @Autowired RestTestClient restClient;
    
    @Test
    void getUsers() {
        restClient.get().uri("/api/users")
            .exchange()
            .expectStatus().isOk()
            .expectBody().jsonPath("$.length()").isGreaterThan(0);
    }
}
```

- JUnit 4 support **entièrement supprimé** (SpringRunner, SpringClassRule)
- JUnit 6 supporté
- `@MockitoBean` / `@MockitoSpyBean` supportent les beans non-singleton

---

## Migration 3.x → 4.x

### Prérequis

1. Être sur la **dernière 3.5.x** d'abord
2. Résoudre tous les appels de méthodes dépréciées
3. Vérifier la compatibilité Spring Cloud

### Étapes critiques

```xml
<!-- Ajouter le migrator pour analyser automatiquement -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-properties-migrator</artifactId>
    <scope>runtime</scope>
</dependency>
```

1. **Starters** : renommer (webmvc, aspectj, security-oauth2-*)
2. **Jackson** : migrer group ID `com.fasterxml.jackson` → `tools.jackson`
3. **Tests** : `@MockBean` → `@MockitoBean`, ajouter `@AutoConfigureMockMvc`
4. **Undertow** → Tomcat ou Jetty
5. **Properties** : `spring.session.redis.*` → `spring.session.data.redis.*`
6. **Security** : `authorizeRequests` → `authorizeHttpRequests`, `and()` supprimé

### Transition progressive

```xml
<!-- Utiliser le starter classic pour migrer progressivement -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-classic</artifactId>
</dependency>
```

---

## Suppressions depuis 3.x

| Supprimé | Remplacement |
|---|---|
| Undertow | Tomcat 11 ou Jetty 12.1 |
| `@MockBean` / `@SpyBean` | `@MockitoBean` / `@MockitoSpyBean` |
| JUnit 4 support | JUnit 5/6 |
| Jackson 2 (non déprécié) | Jackson 3.0 (`tools.jackson`) |
| `authorizeRequests()` | `authorizeHttpRequests()` |
| `MvcRequestMatcher` | `PathPatternRequestMatcher` |
| `ListenableFuture` | `CompletableFuture` |
| Spring Session Hazelcast/MongoDB | Maintenus par les projets respectifs |
| OkHttp3 | JDK HttpClient |
| RestTemplate (docs deprecated) | RestClient, WebClient, HTTP interfaces |

---

Sources :
- [Spring Boot 4.0 Release Notes](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Release-Notes)
- [Spring Boot 4.0 Migration Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide)
- [Spring Framework 7.0 Release Notes](https://github.com/spring-projects/spring-framework/wiki/Spring-Framework-7.0-Release-Notes)
- [Spring Boot 4.0.0 Announcement](https://spring.io/blog/2025/11/20/spring-boot-4-0-0-available-now/)
- [Spring Security 7.0 What's New](https://docs.spring.io/spring-security/reference/whats-new.html)
- [Spring Boot 4 & Spring Framework 7 (Baeldung)](https://www.baeldung.com/spring-boot-4-spring-framework-7)
