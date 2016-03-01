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

You should see the following output (or similar):
```
illium:kube-cluster cd4$ ./kubectl get pods --all-namespaces
NAMESPACE       NAME                        READY     STATUS    RESTARTS   AGE
calico-system   calico-policy-agent-1s1f4   1/1       Running   0          1m
kube-system     kube-dns-v9-dtay6           4/4       Running   0          1m
kube-system     kube-ui-v4-cs8ya            1/1       Running   0          1m
```

# Running the demo.
The included demo sets up a frontend and backend service (each just running nginx)
and configures policy on each.  Demo files are located [here](./demo/).

1) Create the frontend and backend ReplicationControllers and Services.
```
./kubectl create -f demo/manifests
```
Once all the pods are started, they should have full connectivity. 

```
# Get the backend from the frontend.
./kubectl exec -ti frontend-xxxxx -- curl backend 

# Get the frontend using a NodePort.
curl http://172.18.18.101:30001

# Get the frontend from the backend. 
./kubectl exec -ti backend-xxxxx -- curl frontend
```

2) Enable isolation
```
./kubectl annotate ns default "net.alpha.kubernetes.io/network-isolation=yes" --overwrite=true
```

The services should not be able to access each other any more.

3) On the master, create the "backend-policy.yaml" file to allow traffic from the frontend to the backend.
```
cat backend-policy.yaml | ./policy create
./policy list
```
> View the existing policies with `./policy get <namespace> <policy_name>`

The frontend can now curl the backend, but cannot ping it (since only TCP 80 is allowed)
The backend cannot access the frontend at all.

4) On the master, expose the frontend service to the "internet"
```
cat frontend-policy.yaml | ./policy create
./policy list
```

The frontend should be accessible from anywhere (but only on TCP 80).

To access it via NodePort:
```
curl http://172.18.18.101:30001 
```
