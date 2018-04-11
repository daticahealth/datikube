FROM golang:1.10.1
ADD . $GOPATH/src/github.com/daticahealth/datikube
WORKDIR $GOPATH/src/github.com/daticahealth/datikube
CMD ./test.sh
