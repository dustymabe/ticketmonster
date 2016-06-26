#!/bin/bash
docker rm -f wildfly db modcluster
oc delete project production
sleep 10
oc new-project production
