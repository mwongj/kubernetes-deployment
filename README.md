# On-premises Kubernetes deployment

## Overview

This repository contains a reference implementation of bootstrapping and installation
of a Kubernetes cluster on-premises with an external ingress gateway. The provided
tooling can be used both as a basis for personal projects and for educational purposes.

The goal of the project is to provide tooling for reproducible deployment of a fully
functional Kubernetes cluster for on-premises including support for dynamic
provisioning of `PersistentVolumes` an `LoadBalancer` service types.

A detailed description is available in
[The Ultimate Kubernetes Homelab Guide: From Zero to Production Cluster On-Premises](https://datastrophic.io/kubernetes-homelab-with-proxmox-kubeadm-calico-openebs-and-metallb/) blog post.

Software used:

-   `Terraform` for infrastructure provisioning
-   `Ansible` for deployment automation
-   `Helm` for Kubernetes package management
-   `Kubeadm` for Kubernetes cluster bootstrapping
-   `Containerd` as the container runtime
-   `Calico` for pod networking
-   `MetalLB` for exposing `LoadBalancer` type services
-   `OpenEBS` for volume provisioning
-   `Cert-manager` for managing certificates for SSL termination
-   `Istio` for ingress and traffic management
-   `External-dns` for managing remote dns records

## Pre-requisites

-   cluster machines/VMs should be provisioned and accessible over SSH
-   it is recommended to use Ubuntu 24.04 as cluster OS
-   the current user should have superuser privileges on the cluster nodes
-   Ansible installed locally
-   Terraform installed locally

## Bootstrapping the infrastructure on Proxmox

The [proxmox](proxmox) directory of this repo contains automation for the initial
infrastructure bootstrapping using `cloud-init` templates and Proxmox Terraform provider.

The terraform will generate a dynamic inventory file `ansible/inventory.ini`.

## Quickstart

Installation consists of the following phases:

-   prepare machines for Kubernetes installation
    -   install common packages, disable swap, enable port forwarding, install container runtime
-   Kubernetes installation
    -   bootstrap control plane, install container networking, bootstrap worker nodes

To prepare machines for Kubernetes installation, run:

```console
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yaml -K
```

> **NOTE:** the bootstrap step usually required to run only once or when new nodes joined.

To install Kubernetes, run:

```console
ansible-playbook -i ansible/inventory.ini ansible/kubernetes-install.yaml -K
```

Once the playbook run completes, a kubeconfig file `admin.conf` will be fetched to the current directory. To prevent needing to specify the kubeconfig set the `KUBECONFIG` environment variable with:

```console
export KUBECONFIG="${KUBECONFIG}:${HOME}/path/to/admin.conf"
```

To verify the cluster is up and available, run:

```console
$> kubectl get nodes
NAME                                        STATUS   ROLES           AGE     VERSION
control-plane-0.k8s.cluster.ad.wongway.io   Ready    control-plane   3h13m   v1.29.0
worker-0.k8s.cluster.ad.wongway.io          Ready    <none>          3h12m   v1.29.0
worker-1.k8s.cluster.ad.wongway.io          Ready    <none>          3h12m   v1.29.0
```

Consider running [sonobuoy](https://sonobuoy.io/) conformance test to validate the cluster configuration and health.

To uninstall Kubernetes, run:

```console
ansible-playbook -i ansible/inventory.ini ansible/kubernetes-reset.yaml -K
```

This playbook will run `kubeadm reset` on all nodes, remove configuration changes, and stop Kubelets.

## Persistent volumes with EBS

There is a plenty of storage solutions on Kubernetes. At the moment of writing,
[OpenEBS](https://openebs.io/) looked like a good fit for having storage installed
with minimal friction.

For the homelab setup, a [local hostpath](https://openebs.io/docs/user-guides/localpv-hostpath)
provisioner should be sufficient, however, OpenEBS provides multiple options for
a replicated storage backing Persistent Volumes.

To use only host-local Persistent Volumes, it is sufficient to install a lite
version of OpenEBS:

```console
kubectl apply -f https://openebs.github.io/charts/openebs-operator-lite.yaml
```

Once the Operator is installed, create a `StorageClass` and annotate it as **default**:

```console
kubectl apply -f ansible/openebs-sc.yaml
```

To verify the installation, follow the official [OpenEBS documentation](https://openebs.io/docs/user-guides/localpv-hostpath#install-verification).

## MetalLB

To install MetalLB, check the configuration in [ansible/roles/metallb/templates/metallb-config.yaml](ansible/roles/metallb/templates/metallb-config.yaml) and update variables if needed. The address range must be relevant for the target
environment so the addresses can be allocated.

To install MetalLB, run:

```console
ansible-playbook -i ansible/inventory.ini ansible/metallb.yaml -K
```

## Istio

Istio provides multiple [installation options](https://istio.io/latest/docs/setup/install/).
To simplify the installation process, download and install `istioctl` from [releases page](https://github.com/istio/istio/releases/).

It is recommended to install Istio with the [default configuration profile](https://istio.io/latest/docs/setup/additional-setup/config-profiles/). This profile is recommended for production deployments and deploys a single ingress gateway.
To install Istio with the default profile, run:

```console
ansible-playbook -i ansible/inventory.ini ansible/istioctl.yaml -K
```

Once Istio is installed, you can check that the Ingress Gateway is up and has an associated `Service`
of a `LoadBalancer` type with an IP address from MetalLB. Run:

```console
kubectl get svc istio-ingressgateway -n istio-system
```

Example:

```console
NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                                      AGE
istio-ingressgateway   LoadBalancer   10.108.231.216   10.0.5.100    15021:32014/TCP,80:30636/TCP,443:30677/TCP   21m
```

### Deployment exposed via Istio Ingress Gateway

To expose a deployment via an istio ingress gateway there are several resources that are needed:

-   [Gateway](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/): A load balancer operating at the edge of the mesh that receives incoming HTTP/TCP connections and allows external traffic to enter the istio service mesh
-   [Service](https://kubernetes.io/docs/concepts/services-networking/service/): A unit of application behavior bound to a unique name in a service regsitry
-   [VirtualService](https://istio.io/latest/docs/reference/config/networking/virtual-service/): Defines a set of traffic routing rules to apply. If traffic is matched it is forwarded to the destination service (or subset/version of it) defined in the registry
-   [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): Describes the desired state for pods and replicasets

In the previous playbook to install istio a gateway was created in the `istio-system` namespace with a wildcard host pattern so it can be reused by multiple deployments. The deployments will be routed by the `VirtualServices` using the URL path. It is also possible to create a `Gateway` per application but for the demo purposes, a path-based routing seems to be more convenient.

To verify the installation, MetalLB, Ingress Gateway, and Istio configuration let's create a test Nginx `Deployment` to create the other resources needed for routing along with the nginx deployment:

#### Deploying Nginx

```console
 kubectl apply -f ansible/apps/examples/nginx/nginx.yaml
```

To get the gateway ip run:

```console
export GATEWAY_IP=$(kubectl get svc -n istio-system istio-ingressgateway -ojsonpath='{.status.loadBalancer.ingress[0].ip}')
```

The Nginx welcome page should be available at the gateway ip assigned by metallb, http://$GATEWAY_IP

## Cert-manager

Cert-manager is a certificate management tool that handles issuing or renewing certificates to ensure they are valid and up to date automatically. For the homelab we'll use [LetsEncrypt](https://letsencrypt.org/how-it-works/) to issue certificates and Cloudflare with DNS challenges to secure ingress for the cluster.

Before we create the cluste resources we need to create a Cloudflare API token. Create and verify the domain you want to create an SSL certificate. Go to Cloudflare dashboard > My Profile (Right top corner) > API Tokens. Click Create Token button and Create custom token button. Under permissions add the following resource permissions:

| API Token Resource | API Token Permission            | Value |
| ------------------ | ------------------------------- | ----- |
| Account            | Access: Mutual TLS Certificates | Edit  |
| Account            | Account Settings                | Edit  |
| Zone               | Zone Settings                   | Edit  |
| Zone               | Zone                            | Edit  |
| Zone               | SSL and Certificates            | Edit  |
| Zone               | DNS                             | Edit  |

Click Create Token. Copy the token and update the environment variable `CF_API_TOKEN` with the value:

```console
export CF_API_TOKEN=<cloudflare api token>
```

Set the email to use for LetsEncrypt:

```console
export ACME_EMAIL=<your email>
```

Update the staging and prod cluster issuer `dnsNames` values in the `cluster-issuer.yaml` files in `/ansible/roles/cert-manager/templates/`.

There are two issuers, one for staging and one for production. The production LetsEncrypt server is rate limited so start with staging first and once the certificate is issued install the production resources.

**Note: if you want to avoid installing production resources, comment them out in the cert-manager playbook.**

To install cert-manager, run:

```console
ansible-playbook -i ansible/inventory.ini ansible/cert-manager.yaml -K
```

You can monitor logs of the certificate issuance with:

```console
kubectl -n istio-system get certs,certificaterequests,order,challenges,ingress -o wide
```

Once the certificate has been issued you can update the gateway:

```console
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: ingress-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*"
      tls:
        httpsRedirect: true
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: "wongwayio-cert-prod"
      hosts:
        - "*"
EOF
```

## Kubernetes Dashboard

Install Kubernetes Dashboard following the [docs](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/). At the moment of writing, it is sufficient to run:

```console
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

To access the dashboard UI, run `kubectl --kubeconfig=admin.conf proxy` and open this link in your browser:
[localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/).

To login into the Dashboard, it is recommended to create a user as per the [Dashboard docs](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md). To create an admin user verify the ansible variable kubernetes_dashboard.name is correct then run:

```console
ansible-playbook -i ansible/inventory.ini ansible/kubernetes-dashboard-adminuser.yaml -K
```

Once the user is created the login token will be output to a file `kubernetes-dashboard-admin-token-{{ inventory_hostname }}.txt` in the current directory. You may also get the login token by running:

```console
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
```

You can also create a long-lived token as per [Getting a long-lived Bearer Token for ServiceAccount](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md#getting-a-long-lived-bearer-token-for-serviceaccount).

To remove the admin user created, run:

```console
ansible-playbook -i ansible/inventory.ini ansible/kubernetes-dashboard-adminuser-reset.yaml -K
```

Afterwards, you can run the `get secret` command above and you should receive:

```text
Error from server (NotFound): secrets "admin-user" not found
```
