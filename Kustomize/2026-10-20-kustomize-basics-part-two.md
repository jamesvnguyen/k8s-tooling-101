# Kustomize Part Two

Picks up where Kustomize Basics stopped. Part one changed every resource at once with transformers. This part changes specific resources with patches, then splits configuration into a shared base and per-environment overlays, then pulls optional features out into components that each environment can switch on or off

Covers: patches (JSON 6902 and strategic merge, dictionaries and lists, inline and in files, targeting), overlays, and components

Not covered here, but worth to review after class: generators, garbage collection

Worked examples: `Kustomize/4_patches/` for patches, `Kustomize/5_overlays/` for overlays and `Kustomize/6_components/` for components. The `base/` in the last two is the manifests from `Kustomize/4_patches/` without the patches, so the app is the same one (MongoDB, RabbitMQ and nginx) used throughout part one

The "Try it" parts are what we run in the session; section 7 has exercises for afterwards

---

## Key terms

| Term | Definition |
|------|------------|
| **Patch** | A change to specific fields of specific resources, for example "set `replicas` to 5 on the Deployment named `nginx-deployment`". |
| **JSON 6902 patch** | A patch written as a list of operations (`add`, `remove`, `replace` and so on), each with a path. Named after the RFC that defines it. |
| **Strategic merge patch** | A patch written as a partial copy of the resource. Kustomize merges it into the original. |
| **Target** | The block in a patch entry that says which resources the patch applies to: by kind, name, label, and so on. |
| **Path** | Where in the resource a JSON 6902 operation acts, for example `/spec/replicas`. List items are numbered from 0. |
| **Merge key** | The field strategic merge uses to match items in a list, for example a container's `name`. |
| **Base** | A directory of manifests holding the shared default configuration. It knows nothing about environments. |
| **Overlay** | A directory that lists a base under `resources:` and adds what's different for one environment. |
| **Component** | A reusable bundle of resources and patches (`kind: Component`) that an overlay switches on by listing it under `components:`. |

---

## 1. Where part one left off

Part one ended with `Kustomize/3_transformers/`: one app, nested directories, and transformers adding a prefix and labels to everything, but this has two gaps.

Transformers can't single anything out. `namePrefix` renames every resource and `labels` labels every resource. There's no way to say "five replicas, but only for nginx"

There was also still one set of manifests, which means there are three duplicated `deployment.yaml` files from part one section 1. Transformers gave us a way to change things, but not a place to keep the per-environment differences

Patches fix the first portion, and overlays fix the second. Finally, components handle what's left once the number of environments grows

---

## 2. Patches

A patch is the other way of changing Kubernetes config with Kustomize. Where a transformer changes the same field on everything, a patch changes particular fields on particular resources.

Every patch needs three things:

- **What to do**: add, replace or remove a value.
- **Which resource**: the target, by kind and name, or by label.
- **Where and what**: the path to the field, and the new value.

Every patch entry goes under one field in `kustomization.yaml`, `patches:`, and comes in one of two formats. JSON 6902 and  Strategic merge. Either can be written inline or kept in a separate file.

> Older configs use `patchesStrategicMerge:` and `patchesJson6902:` instead. Both still work on v5 but print `Warning: 'patchesStrategicMerge' is deprecated. Please use 'patches' instead.` `kustomize edit fix` converts them, along with `bases:` and `commonLabels:`.

### JSON 6902

A list of operations. Each one needs three things: `op` (what to do), `path` (where to do it) and, for most ops, `value` (what to put there). The `target:` block says which resource the operations apply to.

Patch 1 from `Kustomize/4_patches/kustomization.yaml` scales nginx from 1 replica to 3. The `target:` picks out `nginx-deployment`, and the `path` points at the one field to change:


<table>
<tr>
<td valign="top">

**nginx/nginx-depl.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1  # <- before
  selector:
    matchLabels:
      component: nginx
  template:
    metadata:
      labels:
        component: nginx
    spec:
      containers:
        - name: nginx
          image: nginx
```

</td>
<td valign="top">

**kustomization.yaml (patch 1)**

```yaml
patches:
  - target:
      kind: Deployment
      name: nginx-deployment
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
```

</td>
<td valign="top">

**Build output**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3  # <- after
  selector:
    matchLabels:
      component: nginx
  template:
    metadata:
      labels:
        component: nginx
    spec:
      containers:
        - name: nginx
          image: nginx
```

</td>
</tr>
</table>

With JSON6902, the `target:` block is required. Leave it out and the build fails with `must specify a target for JSON patch`.

Patch 5 renames the same Deployment to `web-deployment`. `metadata.name` is just another path, so the patch looks the same as patch 1 with a different `path` and `value`. Patches run in order, so the rename starts from patch 1's output and the replica count of 3 carries through:

<table>
<tr>
<td valign="top">

**After patch 1**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment  # <- before
spec:
  replicas: 3
  selector:
    matchLabels:
      component: nginx
  template:
    metadata:
      labels:
        component: nginx
    spec:
      containers:
        - name: nginx
          image: nginx
```

</td>
<td valign="top">

**kustomization.yaml (patch 5)**

```yaml
patches:
  - target:
      kind: Deployment
      name: nginx-deployment
    patch: |-
      - op: replace
        path: /metadata/name
        value: web-deployment
```

</td>
<td valign="top">

**Build output**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deployment  # <- after
spec:
  replicas: 3
  selector:
    matchLabels:
      component: nginx
  template:
    metadata:
      labels:
        component: nginx
    spec:
      containers:
        - name: nginx
          image: nginx
```

</td>
</tr>
</table>

Above the middle yaml, the target still says `nginx-deployment` because the target matches the name the resource had before this patch ran.

 `kustomize build` sorts the fields alphabetically, but the values are the same.

 ### Targeting

The `target:` block can select more than one resource.

| Target | Matches |
|---|---|
| `kind: Deployment` | Every Deployment in the build |
| `kind: Deployment`, `name: nginx-deployment` | That one Deployment |
| `name: (db\|rabbitmq)-deployment` | Names matching the regular expression |
| `labelSelector: tier=frontend` | Resources with that label |
| `annotationSelector: ...` | Resources with that annotation |

> A JSON 6902 target that matches nothing is not an error. The build succeeds and the patch does nothing. If a patch doesn't seem to be applying, check the target first: kind, name, and spelling.

### Order

Patches run in the order they're listed, each one seeing the output of the one before. That matters mainly for renames. Once a patch changes `/metadata/name`, Kustomize still remembers the original name, so later patches can target the resource by either.


The operations:

| Op | What it does | Fails when |
|---|---|---|
| `add` | Adds a field, or inserts into a list. Overwrites if the map key already exists. | The parent path doesn't exist |
| `replace` | Changes an existing value | The parent path doesn't exist. A missing map key is added rather than failing; see "Patching dictionaries" |
| `remove` | Deletes a field or list item | The path doesn't exist |
| `copy` | Copies a value from `from` to `path` | `from` doesn't exist |
| `move` | Moves a value from `from` to `path` | `from` doesn't exist |
| `test` | Checks a value and fails the build if it doesn't match | The value differs |


### Strategic merge

Write the part of the resource you want changed, and only that part. Kustomize finds the matching resource by `apiVersion`, `kind` and `metadata.name` and merges the two together.

The simplest case is one field. This is lab patch 1 again, nginx from 1 replica to 3, written as strategic merge instead of JSON 6902:

<table>
<tr>
<td valign="top">

**nginx/nginx-depl.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1  # <- before
  selector:
    matchLabels:
      component: nginx
  template:
    metadata:
      labels:
        component: nginx
    spec:
      containers:
        - name: nginx
          image: nginx
```

</td>
<td valign="top">

**kustomization.yaml**

```yaml
patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: nginx-deployment
      spec:
        replicas: 3
```

</td>
<td valign="top">

**Build output**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3  # <- after
  selector:
    matchLabels:
      component: nginx
  template:
    metadata:
      labels:
        component: nginx
    spec:
      containers:
        - name: nginx
          image: nginx
```

</td>
</tr>
</table>

The patch has only the header and the one field. Everything else in the output comes from the original file.

The header (`apiVersion`, `kind`, `metadata.name`) is how the patch finds its resource. Get the name wrong and the build fails:

```
Error: no resource matches strategic merge patch "Deployment.v1.apps/webb.[noNs]"
```

Strategic merge can't rename a resource or `test` a value, and removing something takes a marker (`null`, or `$patch: delete` in a list) rather than an operation

### Patching dictionaries

Most of a Kubernetes manifest is dictionaries (maps of keys to values): `metadata.labels`, a ConfigMap's `data`, a Service's `spec`. There are three things you can do to a key in a dictionary

**Add a key.** Patch 2 adds two labels to the db pod template. Each `add` names the new key at the end of its path. The existing `component: db` label isn't mentioned in the patch, so it's kept:

<table>
<tr>
<td valign="top">

**db/db-depl.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      component: db
  template:
    metadata:
      labels:  # <- before
        component: db
    spec:
      containers:
        - name: mongo
          image: mongo
          # env unchanged
```

</td>
<td valign="top">

**kustomization.yaml (patch 2)**

```yaml
patches:
  - target:
      kind: Deployment
      name: db-deployment
    path: db-label-patch.yaml

# db-label-patch.yaml
- op: add
  path: /spec/template/metadata/labels/cluster
  value: staging
- op: add
  path: /spec/template/metadata/labels/feature
  value: db
```

</td>
<td valign="top">

**Build output**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      component: db
  template:
    metadata:
      labels:
        component: db
        cluster: staging  # <- added
        feature: db       # <- added
    spec:
      containers:
        - name: mongo
          image: mongo
          # env unchanged
```

</td>
</tr>
</table>

**Replace a key.** Patch 6 fixes the RabbitMQ username, which was `redis` from a copy-paste:

<table>
<tr>
<td valign="top">

**message-broker/rabbitmq-config.yaml**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rabbitmq-credentials
data:
  username: "redis"  # <- before
  password: "password123"
```

</td>
<td valign="top">

**kustomization.yaml (patch 6)**

```yaml
patches:
  - target:
      kind: ConfigMap
      name: rabbitmq-credentials
    patch: |-
      - op: replace
        path: /data/username
        value: rabbit
```

</td>
<td valign="top">

**Build output**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rabbitmq-credentials
data:
  username: "rabbit"  # <- after
  password: "password123"
```

</td>
</tr>
</table>

**Remove a key.** Patch 7 takes `type: NodePort` off `nginx-service`. With no `type`, the Service falls back to the default, `ClusterIP`, and is no longer reachable from outside the cluster:

<table>
<tr>
<td valign="top">

**nginx/nginx-service.yaml**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    component: nginx
  ports:
    - protocol: "TCP"
      port: 80
      targetPort: 80
  type: NodePort  # <- before
```

</td>
<td valign="top">

**kustomization.yaml (patch 7)**

```yaml
patches:
  - target:
      kind: Service
      name: nginx-service
    patch: |-
      - op: remove
        path: /spec/type
```

</td>
<td valign="top">

**Build output**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    component: nginx
  ports:
    - protocol: "TCP"
      port: 80
      targetPort: 80
  # type is gone  <- after
```

</td>
</tr>
</table>

The three operations in both formats:

| | JSON 6902 | Strategic merge |
|---|---|---|
| Add a key | `add` with the new key at the end of the `path` | Give the new key; other keys stay |
| Replace a key | `replace`, or `add`, which overwrites an existing key | Give the key with its new value |
| Remove a key | `remove` | Set the key to `null` |
| Key isn't there | `remove` fails the build. `replace` adds the key (below) | `null` on a missing key does nothing |

> RFC 6902 says `replace` should fail if the key doesn't exist. Kustomize v5 (tested on v5.8.2) adds the key instead, and only fails if the parent is missing too. A typo like `/data/usrname` therefore builds cleanly and leaves you with a second key. If the key has to exist already, put a `test` op on it before the `replace`.

### Patching lists

Lists work differently in the two formats, and this is where most of the difference between them comes from.

JSON 6902 only knows positions. `/spec/template/spec/containers/0` is "whichever container is first", and `/-` is "after the last one"

Strategic merge knows which lists in a Kubernetes object have a merge key, and matches items by that key instead of by position. The common ones:

| List | Merge key |
|---|---|
| `containers`, `initContainers` | `name` |
| `env` | `name` |
| `volumes`, `volumeMounts` | `name` (`mountPath` for mounts) |
| Container `ports` | `containerPort` |
| Service `ports` | `port` |

A list with no merge key, such as container `args` or `command`, is replaced in full. If you patch `args` with one item, you end up with one item.

The same three operations as dictionaries apply: add an item, replace an item, remove an item.

#### Adding an item, strategic merge

Lab patch 4, `rabbitmq-patch.yaml`, uses both. It names the `rabbitmq` container, which matches the existing one, so it's merged into it rather than added. Inside it, the env var has a new name, so it's added to the list. The two original env vars aren't in the patch, so they're kept:

<table>
<tr>
<td valign="top">

**message-broker/rabbitmq-depl.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      component: rabbitmq
  template:
    metadata:
      labels:
        component: rabbitmq
    spec:
      containers:
        - name: rabbitmq
          image: rabbitmq
          env:
            - name: RABBITMQ_DEFAULT_USER
              valueFrom:
                configMapKeyRef:
                  name: rabbitmq-credentials
                  key: username
            - name: RABBITMQ_DEFAULT_PASS
              valueFrom:
                configMapKeyRef:
                  name: rabbitmq-credentials
                  key: password
```

</td>
<td valign="top">

**rabbitmq-patch.yaml (patch 4)**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq-deployment
spec:
  template:
    spec:
      containers:
        - name: rabbitmq
          env:
            - name: RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS
              value: "+S 2:2"
          resources:
            requests:
              memory: 256Mi
```

</td>
<td valign="top">

**Build output**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      component: rabbitmq
  template:
    metadata:
      labels:
        component: rabbitmq
    spec:
      containers:
        - name: rabbitmq
          image: rabbitmq
          env:
            - name: RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS  # <- added
              value: "+S 2:2"
            - name: RABBITMQ_DEFAULT_USER
              valueFrom:
                configMapKeyRef:
                  name: rabbitmq-credentials
                  key: username
            - name: RABBITMQ_DEFAULT_PASS
              valueFrom:
                configMapKeyRef:
                  name: rabbitmq-credentials
                  key: password
          resources:          # <- added
            requests:
              memory: 256Mi
```

</td>
</tr>
</table>

The new env var goes at the front of the list, not the end. The image and the existing env vars are untouched, and the patch never had to say where in either list anything was.

The same rule is how you add a sidecar: a container with a new `name` is added as a second container, and it goes first. Give it the name of an existing container instead and it merges into that one, replacing its image. Section 7 has an exercise on this.

#### Adding an item, JSON 6902

A sidecar as a JSON 6902 patch. It needs a target, and `/-` means "after the last item", so here memcached goes last:

```yaml
patches:
  - target:
      kind: Deployment
      name: nginx-deployment
    patch: |-
      - op: add
        path: /spec/template/spec/containers/-
        value:
          name: memcached
          image: memcached
```

#### Replacing an item

To change the nginx image, JSON 6902 replaces the whole item at index 0. Strategic merge names the container and gives only the field that changes. Both build to `image: nginx:1.27.2`. Neither patch is in the lab:

<table>
<tr>
<td valign="top">

**nginx/nginx-depl.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      component: nginx
  template:
    metadata:
      labels:
        component: nginx
    spec:
      containers:
        - name: nginx
          image: nginx  # <- before
```

</td>
<td valign="top">

**JSON 6902: replace item 0**

```yaml
- target:
    kind: Deployment
    name: nginx-deployment
  patch: |-
    - op: replace
      path: /spec/template/spec/containers/0
      value:
        name: nginx
        image: nginx:1.27.2
```

</td>
<td valign="top">

**Strategic merge: match by name**

```yaml
- patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx-deployment
    spec:
      template:
        spec:
          containers:
            - name: nginx
              image: nginx:1.27.2
```

</td>
</tr>
</table>

The JSON 6902 `value` is the complete new item. Anything not in it is gone, so if the container had ports or env vars they'd need to be repeated. To change only the image, point the path at the field instead: `/spec/template/spec/containers/0/image`. Lab patch 3 does exactly that on a Service, replacing `/spec/ports/0/port` and leaving the rest of the port entry alone.

#### Removing an item

JSON 6902 removes by index. Strategic merge names the item and marks it with `$patch: delete`. Both remove `RABBITMQ_DEFAULT_PASS`. This one is only to show the mechanics; RabbitMQ would fall back to its default password without it:

<table>
<tr>
<td valign="top">

**message-broker/rabbitmq-depl.yaml (env only)**

```yaml
          env:
            - name: RABBITMQ_DEFAULT_USER
              valueFrom:
                configMapKeyRef:
                  name: rabbitmq-credentials
                  key: username
            - name: RABBITMQ_DEFAULT_PASS  # <- item 1
              valueFrom:
                configMapKeyRef:
                  name: rabbitmq-credentials
                  key: password
```

</td>
<td valign="top">

**JSON 6902: remove item 1**

```yaml
- target:
    kind: Deployment
    name: rabbitmq-deployment
  patch: |-
    - op: remove
      path: /spec/template/spec/containers/0/env/1
```

</td>
<td valign="top">

**Strategic merge: $patch: delete**

```yaml
- patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: rabbitmq-deployment
    spec:
      template:
        spec:
          containers:
            - name: rabbitmq
              env:
                - name: RABBITMQ_DEFAULT_PASS
                  $patch: delete
```

</td>
</tr>
</table>

A `remove` on an index that doesn't exist fails the build:

```
Error: error in remove for path: '/spec/template/spec/containers/1': Unable to access invalid index: 1: invalid index referenced
```

#### The index problem

The weak point of JSON 6902 is list indexes. `/containers/0` means "whichever container is first", and if someone adds a sidecar to the base above it, the patch quietly edits the wrong one. A `test` op in front of the change turns that into a build failure instead:

```yaml
- op: test
  path: /spec/template/spec/containers/0/name
  value: nginx
- op: replace
  path: /spec/template/spec/containers/0/image
  value: nginx:1.27.2
```

If the guard doesn't match, the build stops:

```
Error: testing value /spec/template/spec/containers/0/name failed: test failed
```

Lists side by side:

| | JSON 6902 | Strategic merge |
|---|---|---|
| Add an item | `add` to `/-` (end) or to an index | Give an item with a new merge key. It goes first. |
| Replace an item | `replace` on the index, with the whole new item | Give the merge key and the fields that change |
| Change one field of an item | `replace` on `/<list>/<index>/<field>` | Same as replacing an item |
| Remove an item | `remove` on the index | The merge key plus `$patch: delete` |
| Finds the item by | Position | Merge key |
| List with no merge key (`args`) | Works the same as any other list | The whole list is replaced |

### Choosing a format

Most changes can be written either way, and the parts above show both. The one to watch for is a change to a list item's merge key. Lab patch 3 moves `db-service` from port 27017 to 30000, and only JSON 6902 can do it.

Service `ports` merge on the `port` field, so a strategic merge patch with `port: 30000` doesn't find the existing 27017 entry. It adds a second port:

```yaml
# Strategic merge: looks right, isn't
spec:
  ports:
    - port: 30000
      targetPort: 27017
      nodePort: 30017
```

```yaml
# Build output: two ports, 27017 still there
  ports:
  - nodePort: 30017
    port: 30000
    targetPort: 27017
  - port: 27017
    protocol: TCP
    targetPort: 27017
```

JSON 6902 addresses the entry by its position, `/spec/ports/0/port`, and changes its value. That's why the lab uses it here.

| | Strategic merge | JSON 6902 |
|---|---|---|
| Reads like | The resource itself | A list of edits |
| Finding the resource | The patch header (`kind`, `metadata.name`) | A `target:` block, which is required |
| List items | Matched by merge key (containers and env by `name`), so position doesn't matter | Matched by index (`/containers/0`), which breaks if the order changes |
| Several fields at once | One block | One op per field |
| Removing a field | Awkward: needs a `$patch: delete` directive or `null` | `remove` |
| Changing a list item's key (a Service `port`, a container `name`) | Not possible: it adds a new item instead | `replace` on the path |
| Renaming a resource | Not possible: the name is how the patch finds its resource | `replace` on `/metadata/name` |
| Guarding against a changed base | None | A `test` op |
| Custom resources | Maps merge, but Kustomize doesn't know their merge keys, so lists are replaced whole | Works the same as on any other kind |

A reasonable default: use strategic merge for adding or changing values, especially inside containers. Use JSON 6902 to remove a field, rename a resource, change a list item's key field, or change a list on a custom resource, and put a `test` op in front of any index-based path.

### Inline or in a file

A reasonable rule: inline for a few lines that only make sense next to this kustomization, a file for anything longer or anything someone needs to review on its own.

A patch file has to be inside the kustomization's directory or below it. Kustomize refuses `../`:

```
Error: ... security; file '.../shared/replicas.yaml' is not in or below '.../app'
```


### Try it

`Kustomize/4_patches/` is the worked example. It's the same three components as `Kustomize/3_transformers/`, copied without the transformers, with seven patches in the top-level `kustomization.yaml`. The only change to the manifests is nginx starting at 1 replica, so the first patch has something to change.

```
Kustomize/4_patches/
├── kustomization.yaml              # resources + 7 patches
├── db-label-patch.yaml             # JSON 6902 ops, used with a target
├── rabbitmq-patch.yaml             # strategic merge, names its own target
├── db/
├── message-broker/
└── nginx/
```

Open the kustomization and walk through it:

```bash
cat Kustomize/4_patches/kustomization.yaml
```

| # | Format | Inline or file | What it does | Shown in |
|---|---|---|---|---|
| 1 | JSON 6902 | Inline | nginx replicas 1 to 3 | JSON 6902 |
| 2 | JSON 6902 | `db-label-patch.yaml` | Adds two labels to the db pods | Patching dictionaries |
| 3 | JSON 6902 | Inline | db Service port 27017 to 30000, adds `nodePort: 30017` | Choosing a format |
| 4 | Strategic merge | `rabbitmq-patch.yaml` | Adds an env var and a memory request to RabbitMQ | Patching lists |
| 5 | JSON 6902 | Inline | Renames `nginx-deployment` to `web-deployment` | JSON 6902 |
| 6 | JSON 6902 | Inline | RabbitMQ username `redis` to `rabbit` | Patching dictionaries |
| 7 | JSON 6902 | Inline | Removes `type` from `nginx-service` | Patching dictionaries |

Patch 3 changes `port` and leaves `targetPort` alone. `port` is what clients inside the cluster connect to, `targetPort` is what MongoDB listens on inside the pod. Changing `targetPort` to 30000 as well would leave the Service sending traffic to a port nothing is listening on.

The labels in patch 2 go on the pod template only, not on `spec.selector`. That's safe: the selector still matches, and the pods just carry two extra labels. Adding them to the selector would hit the `field is immutable` problem from part one.

Build it:

```bash
kustomize build Kustomize/4_patches
```

Good output:
- The nginx Deployment is called `web-deployment` and has `replicas: 3`.
- `rabbitmq-credentials` has `username: rabbit`.
- `nginx-service` has no `type:` line, so it's `ClusterIP`.
- `db-deployment`'s pod template labels are `component: db`, `cluster: staging` and `feature: db`. Its `selector` still only has `component: db`.
- `db-service` has `port: 30000`, `targetPort: 27017` and `nodePort: 30017`.
- `rabbitmq-deployment` has three env vars, the new scheduler one first and then the two original credential ones, and a `memory: 256Mi` request. The env list merged by name, so the originals survived.

Bad output: `no resource matches strategic merge patch` means the name in `rabbitmq-patch.yaml` doesn't match the Deployment.

Apply it and check:

```bash
kubectl apply -k Kustomize/4_patches
kubectl get deploy
kubectl get pods -l component=db -L cluster,feature
kubectl get svc
```

Good output: `web-deployment` at `3/3` (no `nginx-deployment`), the db pod with `staging` and `db` in the `CLUSTER` and `FEATURE` columns, `db-service` showing `30000:30017/TCP`, and `nginx-service` as `ClusterIP` with no node port.

This deploys into whichever namespace your context points at, usually `default`, because there's no `namespace:` in this kustomization.

> Destructive, lab cluster only.

```bash
kubectl delete -k Kustomize/4_patches
```

---

## 3. Overlays

There's nothing new to learn in Kustomize for overlays. An overlay is just a `kustomization.yaml` that lists another directory under `resources:` and changes it, using the same patches and transformers covered so far. `Kustomize/4_patches/` is close already: move its seven patches into a separate directory that lists `../` under `resources:` and you have a base and one overlay.

What overlays add is a convention for where things go:

```
k8s/
├── base/
│   ├── kustomization.yaml
│   └── deployment.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    ├── stage/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

The base holds everything shared and nothing environment-specific. No namespace, no environment label, no replica count anyone cares about. Each overlay holds only the differences. If a value is the same in every overlay, it belongs in the base.

### Finishing the part one example

Part one section 1 had three copies of a `web` Deployment and a table of the six values that differed between them. As a base and three overlays:

`base/deployment.yaml` is the dev file from part one with the `environment` label removed:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
```

`base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
```

Then one short file per environment:

<table>
<tr>
<th><code>overlays/dev/kustomization.yaml</code></th>
<th><code>overlays/stage/kustomization.yaml</code></th>
<th><code>overlays/prod/kustomization.yaml</code></th>
</tr>
<tr>
<td valign="top">

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

labels:
  - pairs:
      environment: dev
```

</td>
<td valign="top">

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

labels:
  - pairs:
      environment: stage

replicas:
  - name: web
    count: 2

images:
  - name: nginx
    newTag: "1.27.2"
```

</td>
<td valign="top">

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

labels:
  - pairs:
      environment: prod
      cost-centre: platform

replicas:
  - name: web
    count: 10

images:
  - name: nginx
    newTag: "1.27.2"

patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: web
      spec:
        template:
          spec:
            containers:
              - name: nginx
                resources:
                  requests:
                    cpu: 500m
                    memory: 512Mi
```

</td>
</tr>
</table>

Each of the six rows from the part one table now appears exactly once, in the overlay it applies to. A CVE bump that applies everywhere is a one-line change in the base. `kustomize build overlays/prod` produces the same Deployment as the original hand-written prod file.

### Resources only one environment needs

An overlay can add resources as well as change them. Put the file in the overlay's directory and list it under `resources:` next to the base. The lab's overlays already do this with `namespace.yaml`, since each environment needs its own Namespace object.

In `Kustomize/5_overlays/`, prod also gets a NetworkPolicy that dev and staging don't have. It only lets pods in prod's own namespace reach MongoDB:

<table>
<tr>
<th><code>Kustomize/5_overlays/</code></th>
<th><code>overlays/prod/kustomization.yaml</code></th>
</tr>
<tr>
<td valign="top">

```
5_overlays/
├── base/
│   ├── kustomization.yaml
│   ├── db/
│   ├── message-broker/
│   └── nginx/
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── namespace.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   └── namespace.yaml
    └── prod/
        ├── kustomization.yaml
        ├── namespace.yaml
        └── db-network-policy.yaml   # <- prod only
```

</td>
<td valign="top">

```yaml
namespace: prod

resources:
  - ../../base
  - namespace.yaml
  - db-network-policy.yaml   # <- prod only

labels:
  - pairs:
      environment: prod
      cost-centre: platform

images:
  - name: nginx
    newTag: "1.27.2"

replicas:
  - name: nginx-deployment
    count: 5

patches:
  # nginx rename, db-service type,
  # nginx resource requests
```

</td>
</tr>
</table>

`overlays/prod/db-network-policy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-network-policy
spec:
  podSelector:
    matchLabels:
      component: db
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 27017
```

The file has no namespace or environment label in it. It gets `namespace: prod` and `environment: prod` from the overlay, the same as everything that comes from the base. The overlay's patches and transformers apply to its own resources too, so a resource added here is treated the same as one from the base.

Where an extra resource goes depends on how many environments need it:

| Needed by | Put it in |
|---|---|
| Every environment | The base |
| One environment | That overlay's directory, listed under `resources:` |
| Two or more, but not all | A component (section 4), so the file isn't copied between overlays |


> Older examples list the base under `bases:` and the extra files under `resources:`. `bases:` is deprecated in v5; everything goes under `resources:`.

> A NetworkPolicy only takes effect if the cluster's network plugin enforces it. Calico and Cilium do; Flannel on its own doesn't. On a plugin that doesn't, the object is created and silently ignored.

### More than labels: a name per environment

An environment label is the smallest difference an overlay can make. In `Kustomize/5_overlays/` each environment also gives nginx its own name, and dev does it differently from staging and prod so the two approaches can be compared.

<table>
<tr>
<th><code>overlays/dev/kustomization.yaml</code></th>
<th><code>overlays/staging/kustomization.yaml</code></th>
</tr>
<tr>
<td valign="top">

```yaml
namespace: dev

resources:
  - ../../base
  - namespace.yaml

namePrefix: dev-

labels:
  - pairs:
      environment: dev
```

</td>
<td valign="top">

```yaml
patches:
  - target:
      kind: Deployment
      name: nginx-deployment
    patch: |-
      - op: replace
        path: /metadata/name
        value: staging-nginx-deployment

  - target:
      kind: Service
      name: nginx-service
    patch: |-
      - op: replace
        path: /metadata/name
        value: staging-nginx-service
```

</td>
</tr>
</table>

`namePrefix` is a transformer, so it renames every object from the base, not just nginx. The Namespace object is left alone. Kustomize also updates the references it knows about: `db-deployment` reads its credentials through a `configMapKeyRef`, and in dev that now points at `dev-db-credentials`. The patches in staging only touch their targets, so the database and broker keep their base names.

Staging and prod also set `images:` and `replicas:`. Both still say `nginx-deployment`, the base name, even though a patch in the same file renames it. Kustomize keeps track of each resource's original name, and targets and transformers match on that.

#### Try it

```bash
cd Kustomize/5_overlays
kustomize build overlays/dev | grep -E '^  name: '
kustomize build overlays/staging | grep -E '^  name: '
```

What it does: lists the name of every object in dev, then in staging.
Good output: in dev, every name except the `dev` Namespace starts with `dev-`. In staging, only `staging-nginx-deployment` and `staging-nginx-service` have a prefix; `db-deployment`, `rabbitmq-service` and the rest are unchanged.

```bash
kustomize build overlays/dev | grep -A2 configMapKeyRef | head -3
```

What it does: shows the first ConfigMap reference in dev's db Deployment.
Good output: `name: dev-db-credentials`. The prefix renamed the ConfigMap and the reference together.

```bash
for e in dev staging prod; do
  echo "$e:" $(kustomize build overlays/$e | awk '/name: .*nginx-deployment/,/^---/' | grep -E 'replicas:|image:|cpu:')
done
```

What it does: pulls the replica count, image and CPU request out of each environment's nginx Deployment.
Good output:

```
dev: replicas: 1 - image: nginx
staging: replicas: 2 - image: nginx:1.27.2
prod: replicas: 5 - image: nginx:1.27.2 cpu: 250m
```

Staging and prod also both drop `type: NodePort` from `db-service`, and each overlay has its own copy of that patch. Removing that copy is what section 4 is for.

---

## 4. Components

Overlays work well when each environment is "the base plus some changes". They get awkward when there are optional features that different environments mix and match.

Take the app in the lab. There are four things that some environments want and others don't:

| Feature | dev | staging | prod |
|---|---|---|---|
| Mongo admin UI (mongo-express) | Yes | Yes | No |
| Database not exposed outside the cluster | No | Yes | Yes |
| Resource requests and limits on every Deployment | No | Yes | Yes |
| High availability for nginx (3 replicas, spread, PodDisruptionBudget) | No | No | Yes |

No single chain of overlays fits that. Prod built on top of staging would inherit the admin UI and have to remove it. Staging built on top of dev has the same problem in reverse. The alternative is copying the same patches into two overlays, which is the duplication Kustomize was supposed to remove.

A component packages one feature (resources, patches, transformers, whatever it needs) so that any overlay can include it with one line.

### Writing one

A component is a directory with a `kustomization.yaml`, the same as anything else, but with a different header:

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
```

The `v1alpha1` is not a typo. Components have kept that version for years and are in wide use regardless.

Below the header it takes the same fields as a normal kustomization: `resources:`, `patches:`, `labels:`, `images:` and so on.

An overlay includes it under `components:`, not `resources:`:

```yaml
resources:
  - ../../base

components:
  - ../../components/db-internal
```

Mixing the two up is an error either way:

```
# Component listed under resources:
expected kind != 'Component' for path '.../components/db-internal'

# Kustomization listed under components:
expected kind 'Component' for path '.../base' but got 'Kustomization'
```

### Why not just another directory under resources

The difference is what the patches can see. A kustomization under `resources:` is built on its own first and its output is added to the parent. Its patches can only touch its own resources. A component isn't built on its own. It's applied to everything the overlay has collected so far, so a patch in a component can change resources from the base.

`components/db-internal` is a good example. It's nothing but a patch on `db-service`, which lives in the base. As a normal kustomization under `resources:`, that patch would have nothing to apply to.

### Build order

For any one `kustomization.yaml`, Kustomize does this:

1. Collect everything under `resources:`.
2. Apply each component, in the order listed. Each one sees the output of the one before.
3. Apply the overlay's own transformers and patches (`namespace:`, `labels:`, `images:`, `patches:` and the rest).

Two consequences come up in practice.

The overlay always has the last word. In the lab, `high-availability` sets nginx to 3 replicas and prod's own patch sets it to 5. Prod gets 5. Component values are defaults that an overlay can still override.

Component order matters when one component's patch should apply to another component's resources. `resource-limits` patches every Deployment. If it's listed before `mongo-express`, the mongo-express Deployment doesn't exist yet and ends up without limits. The build doesn't warn about this.

### Try it

`Kustomize/6_components/` has the same base, four components and three overlays that use them. The full layout and the exercises are in section 7. In the session, build the three overlays and compare them.

```bash
cd Kustomize/6_components
cat overlays/prod/kustomization.yaml
```

What it does: shows prod's overlay. The base and a prod-only NetworkPolicy under `resources:`, three components, the image tag, and patches of its own that set nginx to 5 replicas and rename it to `prod-nginx-deployment`.

```bash
for e in dev staging prod; do
  echo "$e: mongo-express=$(kustomize build overlays/$e | grep -c 'name: mongo-express-deployment') netpol=$(kustomize build overlays/$e | grep -c 'kind: NetworkPolicy')"
done
```

What it does: builds each overlay and counts two things that only some environments get.
Good output:

```
dev: mongo-express=1 netpol=0
staging: mongo-express=1 netpol=0
prod: mongo-express=0 netpol=1
```

mongo-express comes from a component that dev and staging include. The NetworkPolicy is a plain resource in prod's overlay.

```bash
kustomize build overlays/prod | grep -B1 -A5 "name: prod-nginx-deployment" | grep -E "name:|replicas"
```

What it does: finds nginx's replica count in prod.
Good output: `name: prod-nginx-deployment` and `replicas: 5`. `high-availability` set 3 and prod's own patch set 5. The overlay runs last, so 5 wins.

Apply staging and check it:

```bash
kubectl apply -k overlays/staging
kubectl get deploy,svc -n staging
```

Good output: `namespace/staging created` followed by 10 more `created` lines. Four Deployments, including `mongo-express-deployment`, and `db-service` listed as `ClusterIP` because of the `db-internal` component. mongo-express may restart a few times until MongoDB is ready, which settles on its own.

> Destructive, lab cluster only.

```bash
kubectl delete -k overlays/staging
```

---

## 5. Which tool for which change

| The change | Use |
|---|---|
| Applies to every resource | A transformer: `namespace`, `namePrefix`, `labels`, `images` |
| One field on one resource | A patch. Strategic merge to add or change values; JSON 6902 to remove, rename, change a list item's key, or guard with `test` |
| Differs per environment | An overlay, holding only that environment's differences |
| An extra resource only one environment needs | A file in that overlay, listed under `resources:` |
| A feature some environments want and others don't | A component, included by the overlays that want it |

### Worth remembering

- The base holds nothing environment-specific. If a value is the same in every overlay, it moves to the base. If it's different in one, it moves out.
- For any one `kustomization.yaml`: resources first, then components in the order listed, then its own transformers and patches. Most "where did that value come from" questions are answered by reading it in that order, then checking one level down.
- Build before you apply, and diff the builds in review. `diff <(kustomize build overlays/staging) <(kustomize build overlays/prod)` says more about a change than the diff of the source files.
- Silent no-ops are the dangerous ones: a JSON 6902 target that matches nothing, or a component listed before the resources it should patch. Neither fails the build.
- Guard list-index patches with `test`, and decide selector labels before the first deploy.

### Troubleshooting someone else's overlay

1. Get the rendered output: `kustomize build <overlay>`, or `kubectl kustomize <overlay>` if only kubectl is installed. It needs no cluster access and can be shared.
2. Get the versions: `kustomize version` and `kubectl version --client`. The two can build the same tree differently.
3. Read the overlay in build order and find which file produced the value in question.

---

## 6. Common errors

| Message or symptom | Cause | Check |
|---|---|---|
| `no resource matches strategic merge patch "Deployment.v1.apps/<name>..."` | The name, kind or apiVersion in the patch header doesn't match anything | Build the base and compare names exactly |
| `must specify a target for JSON patch` | A JSON 6902 patch with no `target:` block | Add `target:` with at least a `kind` |
| `security; file '...' is not in or below '...'` | A patch `path:` points outside the kustomization's directory, often a `../` shared between overlays | Move the shared change into the base or a component |
| `unable to parse SM or JSON patch` | Indentation under an inline `patch: \|-` is off | Line the ops up under `- op:`, or move the patch to a file |
| A JSON 6902 patch has no effect, no error | The `target:` matches nothing | Kind and name spelling, and whether an earlier patch renamed it |
| `replace operation does not apply: doc is missing path` | `replace` or `remove` on a field that doesn't exist | Use `add` to create a field, and check list indexes |
| `testing value <path> failed: test failed` | A `test` guard didn't match, because the base changed or the patch ran twice | What's at that path in the base now |
| A container lost its args after a strategic merge | Lists without a merge key are replaced, not merged | Patch the whole list, or use JSON 6902 |
| A second container appeared | The container `name` in a strategic merge patch didn't match | Container names in the base |
| A sidecar patch replaced the main container's image | The sidecar's `name` matched the existing container | Give the sidecar its own name |
| A JSON 6902 patch on `/containers/0` hit the wrong container | A strategic merge patch added a container, and new containers go first | Put a `test` on the container name before the change |
| `expected kind != 'Component'` | A component listed under `resources:` | Move it to `components:` |
| `expected kind 'Component' ... but got 'Kustomization'` | A normal kustomization listed under `components:` | Move it to `resources:`, or change its header |
| A component's patch skipped a resource added by another component | Component order | List the component that adds resources first |
| An overlay value is ignored | The overlay's own patches run after components, or a later patch overwrote it | Read the overlay top to bottom in build order |
| A pod can't reach another Service after adding `namePrefix` | The prefix renames objects and the references Kustomize knows about, but not hostnames in env values or config files | Grep the build for the old name |
| Deprecation warning on `patchesStrategicMerge`, `patchesJson6902` or `bases` | Config written for v4 | `kustomize edit fix` |
| `Unable to access invalid index` | A JSON 6902 `remove` or `replace` on a list index that doesn't exist | Build without the patch and count the items |

---

## 7. Practice

These are for after the session. Everything here is `kustomize build`, so no cluster access is needed except where a task says otherwise.

### Patches

Work in a copy of `Kustomize/4_patches` so the lab stays as it is:

```bash
cp -r Kustomize/4_patches ~/patches-practice
cd ~/patches-practice
kustomize build . > before.yaml
```

After each exercise, `diff before.yaml <(kustomize build .)` shows exactly what your patch changed.

#### 1. The port that wouldn't change

Replace patch 3 (the inline JSON 6902 on `db-service`) with a strategic merge patch that sets `port: 30000`, `targetPort: 27017` and `nodePort: 30017`. Build it and look at `db-service`.

Good output: two ports, 30000 and the original 27017. Service ports merge on `port`, so a new port number is a new item. Put the JSON 6902 version back.

#### 2. Break an index

Add a memcached sidecar as a strategic merge patch, listed first under `patches:`:

```yaml
- patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx-deployment
    spec:
      template:
        spec:
          containers:
            - name: memcached
              image: memcached
```

Build and check the nginx Deployment: two containers, memcached first. Then add a JSON 6902 patch straight after it that sets `/spec/template/spec/containers/0/image` to `nginx:1.27.2`. Build and check which container got the new image.

Good output: memcached is running `nginx:1.27.2`, and nginx is unchanged. Now put a `test` op on `/spec/template/spec/containers/0/name` with `value: nginx` in front of the `replace`, and build again.

Good output: `testing value /spec/template/spec/containers/0/name failed: test failed`. That's the guard working.

#### 3. A silent no-op

Change the target in patch 7 from `nginx-service` to `nginx-svc` and build.

Good output: the build succeeds, and `nginx-service` still has `type: NodePort`. Nothing warns you. Change it back.

#### 4. Remove with strategic merge

Write a strategic merge patch that removes `type` from `db-service` with `type: null`, and check it builds to the same result as a JSON 6902 `remove` on `/spec/type`. Then explain why it would fail on apply alongside patch 3.

<details>
<summary>Answer</summary>

Patch 3 adds `nodePort: 30017`. Without `type: NodePort` the Service is `ClusterIP`, and the API server rejects a `nodePort` on a `ClusterIP` Service. `kustomize build` doesn't validate that, so it only shows up on `kubectl apply`.

</details>

### Overlays and components

`Kustomize/6_components/` puts sections 3 and 4 together.

```
Kustomize/6_components/
├── base/                           # the Kustomize/4_patches manifests, without the patches
├── components/
│   ├── mongo-express/              # 2 new resources: Deployment + Service
│   ├── db-internal/                # 1 JSON 6902 patch on db-service
│   ├── resource-limits/            # 1 JSON 6902 patch on every Deployment
│   └── high-availability/          # 1 new resource (PDB) + 1 strategic merge patch
└── overlays/
    ├── dev/                        # mongo-express, nginx rename
    ├── staging/                    # mongo-express, db-internal, resource-limits, nginx rename
    └── prod/                       # db-internal, resource-limits, high-availability, plus its own patches and NetworkPolicy
```

The four components cover the main shapes a component can take: resources only, a patch only, and both together.

`overlays/staging/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# staging: close to prod (limits, internal db) but keeps the admin UI
# and doesn't need the HA setup.
namespace: staging

resources:
  - ../../base
  - namespace.yaml

# Order matters: mongo-express comes before resource-limits so its
# Deployment exists by the time the limits patch runs.
components:
  - ../../components/mongo-express
  - ../../components/db-internal
  - ../../components/resource-limits

labels:
  - pairs:
      environment: staging

patches:
  - target:
      kind: Deployment
      name: nginx-deployment
    patch: |-
      - op: replace
        path: /metadata/name
        value: staging-nginx-deployment

  - target:
      kind: Service
      name: nginx-service
    patch: |-
      - op: replace
        path: /metadata/name
        value: staging-nginx-service
```

`components/high-availability/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

# A new resource and a patch together: three nginx replicas, spread
# across nodes, and a PodDisruptionBudget so a node drain can't take
# them all down at once.
resources:
  - nginx-pdb.yaml

patches:
  - path: nginx-spread.yaml
```

The rest are in the directory, each with a comment saying what it does.

#### Setup

From the root of the lessons repo, work in a copy so the lab stays as it is. Tasks 2 and 3 edit files.

```bash
cp -r Kustomize/6_components ~/overlays-practice
cd ~/overlays-practice
kustomize version
kubectl config current-context
```

Good output: a v5 Kustomize, and the lab cluster as the current context. Only task 4 uses the cluster.

#### Task 1: build all three and compare

```bash
kustomize build overlays/dev
kustomize build overlays/staging
kustomize build overlays/prod
```

Good output:

| | dev | staging | prod |
|---|---|---|---|
| Objects | 11 | 11 | 11 |
| `mongo-express-deployment` | Yes | Yes | No |
| nginx Deployment name | `dev-nginx-deployment` | `staging-nginx-deployment` | `prod-nginx-deployment` |
| `db-service` `type:` | `NodePort` | none (ClusterIP) | none (ClusterIP) |
| `resources:` on Deployments | No | Yes, all 4 | Yes, all 3 |
| nginx replicas | 1 | 1 | 5 |
| nginx image | `nginx` | `nginx` | `nginx:1.27.2` |
| `nginx-pdb` | No | No | Yes |
| `db-network-policy` | No | No | Yes |

Then diff staging against prod:

```bash
diff <(kustomize build overlays/staging) <(kustomize build overlays/prod)
```

Every difference in that output should trace back to a line in one of the two overlays or a component one of them includes. Pick two and find where they come from.

#### Task 2: break the component order

In `overlays/staging/kustomization.yaml`, move `mongo-express` to the bottom of the `components:` list and rebuild:

```bash
kustomize build overlays/staging | awk '/name: mongo-express-deployment/,/^---/' | grep -c memory
```

Good output: `0`. The limits patch ran before the mongo-express Deployment existed. The build succeeded and nothing warned you.

Put it back at the top and run the same command. Good output: `2` (the request and the limit).

#### Task 3: write a component

The patches lab in `Kustomize/4_patches/` added a `RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS` env var to RabbitMQ. Staging now wants it too. Turn it into a component called `rabbitmq-tuning` and include it in staging and prod.

1. Create `components/rabbitmq-tuning/kustomization.yaml`.
2. Use a JSON 6902 `add` to `/spec/template/spec/containers/0/env/-`. The original was a strategic merge patch, `Kustomize/4_patches/rabbitmq-patch.yaml`; take just the env var from it.
3. Add it to `components:` in `overlays/staging` and `overlays/prod`.

<details>
<summary>Solution</summary>

`components/rabbitmq-tuning/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

patches:
  - target:
      kind: Deployment
      name: rabbitmq-deployment
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS
          value: "+S 2:2"
```

In both overlays:

```yaml
components:
  # ...existing entries...
  - ../../components/rabbitmq-tuning
```

</details>

Check it:

```bash
for e in dev staging prod; do echo "$e: $(kustomize build overlays/$e | grep -c RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS)"; done
```

Good output: `dev: 0`, `staging: 1`, `prod: 1`.

#### Task 4: deploy one

```bash
kubectl apply -k overlays/staging
kubectl get deploy,svc,pdb -n staging
kubectl get pods -n staging
```

Good output: `namespace/staging created` followed by 10 more `created` lines. `db-service` shows as `ClusterIP`. After a minute or so, 4 pods `Running`.

The mongo-express pod may restart a few times before the database is ready to accept connections. That settles on its own. **TODO: verify** on the lab cluster how long it takes.

Then open the admin UI through a port-forward, since it isn't exposed:

```bash
kubectl port-forward -n staging svc/mongo-express-service 8081:8081
```

Browse to `http://localhost:8081`. The image may ask for a login. **TODO: verify** the default credentials for `mongo-express:1.0.2` before the session.

#### Success criteria

- [ ] All three overlays build, and the counts match the table in task 1
- [ ] `rabbitmq-tuning` exists, and the check in task 3 prints `0`, `1`, `1`
- [ ] `kubectl get pods -n staging` shows 4 pods `Running`
- [ ] You can explain why prod has 5 nginx replicas when `high-availability` sets 3

#### Stretch task

Add `overlays/prod-eu/`: everything prod has, in namespace `prod-eu`, with a `region: eu` label, and without the admin UI coming back. Build it and confirm it has 11 objects and every name matches prod's.

An overlay can list another overlay under `resources:`, so `../prod` works as a base. Then ask: should it be an overlay on `overlays/prod`, or a fresh overlay on `base` that lists the same components? Both work. The first is shorter. The second can be read on its own without opening another file.

#### Clean up

> Destructive, lab cluster only.

```bash
kubectl delete -k overlays/staging
```

Good output: 11 `deleted` lines, starting with the namespace.

> The database and broker credentials in this lab are throwaway values in a ConfigMap. Part three moves them into Secrets with a generator.

---

## 8. What's next

- **Generators**: `configMapGenerator` and `secretGenerator`, building ConfigMaps and Secrets from literals or files instead of writing them, and the name hash that rolls pods when the content changes. The lab ConfigMaps holding credentials are the first thing to move.
- **Garbage collection**: what happens to objects that drop out of the build. Try it with `Kustomize/4_patches`: apply it, remove `nginx/` from `resources:`, apply again, and the nginx Deployment is still running.

---

## Reference

- Kustomize patches: https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/
- Kustomize components: https://kubectl.docs.kubernetes.io/guides/config_management/components/
- Declarative Management of Kubernetes Objects Using Kustomize: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
- Strategic merge patch behaviour: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/
- Strategic merge patch directives (`$patch: delete`): https://github.com/kubernetes/community/blob/master/contributors/devel/sig-api-machinery/strategic-merge-patch.md
- RFC 6902, JSON Patch: https://datatracker.ietf.org/doc/html/rfc6902
- RFC 6901, JSON Pointer (path syntax, `~1`): https://datatracker.ietf.org/doc/html/rfc6901
- PodDisruptionBudget: https://kubernetes.io/docs/tasks/run-application/configure-pdb/
- NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/
