# Edge deployment on Kubernetes

⏱️ **Time:** installation within 35min

💻 **Environment:** tested on Kubernetes `1.28`, `1.29`, `1.30` and `1.31`

[`<img src="https://github.com/kerberos-io/deployment/workflows/Deploy%20on%20Kubernetes/badge.svg"/>`](https://github.com/kerberos-io/deployment/actions/workflows/kind.yaml)

---

Kubernetes is an open-source platform for automating the deployment, scaling, and management of containerized applications. It provides features like automated deployment, self-healing, service discovery, and storage orchestration. Kubernetes is essential for modern cloud-native application development and operations.

In this tutorial, we will guide you through installing the edge stack, which includes Agent, Vault, and the Data Filtering Service. This setup enables the storage of recordings from multiple cameras at the edge, facilitating local data processing and ensuring secure and efficient management of video streams.

## Install Kubernetes on Ubuntu with kubeadm

Kubernetes can be installed on various Linux distributions. This tutorial specifically focuses on the installation process for Ubuntu using the `kubeadm` method. For the most up-to-date installation guide, we recommend referring to [the official Kubernetes documentation](https://kubernetes.io/docs/setup/production-environment/) and [`kubeadm` documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/).

Let's prepare the system and install the relevant packages.

```bash
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet
```

Enable ip forwarding.

```bash
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
```

Install containerd runtime

```bash
apt-get install containerd -y
```

Now we have everything installed let's go ahead and create the cluster using `kubeadm`.

```bash
kubeadm init --pod-network-cidr=192.168.0.0/16
```

Once completed you will see something similar.

```bash
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 209.38.97.191:6443 --token dd9jhg.t734mc1dkr2qhcir \
	--discovery-token-ca-cert-hash sha256:dcea694458128b8cad4315dbbdab11796cd2bef03d08a3ce2caed3fc1837d63b
```

Save the `.kube/config` file to enable the use of `kubectl` for interacting with the Kubernetes cluster.

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Install `Calico` as the networking solution for your Kubernetes cluster. Calico provides a robust and scalable networking layer, enabling secure and efficient communication between your pods. To deploy Calico, apply the following manifest:

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/custom-resources.yaml
watch kubectl get pods -n calico-system
```

Remove the taint to allow scheduling of pods on the master node, as this is a single-node cluster.

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

Verify the installation by checking the status of the nodes and pods. Wait for all components to be in the `Running` state.

```bash
# Check the status of the nodes
kubectl get nodes

# Check the status of the pods in the kube-system namespace
kubectl get pods -n kube-system
```

Ensure that all nodes are in the Ready state and all pods are in the Running state before proceeding with further configurations or deployments.

## Dependencies

When installing the ecosystem, several dependencies are required for storage, such as a database (e.g., MongoDB) and a message broker (e.g., RabbitMQ) for asynchronous behavior. We will install these components before setting up the Agents and Vault.

### Clone repository

Next, clone this repository for the Garage S3 manifests, MongoDB Helm chart values, and other required components.

```bash
git clone https://github.com/kerberos-io/deployment
cd deployment
```

### OpenEBS

When you create a Kubernetes cluster using `kubeadm` on a bare metal machine

### Object storage: Garage (default)

After creating the `ssd-hostpath` StorageClass for your provisioner, run:

```sh
bash scripts/install-garage.sh
bash scripts/check-garage.sh
```

See the [Garage guide](./base/garage/README.md) for generated credentials,
Vault provider settings, persistence and existing MinIO compatibility. Garage
uses S3 port `3900` internally and NodePort `30090`; it needs no operator.
Skip the following legacy section when using the default installation.

### Optional legacy object storage: MinIO

MinIO is a high-performance, distributed object storage system that is compatible with Amazon S3 cloud storage service. It is designed to handle large-scale data storage and retrieval, making it an ideal choice for modern cloud-native applications.

In the context of the ecosystem, MinIO will be used to store recordings from the Agents. These recordings are crucial for surveillance and monitoring purposes, and having a reliable storage solution like MinIO ensures that the data is stored securely and can be accessed efficiently.

```bash
git clone --depth 1 --branch v6.0.1 https://github.com/minio/operator.git && kubectl apply -k operator/
```

View the minio operator status with:

```bash
kubectl get po -w -A
```

Next we'll create a tenant

```bash
sed -i 's/openebs-hostpath/microk8s-hostpath/g' ./minio-tenant-base.yaml
kubectl apply -f minio-tenant-base.yaml
```

View the minio tenant status with:

```bash
kubectl get po -w -A
```

You should see the `myminio` tenant being created

```bash
minio-tenant   myminio-pool-0-0       2/2     Running   0       60s
```

We create a bucket in the minio tenant

You might need to install the minio client if not yet available.

```bash
curl https://dl.min.io/client/mc/release/linux-amd64/mc \
  --create-dirs \
  -o $HOME/minio-binaries/mc

chmod +x $HOME/minio-binaries/mc
export PATH=$PATH:$HOME/minio-binaries/
```

Expose the minio service so we can reach it from our local station.

```bash
kubectl port-forward svc/myminio-hl 9000 -n minio-tenant &
```

Create the `mybucket` bucket in the `myminio` tenant.

```bash
mc alias set myminio http://localhost:9000 minio minio123 --insecure
mc mb myminio/mybucket --insecure
```

Close the port-forward

```bash
pkill -f "port-forward"
```

The expected output should resemble the following:

```bash
root@microk8s:~/deployment# mc mb myminio/mybucket --insecure
Handling connection for 9000
Bucket created successfully `myminio/mybucket`.
```

or if not possible we will access the minio console using a reverse tunnel.

```bash
kubectl port-forward svc/myminio-console -n minio-tenant 8080:9090
ssh -L 8080:localhost:8080 youruser@x.x.x.x
```

To access the application, open your browser and navigate to `localhost:8080`. Use the credentials specified in the `minio-tenant-base.yaml` configuration file to log in. Once logged in, you can create a new bucket, such as `mybucket`, or choose a name of your preference.

### Database: MongoDB

When using Vault, it will persist references to the recordings stored in your storage provider in a MongoDB database. As used before, we are using `helm` to install MongoDB in our Kubernetes cluster. Within the Vault project we are using the latest official mongodb driver, so we support all major MongoDB versions (4.x, 5.x, 6.x, 7.x).

Have a look into the `./mongodb-values.yaml` file, you will find plenty of configurations for the MongoDB helm chart. To change the username and password of the MongoDB instance, go ahead and [find the attribute where](https://github.com/kerberos-io/vault/blob/master/kubernetes/mongodb/values.yaml#L148) you can change the root password. Please note that we are using the official [Bitnami Mongodb helm chart](https://github.com/bitnami/charts/tree/main/bitnami/mongodb), so please use their repository for more indepth configuration.

Next to that you might also consider a SaaS MongoDB deployment using MongoDB Atlas or using a managed cloud like AWS, GCP, Azure or Alibaba cloud. A managed service takes away a lot of management and maintenance from your side (backups, security, sharing, etc). If you do want to install MongoDB in your own cluster then please continue with this tutorial.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
kubectl create namespace mongodb
```

Note: If you are installing a self-hosted Kubernetes cluster, we recommend using `openebs`. Therefore make sure to uncomment the `global`.`storageClass` attribute, and make sure it's using `microk8s-hostpath` instead.

```bash
sed -i 's/openebs-hostpath/microk8s-hostpath/g' ./mongodb-values.yaml
helm install mongodb -n mongodb bitnami/mongodb --values ./mongodb-values.yaml
```

Or after updating the `./mongodb-values.yaml` file again

```bash
helm upgrade mongodb -n mongodb bitnami/mongodb --values ./mongodb-values.yaml
```

View the MongoDB status and wait until it's properly running

```bash
kubectl get po -w -A
```

### Message broker: RabbitMQ

Now we can store recordings in `MinIO` and metadata in `MongoDB`. The remaining task is to store events in a message broker such as `RabbitMQ`. This setup enables an asynchronous event-driven approach, allowing you to receive real-time event each time a recording is uploaded. By doing so, you can develop custom logic and abstract the camera network from your machine learning models or computer vision algorithms. The primary focus is on the recordings, not the complex camera infrastructure.

```bash
kubectl create namespace rabbitmq
```

```bash
sed -i 's/openebs-hostpath/microk8s-hostpath/g' ./rabbitmq-values.yaml
helm install rabbitmq bitnami/rabbitmq -n rabbitmq -f rabbitmq-values.yaml
```

View the RabbitMQ status and wait until it's properly running

```bash
kubectl get po -w -A
```

### Vault

Vault requires a configuration to connect to the MongoDB instance. To handle this a `configmap` is defined in the `./mongodb-configmap.yaml` file. Modify the MongoDB credentials in the `./mongodb-configmap.yaml` file, and make sure they match the credentials of your MongoDB instance, as described above. There are two ways of configuring the MongoDB connection, either you provide a `MONGODB_URI` or you specify the individual variables `MONGODB_USERNAME`, `MONGODB_PASSWORD`, etc.

As mentioned above a managed MongoDB is easier to setup and manage, for example for MongoDB Atlas, you will get a MongoDB URI in the form of `"mongodb+srv://xx:xx@kerberos-hub.xxx.mongodb.net/?retryWrites=true&w=majority&appName=xxx"`. By applying this value into the `MONGODB_URI` field, you will have setup your MongoDB connection successfully.

```yaml
- name: MONGODB_URI
  value: "mongodb+srv://xx:xx@kerberos-hub.xxx.mongodb.net/?retryWrites=true&w=majority&appName=xxx"
```

Once you applied this value, the other values like `MONGODB_USERNAME`, `MONGODB_PASSWORD` and others will be ignored. If you don't like the `MONGODB_URI` format you can still use the old way of defining the MongoDB connection by providing the different values.

```yaml
    - name: MONGODB_USERNAME
      value: "root"
    - name: MONGODB_PASSWORD
->    value: "yourmongodbpassword"
```

Create the `kerberos-vault` namespace.

```bash
kubectl create namespace kerberos-vault
```

Apply the manifests, so the Vault application is deployed and knows how to connect to the MongoDB.

```bash
kubectl apply -f ./mongodb-configmap.yaml -n kerberos-vault
kubectl apply -f ./kerberos-vault-deployment.yaml -n kerberos-vault
kubectl apply -f ./kerberos-vault-service.yaml -n kerberos-vault
```

Verify if the pod is running

```bash
kubectl get po -w -A
```

#### Access the UI

If you have opted for the `NodePort` configuration, you can access the Vault via the `http://localhost:30080` endpoint in your browser. For server installations without a GUI, consider setting up a reverse proxy to enable browser access from your local machine. Alternatively, you may utilize a `LoadBalancer` if one is available or if you are deploying on a managed Kubernetes service.

```bash
ssh -L 8080:localhost:30080 user@server-ip -p 22
```

#### Configure the Vault

With the Vault installed, we can proceed to configure the various components. Currently, this must be done through the Vault UI, but we plan to make it configurable via environment variables, eliminating the need for manual UI configurations.

![Configure Vault](./assets/images/configure-vault.gif)

- Navigate to the `Storage Providers` menu and select the (+ Add Storage Provider) button. A modal will appear where you can input the required details. After entering the information, click the "Verify" button to ensure the configuration is valid. Once you receive a "Configuration is valid and working" message, click the "Add Storage Provider" button to complete the process.

  - MinIO/S3-compatible provider type (Garage backend)
    - Enabled: true
    - Provider name: garage
    - Bucket name: mybucket
    - Region: garage
    - Hostname: garage.garage:3900
    - SSL: false
    - Access key: `access-key` from Secret `garage/garage-credentials`
    - Secret key: `secret-key` from the same Secret

For the optional legacy MinIO installation, retain that backend's hostname,
credentials and provider name instead. See the [Garage guide](./base/garage/README.md)
before switching an existing installation.

- Navigate to the `Integrations` menu and select the (+ Add Integration) button. A modal will appear where you can input the required details. After entering the information, click the "Verify" button to ensure the configuration is valid. Once you receive a "Configuration is valid and working" message, click the "Add Integration" button to complete the process.

  - RabbitMQ
    - Enabled: true
    - Integration name: rabbitmq
    - Broker: rabbitmq.rabbitmq:5672
    - Exchange: `<empty>`
    - Queue: data-filtering
    - Username: yourusername
    - Password: yourpassword

- Navigate to the `Accounts` menu and click the (+ Add Account) button. A modal will appear where you can input the required details. After entering the information, click the "Add Account" button to complete the process.

  - Enabled: true
  - Account name: myaccount
  - Main provider: garage (or the retained provider for an existing installation)
  - Day limit: 30
  - Integration: rabbitmq
  - Directory: \*
  - Access key: XJoi2@bgSOvOYBy# (or generate new keys, but don't forget to update them in the next steps)
  - Secret key: OGGqat4lXRpL@9XBYc8FUaId@5 (or generate new keys, but don't forget to update them in the next steps)

### Create an Agent

Check [Agent HTTP port compatibility](./README.md#agent-http-port-compatibility)
before selecting an image: published releases use internal port `80`, while
the forthcoming hardened image requires `8080` and matching Service targets.

After deploying the Vault and configuring the necessary services for storage, database, and integration, you can proceed to deploy the Agent with the appropriate configuration. Review the `kerberos-agent-deployment.yaml` file and adjust the relevant settings, such as the RTSP URL, to ensure proper functionality. As mentioned below note that you can opt for the [Factory](https://github.com/kerberos-io/factory/tree/master/kubernetes) which gives you a UI to manage the creation of Agents. **_(Please note if you generated new the keys in the previous Vault account creation, you need to update those in the Agent deployment)_**

```bash
kubectl apply -f kerberos-agent-deployment.yaml
```

Review the creation of the Agent and review the logs of the container to validate the Agent is able to connect to the IP camera, and if a recording is being created and transferred to the Vault

```bash
kubectl get po -w -A
kubectl logs -f kerberos-agent...
```

To validate the Vault and review any stored recordings, access the user interface at `http://localhost:30080` (after establishing the reverse tunnel).

### Create Agents through Factory

Managing Agents through seperate configuration files might feel cumbersome, especially for non-technical users. This is where Factory comes into the picture. Factory provides a visual view that allows you to rapidly connect cameras through a user interface, which allows users without any technical background about cameras and kubernetes create Agents.

Factory also requires a mongodb, just like Vault. Luckily you can reuse the mongodb installation we have deployed earlier, the only thing we'll need to do is to create another `configmap.yaml` in the `kerberos-factory` namespace.

Create the `kerberos-factory` namespace.

```bash
kubectl create namespace kerberos-factory
```

Apply the manifests, so the Factory application is deployed and knows how to connect to the MongoDB.

```bash
kubectl apply -f ./mongodb-configmap.yaml -n kerberos-factory
kubectl apply -f ./kerberos-factory-deployment.yaml -n kerberos-factory
kubectl apply -f ./kerberos-factory-service.yaml -n kerberos-factory
```

To allow our Factory to create Kubernetes resources we will need to apply an additional cluster role. This will allow our Factory deployment to read and write resources to our Kubernetes cluster.

```bash
kubectl apply -f ./kerberos-factory-clusterrole.yaml -n kerberos-factory
```

Verify if the pod is running

```bash
kubectl get po -w -A
```

### Optimized Data Filtering for Enhanced Bandwidth Efficiency and Relevance

Once your Agents are properly connected and all recordings are stored in the Vault, you may encounter additional challenges such as bandwidth limitations, storage constraints, and the need to efficiently locate relevant data. To accomplish this, we can configure an integration to filter the recordings, ensuring that only the relevant ones are retained.

Assuming all configurations are correctly set and all Kubernetes deployments are operational, you can apply the `data-filtering-deployment.yaml` deployment. This deployment will schedule a pod that listens to the configured integration in Vault and runs a YOLOv8 model to evaluate the recordings and match them against specified conditions.

Please note that if you do not have a GPU on the device, you will need to disable the resource limit of the nvidia/gpu. Once done the filtering will run on the CPU.

```bash
sed -e '/resources/ s/^#*/#/' -i ./data-filtering-deployment.yaml
sed -e '/limits/ s/^#*/#/' -i ./data-filtering-deployment.yaml
sed -e '/nvidia/ s/^#*/#/' -i ./data-filtering-deployment.yaml
```

Let's deploy the data filtering pod (with or without GPU support).

```bash
kubectl apply -f data-filtering-deployment.yaml
```

Each time a recording is stored in the Vault, the `data-filtering` pod will receive a notification and execute the specified model (YOLOv8 by default). Based on the defined conditions, the `data-filtering` pod may forward the recording to a remote Vault, trigger alerts, or send notifications.

Ensure that the `data-filtering` workload is actively running, receiving messages from the integration, and performing the necessary processing tasks.

```bash
kubectl get po -w -A
kubectl logs -f data...
```

You might see something like below, whereas the `data-filtering` pod is iterating over recordings and frames, looking for a person. Once it finds the person it will try to `forward` the recording to a remote Vault.

```bash
Persons: 0, Cars: 0, Trucks: 0
Condition not met, not forwarding video to remote vault
Persons: 0, Cars: 0, Trucks: 0
Condition not met, not forwarding video to remote vault
Persons: 1, Cars: 0, Trucks: 0
Condition met, forwarding video to remote vault
Condition met, stopping the video loop, and forwarding video to remote vault
Something went wrong while forwarding media
Delete media from http://vault-lb.kerberos-vault/api
   - Classification took: 22.4 seconds, @ 3 fps.
     - 0.15s for preprocessing and initialisation
     - 22.25s for processing of which:
       - 0.99s for class prediction
       - 21.26s for other processing
     - 0s for postprocessing
   - Original video: 31.5 seconds, @ 30.0 fps @ 1920x1080. File size of 2.1 MB
8) Releasing video writer and closing video capture
```

As indicated by the logs `Something went wrong while forwarding media`, the forwarding process failed due to the absence of an integration between the two `Vaults`. Currently, only one `Vault` is available. To enable this feature, you will need to [install a second `Vault` in the cloud](./README.k8s-managed.md) with access to cloud storage.

### Add forwarding integration

If you have setup a secondary Vault in the cloud, attached cloud Object storage to it, we can continue and add an additional integration through the UI.

```bash
ssh -L 8080:localhost:30080 user@server-ip -p 22
```

Navigate to the `Vault` application in your browser, access the `Integration` section, and add a new integration. This integration will connect your local Vault to the remote Vault, and will tell the system to set recordings in a `forwarding state`.

- Add an integration

  - Vault
    - Enabled: true
    - Integration name: remote-vault
    - Forwarding mode: continuous
    - Url: http(s)://yourvault.com/api
    - Provider: The name of the remote storage provider
    - Access Key: The access key of the account you have created on the remote Vault
    - Secret Access Key: The secret access key of the account you have created on the remote Vault

If the integration is functioning correctly, you should observe that recordings are initially marked in gray as "To be forwarded." After a short period, some recordings will be updated to green, indicating they have been "Forwarded by."

## Cleanup

If you consider to remove the ecosystem you might just disable the microk8s installation

```bash
microk8s reset
sudo snap remove microk8s
```

or if you want to keep the microk8s installation you can also delete the individual deployments.

```bash
kubectl delete -f data-filtering-deployment.yaml
kubectl delete -f kerberos-agent-deployment.yaml
kubectl delete -f ./kerberos-vault-deployment.yaml -n kerberos-vault
kubectl delete -f ./mongodb-config.yaml -n kerberos-vault
helm del rabbitmq -n rabbitmq
helm del mongodb -n mongodb
git clone --depth 1 --branch v6.0.1 https://github.com/minio/operator.git && kubectl delete -k operator/
```

You can confirm all the workloads were removed from your system.

```bash
kubectl get po -w -A
```
