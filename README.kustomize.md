# Deployment on Microk8s with Kustomize

⏱️ **Time:** installation within 25min

💻 **Environment:** tested on Ubuntu 20.04 LTS, 22.04 LTS, 24.04 LTS

[<img src="https://github.com/kerberos-io/deployment/workflows/Deploy%20on%20Microk8s/badge.svg"/>](https://github.com/kerberos-io/deployment/actions/workflows/microk8s.yaml)

---

MicroK8s is a lightweight, fast, and secure Kubernetes distribution designed for developers and edge computing use cases. Developed by Canonical, MicroK8s is a minimalistic version of Kubernetes that can be installed with a single command and runs on various platforms, including Linux, macOS, and Windows. It is ideal for local development, CI/CD pipelines, IoT, and edge deployments due to its small footprint and ease of use. MicroK8s includes essential Kubernetes components and add-ons, such as DNS, storage, and the Kubernetes dashboard, making it a convenient choice for both beginners and experienced Kubernetes users.

In this tutorial, we will guide you through the installation of the complete stack, which includes the Agent, Factory, Vault, and Hub. This setup enables the storage of recordings from multiple cameras at the edge, facilitating local data processing and ensuring secure and efficient management of video streams. To simplify our efforts we will execute the installation using Kustomize.

## Install Microk8s

To install MicroK8s on your system, follow these steps. First, ensure that you have `snapd` installed on your machine. If not, you can install it using the following command:

To install MicroK8s on your system, follow these steps.

1. **Ensure that you have `snapd` installed on your machine.**
   If not, you can install it using the following command:

   ```bash
   sudo apt update
   sudo apt install snapd
   ```

2. Install MicroK8s. Once snapd is installed, you can install MicroK8s with:

   ```bash
   sudo snap install microk8s --classic --channel=1.32/stable
   ```

3. Add your user to the microk8s group. This step is necessary to avoid using sudo for MicroK8s commands:

   ```bash
   sudo usermod -a -G microk8s $USER
   sudo chown -f -R $USER ~/.kube
   ```

4. Apply the new group membership. You need to re-enter your session for the group change to take effect:

   ```bash
   su - $USER
   ```

5. After this, reload the user groups either via a reboot or by running 'newgrp microk8s'.

   ```bash
   newgrp microk8s
   ```

6. Check the status of MicroK8s. Ensure that MicroK8s is running correctly:

   ```bash
   microk8s status --wait-ready
   ```

7. Add an alias for kubectl as microk8s:

To simplify the usage of `kubectl` with MicroK8s, you can create an alias. This allows you to use the `kubectl` command without needing to prefix it with `microk8s.` every time. Add the following line to your shell configuration file (e.g., `.bashrc`, `.zshrc`):

```sh
sudo snap alias microk8s.kubectl kubectl
sudo snap alias microk8s.helm helm
```

or use the `alias` command:

```sh
alias kubectl='microk8s kubectl'
alias helm='microk8s helm'
```

For more detailed instructions and troubleshooting, please refer to the official MicroK8s documentation.

## Dependencies

When deploying the various solutions, several dependencies are essential for storage, including a database (e.g., MongoDB) and a message broker (e.g., RabbitMQ) for asynchronous operations. These components must be installed prior to setting up the Agents, Factory, Vault, and Hub.

One of the significant advantages of MicroK8s is its built-in addons, which can be enabled with a single command. This feature eliminates the need for complex Helm charts or operators, thereby simplifying the setup process. In this guide, we will enable several common services, such as DNS, GPU support, and storage, to streamline the installation. However, if you prefer more control, you may opt to manually install these components using their respective Helm charts or operators.

```bash
microk8s enable dns
microk8s enable dashboard
microk8s enable nvidia
microk8s enable hostpath-storage
```

You can verify the status of the enabled addons by running the following command:

```sh
microk8s.status
```

Or view the pod status with:

```bash
kubectl get po -w -A
```

### Clone repository

Next, clone this repository for the Garage S3 manifests, MongoDB Helm chart values, and other required components.

```bash
git clone https://github.com/kerberos-io/deployment
cd deployment
```

## Kustomize

The default base uses [Garage S3](./base/garage/README.md). Before a native
Kustomize apply, run `bash scripts/install-garage.sh --prepare-only` to create
its namespace and persistent credentials. `configure.sh apply` does this
automatically. Do not enable the MinIO addon for this default stack. Existing
MinIO installations must keep their backend/provider settings until their data
is explicitly migrated; do not prune their storage resources.

In contrast to the detailed installation instructions, as mentioned here, an easier option to install is to use our Kustomize configure. This will allow you to specify and create your own overlays to install all the different components through a single command line.

Kustomize uses the concept of `bases` and `overlays`, allowing you to customize the base installation with different settings (an overlay). Before executing the `kustomize` command below, navigate to the `overlays/microk8s/kustomization.yaml` file and modify the `inlineValues` of the Hub to match the IP address of your node. Please note that when using Multipass, WSL, or any other type of virtualization, your IP address will differ from the IP address of your host machine. Verify your IP address using the `ifconfig` command.

To simplify the experience, we have created a `configure.sh` script to automate the installation. You can run the script as shown below by providing the IP address of the host machine (or virtualization) and the storage path on the host machine (or virtualization) to persist the state of the various containers.

### A. Scripted installation

To create a new deployment you can use following command.

```bash
ubuntu@xxxx:~/deployment$ ./configure.sh
Usage: ./configure.sh {apply|delete} [-s <storage_path>] [-i <ip_address>]
```

When looking into the `configure.sh` script, you will notice that `microk8s` is utilized. You are encouraged to adjust the overlay to suit your requirements or create a new overlay as needed.

```bash
ubuntu@xxxx:~/deployment$ ./configure.sh apply -i x.x.x.x -s /media/storage
```

To delete you can use the deletion argument.

```bash
ubuntu@xxxx:~/deployment$ ./configure.sh delete
```

### B. Native installation

If you prefer to use `kustomize` directly without the `configure.sh` script, that's perfectly fine. You can adjust an existing overlay or create a new one to suit your needs. By using the `kustomize` configuration mechanism, you can override our `base` directory settings.

```yaml
valuesInline:
   license: "L/+FAw...sJZRBAA"
   mqtt:
      host: "localhost"
      port: "31080"
      protocol: "ws"
      ...
      host: "turn:localhost:8443"
      ...
   kerberoshub:
      api:
      url: "localhost:32081"
```

Within the deployment we are creating a new storage class, pointing to the desired location on disk to store database information, recordings and more. Change the `/media/Storage` value to point to the desired location.

```yaml
patches:
  - target:
      kind: StorageClass
      name: ssd-hostpath
    patch: |-
      - op: replace
        path: /parameters/pvDir
        value: /media/Storage
```

Run the modified overlay using the following command:

```bash
kubectl kustomize overlays/microk8s/ --enable-helm --load-restrictor LoadRestrictionsNone | kubectl apply -f -
```

Once the installation is running you should see something like following:

```bash
ubuntuvms@ubuntuvms:~/deployment$ kubectl kustomize overlays/microk8s/ --enable-helm  --load-restrictor LoadRestrictionsNone | kubectl apply -f -
namespace/kerberos-agent unchanged
namespace/kerberos-factory unchanged
namespace/kerberos-hub unchanged
namespace/kerberos-vault unchanged
namespace/garage unchanged
namespace/mongodb unchanged
namespace/rabbitmq unchanged
namespace/vernemq unchanged
customresourcedefinition.apiextensions.k8s.io/alertmanagerconfigs.monitoring.coreos.com configured
customresourcedefinition.apiextensions.k8s.io/alertmanagers.monitoring.coreos.com configured
customresourcedefinition.apiextensions.k8s.io/podmonitors.monitoring.coreos.com configured
customresourcedefinition.apiextensions.k8s.io/probes.monitoring.coreos.com configured
customresourcedefinition.apiextensions.k8s.io/prometheuses.monitoring.coreos.com configured
customresourcedefinition.apiextensions.k8s.io/prometheusrules.monitoring.coreos.com configured
customresourcedefinition.apiextensions.k8s.io/servicemonitors.monitoring.coreos.com configured
customresourcedefinition.apiextensions.k8s.io/thanosrulers.monitoring.coreos.com configured
...
```

Verify the installation using the `kubectl` command, it might take some time until all the Kubernetes pods are spinned up. Once everything is stable you should be able to access Factory, Vault and Hub using the node ip address their designated node ports. Continue with the [`configuration tutorial`](./README.configure.md) to start with the configuration and integration of the various tools.

### Install Turnserver

If installed and configured correctly, you should be able to access the various user interfaces and view live streams. However, to access the high-definition live view, it is necessary to install and configure a TURN server, such as coturn.

```bash
sudo apt-get install -y coturn
```

After installing, clear the contents of the `/etc/turnserver.conf` configuration file.

```bash
sudo nano /etc/turnserver.conf
```

Add following configuration and save the `turnserver.conf` file. Make sure to replace `<ip_address>` with the host IP address.

```conf
listening-port=8443
relay-ip=<ip_address>
fingerprint
lt-cred-mech
user=username1:password1
syslog
```

Enable coturn on startup

```bash
sudo systemctl enable coturn
sudo systemctl restart coturn
```

## Custom layout

Once the installation is complete, you can customize the user interface with your own branding. A persistent volume claim (PVC) has been created and attached to the `hub-frontend` pod. To locate the persistent volume, navigate to your specified storage path. The volume will have a name starting with `kerberos-hub-custom-layout-claim-pvc`.

```bash
cp -r base/volume/* /media/storage/kerberos-hub-custom-layout-claim-pvc-.../
```

Once the files are copied, you should see the CSS override on the Hub landing page.

## Access and configuration

Todo

## Cleanup

If you consider to remove the complete stack you might just disable the Microk8s installation

```bash
microk8s reset
sudo snap remove microk8s
```

You can confirm all the workloads were removed from your system.

```bash
kubectl get po -w -A
```
