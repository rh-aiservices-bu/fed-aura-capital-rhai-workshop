# Fed Aura Capital -- GitOps automation

ArgoCD **app-of-apps** automation for the Fed Aura Capital / RHOAI features
workshop. Everything here is generated from the manifests in
[`../templates/`](../templates), keeping the same split, and follows the RHDP
`shared-cluster` convention of one chart for cluster-wide infrastructure and one
for per-user tenants:

| chart | scope | source | applied |
|---|---|---|---|
| `bootstrap-infra` | cluster-wide "global" infrastructure | `templates/admin/` | **once**, before any user exists |
| `bootstrap-tenant` | one copy per workshop user in `wksp-<user>` | `templates/user/` | **after**, fanned out over `user1..userN` |

```
gitops/
├── bootstrap-infra/                 # 8 Applications      (sync-waves -1 .. 3)
│   ├── values.yaml
│   ├── values-rhai-features-workshop.yaml
│   └── templates/
│       ├── extra-resources/gitops.yaml   # openshift-gitops namespace + ArgoCD tuning
│       └── *.yaml
├── bootstrap-tenant/                # 7 ApplicationSets   (sync-waves  5 .. 9)
│   ├── values.yaml
│   ├── values-rhai-features-workshop.yaml
│   └── templates/*.yaml
└── deployments/
    ├── admin/{dashboard-config,mlflow,mcp,workbench-image,model-catalog,maas,llmd,evalhub}
    └── user/{workspace,minio,dspa,automl,model-catalog,ogx}
```

`mortgage-ai` has no chart of its own under `deployments/user/`: the
ApplicationSet points at the existing chart in
[`../deployments/mortgage-ai`](../deployments/mortgage-ai) and injects per-user
values, so the GitOps and standalone installs never drift.

## Two-phase rollout

**Phase 1 -- global infrastructure (admin CI job):**

```bash
helm upgrade --install bootstrap-infra gitops/bootstrap-infra \
  -n openshift-gitops --create-namespace \
  -f /path/to/injected-values.yaml
```

**Phase 2 -- per-user workspaces, once the user count is known:**

```bash
helm upgrade --install bootstrap-tenant gitops/bootstrap-tenant \
  -n openshift-gitops \
  --set user.count=15 \
  -f /path/to/injected-values.yaml
```

Adding users later is the same command with a higher `user.count` -- the
ApplicationSets grow, existing users are untouched.

Within each phase, ordering is handled by ArgoCD sync waves:

| wave | chart | component |
|------|-------|-----------|
| `-1` | infra | `admin/dashboard-config` -- RHOAI dashboard feature flags |
| `0`  | infra | `admin/mlflow`, `admin/mcp`, `admin/workbench-image` |
| `1`  | infra | `admin/model-catalog`, `admin/maas` |
| `2`  | infra | `admin/llmd` (opt-in) |
| `3`  | infra | `admin/evalhub` |
| `5`  | tenant | `user/workspace` -- namespace + injected LLM credentials |
| `6`  | tenant | `user/minio` -- object store + RHOAI data connections |
| `7`  | tenant | `user/dspa`, `user/automl`, `user/model-catalog` (opt-in) |
| `8`  | tenant | `user/ogx` |
| `9`  | tenant | `user/mortgage-ai` |

## Injected values (agnosticv)

Everything environment-specific is a value, so
`agd_v2/rhai-features-workshop/common.yaml` can inject it without touching git.
Nothing secret is committed -- the defaults are obvious placeholders.

| value | chart | used by |
|---|---|---|
| `bootstrap.repoURL` / `.targetRevision` | both | git source of truth |
| `bootstrap.pathPrefix` | both | `gitops` here, `automation/gitops` in rhai-features-workshop |
| `deployer.domain` | tenant | builds `mortgage-ai-wksp-userN.<domain>` routes |
| `user.count` / `.prefix` / `.namespacePrefix` | tenant | `wksp-user1..N` |
| `remotellm.url` / `.id` / `.apiToken` | both | `admin/maas`; `user/workspace`, `user/ogx`, mortgage-ai |
| `remotellm.endpoint` | infra | `admin/maas` -- hostname only, `ExternalProvider` rejects a scheme/path |
| `minio.rootUser` / `.rootPassword` | tenant | `user/minio` + mortgage-ai S3 config |
| `tinyllama.enabled` | tenant | registers the in-cluster TinyLlama as an OGX provider |

Example `common.yaml` fragment:

```yaml
# agd_v2/rhai-features-workshop/common.yaml
fac_gitops_common: &fac_gitops_common
  bootstrap:
    repoURL: https://github.com/rhpds/rhai-features-workshop
    targetRevision: main
    pathPrefix: automation/gitops
  deployer:
    domain: "apps.cluster-{{ guid }}.{{ sandbox_openshift_domain }}"
    apiUrl: "https://api.cluster-{{ guid }}.{{ sandbox_openshift_domain }}:6443"
  remotellm:
    enabled: true
    url: "{{ maas_base_url }}"
    endpoint: "{{ maas_hostname }}"
    id: "{{ maas_model_id }}"
    apiToken: "{{ maas_api_token }}"

fac_bootstrap_infra_values:
  <<: *fac_gitops_common

fac_bootstrap_tenant_values:
  <<: *fac_gitops_common
  user:
    count: 15
    prefix: user
    namespacePrefix: wksp
  minio:
    rootUser: minio
    rootPassword: "{{ common_password }}"
  components:
    mortgageAi:
      chartPath: automation/gitops/deployments/mortgage-ai
```

## Component toggles

Every component has `components.<name>.enabled`. Off by default because they
need extra cluster capacity or prerequisites:

- `bootstrap-infra` `components.llmd.enabled` -- needs cert-manager plus the
  `cert-manager-ingress-cert` secret in `openshift-ingress`. When you enable it,
  also set `tinyllama.enabled=true` on `bootstrap-tenant` so OGX picks up the
  in-cluster endpoint as a second inference provider.
- `bootstrap-tenant` `components.modelCatalog.enabled` -- one vLLM CPU pod per
  model **per user** (4-8 cores, 8-16Gi each). Within that chart only
  `tinyllama` is enabled; `qwen3-06b` is off.

## Notes on the conversion from `templates/`

- **Namespace ownership.** `templates/user/minio/00-namespace.yaml` created
  `wksp-user1`; the namespace now belongs to `user/workspace` so every other
  per-user chart can depend on it -- and on its `opendatahub.io/dashboard=true`
  label, which is how MLflow discovers workspaces.
- **Data connections consolidated.** The `pipeline` and `automl` S3 connection
  secrets describe the same MinIO, so they are generated from one `connections`
  list in `user/minio` instead of living in two charts.
- **`OdhDashboardConfig` has a single owner.**
  `templates/admin/llmd/01-enable-gateway-discovery.yaml` patched the same
  singleton that `admin/dashboard-config` manages (which already sets
  `llmGatewayField: true`), so it is not part of the `llmd` chart -- two
  Applications would fight over it forever.
- **`{{.Name}}` is KServe's, not Helm's.** In the ServingRuntime args it is
  escaped as `{{ "{{.Name}}" }}` so it reaches the cluster verbatim.
- **MLflow auth.** `values-fedaura.yaml` needed a hand-minted
  `MLFLOW_TRACKING_TOKEN`; the ApplicationSet uses
  `MLFLOW_TRACKING_AUTH: kubernetes` with `mlflow.rbac.enabled=true` instead, so
  the pod's own ServiceAccount token is used and no manual step is required.
- **AutoML dataset** ships in `user/automl/files/` and is mounted through a
  ConfigMap (~310KB per user), matching what the old `configMapGenerator` did.

### Deliberately not in GitOps

Still driven from `templates/`, because they are not declarative cluster state:

| path | why |
|---|---|
| `templates/user/openshell/` | shell installer + local sandbox image build |
| `templates/admin/global-prompts/` | registers a prompt over the MLflow REST API via `oc port-forward` |
| `templates/admin/evalhub/eval-*.yaml`, `data/`, `*.ipynb` | EvalHub job definitions and lab content, submitted by the user during the workshop |
| `templates/admin/custom-workbench/Containerfile` | image build input; the resulting ImageStream *is* in `admin/workbench-image` |

Per-user RBAC is also out of scope here -- workshop user accounts and their
namespace bindings come from the agnosticd authentication workloads.

## Validate locally

```bash
helm lint gitops/bootstrap-infra gitops/bootstrap-tenant gitops/deployments/admin/* gitops/deployments/user/*
helm template infra  gitops/bootstrap-infra
helm template tenant gitops/bootstrap-tenant --set user.count=3
helm template t gitops/deployments/user/minio --set username=user1
```
