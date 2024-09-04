# Übersicht für Cluster: ftctl-pf01 (ingress)

| Namespace    | Name                                   | Hosts                                    | Adresse       | Ports     |
|:-------------|:---------------------------------------|:-----------------------------------------|:--------------|:----------|
| argocd       | argocd-toolchain-pf01-server           | argocd.pf01.ftctl.f-i-ts.io              | 212.34.89.224 | 443       |
| logging      | loki-distributed-gateway               | gateway.loki.pf01.ftctl.mpls.f-i-ts.io   | 100.127.143.1 | 80, 443   |
| monitoring   | grafana-zenmon                         | grafana.pf01.ftctl.f-i-ts.io             | 212.34.89.224 | 80, 443   |
| monitoring   | grafana-zenmon-mpls                    | grafana-pf01.lab.f-i-ts.io               | 100.127.143.1 | 80, 443   |
| monitoring   | prometheus-stack-zenmon-thanos-receive | receive.thanos.pf01.ftctl.mpls.f-i-ts.io | 100.127.143.1 | 80, 443   |
| zisweb-proxy | zisweb-proxy                           | zisweb.pf01.ftctl.mpls.f-i-ts.io         | 100.127.143.1 | 8000, 443 |
