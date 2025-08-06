# Argo Workflow Template Types

> This note describes the main template types used in Argo Workflows. For a workflow overview, see [[Workflow]].

Templates in Argo define workflow steps. They fall into two main groups:

- **Template Definitions:** Describe what a step does.
- **Template Invocators:** Describe how steps are executed.

---

## Template Definitions

### Container
Runs a containerized application or script.

```yaml
- name: whalesay
  container:
    image: docker/whalesay
    command: [cowsay]
    args: ["hello world"]
```

### Resource
Creates, modifies, or deletes Kubernetes resources.

```yaml
- name: k8s-owner-reference
  resource:
    action: create
    manifest: |
      apiVersion: v1
      kind: ConfigMap
      metadata:
        generateName: owned-eg-
      data:
        some: value
```

### Script
Runs an inline script without a separate container image.

```yaml
- name: gen-random-int
  script:
    image: python:alpine3.6
    command: [python]
    source: |
      import random
      i = random.randint(1, 100)
      print(i)
```

### Suspend
Pauses execution for a set duration or until resumed.

```yaml
- name: delay
  suspend:
    duration: "20s"
```

---

## Template Invocators

### DAG (Directed Acyclic Graph)
Defines tasks with dependencies.

```yaml
- name: diamond
  dag:
    tasks:
    - name: A
      template: echo
    - name: B
      dependencies: [A]
      template: echo
    - name: C
      dependencies: [A]
      template: echo
    - name: D
      dependencies: [B, C]
      template: echo
```

### Steps
Defines sequential or parallel steps.

```yaml
- name: hello-hello-hello
  steps:
  - - name: step1
      template: prepare-data
    - name: step2a
      template: run-data-first-half
    - name: step2b
      template: run-data-second-half
```

---

> **Tip:** Use Obsidian’s backlinks and tags to connect related concepts and workflows.