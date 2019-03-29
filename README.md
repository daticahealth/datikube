# datikube

CLI tool to make interfacing with [Datica](https://datica.com/)-managed [Kubernetes](https://kubernetes.io/) clusters easy.

## Workflow

Required inputs:
* Context name: We strongly recommend using the provided cluster name for your context. This will be similar to "yourorg-stg-01"
* Kubernetes API Server Load Balancer URL: This is provided by Datica when we hand off your cluster.
* Cluster Certificate Authority: This file is provided by Datica when we hand off your cluster.

1. `datikube set-context yourorg-stg-01 https://yourorg-stg-01-apiserver-abc123.example.com/ /path/to/my/ca.pem`
2. Sign in with your Datica credentials.
3. `kubectl --context my-cluster get pods`

Datica account sessions expire after 24 hours (`kubectl` will give an error of "`You must be logged in to the server (Unauthorized).`" if the token has expired) To get a new token:

1. `datikube refresh`

## Installation

Follow the instructions on [the latest release](https://github.com/daticahealth/datikube/releases).

## Usage Help

```sh
datikube --help
```

## Building from source

1. Install Go (>= 1.9). Make sure`$GOBIN` and `$GOPATH` are set.
3. Install [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/).
3. Clone this repo inside of `$GOPATH/src/github.com/daticahealth`.
4. `go build`
5. `./datikube --help`

### Handling dependencies

Make sure [Dep](https://golang.github.io/dep/docs/installation.html) is installed.

* Add: `dep ensure -add github.com/whoever/whatever`
* Update: `dep ensure -update github.com/whoever/whatever`
* Update all: `dep ensure -update` (_please don't run this unless you absolutely have to_)
