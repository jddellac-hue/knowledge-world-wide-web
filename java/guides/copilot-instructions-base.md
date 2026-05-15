# Instructions GitHub Copilot — Base partagée Java/Maven/Spring

> Ce fichier contient les conventions **génériques** applicables à tout projet Java/Maven/Spring Boot.
> Il est complété par un `copilot-instructions.md` spécifique au projet dans `.github/`.

## Stack technique cible

- **Java** : 17 ou 21 (LTS)
- **Build** : Maven (pas de Gradle)
- **Framework** : Spring Boot 3.x / 4.x, Spring Cloud
- **ORM** : Spring Data JPA
- **Mapping** : MapStruct + Lombok
- **Tests** : JUnit 5 (Jupiter), Mockito, AssertJ
- **Tests BDD** : Cucumber (optionnel)
- **Couverture** : JaCoCo via profil Maven **`-Pjacoco`**
- Structure : `src/main/java` pour le code source, `src/test/java` pour les tests

## Conventions de code

- Toujours écrire le code et les commentaires techniques en **anglais**.
- Respecter les conventions Java standard (camelCase, PascalCase pour les classes).
- Préférer l'injection par constructeur à l'injection par champ.
- Les méthodes publiques doivent avoir une Javadoc décrivant le contrat (paramètres, retour, exceptions).

## Conventions de test unitaire

### Nommage et annotations

- Suffixer les classes de test avec `Test` : `UserService` → `UserServiceTest`.
- **Toujours** utiliser `@DisplayName` sur les classes et méthodes de test pour décrire le comportement **en français**.
- Utiliser `@Nested` pour regrouper les tests par méthode ou par contexte fonctionnel.
- Convention de nommage des méthodes : `should_ExpectedBehavior_when_Condition`.

### Structure de test

- Suivre le pattern **Arrange-Act-Assert (AAA)** dans chaque test, sans commentaires de phase.
- Un seul comportement testé par méthode `@Test`.
- Tests indépendants et idempotents (aucun ordre d'exécution requis).
- Utiliser `@BeforeEach` pour le setup, jamais de données partagées mutables entre tests.

### Couverture de branche

- Tester explicitement **chaque branche** de chaque `if/else`, `switch`, opérateur ternaire, et `try/catch`.
- Tester les cas limites : `null`, chaînes vides, listes vides, valeurs aux bornes (0, -1, Integer.MAX_VALUE).
- Tester les chemins d'exception : `assertThrows` avec vérification du message.
- Utiliser `@ParameterizedTest` avec `@CsvSource`, `@ValueSource`, `@MethodSource`, `@EnumSource` pour couvrir les combinaisons d'entrées.
- Grouper les assertions liées avec `assertAll()` pour voir toutes les failures d'un coup.

### Assertions

- Préférer **AssertJ** (`assertThat(...)`) pour la lisibilité et la richesse des matchers.
- À défaut, utiliser `org.junit.jupiter.api.Assertions`.
- Toujours fournir un **message descriptif** aux assertions qui pourraient être ambiguës.
- Utiliser `assertThatThrownBy(() -> ...).isInstanceOf(...).hasMessageContaining(...)`.

### Mocking

- Utiliser Mockito avec `@ExtendWith(MockitoExtension.class)`.
- Annoter avec `@Mock` pour les dépendances, `@InjectMocks` pour la classe testée.
- Vérifier les interactions avec `verify()` uniquement quand l'interaction est le contrat (effets de bord).
- Ne jamais mocker la classe sous test elle-même.

### Organisation

- Un fichier de test par classe de production.
- Si un fichier de test dépasse 300 lignes, le découper en fichiers séparés par contexte fonctionnel.
- Utiliser `@Tag("unit")` sur les tests unitaires, `@Tag("integration")` sur les tests d'intégration.
- Utiliser `@Disabled("raison")` si un test doit être temporairement désactivé.

## Commandes de build et test

```bash
# Lancer les tests unitaires (module-scoped)
mvn -f <module>/pom.xml clean test -DskipITs

# Lancer les tests avec couverture JaCoCo (profil dédié)
mvn -f <module>/pom.xml clean test -Pjacoco -DskipITs

# Vérifier les seuils de couverture
mvn -f <module>/pom.xml clean verify -Pjacoco -DskipITs
```

**Important** : JaCoCo est dans un profil Maven. Sans `-Pjacoco`, aucun rapport de couverture ne sera généré.

## Critères qualité

- Couverture JaCoCo ≥ seuil configuré dans le `pom.xml` du module
- Zéro test ignoré sans justification dans `@Disabled`
- Tous les tests passent (`mvn clean test` retourne 0)
- `mvn clean verify -Pjacoco -DskipITs` passe sans erreur

## Attention particulières (projets Java Spring)

- **Lombok** : les getter/setter générés ne nécessitent pas de test unitaire manuel
- **MapStruct** : tester les mappers via leur interface, pas l'implémentation générée
- **JUnit 4 coexiste** avec JUnit 5 (Cucumber). Ne jamais utiliser `org.junit.Test` pour les nouveaux tests, uniquement `org.junit.jupiter.api.Test`
- **Tagging obligatoire** : `@Tag("unit")` pour TU, `@Tag("integration")` pour tests de contexte Spring
- **AssertJ first** : éviter `org.junit.jupiter.api.Assertions` quand une assertion AssertJ équivalente existe
- **Classes de tests volumineuses** : au-delà de ~300 lignes, scinder par contexte métier
- **Branches répétitives** : préférer `@ParameterizedTest` pour les variations null/vide/bornes

## Documentation et README

- Le README reste écrit en **français** pour la partie fonctionnelle et en anglais pour la partie technique.

