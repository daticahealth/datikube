#!/bin/bash -e

echo "!!! Vetting !!!"
go vet $(go list ./... | grep -v /vendor/)

echo "!!! Running tests !!!"
# excluding /vendor isn't needed if you're on Go 1.9 or above, which you should be if you followed the README.
go test -v ./...
