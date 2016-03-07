# Creating the Cluster
Set the correct `OS=` variable in `Makefile` - either `darwin` if you're running this on Mac, or `linux` if running on Linux.

You can start a cluster with:
```
make cluster
```

This will spin up 1 Kubernetes master and 3 minions.  Creating the cluster downloads a `kubectl` binary and configures TLS, so you can run the following locally once the cluster is running:
```
kubectl get pods --all-namespaces 
```  

> Note: Starting the cluster may take 5-10 minutes, as it downloads all the Docker images necessary for the demo.

You should see the following output (or similar):
```
illium:kube-cluster cd4$ ./kubectl get pods --all-namespaces
NAMESPACE       NAME                        READY     STATUS    RESTARTS   AGE
calico-system   calico-policy-agent-1s1f4   1/1       Running   0          1m
kube-system     kube-dns-v9-dtay6           4/4       Running   0          1m
kube-system     kube-ui-v4-cs8ya            1/1       Running   0          1m
```

# Running the stars demo
The included demo sets up a frontend and backend service
and configures policy on each.  Demo files are located [here](./demo/).

1) Log into the master.  The following commands are all run on the Master.
```
vagrant ssh k8s-master
```

2) Create the frontend and backend ReplicationControllers and Services.
```
kubectl create -f stars-demo-files/ 
```
Once all the pods are started, they should have full connectivity. You can see this 
via the UI by visiting `http://172.18.18.101:30002` in a browser. 

3) Enable isolation
```
kubectl annotate ns default "net.alpha.kubernetes.io/network-isolation=yes" --overwrite=true
kubectl annotate ns client "net.alpha.kubernetes.io/network-isolation=yes" --overwrite=true
```

The UI will no longer be able to access the pods, so they will no longer show up in the UI.  Allow 
the UI to access the pods via a NetworkPolicy.
```
# Allow access from the management UI. 
policy create -f allow-ui.yaml
policy create -f allow-ui-client.yaml
policy list
```

The UI should now show the pods, but the services should not be able to access each other any more.

4) Create the "backend-policy.yaml" file to allow traffic from the frontend to the backend.
```
policy create -f backend-policy.yaml
policy list
```

The frontend can now curl the backend, but cannot ping it (since only TCP 80 is allowed)
The backend cannot access the frontend at all.

5) On the master, expose the frontend service to the `client` namespace.
```
policy create -f frontend-policy.yaml
policy list
```

The client can now access the frontend, but not the backend.  Neither the frontend nor the backend 
can initiate connections to the client.
