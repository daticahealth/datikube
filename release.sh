#!/bin/bash -e

# This script automates Github releases. It is not intended to be run locally.

echo "!!! Prepping release builds !!!"

if [ "${TAG}" = "" ]; then
    echo "TAG variable missing."
    exit 1
fi

if [ "${REPO_OWNER}" = "" ] || [ "${REPO_NAME}" = "" ]; then
    echo "REPO_* variable missing."
    exit 1
fi

if [ "${GITHUB_TOKEN}" = "" ]; then
    echo "GITHUB_TOKEN variable missing."
    exit 1
fi

if [ "${TEST}" = "false" ]; then
    echo "This is not a test run and will release! ABORT NOW IF THIS IS A MISTAKE!"
fi

cat > desc.tmp << EOM
${RELEASE_NOTES}

---

To install, [make sure \`kubectl\` is installed](https://kubernetes.io/docs/tasks/tools/install-kubectl/), then run this command in your terminal:

## OS X

Run this in your terminal:

\`\`\`sh
curl -L -o ./datikube https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${TAG}/datikube_${TAG}_darwin_amd64 && chmod +x ./datikube && sudo mv ./datikube /usr/local/bin/datikube
\`\`\`

## Linux

Run this in your terminal:

\`\`\`sh
curl -L -o ./datikube https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${TAG}/datikube_${TAG}_linux_amd64 && chmod +x ./datikube && sudo mv ./datikube /usr/local/bin/datikube
\`\`\`

## Windows

Download [datikube_${TAG}_windows_amd64.exe](https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${TAG}/datikube_${TAG}_windows_amd64.exe), rename it to \`datikube.exe\`, and place somewhere on your \`\$PATH\`.

EOM

declare -a architectures=("amd64")
declare -a platforms=("windows" "linux" "darwin")

mkdir -p ./builds
for arch in "${architectures[@]}"; do
    for os in "${platforms[@]}"; do
        echo "Building for ${os} ${arch}"
        GOOS=$os GOARCH=$arch GOBIN=. go build .
        if [ "${os}" = "windows" ]; then
            mv ./datikube.exe ./builds/datikube-$TAG-$os-$arch.exe
        else
            mv ./datikube ./builds/datikube-$TAG-$os-$arch
        fi
    done
done

echo "!!! Releasing !!!"

if [ "${TEST}" = "false" ]; then
    echo "Going to release ${TAG} of ${REPO_OWNER}/${REPO_NAME}"

    echo "Installing gothub"
    go get github.com/itchio/gothub

    echo "Creating release"
    cat desc.tmp | gothub release \
        --user ${REPO_OWNER} \
        --repo ${REPO_NAME} \
        --tag "${TAG}" \
        --name "${TAG}" \
        --description "-" \
        --pre-release

    for f in ./builds/*; do
        echo "Uploading ${f}"
        gothub upload \
            --user ${REPO_OWNER} \
            --repo ${REPO_NAME} \
            --tag "${TAG}" \
            --name ${f##*/} \
            --file $f
    done

    echo "Pre-release complete. Check it out: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/${TAG}"
else
    echo "In test mode - not releasing."
fi

echo "Done. 💥"
