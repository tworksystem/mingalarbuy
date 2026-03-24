# Repository Structure Guide

## Current Architecture

```
twork-commerce/
├── lib/                    # Flutter app (main product)
├── wp-content/plugins/     # WordPress plugin (tightly coupled)
└── backend/                # Webhook server (optional)
```

## Recommendation: Hybrid Approach

### Option 1: Monorepo (Recommended for Current State) ✅

**Keep everything together if:**
- Plugin is tightly coupled with Flutter app
- Same team maintains both
- Shared business logic and API contracts
- Easier development and testing workflow

**Structure:**
```
twork-commerce/              # Main repository
├── packages/
│   ├── flutter-app/        # Flutter application
│   ├── wordpress-plugin/   # WordPress plugin
│   └── shared/             # Shared types/contracts (if needed)
└── backend/                 # Optional webhook server
```

### Option 2: Separate Repositories (Future Consideration)

**Split when:**
- Plugin becomes a standalone product
- Multiple projects need the plugin
- Different teams maintain different parts
- Plugin needs independent versioning/releases

**Structure:**
```
twork-commerce/              # Flutter app repository
└── (references plugin via git submodule or package)

twork-points-system-plugin/  # WordPress plugin repository
└── (standalone, versioned independently)
```

## Decision Matrix

| Factor | Monorepo | Separate Repos |
|--------|----------|----------------|
| **Coupling** | Tightly coupled ✅ | Loosely coupled |
| **Team Size** | Small team ✅ | Large/multiple teams |
| **Reusability** | Single use ✅ | Multiple projects |
| **Versioning** | Synchronized ✅ | Independent |
| **CI/CD** | Single pipeline ✅ | Separate pipelines |
| **Development** | Easier ✅ | More complex |

## Current Recommendation: **Monorepo**

### Why?
1. ✅ Plugin is specifically built for this Flutter app
2. ✅ Shared API contracts and business logic
3. ✅ Easier to maintain consistency
4. ✅ Simpler development workflow
5. ✅ Single source of truth

### When to Split?
Consider separating when:
- Plugin is used by 3+ different projects
- Plugin has its own release cycle
- Different team maintains the plugin
- Plugin becomes a commercial product

## Implementation: Monorepo Best Practices

### 1. Clear Directory Structure
```
twork-commerce/
├── lib/                          # Flutter app
├── wp-content/plugins/           # WordPress plugin
│   └── twork-points-system/
├── backend/                      # Backend services
├── docs/                         # Shared documentation
└── scripts/                      # Shared build/deploy scripts
```

### 2. Version Management
- Use tags for releases: `v1.0.0`, `v1.1.0`
- Document which plugin version works with which app version
- Use CHANGELOG.md for both components

### 3. CI/CD Strategy
```yaml
# .github/workflows/ci.yml
jobs:
  flutter:
    # Test Flutter app
  wordpress-plugin:
    # Test WordPress plugin
  integration:
    # Test integration between app and plugin
```

### 4. Documentation
- Main README.md for overall project
- `docs/PLUGIN.md` for plugin-specific docs
- `docs/API.md` for shared API contracts

## Migration Path (If Needed Later)

If you decide to split later:

1. **Create new repository** for plugin
2. **Use git subtree or submodule** for gradual migration
3. **Maintain compatibility** during transition
4. **Update documentation** and CI/CD

### Using Git Subtree (Recommended)
```bash
# Extract plugin to separate repo
git subtree push --prefix=wp-content/plugins/twork-points-system \
  origin plugin-only

# Or use as submodule
git submodule add <plugin-repo-url> wp-content/plugins/twork-points-system
```

## Conclusion

**For now: Keep as Monorepo** ✅

- Simpler development
- Better for small teams
- Easier to maintain consistency
- Can split later if needed

**Future: Consider splitting if:**
- Plugin becomes standalone product
- Multiple projects need it
- Different teams maintain it

---

## References

- [Monorepo vs Multi-repo](https://www.atlassian.com/git/tutorials/monorepos)
- [Git Subtree](https://www.atlassian.com/git/tutorials/git-subtree)
- [Git Submodules](https://www.atlassian.com/git/tutorials/git-submodule)

