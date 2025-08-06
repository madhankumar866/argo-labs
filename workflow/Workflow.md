# Argo Workflow Overview

> A workflow is a series of tasks, processes, or steps executed in a specific sequence to achieve a particular goal or outcome.

---

## Simple Workflow Example

The main part of a Workflow spec contains an entry point and a list of templates:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
Metadata:
  generateName: hello-world-
Spec:
  entrypoint: whalesay
  templates:
    - name: whalesay
      container:
        image: docker/whalesay
        command: [cowsay]
        args: ["hello world"]
```

---

## Core Parts of a Workflow Spec

- **Entrypoint**: Specifies the name of the template that serves as the entry point for the workflow. It defines the starting point of the workflow execution.
- **Templates**: A template represents a step or task in the workflow that should be executed. There are several types of templates. See [[Template types]] for details.

---