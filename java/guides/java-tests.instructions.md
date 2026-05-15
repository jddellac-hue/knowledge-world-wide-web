---
applyTo: "src/test/java/**/*.java"
---

# Instructions spécifiques aux fichiers de test Java (partagées)

## Structure obligatoire

- `@ExtendWith(MockitoExtension.class)` en en-tête de classe
- `@DisplayName("NomClasse — Description")` sur la classe de test
- Un `@Nested` par méthode publique testée, avec `@DisplayName`
- Pattern AAA (Arrange-Act-Assert) dans chaque méthode de test
- `@Tag("unit")` obligatoire pour les tests unitaires
- `@Tag("integration")` obligatoire pour les tests d'intégration
- En complétion, ne jamais supprimer un test existant qui compile et passe
- Variable locale pour le System Under Test : `sut` (pas `service`, `instance`, etc.)

## Assertions

- Préférer AssertJ : `assertThat(result).isEqualTo(expected)`
- Exceptions : `assertThatThrownBy(() -> ...).isInstanceOf(X.class).hasMessageContaining("...")`
- Assertions groupées : `assertAll("contexte", () -> ..., () -> ...)`
- **Minimum 2 assertions par test** : une sur le résultat, une sur le contrat
- Jamais `assertNotNull` comme seule assertion
- Utiliser `.as("description")` sur les assertions ambiguës
- Collections : `containsExactly()` pour l'ordre garanti, `containsExactlyInAnyOrder()` sinon
- Objects complexes : `extracting("field1", "field2").containsExactly(v1, v2)`
- Soft assertions pour valider plusieurs champs sans arrêt au premier échec :
  ```java
  SoftAssertions.assertSoftly(soft -> {
      soft.assertThat(result.getName()).isEqualTo("expected");
      soft.assertThat(result.getAge()).isEqualTo(42);
  });
  ```

## Couverture de branche

Pour chaque méthode testée :
- Le chemin nominal
- Chaque branche conditionnelle (`if true` ET `if false`)
- Les cas d'erreur (exceptions, validations)
- Les valeurs limites (null, vide, bornes numériques)
- Préférer `@ParameterizedTest` pour les entrées répétitives
- Pour `if (x instanceof Type t)` : tester les deux branches (match et non-match)
- Pour `switch` expression/statement : tester chaque case + default
- Pour `Optional` : tester `isPresent()` et `isEmpty()`
- Pour les ternaires : tester les deux résultats

## @ParameterizedTest — Guide de sélection

| Source | Quand l'utiliser | Exemple |
|--------|-----------------|---------|
| `@NullAndEmptySource` | Entrées null + vide (String, Collection) | Validation d'entrée |
| `@ValueSource` | Valeurs primitives ou String | Bornes numériques, formats |
| `@CsvSource` | Paires entrée → résultat attendu | Mapping, calcul |
| `@EnumSource` | Toutes les valeurs d'un enum | Traitement par statut |
| `@MethodSource` | Objets complexes ou cas nombreux | Builders, DTOs |

```java
@ParameterizedTest(name = "devrait retourner {1} quand l''entrée est {0}")
@CsvSource({
    "VALID_INPUT, EXPECTED_OUTPUT",
    "'', EMPTY_RESULT",
    "EDGE_CASE, EDGE_RESULT"
})
@DisplayName("devrait traiter correctement les entrées")
void should_ProcessInput_when_VariousInputs(String input, String expected) { ... }
```

## Nommage

- Méthode : `should_ExpectedBehavior_when_Condition`
- `@DisplayName` : phrase **en français** commençant par "devrait" ou "Doit"
- `@ParameterizedTest(name = ...)` : inclure `{0}` pour afficher la valeur

## Patterns avancés — Test Data

### Test Data Builder (préféré aux constructeurs longs)

```java
// Dans src/test/java
class MonEntiteTestBuilder {
    private String nom = "default-nom";
    private int age = 30;

    static MonEntiteTestBuilder aMonEntite() { return new MonEntiteTestBuilder(); }
    MonEntiteTestBuilder withNom(String nom) { this.nom = nom; return this; }
    MonEntiteTestBuilder withAge(int age) { this.age = age; return this; }
    MonEntite build() { return new MonEntite(nom, age); }
}

// Usage
var entite = aMonEntite().withNom("test").withAge(0).build();
```

### Factory Methods pour profils de données

```java
static MonEntite buildComplet() { return aMonEntite().build(); }
static MonEntite buildMinimal() { return aMonEntite().withNom(null).withAge(0).build(); }
static MonEntite buildAvecTousLesNulls() { return aMonEntite().withNom(null).build(); }
```

### ArgumentCaptor pour vérifier les objets construits dans le code

```java
@Captor
private ArgumentCaptor<MonObjet> captor;

// ...
verify(dependency).save(captor.capture());
assertThat(captor.getValue().getName()).isEqualTo("expected");
```

## Pièges connus — Spring Boot 3+ / 4.x (Jakarta)

- Utiliser `jakarta.servlet.error.status_code` (pas `javax.*`)
- Tout `javax.*` est `jakarta.*` en Spring Boot 3+
- `RestClientCustomizer` a migré vers `org.springframework.boot.restclient` en SB 4.x
- `RestClient` remplace `RestTemplate` — tester avec `MockRestServiceServer` ou mock du builder

## Pièges connus — Bibliothèques tierces

- Ne jamais supposer l'API d'une bibliothèque : vérifier les méthodes publiques réelles
- Exceptions wrappées : déterminer l'exception réelle par un premier run
- Mockito 5+ : supporte `final` classes/methods par défaut (pas besoin de `mockito-inline`)

## Pièges connus — Micrometer

- `registry.config().commonTags()` ne supporte pas d'assertions directes
- Créer un meter puis vérifier `meter.getId().getTags()`

## Pièges connus — MapStruct

- Toujours tester via l'interface : `Mappers.getMapper(MonMapper.class)`
- Ne jamais instancier l'implémentation `MonMapperImpl` directement
- Tester : null input, empty collections, nested mappings, mappings custom `@AfterMapping`
- Les méthodes `default` dans l'interface mapper **doivent** être testées

## Pièges connus — JPA / H2

- `@DataJpaTest` utilise H2 par défaut — les divergences Oracle/H2 sont possibles
- Fonctions Oracle (`NVL`, `DECODE`, etc.) non supportées en H2
- Utiliser `@Sql` pour charger des données de test plutôt que `@BeforeEach` avec `save()`

## Beans `@Value` sans contexte Spring

Utiliser `ReflectionTestUtils.setField(bean, "fieldName", value)` pour injecter des valeurs
`@Value` dans des tests unitaires sans démarrer le contexte Spring.

## Test slices Spring Boot — Guide rapide

| Slice | Annotation | Ce qui est chargé | Usage |
|-------|-----------|-------------------|-------|
| Web MVC | `@WebMvcTest(Controller.class)` | Controller + MVC infra | Tests REST (MockMvc) |
| JPA | `@DataJpaTest` | Repositories + H2 | Tests de requêtes |
| JSON | `@JsonTest` | ObjectMapper | Tests de sérialisation |
| Full context | `@SpringBootTest` | Tout | Tests d'intégration (Cucumber) |

> ⚠️ Les test slices sont des tests **d'intégration** → `@Tag("integration")`, pas `@Tag("unit")`.

## Ce qu'il ne faut PAS faire

- Pas de `Thread.sleep()` dans les tests unitaires
- Pas de dépendances inter-tests (état partagé mutable)
- Pas de logique complexe dans les tests (`if`, `for`, `while`)
- Pas de mock de la classe sous test
- Pas de `@Autowired` dans les tests unitaires (réservé aux tests d'intégration)
- Pas de classes de tests monolithiques : découper au-delà de 300 lignes
- Pas d'assertions JUnit si équivalent AssertJ disponible
- Pas de tests POJO Lombok : exclure de JaCoCo plutôt que tester
- Pas d'un seul test couvrant plusieurs comportements distincts
- Pas de `@Disabled` sans message de justification
- Pas de `verify()` sans `ArgumentCaptor` quand l'argument est construit dans le code sous test
- Pas de `any()` dans `verify()` quand on peut matcher exactement
