# Angular — Référence avancée

## Angular 15-17 : évolutions clés

### Standalone Components (Angular 15+)

```typescript
@Component({
  selector: 'app-user',
  standalone: true,
  imports: [CommonModule, RouterModule],
  template: `<h1>{{ user.name }}</h1>`
})
export class UserComponent {
  @Input() user!: User;
}
```

Plus besoin de `NgModule` pour les nouveaux composants. `bootstrapApplication()` remplace `platformBrowserDynamic().bootstrapModule()`.

### Signals (Angular 16+)

```typescript
@Component({
  template: `
    <p>Count: {{ count() }}</p>
    <p>Double: {{ double() }}</p>
    <button (click)="increment()">+1</button>
  `
})
export class CounterComponent {
  count = signal(0);
  double = computed(() => this.count() * 2);

  increment() {
    this.count.update(v => v + 1);
  }
}
```

Signals remplacent progressivement les Observables pour l'état local. Plus performant (détection de changements granulaire).

### Control Flow (Angular 17+)

```html
<!-- Nouveau (remplace *ngIf, *ngFor, *ngSwitch) -->
@if (user) {
  <h1>{{ user.name }}</h1>
} @else {
  <p>No user</p>
}

@for (item of items; track item.id) {
  <li>{{ item.name }}</li>
} @empty {
  <p>No items</p>
}

@switch (status) {
  @case ('active') { <span class="green">Active</span> }
  @case ('inactive') { <span class="red">Inactive</span> }
  @default { <span>Unknown</span> }
}
```

### Defer Blocks (Angular 17+)

```html
@defer (on viewport) {
  <app-heavy-component />
} @placeholder {
  <p>Scroll to load...</p>
} @loading (minimum 500ms) {
  <app-spinner />
} @error {
  <p>Failed to load</p>
}
```

Triggers : `on viewport`, `on idle`, `on interaction`, `on hover`, `on timer(5s)`, `when condition`.

## Architecture

### Modules vs Standalone

| Approche | Quand l'utiliser |
|----------|-----------------|
| `NgModule` | Projets existants Angular < 15 |
| `standalone` | Nouveaux composants, nouveaux projets |
| Mixte | Migration progressive (les deux coexistent) |

### Lazy Loading

```typescript
// app.routes.ts
export const routes: Routes = [
  {
    path: 'admin',
    loadComponent: () => import('./admin/admin.component').then(m => m.AdminComponent),
    canActivate: [authGuard]
  },
  {
    path: 'dashboard',
    loadChildren: () => import('./dashboard/routes').then(m => m.DASHBOARD_ROUTES)
  }
];
```

### Route Guards (fonctionnels, Angular 15+)

```typescript
export const authGuard: CanActivateFn = (route, state) => {
  const auth = inject(AuthService);
  return auth.isAuthenticated() ? true : inject(Router).createUrlTree(['/login']);
};
```

## State Management

### Signals (état local)

```typescript
@Injectable({ providedIn: 'root' })
export class CartService {
  private items = signal<CartItem[]>([]);
  
  readonly count = computed(() => this.items().length);
  readonly total = computed(() => this.items().reduce((sum, i) => sum + i.price, 0));
  
  add(item: CartItem) {
    this.items.update(items => [...items, item]);
  }
}
```

### RxJS (flux asynchrones)

```typescript
// Debounce search
this.searchControl.valueChanges.pipe(
  debounceTime(300),
  distinctUntilChanged(),
  switchMap(term => this.searchService.search(term)),
  takeUntilDestroyed()  // Angular 16+ : auto-unsubscribe
).subscribe(results => this.results.set(results));
```

## Forms

### Reactive Forms

```typescript
@Component({
  template: `
    <form [formGroup]="form" (ngSubmit)="submit()">
      <input formControlName="name" />
      @if (form.controls.name.errors?.['required']) {
        <span class="error">Nom requis</span>
      }
    </form>
  `
})
export class UserFormComponent {
  form = inject(FormBuilder).group({
    name: ['', [Validators.required, Validators.minLength(2)]],
    email: ['', [Validators.required, Validators.email]],
  });
}
```

## HTTP

### Interceptors (fonctionnels, Angular 15+)

```typescript
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const token = inject(AuthService).getToken();
  const authReq = token
    ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : req;
  return next(authReq);
};

// Dans la config
provideHttpClient(withInterceptors([authInterceptor]))
```

### Error handling

```typescript
this.http.get<User[]>('/api/users').pipe(
  retry({ count: 3, delay: 1000 }),
  catchError(err => {
    this.errorService.handle(err);
    return of([]);
  })
);
```

## Testing

### Jest setup

```json
// jest.config.ts
export default {
  preset: 'jest-preset-angular',
  setupFilesAfterSetup: ['<rootDir>/setup-jest.ts'],
  transformIgnorePatterns: ['node_modules/(?!@angular|rxjs)']
};
```

### Component test

```typescript
describe('UserComponent', () => {
  let fixture: ComponentFixture<UserComponent>;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [UserComponent],
      providers: [
        { provide: UserService, useValue: { getUser: () => of(mockUser) } }
      ]
    });
    fixture = TestBed.createComponent(UserComponent);
    fixture.detectChanges();
  });

  it('should display user name', () => {
    expect(fixture.nativeElement.textContent).toContain('John');
  });
});
```

### HttpClient test

```typescript
it('should fetch users', () => {
  const httpMock = TestBed.inject(HttpTestingController);
  service.getUsers().subscribe(users => expect(users.length).toBe(2));
  httpMock.expectOne('/api/users').flush([{ id: 1 }, { id: 2 }]);
});
```

## Performance

### OnPush Change Detection

```typescript
@Component({
  changeDetection: ChangeDetectionStrategy.OnPush,
  // ...
})
```

Le composant n'est re-rendu que si :
- Un `@Input` change (référence)
- Un événement du template est déclenché
- Un signal change
- `markForCheck()` est appelé

### trackBy pour @for / *ngFor

```html
@for (item of items; track item.id) { ... }
```

Sans `track`, Angular recrée tous les éléments DOM à chaque changement.

## Pitfalls

| Piège | Symptôme | Solution |
|-------|----------|---------|
| Memory leaks (subscriptions) | RAM qui monte | `takeUntilDestroyed()` ou `async` pipe |
| zone.js overhead | UI lente | `OnPush` + signals |
| Bundle trop gros | Load time long | Lazy loading, tree shaking |
| Circular dependencies | Build error | Restructurer les imports |
| ExpressionChangedAfterItHasBeenChecked | Error en dev | Déplacer la logique dans ngAfterViewInit |
| **AOT supprime les attributs de directive** | Sélecteur CSS `a[routerLink='...']` ne fonctionne pas en prod | En production (AOT), Angular supprime les attributs de directive custom (`routerLink`, `appMyDirective`) du DOM. Dans les tests E2E (Playwright, Selenium), utiliser `a[href$='/route']` plutôt que `a[routerLink='/route']`. Les attributs natifs HTML (`href`, `data-*`, `id`, `class`) sont conservés. |
