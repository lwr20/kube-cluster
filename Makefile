K8S_VERSION=1.1.3

all: apply-node-labels deploy-pinger
ssl-keys: admin.pem apiserver.pem 

# Creates a Kubernetes cluster which passes the k8s conformance tests.
run:
	make calico-cni-binaries
	make clean-webserver
	make create-cluster-vagrant
	make kube-system
	make run-dns-pod
	make run-kube-ui

calico-cni-binaries:
	cd calico-cni && git checkout master && git pull origin master && make clean && make binary

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

kubectl: admin.pem
	rm -f ./kubectl
	wget http://storage.googleapis.com/kubernetes-release/release/v$(K8S_VERSION)/bin/linux/amd64/kubectl
	chmod +x kubectl
	./kubectl config set-cluster default-cluster --server=https://172.18.18.101 --certificate-authority=ca.pem
	./kubectl config set-credentials default-admin --certificate-authority=ca.pem --client-key=admin-key.pem --client-certificate=admin.pem
	./kubectl config set-context default-system --cluster=default-cluster --user=default-admin
	./kubectl config use-context default-system

remove-dns: kubectl
	./kubectl --namespace=kube-system delete rc kube-dns-v9
	./kubectl --namespace=kube-system delete svc kube-dns

run-dns-pod:  kubectl
	./kubectl create -f dns/dns-addon.yaml

remove-kube-ui: kubectl
	./kubectl --namespace=kube-system delete rc kube-ui-v4
	./kubectl --namespace=kube-system delete svc kube-ui

run-kube-ui: kubectl
	./kubectl create -f kube-ui/

kube-system: kubectl
	./kubectl create -f namespaces/kube-system.yaml

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

scale-pinger:
	kubectl scale --replicas=20 rc/pinger

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

.PHONEY: ${LOG_RETRIEVAL_TARGETS}
