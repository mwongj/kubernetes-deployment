# On-premises Kubernetes deployment
## Overview
This repository contains a reference implementation of bootstrapping and installation
of a Kubernetes cluster on-premises. The provided tooling can be used both as a basis
for personal projects and for educational purposes.

The goal of the project is to provide tooling for reproducible deployment of a fully
functional Kubernetes cluster for on-premises including support for dynamic
provisioning of `PersistentVolumes` an `LoadBalancer` service types.

A detailed description is available in
[The Ultimate Kubernetes Homelab Guide: From Zero to Production Cluster On-Premises](https://datastrophic.io/kubernetes-homelab-with-proxmox-kubeadm-calico-openebs-and-metallb/) blog post.

Software used:
* `Ansible` for deployment automation
* `kubeadm` for Kubernetes cluster bootstrapping
* `containerd` container runtime
* `Calico` for pod networking
* `MetalLB` for exposing `LoadBalancer` type services
* `OpenEBS` for volume provisioning
* `Istio` for ingress and traffic management

## Pre-requisites
* cluster machines/VMs should be provisioned and accessible over SSH
* it is recommended to use Ubuntu 20.04 as cluster OS
* the current user should have superuser privileges on the cluster nodes
* Ansible installed locally

## Bootstrapping the infrastructure on Proxmox
The [proxmox](proxmox) directory of this repo contains automation for the initial
infrastructure bootstrapping using `cloud-init` templates and Proxmox Terraform provider.

The terraform will generate a dynamic inventory file `proxmox/terraform/inventory.ini` to use with ansible.

## Quickstart
Installation consists of the following phases:
* prepare machines for Kubernetes installation
  * install common packages, disable swap, enable port forwarding, install container runtime
* Kubernetes installation
  * bootstrap control plane, install container networking, bootstrap worker nodes

To prepare machines for Kubernetes installation, run:
```
ansible-playbook -i proxmox/terraform/inventory.ini ansible/bootstrap.yaml -K
```

> **NOTE:** the bootstrap step usually required to run only once or when new nodes joined.

To install Kubernetes, run:
```
ansible-playbook -i proxmox/terraform/inventory.ini ansible/kubernetes-install.yaml -K
```

Once the playbook run completes, a kubeconfig file `admin.conf` will be fetched to the current directory. To prevent needing to specify the kubeconfig set the `KUBECONFIG` environment variable with:
```
export KUBECONFIG="${KUBECONFIG}:${HOME}/path/to/admin.conf"
```

To verify the cluster is up and available, run:

```
$> kubectl get nodes
NAME                          STATUS   ROLES                  AGE     VERSION
control-plane-0.k8s.cluster   Ready    control-plane,master   4m40s   v1.21.6
worker-0                      Ready    <none>                 4m5s    v1.21.6
worker-1                      Ready    <none>                 4m5s    v1.21.6
worker-2                      Ready    <none>                 4m4s    v1.21.6
```

Consider running [sonobuoy](https://sonobuoy.io/) conformance test to validate the cluster configuration and health.    

To uninstall Kubernetes, run:
```
ansible-playbook -i proxmox/terraform/inventory.ini ansible/kubernetes-reset.yaml -K
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
```
kubectl apply -f https://openebs.github.io/charts/openebs-operator-lite.yaml
```

Once the Operator is installed, create a `StorageClass` and annotate it as **default**:
```
kubectl apply -f ansible/openebs-sc.yaml
```

To verify the installation, follow the official [OpenEBS documentation](https://openebs.io/docs/user-guides/localpv-hostpath#install-verification).

## MetalLB

To install MetalLB, check the configuration in [ansible/roles/metallb/templates/metallb-config.yaml](ansible/roles/metallb/templates/metallb-config.yaml) and update variables if needed. The address range must be relevant for the target
environment so the addresses can be allocated.

To install MetalLB, run:
```
ansible-playbook -i proxmox/terraform/inventory.ini ansible/metallb.yaml -K
```

## Kubernetes Dashboard
Install Kubernetes Dashboard following the [docs](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/). At the moment of writing, it is sufficient to run:
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

To access the dashboard UI, run `kubectl --kubeconfig=admin.conf proxy` and open this link in your browser:
[localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/).

To login into the Dashboard, it is recommended to create a user as per the [Dashboard docs](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md). To create an admin user verify the ansible variable kubernetes_dashboard.name is correct then run:
```
ansible-playbook -i proxmox/terraform/inventory.ini ansible/kubernetes-dashboard-adminuser.yaml -K
```

Once the user is created the login token will be output to a file `kubernetes-dashboard-admin-token-{{ inventory_hostname }}.txt` in the current directory. You may also get the login token by running:
```
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
```

You can also create a long-lived token as per [Getting a long-lived Bearer Token for ServiceAccount](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md#getting-a-long-lived-bearer-token-for-serviceaccount).

To remove the admin user created, run:
```
ansible-playbook -i proxmox/terraform/inventory.ini ansible/kubernetes-dashboard-adminuser-reset.yaml -K
```
Afterwards, you can run the `get secret` command above and you should receive:
```
Error from server (NotFound): secrets "admin-user" not found
```

## Istio

Istio provides multiple [installation options](https://istio.io/latest/docs/setup/install/).
To simplify the installation process, download and install `istioctl` from [releases page](https://github.com/istio/istio/releases/).

It is recommended to install Istio with the [default configuration profile](https://istio.io/latest/docs/setup/additional-setup/config-profiles/). This profile is recommended for production deployments and deploys a single ingress gateway.
To install Istio with the default profile, run:
```
ansible-playbook -i proxmox/terraform/inventory.ini ansible/istioctl.yaml -K
```

Once Istio is installed, you can check that the Ingress Gateway is up and has an associated `Service`
of a `LoadBalancer` type with an IP address from MetalLB. Example:
```
kubectl get svc istio-ingressgateway --namespace istio-system

NAME                   TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                      AGE
istio-ingressgateway   LoadBalancer   10.107.130.40   192.168.50.150   15021:30659/TCP,80:31754/TCP,443:32354/TCP   75s
```

### Example deployment exposed via Istio Ingress Gateway
#### Deploying Nginx
To verify the installation, MetalLB, Ingress Gateway, and Istio configuration let's create
a test Nginx `Deployment`:
```
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - image: nginx
        name: nginx

---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx
  name: nginx
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: nginx
  type: ClusterIP
```

To verify the deployment, run:
```
 kubectl port-forward service/nginx 8080:80
 ```
The Nginx welcome page should be available at [localhost:8080](http://localhost:8080/).

#### Exposing Nginx deployment with Istio `Gateway` and `VirtualService`
To expose a deployment via Istio ingress gateway it is first required to create a [Gateway](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/).

We will create a shared `Gateway` in the `istio-system` namespace with a wildcard host pattern so it can be reused
by other deployments. The deployments will be routed by the `VirtualServices` using the URL path later on.
It is also possible to create a `Gateway` per application but for the demo purposes, a path-based routing
seems to be more convenient.
```
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: shared-gateway
  namespace: istio-system
spec:
  selector:
    # Use the default Ingress Gateway installed by Istio
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
```

Now, we should define the route and [create a VirtualService](https://istio.io/latest/docs/reference/config/networking/virtual-service/) to route the traffic to Nginx `Service`:
 ```
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
 name: nginx
spec:
 hosts:
 - "*"
 gateways:
 - nginx-gateway
 http:
 - name: "nginx-test"
   match:
   - uri:
       prefix: "/nginx-test"
   rewrite:
     uri: "/"
   route:
   - destination:
       host: nginx.default.svc.cluster.local
       port:
         number: 80
```

The `VirtualService` defines a prefix `prefix: "/nginx-test"` so that all requests
to the `<Enpoint URL>/nginx-test` will be routed to the Nginx `Service`.
The endpoint URL is a load balancer address of the Istio Ingress Gateway.
It comes handy to discover and export it to an environment variable for later use:
```
export INGRESS_HOST=$(kubectl get svc istio-ingressgateway --namespace istio-system -o yaml -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Now, we can verify that the deployment is exposed via the gateway at `http://$INGRESS_HOST/nginx-test`.
