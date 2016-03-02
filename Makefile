K8S_VERSION=1.1.8

# Which OS version to use for kubectl
# `darwin` or `linux`
OS=darwin

all: apply-node-labels deploy-pinger
ssl-keys: admin.pem apiserver.pem 

# Creates a Kubernetes cluster which passes the k8s conformance tests.
cluster:
	make clean-webserver        # Stop any existing webserver.
	make clean-keys             # Remove any SSL keys.
	make clean-kubectl	    # Remove old kubectl
	make kubectl                # Get kubectl
	make create-cluster-vagrant # Start the cluster.
	make install-addons

# Installs Kubernetes addons
install-addons:
	-./kubectl create -f addons/kube-system.yaml
	-./kubectl create -f addons/

# Builds the latest calico-cni binaries.
binaries: 
	make -C calico-cni binary

# Cleans the calico-cni submodule.
clean-binaries:
	make -C calico-cni clean

destroy-cluster-vagrant: 
	-vagrant destroy -f

create-cluster-vagrant: destroy-cluster-vagrant webserver
	vagrant up

webserver: ssl-keys
	python -m SimpleHTTPServer &

clean-webserver: clean-keys
	(sudo killall python) || echo "Server not running"

generate-certs:
	sudo openssl/create_keys.sh

clean-kubectl:
	rm -f kubectl

kubectl: admin.pem
	wget http://storage.googleapis.com/kubernetes-release/release/v$(K8S_VERSION)/bin/$(OS)/amd64/kubectl
	chmod +x kubectl
	./kubectl config set-cluster default-cluster --server=https://172.18.18.101 --certificate-authority=ca.pem
	./kubectl config set-credentials default-admin --certificate-authority=ca.pem --client-key=admin-key.pem --client-certificate=admin.pem
	./kubectl config set-context default-system --cluster=default-cluster --user=default-admin
	./kubectl config use-context default-system

remove-dns: 
	./kubectl --namespace=kube-system delete rc kube-dns-v9
	./kubectl --namespace=kube-system delete svc kube-dns

run-dns-pod:
	./kubectl create -f dns/dns-addon.yaml

remove-kube-ui:
	./kubectl --namespace=kube-system delete rc kube-ui-v4
	./kubectl --namespace=kube-system delete svc kube-ui

calicoctl:
	wget http://www.projectcalico.org/builds/calicoctl
	chmod +x calicoctl

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
