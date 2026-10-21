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

Patches are next.

## Running the labs

All you need is `kubectl`. Kustomize is built into it. Clone the repo and run the commands from the lesson against a lab or test cluster:

```bash
kubectl kustomize Kustomize/1_basics   # print the YAML, touches nothing
kubectl apply -k Kustomize/1_basics    # deploy it
kubectl delete -k Kustomize/1_basics   # clean up
```
