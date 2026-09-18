# This tree has moved

The GitOps automation now lives in **[rhpds/rhai-features-workshop](https://github.com/rhpds/rhai-features-workshop)**
under [`automation/gitops/`](https://github.com/rhpds/rhai-features-workshop/tree/main/automation/gitops).

**Do not re-add charts here.** Nothing reads this directory. RHDP provisions the
workshop from the other repo:

```yaml
# agnosticv agd_v2/rhai-features-workshop/common.yaml
ocp4_workload_gitops_bootstrap_repo_url:  https://github.com/rhpds/rhai-features-workshop.git
ocp4_workload_gitops_bootstrap_repo_path: automation/gitops/bootstrap-infra
```

## Why it was removed

Two copies existed and drifted in both directions. By the time this file was
written the copy here was 126 files against 154 there, and neither was a superset:

- only here: the OpenShell gateway, policies and sandbox provisioning for module
  5.3 -- so ArgoCD never deployed any of it and the exercise had no sandbox on a
  real order,
- only there: the RHOAI operator and `DataScienceCluster`, the MaaS platform
  installer, the Agent Sandbox operator, retry policies on every Application,
  per-user namespace RBAC, the ArgoCD controller memory fix and the guardrails
  wiring.

Everything that was here has been ported (rhpds/rhai-features-workshop#17). The
only file without an equivalent was `bootstrap-infra/values-rhai-features-workshop.yaml`,
an overlay that pointed this tree at the other repo -- its values are the chart
defaults there now, so it served no purpose.

## What still lives in this repo

The workshop **content** (`content/`) is authored here and mirrored into the other
repo, along with `deployments/mortgage-ai`, which is vendored there and kept
byte-identical. `templates/` remains the imperative bootstrap path for the pieces
that are not declarative cluster state; note that the OpenShell policies are now
owned by the chart, so `templates/user/openshell/setup-sandbox.sh` must not be
treated as their source of truth.
