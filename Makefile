LOCALBIN ?= $(shell pwd)/bin
ENVTEST ?= $(LOCALBIN)/setup-envtest
ENVTEST_K8S_VERSION = 1.23
KIND ?= $(LOCALBIN)/kind
CMCTL ?= $(LOCALBIN)/cmctl
SKAFFOLD ?= $(LOCALBIN)/skaffold
KUTTL ?= $(LOCALBIN)/kuttl
KUBECTL ?= $(LOCALBIN)/kubectl
GOARCH ?= $(shell go env GOARCH)
GOOS ?= $(shell go env GOOS)
KIND_VERSION ?= v0.31.0
KIND_NODE_IMAGE ?= kindest/node:v1.34.3@sha256:08497ee19eace7b4b5348db5c6a1591d7752b164530a36f855cb0f2bdcbadd48
KUBECTL_VERSION ?= v1.34.6
CERT_MANAGER_VERSION ?= v1.20.2
CMCTL_VERSION ?= v2.3.0
CALICO_VERSION ?= v3.31.3
CDI_VERSION ?= v1.63.1
KUTTL_VERSION ?= v0.25.0

all: test

generate:
	iidfile=$$(mktemp /tmp/iid-XXXXXX) && \
	docker build -f hack/Dockerfile --iidfile $$iidfile . && \
	docker run --rm -v $$PWD:/go/src/github.com/smartxworks/virtink -w /go/src/github.com/smartxworks/virtink $$(cat $$iidfile) ./hack/generate.sh && \
	rm -rf $$iidfile

fmt:
	go fmt ./...

test: envtest
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path)" go test ./... -coverprofile cover.out

$(LOCALBIN):
	mkdir -p $(LOCALBIN)

.PHONY: envtest
envtest: $(ENVTEST)
$(ENVTEST): $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

.PHONY: kind
kind: $(KIND)
$(KIND): $(LOCALBIN)
	curl -sLo $(KIND) https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-$(GOOS)-$(GOARCH) && chmod +x $(KIND)

.PHONY: kubectl
kubectl: $(KUBECTL)
$(KUBECTL): $(LOCALBIN)
	curl -sLo $(KUBECTL) https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(GOOS)/$(GOARCH)/kubectl && chmod +x $(KUBECTL)

.PHONY: cmctl
cmctl: $(CMCTL)
$(CMCTL): $(LOCALBIN)
	curl -fsSL -o cmctl.tar.gz https://github.com/cert-manager/cmctl/releases/download/$(CMCTL_VERSION)/cmctl_$(GOOS)_$(GOARCH).tar.gz
	tar xzf cmctl.tar.gz -C $(LOCALBIN)
	rm -rf cmctl.tar.gz

.PHONY: skaffold
skaffold: $(SKAFFOLD)
$(SKAFFOLD): $(LOCALBIN)
	curl -sLo $(SKAFFOLD) https://storage.googleapis.com/skaffold/releases/latest/skaffold-$(GOOS)-$(GOARCH) && chmod +x $(SKAFFOLD)

.PHONY: kuttl
kuttl: $(KUTTL)
$(KUTTL): $(LOCALBIN)
	curl -sLo $(KUTTL) https://github.com/kudobuilder/kuttl/releases/download/$(KUTTL_VERSION)/kubectl-kuttl_$(patsubst v%,%,$(KUTTL_VERSION))_$(GOOS)_$(shell uname -m) && chmod +x $(KUTTL)

E2E_KIND_CLUSTER_NAME := virtink-e2e-$(shell date "+%Y-%m-%d-%H-%M-%S")
E2E_KIND_CLUSTER_KUBECONFIG := /tmp/$(E2E_KIND_CLUSTER_NAME).kubeconfig

.PHONY: e2e-image
e2e-image:
	docker buildx build -t virt-controller:e2e -f build/virt-controller/Dockerfile --build-arg PRERUNNER_IMAGE=virt-prerunner:e2e --load .
	docker buildx build -t virt-daemon:e2e -f build/virt-daemon/Dockerfile --load .
	docker buildx build -t virt-prerunner:e2e -f build/virt-prerunner/Dockerfile  --load .

e2e: kind kubectl cmctl skaffold kuttl e2e-image
	echo "e2e kind cluster: $(E2E_KIND_CLUSTER_NAME)"

	$(KIND) create cluster --config test/e2e/config/kind/config.yaml --image $(KIND_NODE_IMAGE) --name $(E2E_KIND_CLUSTER_NAME) --kubeconfig $(E2E_KIND_CLUSTER_KUBECONFIG)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) virt-controller:e2e
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) virt-daemon:e2e
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) virt-prerunner:e2e

	docker pull docker.io/calico/cni:$(CALICO_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) docker.io/calico/cni:$(CALICO_VERSION)
	docker pull docker.io/calico/node:$(CALICO_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) docker.io/calico/node:$(CALICO_VERSION)
	docker pull docker.io/calico/kube-controllers:$(CALICO_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) docker.io/calico/kube-controllers:$(CALICO_VERSION)
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) apply -f https://projectcalico.docs.tigera.io/archive/$(CALICO_VERSION)/manifests/calico.yaml
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) wait -n kube-system deployment calico-kube-controllers --for condition=Available --timeout -1s

	docker pull quay.io/jetstack/cert-manager-controller:$(CERT_MANAGER_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) quay.io/jetstack/cert-manager-controller:$(CERT_MANAGER_VERSION)
	docker pull quay.io/jetstack/cert-manager-cainjector:$(CERT_MANAGER_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) quay.io/jetstack/cert-manager-cainjector:$(CERT_MANAGER_VERSION)
	docker pull quay.io/jetstack/cert-manager-webhook:$(CERT_MANAGER_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) quay.io/jetstack/cert-manager-webhook:$(CERT_MANAGER_VERSION)
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) apply -f https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.yaml
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(CMCTL) check api --wait=10m

	docker pull quay.io/kubevirt/cdi-operator:$(CDI_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) quay.io/kubevirt/cdi-operator:$(CDI_VERSION)
	docker pull quay.io/kubevirt/cdi-apiserver:$(CDI_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) quay.io/kubevirt/cdi-apiserver:$(CDI_VERSION)
	docker pull quay.io/kubevirt/cdi-controller:$(CDI_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) quay.io/kubevirt/cdi-controller:$(CDI_VERSION)
	docker pull quay.io/kubevirt/cdi-uploadproxy:$(CDI_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) quay.io/kubevirt/cdi-uploadproxy:$(CDI_VERSION)
	docker pull quay.io/kubevirt/cdi-importer:$(CDI_VERSION)
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) quay.io/kubevirt/cdi-importer:$(CDI_VERSION)
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$(CDI_VERSION)/cdi-operator.yaml
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) wait -n cdi deployment cdi-operator --for condition=Available --timeout -1s
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$(CDI_VERSION)/cdi-cr.yaml
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) wait cdi.cdi.kubevirt.io cdi --for condition=Available --timeout -1s

	docker pull rook/nfs:master
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) rook/nfs:master
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) apply -f test/e2e/config/rook-nfs/crds.yaml
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) wait crd nfsservers.nfs.rook.io --for condition=Established
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) apply -f test/e2e/config/rook-nfs/

	SKAFFOLD=$(SKAFFOLD) CONTROLLER_IMAGE=virt-controller:e2e DAEMON_IMAGE=virt-daemon:e2e PRERUNNER_IMAGE=virt-prerunner:e2e ./hack/render-manifest.sh | KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) apply -f -
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUBECTL) wait -n virtink-system deployment virt-controller --for condition=Available --timeout -1s

	docker pull smartxworks/virtink-kernel-5.15.12
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) smartxworks/virtink-kernel-5.15.12
	docker pull smartxworks/virtink-container-disk-ubuntu
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) smartxworks/virtink-container-disk-ubuntu
	docker pull smartxworks/virtink-container-rootfs-ubuntu
	$(KIND) load docker-image --name $(E2E_KIND_CLUSTER_NAME) smartxworks/virtink-container-rootfs-ubuntu
	KUBECONFIG=$(E2E_KIND_CLUSTER_KUBECONFIG) $(KUTTL) test --config test/e2e/kuttl-test.yaml

	$(KIND) delete cluster --name $(E2E_KIND_CLUSTER_NAME)
