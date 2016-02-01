.PHONY: binaries

ssl-keys: admin.pem apiserver.pem 
binaries: kubernetes/_output/dockerized/bin/linux/amd64 calico-cni/dist
clean-binaries: clean-calico-plugin clean-kubernetes


# Creates a Kubernetes cluster which passes the k8s conformance tests.
cluster:
	# Clean first.
	make clean-webserver        # Stop any existing webserver.
	make clean-keys             # Remove any SSL keys.
	# Ensure binaries exist. 
	make calico-cni/dist
	make kubernetes/_output/dockerized/bin/linux/amd64
	make kubectl                # Get kubectl
	# Deploy VMS
	make create-cluster-vagrant 
	# Deploy kubernetes apps.
	make kube-system            # Create kube-system namespace.
	make run-dns-pod            # Run DNS addon.
	make run-kube-ui            # Run kube-ui addon.

# Cleans the Kubernetes binaries.
clean-kubernetes:
	make -C kubernetes clean

# Builds Kubernetes binaries.
kubernetes/_output/dockerized/bin/linux/amd64:
	make -C kubernetes quick-release

# Cleans the calico-cni plugin.
clean-calico-plugin:
	make -C calico-cni clean

# Builds calico-cni plugin.
calico-cni/dist:
	make -C calico-cni

# Destroys all vagrant machines.
destroy-cluster-vagrant: clean-webserver 
	-vagrant destroy -f

# Runs vagrant in order to create the VMs necessary for the cluster.
create-cluster-vagrant: destroy-cluster-vagrant webserver
	vagrant up

# Creates a local webserver used by cloud-init to retrieve binaries
# from the host.
webserver: ssl-keys
	python -m SimpleHTTPServer &

# Tears down the local webserver used by cloud-init to retrieve binaries
# from the host.
clean-webserver: clean-keys
	(sudo killall python) || echo "Server not running"

# Generates CA / master certifications for Kubernetes.
generate-certs:
	sudo openssl/create_keys.sh

# Removes kubectl.
clean-kubectl:
	rm -f kubectl

kubectl: admin.pem kubernetes/_output/dockerized/bin/linux/amd64
	cp kubernetes/_output/dockerized/bin/linux/amd64/kubectl .
	chmod +x kubectl

configure-kubectl: kubectl
	./kubectl config set-cluster default-cluster --server=https://172.18.18.101 --certificate-authority=ca.pem
	./kubectl config set-credentials default-admin --certificate-authority=ca.pem --client-key=admin-key.pem --client-certificate=admin.pem
	./kubectl config set-context default-system --cluster=default-cluster --user=default-admin
	./kubectl config use-context default-system

run-dns-pod: kube-system
	./kubectl create -f dns/dns-addon.yaml || echo "Unable to run DNS.  Already running?"

run-kube-ui: kube-system
	./kubectl create -f kube-ui/ || echo "Unable to run kube-ui.  Already running?"

kube-system:
	./kubectl create -f namespaces/kube-system.yaml || echo "Unable to create kube-system namespace. Already running?"

deploy-heapster: remove-heapster
	kubectl create -f heapster

remove-heapster:
	-kubectl delete service monitoring-grafana --grace-period=1 --namespace=kube-system
	-kubectl delete service monitoring-influxdb --grace-period=1 --namespace=kube-system
	-kubectl delete service heapster --grace-period=1 --namespace=kube-system
	-kubectl delete rc heapster --grace-period=1 --namespace=kube-system
	-kubectl delete rc influxdb-grafana --grace-period=1 --namespace=kube-system

vagrant-ssh:
	vagrant ssh-config > vagrant-ssh

heapster-images: vagrant-ssh
	docker pull kubernetes/heapster_grafana:v2.5.0
	docker pull kubernetes/heapster_influxdb:v0.6
	docker pull kubernetes/heapster:v0.19.0
	docker save kubernetes/heapster_grafana:v2.5.0 | ssh -F vagrant-ssh calico-01 docker load
	docker save kubernetes/heapster_influxdb:v0.6 | ssh -F vagrant-ssh calico-01 docker load
	docker save kubernetes/heapster:canary | ssh -F vagrant-ssh calico-01 docker load

apply-node-labels:
	kubectl label nodes -l 'kubernetes.io/hostname!=172.18.18.101' role=node	

deploy-pinger: remove-pinger
	kubectl create -f pinger

remove-pinger:
	-kubectl delete rc pinger --grace-period=1

launch-firefox:
	firefox 'http://172.18.18.101:8080/api/v1/proxy/namespaces/default/services/monitoring-grafana/'

ca-key.pem:
	openssl genrsa -out ca-key.pem 2048
	openssl req -x509 -new -nodes -key ca-key.pem -days 10000 -out ca.pem -subj "/CN=kube-ca"

admin.pem: ca-key.pem 
	openssl genrsa -out admin-key.pem 2048
	openssl req -new -key admin-key.pem -out admin.csr -subj "/CN=kube-admin"
	openssl x509 -req -in admin.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out admin.pem -days 365

apiserver.pem: ca-key.pem 
	openssl genrsa -out apiserver-key.pem 2048
	openssl req -new -key apiserver-key.pem -out apiserver.csr -subj "/CN=kube-apiserver" -config openssl.cnf
	openssl x509 -req -in apiserver.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out apiserver.pem -days 365 -extensions v3_req -extfile openssl.cnf

clean-keys:
	rm -f *.pem
	rm -f ca.srl
	rm -f *.csr

CLUSTER_SIZE := 25
NODE_NUMBERS := $(shell seq -f '%02.0f' 2 ${CLUSTER_SIZE})
LOG_RETRIEVAL_TARGETS := $(addprefix job,${NODE_NUMBERS})

pull-plugin-timings: ${LOG_RETRIEVAL_TARGETS}
	# See http://stackoverflow.com/a/12110773/61318
	#make -j12 CLUSTER_SIZE=2 pull-plugin-timings
	echo "DONE"
	cat timings/*.log > timings/all.timings

${LOG_RETRIEVAL_TARGETS}: job%:
	mkdir -p timings
	ssh -F vagrant-ssh calico-$* grep TIMING  /var/log/calico/kubernetes/calico.log | grep -v status > timings/calico-$*.log

.PHONY: ${LOG_RETRIEVAL_TARGETS}
