Klar. Hier ist eine kompakte README.md, die den Ordner k8s-samples als zentrale Ablage für wiederverwendbare Kubernetes- und OpenShift-Beispiele beschreibt.

# Kubernetes Samples

This folder contains reusable Kubernetes and OpenShift configuration samples, YAML manifests, CLI commands, and small examples.

The purpose of this folder is to provide a central reference and sample repository for common Kubernetes and OpenShift use cases.

## Purpose

The samples can be used as:

- Reference for Kubernetes and OpenShift configurations
- Starting point for new deployments or configurations
- Examples for testing and troubleshooting
- Documentation of commonly used configurations
- Reusable templates for development and engineering activities

> **Important:**  
> The files in this folder are **samples only** and should not be used directly in production environments without review and adaptation.

## Content

Typical examples stored in this folder may include:

- Deployments
- StatefulSets
- Services
- Routes and Ingress configurations
- ConfigMaps
- Secrets examples
- PersistentVolumeClaims (PVC)
- Storage configurations
- Jobs and CronJobs
- NetworkPolicies
- ServiceAccounts and RBAC
- OpenShift-specific resources
- `oc` and `kubectl` command examples
- Troubleshooting examples

## Suggested Structure

    k8s-samples/
    ├── deployments/
    ├── configmaps/
    ├── secrets/
    ├── storage/
    ├── networking/
    ├── jobs/
    ├── rbac/
    ├── openshift/
    └── README.md

## Usage

Before using a sample:

1. Review the YAML or command.
2. Adjust namespaces, resource names, labels, storage classes, and other environment-specific values.
3. Remove or replace placeholder values.
4. Validate the configuration before applying it.
5. Test changes in a non-production environment first.

Example:

    oc apply -f <sample-file>.yaml

or:

    kubectl apply -f <sample-file>.yaml

## Security

Do not store real passwords, tokens, certificates, API keys, or other sensitive information in this repository.

Secret examples should only contain placeholders, for example:

    username: <USERNAME>
    password: <PASSWORD>

Environment-specific or sensitive values should be provided through the appropriate secret management mechanism.

## Naming Convention

Use descriptive and technology-oriented names for sample files.

Examples:

    deployment-example.yaml
    pvc-example.yaml
    secret-file-mount.yaml
    configmap-example.yaml
    networkpolicy-example.yaml
    openshift-route-example.yaml

## Disclaimer

These examples are intended for documentation, reference, testing, and development purposes.

Always review and adapt the samples before using them in a specific Kubernetes or OpenShift environment.