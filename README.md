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

## Running the labs

All you need is `kubectl`. Kustomize is built into it. Clone the repo and run the commands from the lesson against a lab or test cluster:

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
