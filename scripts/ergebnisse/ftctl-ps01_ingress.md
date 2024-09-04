# Übersicht für Cluster: ftctl-ps01 (ingress)

| Namespace    | Name                                   | Hosts                                    | Adresse       | Ports     |
|:-------------|:---------------------------------------|:-----------------------------------------|:--------------|:----------|
| argocd       | argocd-toolchain-ps01-server           | argocd.ps01.ftctl.f-i-ts.io              | 212.34.89.227 | 443       |
| logging      | loki-distributed-gateway               | gateway.loki.ps01.ftctl.mpls.f-i-ts.io   | 100.127.143.4 | 80, 443   |
| monitoring   | grafana-zenmon                         | grafana.ps01.ftctl.f-i-ts.io             | 212.34.89.227 | 80, 443   |
| monitoring   | prometheus-stack-zenmon-thanos-receive | receive.thanos.ps01.ftctl.mpls.f-i-ts.io | 100.127.143.4 | 80, 443   |
| zisweb-proxy | zisweb-proxy                           | zisweb.ps01.ftctl.mpls.f-i-ts.io         | 100.127.143.4 | 8000, 443 |
