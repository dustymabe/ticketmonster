#!/bin/bash
set -eu
#set -x
export OPENSHIFT_HOST="${OPENSHIFT_HOST:=10.1.2.3:8443}"
export DOCKER_HOST="${DOCKER_HOST:=tcp://10.1.2.2:2376}"
WORKSPACE=${WORKSPACE:=/sharedfolder/github.com/eivantsov/ticketmonster/}

OUTPUT='/dev/stdout'
OUTPUT='/dev/null'

cd $WORKSPACE &> $OUTPUT

BRANCH=production
git checkout $BRANCH &> $OUTPUT


function build() {
  echo -e "### Updating git branch '$BRANCH'...\n"
  git pull origin $BRANCH &> $OUTPUT 
  SHA1="$(git log --pretty=format:'%h' -n 1)"
  echo -e "### Fetched revision $SHA1\n"

  echo -e "### Running Maven build...\n"
  mvn package &> $OUTPUT
  cp target/ticket-monster.war misc/Dockerfiles/ticketmonster-ha/ticket-monster.war &> $OUTPUT
  # Silently deploy/build in openshift
  openshift &> $OUTPUT
  echo -e "### Built ticket-monster.war using maven\n"

  echo -e "### Build and deploy to production using ansible-container...\n"
  pushd misc/ &> $OUTPUT
  docker run -it --rm -v $(pwd):/work/ -e DETACH=1 -e DOCKER_HOST dustymabe/ansible-container --debug run &> $OUTPUT
  popd &> $OUTPUT

  echo -e "### Brought up TicketMonster using ansible-container\n"
  docker ps --format "{{.ID}}\t{{.Status}}\t{{.Names}}"
}

function openshift() {
  mkdir /tmp/demo && cp -a misc/* /tmp/demo/
  pushd /tmp/demo/
  sed -i 's|/work/|./|' container.yml
  oc login --insecure-skip-tls-verify=true $OPENSHIFT_HOST -u openshift-dev -p devel
  oc project production
  henge -provider openshift container.yml  | oc create -f -
  sleep 5 # wait a sec, otherwise race conditions happen
  oc start-build wildfly --from-dir Dockerfiles/ticketmonster-ha
  popd && rm -rf /tmp/demo/
}

echo -e "### Polling for updates to git..."
while true; do
  git fetch &> build_log.txt
  echo -n '.'
  if [ -s build_log.txt ]; then
    echo
    build
    exit
  fi
  sleep 5s
done
