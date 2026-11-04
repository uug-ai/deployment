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
