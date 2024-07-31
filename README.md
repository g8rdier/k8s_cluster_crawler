# tc-cluster-crawler

Repo zum Sammeln von Skripten zur Aufbereitung von Kubernetes-Cluster-Daten.  

Die Daten sollen dann zyklisch gesammelt werden und in einer Art KBOM die wichtigen Daten zu unseren Clustern sichtbar machen.

1. Alle Infos über fttc-* und ftctl-Cluster werden über crawl_cluster.sh eingeholt und in .json files zusammengefasst.
2. Infos werden mit einem python skript geparsed und in Form gebracht, daraufhin output als .yaml file
