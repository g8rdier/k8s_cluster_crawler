#!/bin/bash

#Skript zum Sammeln von Daten eines gegebenen Clusters

mkdir results
rm -rf results/*

#nach Anmeldung per cloudctl login Cluster abfragen
for MYCLUSTER in $(cloudctl cluster list --tenant fttc | awk '{print $4}' | grep -v NAME); do echo ${MYCLUSTER}; MYCLUSTERID=$(cloudctl cluster list --tenant fttc | grep -w ${MYCLUSTER} | awk '{print $1}'); echo ${MYCLUSTERID}; cloudctl cluster describe ${MYCLUSTERID} -o json > results/${MYCLUSTER}-result.json; done

exit 0