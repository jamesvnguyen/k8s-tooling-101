# k8s-tooling-101
Beginner friendly Kubernetes lessons with practical exercises

## About

I planned and wrote these lessons, built the labs myself, then used Claude to touch them up. Mostly to tighten the wording, check that the docs match the lab files, and make sure each lab builds

## Lessons

### Kustomize

[Kustomize Basics](Kustomize/2026-10-04-kustomize-basics.md): why Kustomize exists, how it compares to Helm, the `kustomization.yaml` file, organising directories, and transformers.

| Lab | What it shows |
|---|---|
| [`1_basics`](Kustomize/1_basics/) | One `kustomization.yaml` listing every manifest by path |
| [`2_subdirectories`](Kustomize/2_subdirectories/) | The same app, split into nested kustomizations, one per component |
| [`3_transformers`](Kustomize/3_transformers/) | Plain manifests, with name prefixes and suffixes, labels and image tags added by Kustomize |

[Kustomize Basics Pt. 2](Kustomize/2026-10-20-kustomize-basics-part-two.md): patches (JSON 6902 and strategic merge, dictionaries and lists, inline and in files), overlays, and components.

| Lab | What it shows |
|---|---|
| [`4_patches`](Kustomize/4_patches/) | The same app with no environments, where every change is a patch: inline and from a file, JSON 6902 and strategic merge |
| [`5_overlays`](Kustomize/5_overlays/) | A shared `base/` with `dev`, `staging` and `prod` overlays, each patching it for its environment |
| [`6_components`](Kustomize/6_components/) | The same overlays, with optional features (admin UI, internal db, resource limits, high availability) pulled out into components each environment switches on |

Generators and garbage collection are next.

### Helm

[Helm Basics](Helm/2026-11-4-helm-basics.md): why Helm exists, how it compares to Kustomize, charts, releases and revisions, installing someone else's chart, overriding values, writing your own chart, template functions, pipelines, conditionals, `with`, `range`, named templates, and upgrade, history and rollback.

| Lab | What it shows |
|---|---|
| [`1_hello-world`](Helm/charts/1_hello-world/) | The smallest useful chart: one ConfigMap, filled in from values and built-in objects |
| [`2_nginx`](Helm/charts/2_nginx/) | The `web` Deployment from the Kustomize lessons as a chart, with `values-stage.yaml` and `values-prod.yaml` holding only what differs from the dev defaults |

## Running the labs

Clone the repo and run the commands from the lesson against a lab or test cluster.

### Kustomize

All you need is `kubectl`. Kustomize is built into it:

```bash
kubectl kustomize Kustomize/1_basics   # print the YAML, touches nothing
kubectl apply -k Kustomize/1_basics    # deploy it
kubectl delete -k Kustomize/1_basics   # clean up
```

The labs with environments are built per overlay, not from the lab root:

```bash
kubectl kustomize Kustomize/5_overlays/overlays/dev
kubectl apply -k Kustomize/6_components/overlays/prod
```

### Helm

You need `helm` as well as `kubectl`. Section 4 of the lesson covers installing it.

```bash
helm lint Helm/charts/1_hello-world                       # check the chart
helm template hello Helm/charts/1_hello-world -n lesson   # print the YAML, touches nothing
helm install hello Helm/charts/1_hello-world -n lesson --create-namespace   # deploy it
helm uninstall hello -n lesson                            # clean up
```

The nginx chart takes a values file per environment, layered over the defaults:

```bash
helm template web Helm/charts/2_nginx -f Helm/charts/2_nginx/values-prod.yaml
helm install web Helm/charts/2_nginx -n lesson -f Helm/charts/2_nginx/values-stage.yaml
```
