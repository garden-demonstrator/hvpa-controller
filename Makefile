# Copyright (c) 2019 SAP SE or an SAP affiliate company. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

VERSION             := $(shell cat VERSION)
REGISTRY            := eu.gcr.io/gardener-project/gardener
REPO_ROOT           := $(shell dirname "$(realpath $(lastword $(MAKEFILE_LIST)))")

IMAGE_REPOSITORY    := $(REGISTRY)/hvpa-controller
IMAGE_TAG           := $(VERSION)

# Image URL to use all building/pushing image targets
IMG ?= $(IMAGE_REPOSITORY):$(IMAGE_TAG)

# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: manager

# Run tests
test: generate fmt vet
	@env GO111MODULE=on GOFLAGS=-mod=vendor go test ./internal/... ./controllers/... ./utils/... -coverprofile cover.out

# Build manager binary
manager: generate fmt vet
	@env GO111MODULE=on GOFLAGS=-mod=vendor go build -o bin/manager main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet
	@env GO111MODULE=on GOFLAGS=-mod=vendor go run ./main.go --enable-detailed-metrics --logtostderr=true --v=2

# Install CRDs into a cluster
install: manifests
	kubectl apply -f config/crd/bases

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	kubectl apply -f config/crd/bases
	kustomize build config/default | kubectl apply -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	cd "$(REPO_ROOT)/api" && $(CONTROLLER_GEN) $(CRD_OPTIONS) paths="./..." output:crd:artifacts:config=../config/crd/bases
	$(CONTROLLER_GEN) rbac:roleName=manager-role webhook paths="./controllers/..."
	kustomize build config/crd -o config/crd/output/crds.yaml

# Run go fmt against code
fmt:
	@env GO111MODULE=on GOFLAGS=-mod=vendor go fmt ./...

# Run go vet against code
vet:
	@env GO111MODULE=on GOFLAGS=-mod=vendor go vet ./...

# Generate code
generate: controller-gen
	cd "$(REPO_ROOT)/api" && $(CONTROLLER_GEN) object:headerFile=../hack/boilerplate.go.txt paths=./...

# Build the docker image
docker-build: test
	docker build . -t ${IMG}
	@echo "updating kustomize image patch file for manager resource"
	sed -i'' -e 's@image: .*@image: '"${IMG}"'@' ./config/default/manager_image_patch.yaml

# Push the docker image
docker-push:
	docker push ${IMG}

# Revendor
revendor:
	@cd "$(REPO_ROOT)/api" && go mod tidy
	@env GO111MODULE=on go mod tidy
	@env GO111MODULE=on go mod vendor

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	go install sigs.k8s.io/controller-tools/cmd/controller-gen
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif
