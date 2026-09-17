# Fed Aura Capital -- GitOps automation

ArgoCD **app-of-apps** automation for the Fed Aura Capital / RHOAI features
workshop. Everything here is generated from the manifests in
[`../templates/`](../templates), keeping the same admin/user split:

| group | scope | source | applied |
|---|---|---|---|
| `admin.*` | cluster-wide "global" infrastructure, one Application each | `templates/admin/` | **once**, before any user exists |
| `users.*` | one copy per workshop user in `wksp-<user>`, one ApplicationSet each | `templates/user/` | **after**, fanned out over `user1..userN` |

A single `bootstrap-infra` chart owns both groups. There is no separate tenant
chart: this workshop is per-user, so the fan-out is expressed as ApplicationSets
inside the same parent rather than as a second Helm release.

```
gitops/
├── bootstrap-infra/                 # the only thing you install by hand
│   ├── values.yaml                  # user count, repo, cluster domain, injected credentials
│   ├── values-rhai-features-workshop.yaml
│   └── templates/
│       ├── extra-resources/gitops.yaml   # openshift-gitops namespace + ArgoCD tuning
│       ├── admin/*.yaml             # 8 Applications      (sync-waves -1 .. 3)
│       └── user/*.yaml              # 7 ApplicationSets   (sync-waves  5 .. 9)
└── deployments/
    ├── admin/{dashboard-config,mlflow,mcp,workbench-image,model-catalog,maas,llmd,evalhub}
    └── user/{workspace,minio,dspa,automl,model-catalog,ogx}
```

`mortgage-ai` has no chart of its own under `deployments/user/`: the
ApplicationSet points at the existing chart in
[`../deployments/mortgage-ai`](../deployments/mortgage-ai) and injects per-user
values, so the GitOps and standalone installs never drift.

## Two-phase rollout

Sync waves make a single apply converge in the right order, so if the user count
is known up front one command is enough:

```bash
helm upgrade --install bootstrap-infra gitops/bootstrap-infra \
  -n openshift-gitops --create-namespace \
  --set user.count=15 \
  -f /path/to/injected-values.yaml
```

To provision the global infrastructure first and add users in a later CI step,
use the group switches:

```bash
# Phase 1 -- global infrastructure only
helm upgrade --install bootstrap-infra gitops/bootstrap-infra \
  -n openshift-gitops --create-namespace \
  --set users.enabled=false \
  -f /path/to/injected-values.yaml

# Phase 2 -- add the per-user workspaces
helm upgrade --install bootstrap-infra gitops/bootstrap-infra \
  -n openshift-gitops \
  --set user.count=15 \
  -f /path/to/injected-values.yaml
```

Adding users later is the same command with a higher `user.count` -- the
ApplicationSets grow, existing users are untouched.

| wave | component |
|------|-----------|
| `-1` | `admin/dashboard-config` -- RHOAI dashboard feature flags |
| `0`  | `admin/mlflow`, `admin/mcp`, `admin/workbench-image` |
| `1`  | `admin/model-catalog`, `admin/maas` |
| `2`  | `admin/llmd` (opt-in) |
| `3`  | `admin/evalhub` |
| `5`  | `user/workspace` -- namespace + injected LLM credentials |
| `6`  | `user/minio` -- object store + RHOAI data connections |
| `7`  | `user/dspa`, `user/automl`, `user/model-catalog` (opt-in) |
| `8`  | `user/ogx` |
| `9`  | `user/mortgage-ai` |

## Injected values (agnosticv)

Everything environment-specific is a value, so
`agd_v2/rhai-features-workshop/common.yaml` can inject it without touching git.
Nothing secret is committed -- the defaults are obvious placeholders.

| value | used by |
|---|---|
| `bootstrap.repoURL` / `.targetRevision` | every Application |
| `bootstrap.pathPrefix` | every Application -- `gitops` here, `automation/gitops` in rhai-features-workshop |
| `deployer.domain` | `user/mortgage-ai` -- builds `mortgage-ai-wksp-userN.<domain>` routes |
| `user.count` / `.prefix` / `.namespacePrefix` | every user ApplicationSet -- `wksp-user1..N` |
| `remotellm.url` / `.id` / `.apiToken` | `admin/maas`, `user/workspace`, `user/ogx`, `user/mortgage-ai` |
| `remotellm.endpoint` | `admin/maas` -- hostname only, `ExternalProvider` rejects a scheme/path |
| `minio.rootUser` / `.rootPassword` | `user/minio` + mortgage-ai S3 config |

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

fac_bootstrap_values:
  <<: *fac_gitops_common
  user:
    count: 15
    prefix: user
    namespacePrefix: wksp
  minio:
    rootUser: minio
    rootPassword: "{{ common_password }}"
  users:
    mortgageAi:
      chartPath: automation/gitops/deployments/mortgage-ai
```

## Component toggles

Every component has `admin.<name>.enabled` or `users.<name>.enabled`, and the
whole group can be switched with `admin.enabled` / `users.enabled`. Off by
default because they need extra cluster capacity or prerequisites:

- `admin.llmd.enabled` -- needs cert-manager plus the
  `cert-manager-ingress-cert` secret in `openshift-ingress`. When enabled,
  `user/ogx` automatically registers the in-cluster TinyLlama endpoint as a
  second inference provider.
- `users.modelCatalog.enabled` -- one vLLM CPU pod per model **per user**
  (4-8 cores, 8-16Gi each). Within that chart only `tinyllama` is enabled;
  `qwen3-06b` is off.

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
helm lint gitops/bootstrap-infra gitops/deployments/admin/* gitops/deployments/user/*
helm template fac gitops/bootstrap-infra --set user.count=3
helm template fac gitops/bootstrap-infra --set users.enabled=false   # admin phase only
helm template t   gitops/deployments/user/minio --set username=user1
```
